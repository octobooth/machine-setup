# Booth Machine Setup

![CI](https://github.com/octobooth-demos/machine-setup/actions/workflows/ci.yml/badge.svg)

This repository contains setup scripts for configuring booth machines. The scripts install and configure the GitHub Copilot app, Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, Node.js, PowerShell 7 (Windows), iTerm2 (macOS), and related tooling from a shared `config.json`.

**Running a booth?** The [booth playbook](docs/booth-playbook.md) covers the whole event: setting up machines, running demos, and cleaning up the booth accounts afterwards (weekly automatic cleanup and the full post-event reset).

## Features

- Installs the GitHub Copilot app (`github-copilot-app` cask / `GitHub.CopilotApp` winget package) and Copilot CLI.
- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI, logs it in with the scopes the booth demos need, and installs a suite of GitHub CLI extensions.
- Installs Node.js LTS on macOS (via `nvm`) and Windows (via `winget`).
- Installs PowerShell 7 (`Microsoft.PowerShell` winget package) on Windows alongside the built-in Windows PowerShell 5.1, so later steps and scripts can call `pwsh`.
- Installs iTerm2 on macOS, sets its default profile to follow the macOS appearance (GitHub Light Default in light mode, GitHub Dark Default in dark mode) with Monaspace Neon Frozen 14 (ligatures on, thin strokes off), and switches it to the Minimal theme.
- Installs the SF Mono, Monaspace (including the Frozen variants), and Mona Sans fonts on macOS.
- Adds Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, and iTerm2 to the macOS Dock and hides suggested and recent apps there.
- Pins VS Code, VS Code Insiders, the GitHub Copilot app, and Windows Terminal to the Windows taskbar.
- Makes Google Chrome the default browser on macOS (via `defaultbrowser`), including when Chrome was already installed.
- Configures VLC media player settings.
- Creates a demo loader script to launch the required applications and sites.
- Registers shared MCP servers for Copilot CLI.
- Clones the demo repos into `~/repos` and, on macOS, installs the Demo Launcher canvas for every Copilot session. `install-demo-launcher.sh` (macOS/Linux) and `install-demo-launcher.ps1` (Windows) do just that step on a machine that is already set up (see [Demo Launcher](#demo-launcher)).

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, GitHub CLI auth scopes, demo sites, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, iTerm2 theme settings, the Monaspace Frozen font version, Dock apps, and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, taskbar pins, and post-install apps for `setup.ps1`.

`mac.iterm2` controls iTerm2's look. `light` and `dark` each have a `color_scheme_file` (stored in [`iterm2/`](iterm2/README.md)) and a `color_preset` name. `setup.sh` adds both schemes to iTerm2's Color Presets. It turns on **Use separate colors for light and dark mode** in the default profile and applies the light scheme to its light-mode colors and the dark scheme to its dark-mode colors, so iTerm2 switches with the macOS appearance. The plain colors are set to the dark scheme for older iTerm2 versions without that option. It also applies `font` (a PostScript name and size, such as `MonaspaceNeonFrozen-Regular 14`) to the default profile. If iTerm2 has never been opened, it creates that "Default" profile. `theme` sets **Settings > Appearance > General > Theme** through the `TabStyleWithAutomaticOption` preference. It can be `regular` (4), `minimal` (5), `compact` (6), `light` (0), `dark` (1), `light-high-contrast` (2), or `dark-high-contrast` (3), using the values from iTerm2's `iTermPreferencesTabStyle`. `ligatures` sets the profile's **Use ligatures** option (Settings > Profiles > Text). Monaspace's texture healing and coding ligatures only show when it's on, which iTerm2 doesn't do by default. `thin_strokes` sets **Use thin strokes**: `never` (0), `retina-dark-backgrounds-only` (1), `dark-backgrounds-only` (2), `always` (3), or `retina-only` (4, iTerm2's default), from iTerm2's `iTermThinStrokesSetting`. Quit iTerm2 before running setup, because iTerm2 overwrites preference changes when it quits. Once these settings are applied, later runs leave iTerm2 alone. They apply again if you change either `color_preset`, `font`, `theme`, `ligatures`, or `thin_strokes` in `config.json`, or run with `FORCE_REINSTALL=true`. Machines set up before a setting was tracked get it on their next run.

Fonts: the `font-monaspace` cask installs Monaspace, and `font-mona-sans` installs Mona Sans. The `font-sf-mono` cask installs SF Mono from Apple and asks for an admin password. The cask doesn't include Monaspace's "Frozen" fonts (such as Monaspace Neon Frozen, the iTerm2 font). So `setup.sh` downloads `monaspace-frozen-v<version>.zip` from the [githubnext/monaspace release](https://github.com/githubnext/monaspace/releases) pinned in `mac.monaspace_frozen_version`, and copies its `.ttf` files to `~/Library/Fonts`. Later runs skip this step unless the pinned version changes or `FORCE_REINSTALL=true`.

`mac.dock_apps` lists app names (the `.app` bundle in `/Applications`, without `.app`) that `setup.sh` adds to the Dock with the `dockutil` formula. Apps already in the Dock are skipped, even with `FORCE_REINSTALL=true`, so reruns don't add duplicates. This includes Chrome when it was installed outside Homebrew and already pinned. Setup also turns off **Show suggested and recent apps in Dock** and restarts the Dock once if anything changed. It doesn't remove anything, so Downloads and Trash stay.

`windows.taskbar_pins` lists apps that `setup.ps1` pins to the Windows taskbar, in left-to-right order. Each `app_id` is the **AppID** shown by `Get-StartApps`. IDs that contain `!` are packaged apps (such as Windows Terminal), and the rest are desktop apps. Windows has no API to pin apps directly, so setup uses Microsoft's [taskbar layout policy](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps). It writes a layout XML to `%LOCALAPPDATA%\machine-setup\TaskbarLayout.xml`, points the current user's `StartLayoutFile` policy (`HKCU\Software\Policies\Microsoft\Windows\Explorer`) at it, and restarts Explorer so the pins show up. This needs an elevated (Administrator) prompt. Policy pins appear after the default and manually pinned apps, and Windows may pin them again if they're unpinned. On Windows 10, the policy also locks the Start tiles. Later runs skip this step unless the list changes or `FORCE_REINSTALL` is `"true"`.

`shared.gh_auth_scopes` lists the extra scopes the GitHub CLI login needs: `codespace` (the Tailspin Toys demo creates a Codespace), `delete_repo` (the Demo Launcher's cleanup deletes demo repos), `project` (the Copilot Airways demo creates a GitHub Project, and cleanup deletes it), and `workflow` (demo repos include GitHub Actions workflows, and GitHub rejects pushes that add or change `.github/workflows` files without it). A new login requests them, and an existing login missing any of them is upgraded with `gh auth refresh`, which opens a browser to approve. Both scripts ignore `GH_TOKEN`/`GITHUB_TOKEN` for these steps so the stored login is the one updated. To do it by hand, see [GitHub CLI login](#github-cli-login).

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

Clone this repo so you can update the scripts before each run. A ZIP download never updates, so an old copy keeps running old scripts. Both platforms then share the [GitHub CLI login](#github-cli-login) checks below.

### macOS setup

#### 1. Get the setup scripts

1. Open Terminal. On a new Mac, `git` doesn't work until the Xcode Command Line Tools are installed. Install them first: run the command below, click **Install** in the dialog, and wait for it to finish. If it says they're already installed, move on.

   ```bash
   xcode-select --install
   ```

2. Clone the repo:

   ```bash
   git clone https://github.com/octobooth-demos/machine-setup.git ~/repos/machine-setup
   ```

3. Before each booth day, and before re-running `setup.sh` or `install-demo-launcher.sh`, pull the latest:

   ```bash
   git -C ~/repos/machine-setup pull
   ```

**Fallback for a new Mac without Git:** [download the ZIP](https://github.com/octobooth-demos/machine-setup/archive/refs/heads/main.zip) and run commands from the extracted `machine-setup-main` folder. Keep all files together, because the scripts need `config.json` and `setup.sh` also needs the `iterm2/` folder. Setup installs the Xcode Command Line Tools and Git, so switch to a clone afterward. If you stay on the ZIP, download it again before re-running any script.

#### 2. Run setup

1. Open a terminal and go to `~/repos/machine-setup` (or the extracted `machine-setup-main` folder).
2. Run the setup script:

   ```bash
   bash setup.sh
   ```

   The script first checks for the Xcode Command Line Tools, which `git` (used to clone the demo repos) and Homebrew need. If they're missing, it opens the installer: click **Install**, and the script waits until it finishes (up to 30 minutes; set `XCODE_CLT_TIMEOUT` in seconds to change this). If the install fails or times out, run `xcode-select --install`, finish the installer, and run `bash setup.sh` again.

3. The script pauses so you can sign in to GitHub.com in Chrome with the booth/demo account.
4. If Chrome isn't the default browser yet, macOS asks whether to change it. Click **Use “Google Chrome”**, then press Enter. This also works if Chrome was installed before setup ran. If Chrome is already the default, the script skips this step.
5. Approve the GitHub CLI login (or scope upgrade) in the browser when prompted.
6. A launcher script that also opens the GitHub Copilot app is created on the Desktop.
7. Store booth videos in `$HOME/Videos` so the launcher opens them in VLC.

#### Re-running on a Mac that's already set up

You can run `bash setup.sh` again on a configured Mac without resetting it. Steps that are already done are skipped, and changed settings in `config.json` are applied:

- Homebrew packages that are already installed are left alone, and so are Chrome and the GitHub Copilot app when they're already in `/Applications`.
- The Monaspace Frozen fonts are skipped when the pinned version is already installed.
- iTerm2 is skipped when its light and dark color presets, font, theme, ligatures, and thin strokes already match `config.json`.
- Dock apps that are already in the Dock are skipped, and Chrome is skipped when it's already the default browser.
- The GitHub CLI login only asks for missing scopes, and repos already in `~/repos` aren't cloned again.
- The GitHub.com sign-in pause in Chrome still runs. Press Enter if you're already signed in.

To redo everything, run `FORCE_REINSTALL=true bash setup.sh`. To redo just one step, clear its marker and rerun `bash setup.sh`:

```bash
# iTerm2 colors, font, theme, ligatures, and thin strokes (quit iTerm2 first)
defaults delete com.googlecode.iterm2 MachineSetupITerm2Settings

# Monaspace Frozen fonts
rm ~/Library/Fonts/.monaspace-frozen-version
```

`brew uninstall iterm2` doesn't redo the iTerm2 step. Uninstalling removes the app but keeps its preferences, including the marker, so setup reinstalls the app and still skips the theme. Clear the marker instead.

### Windows setup (clean machine)

These steps assume a brand-new Windows 10 or 11 machine with nothing installed beyond what ships with Windows. Sign in to Windows and connect to the internet first. Until setup finishes, you only have the built-in **Windows PowerShell 5.1**. `setup.ps1` is written to run there, and it installs PowerShell 7 for later use.

#### 1. Open an administrator PowerShell

Right-click **Start** and choose **Terminal (Admin)** (Windows 11) or **Windows PowerShell (Admin)** (Windows 10), then approve the User Account Control prompt. Run every command below in this window. `setup.ps1` warns, and some installs can fail, when it isn't run as an administrator.

#### 2. Make sure winget works

`winget` comes with the **App Installer** package from Microsoft Store. On a new machine it can take a few minutes after first sign-in to register. Check it:

```powershell
winget --version
```

If the command isn't found, open Microsoft Store, search for **App Installer**, click **Update** (or **Get**), and open a new administrator window. The first `winget` command may ask you to accept the source agreements; type `Y`.

#### 3. Install Git and get the setup scripts

`setup.ps1` installs Git too, but you need it once now to clone this repo:

```powershell
winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
```

Close the window and open a new administrator PowerShell so `git` is on your `PATH`, then clone:

```powershell
git clone https://github.com/octobooth-demos/machine-setup.git "$HOME\repos\machine-setup"
cd "$HOME\repos\machine-setup"
```

Before each booth day, and before re-running `setup.ps1` or `install-demo-launcher.ps1`, pull the latest with `git -C "$HOME\repos\machine-setup" pull`.

#### 4. Allow the script to run

Windows blocks PowerShell scripts by default. Allow them for this window only (this doesn't change the machine's policy):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

#### 5. Run setup

```powershell
.\setup.ps1
```

What to expect:

1. `winget` installs everything in `windows.packages` in [`config.json`](config.json). PowerShell 7 (`Microsoft.PowerShell`) is installed first, followed by VS Code, VS Code Insiders, Windows Terminal, Git, GitHub CLI, Node.js LTS, Python, VLC, Copilot CLI, the GitHub Copilot app, and GitHub Desktop. This takes a while, and some installers briefly show their own windows.
2. The script refreshes `PATH` after the installs, so the rest of the run can use `pwsh`, `gh`, `code`, and the other new tools. It then configures VLC and pins VS Code, VS Code Insiders, the GitHub Copilot app, and Windows Terminal to the taskbar. The taskbar briefly disappears while Explorer restarts.
3. It pauses so you can sign in to GitHub.com in Microsoft Edge with the booth/demo account. Press Enter when you're signed in.
4. Approve the GitHub CLI login (or scope upgrade) in the browser when prompted. See [GitHub CLI login](#github-cli-login).
5. It installs GitHub CLI extensions, clones the demo repos into `$HOME\repos`, installs VS Code extensions and the theme, and registers MCP servers for Copilot CLI.
6. A launcher script (`load-demos.ps1`) is created on the Desktop.
7. A summary at the end lists anything that failed. Fix the cause and run `.\setup.ps1` again; finished steps are skipped.

#### 6. After setup

- Close the window and open a new terminal so it picks up the updated `PATH`. Check PowerShell 7 with `pwsh --version`. Windows Terminal adds a **PowerShell** profile for it, and Windows PowerShell 5.1 stays installed alongside it. Run future scripts with `pwsh`.
- Store booth videos in `C:\Users\<YourUsername>\Videos` so the launcher opens them in VLC.
- Set up the [Demo Launcher](#windows-repo-setup-scripts-project). To update it later, run `.\install-demo-launcher.ps1` (see [Install or update the canvas on Windows](#install-or-update-the-canvas-on-windows)).
- To add the taskbar pins on a machine that ran setup before they existed, pull the latest and run `.\setup.ps1` again, or run only that step from an Administrator prompt in the repo folder:

  ```powershell
  . .\setup.ps1; Import-Config; Set-TaskbarPins
  ```

  To check it, look for the four icons on the taskbar, and run `Get-ItemProperty HKCU:\Software\Policies\Microsoft\Windows\Explorer` to see `StartLayoutFile` and `LockedStartLayout`. To apply it again after editing the pins, run `$script:ForceReinstall = $true; Set-TaskbarPins` in the same window. To undo it, run `Remove-ItemProperty HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name StartLayoutFile, LockedStartLayout`, restart Explorer, and unpin the icons.

Set `$env:NONINTERACTIVE = "true"` before running `setup.ps1` to skip GitHub browser login, CLI login, and scope refresh. Existing CLI credentials (including `GH_TOKEN` or `GITHUB_TOKEN`) are used to install extensions and clone repositories. Without usable credentials, those steps are deferred with warnings; authenticate with `gh auth login` and rerun setup to complete them. Set `$env:FORCE_REINSTALL = "true"` to redo steps that are normally skipped on reruns.

### GitHub CLI login

The setup scripts handle this for you, but check it on every booth machine (and do it by hand if a script warned about it):

1. Log in as the **booth account** (for example `octobooth-1`), not your personal account. Choose GitHub.com, HTTPS, and log in with a web browser:

   ```bash
   gh auth login -h github.com
   ```

2. Add the extra scopes the demos need:

   ```bash
   gh auth refresh -h github.com -s codespace,delete_repo,project,workflow
   ```

   - `codespace`: the Tailspin Toys demo creates a Codespace.
   - `delete_repo`: the Demo Launcher's cleanup deletes old demo repos.
   - `project`: the Copilot Airways demo creates a GitHub Project, and cleanup deletes it.
   - `workflow`: demo repos include GitHub Actions workflows, and GitHub rejects pushes that add or change files in `.github/workflows` without this scope.

   `gh`'s default scopes (`repo`, `read:org`, `gist`) cover everything else.
3. Check it with `gh auth status`. It should show the booth account as active, with `codespace`, `delete_repo`, `project`, and `workflow` in its token scopes.

The booth account must be a member of the `octobooth-demos` org and allowed to create repositories there, because several demos create their repo in that org. It also needs a Copilot seat for the demos that use Copilot code review, assigning issues to Copilot, and Codespaces.

If `GH_TOKEN` or `GITHUB_TOKEN` is set, `gh` uses that token instead of this login, and `gh auth refresh` won't run. Unset them on booth machines.

### Troubleshooting Windows package installs

If `winget` isn't found, see [Make sure winget works](#2-make-sure-winget-works).


WinGet error `-1978335138` (`0x8A15005E`, pinned certificate mismatch) can occur when querying the Microsoft Store source, even for a package available from the `winget` source. See [microsoft/winget-cli#3109](https://github.com/microsoft/winget-cli/issues/3109). [`setup.ps1`](setup.ps1) explicitly selects `--source winget` to avoid these unrelated Store failures while preserving certificate validation. All entries in `windows.packages` in [`config.json`](config.json) must be available from the `winget` source.

To retry Visual Studio Code installation:

```powershell
winget install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements
```

If the error persists, update App Installer through Microsoft Store and check whether a proxy or security product is intercepting HTTPS traffic. Do not disable certificate checks or certificate pinning.

## Demo Launcher

[`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) (cloned to `~/repos/repo-setup-scripts`) ships a **Demo Launcher** canvas for the GitHub Copilot app. It creates booth demos in the background with `create-repo.sh`/`create-repo.ps1`, opens sessions for them in the Copilot app, and cleans up old demo repos.

### macOS (and Linux): installed loader and project

On booth machines, do both. The loader makes the launcher available in any session if the app loads user extensions, and the project is a guaranteed fallback.

1. On macOS, run `setup.sh`. On Linux, or a Mac that's already set up, run `install-demo-launcher.sh` (see below). Either one clones the repo to `~/repos/repo-setup-scripts` and runs its `install.sh`.
2. Open the GitHub Copilot app and sign in with the booth/demo account.
3. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Don't clone it again: then the loader and the project use the same checkout, and one `bash install-demo-launcher.sh` (or `git -C ~/repos/repo-setup-scripts pull`) plus an app restart updates both.
4. Ask Copilot to "open the demo launcher" in any session. If that doesn't work, ask from a session in the repo-setup-scripts project.

`setup.sh` fast-forwards an existing `~/repos/repo-setup-scripts` checkout (`git pull --ff-only`) and runs the repo's `.github/extensions/demo-launcher/install.sh` when present. That writes a loader to `${COPILOT_HOME:-~/.copilot}/extensions/demo-launcher/extension.mjs` that imports the launcher from the checkout, so later pulls update it.

### Windows: repo-setup-scripts project

`install.sh` is macOS/Linux only, so on Windows the canvas loads from the repo-setup-scripts project. `setup.ps1` clones it to `$HOME\repos\repo-setup-scripts`.

1. Open the GitHub Copilot app and sign in with the booth/demo account.
2. Add the existing local folder `$HOME\repos\repo-setup-scripts` as a project. Don't clone it again, so the update steps below keep the project current.
3. Start a session in that project and ask Copilot to "open the demo launcher".

#### Install or update the canvas on Windows

Before each booth day, update the checkout, then restart the GitHub Copilot app (or reload extensions) so it loads the new launcher. From an up-to-date clone of this repo, in PowerShell:

```powershell
git -C "$HOME\repos\machine-setup" pull
cd "$HOME\repos\machine-setup"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-demo-launcher.ps1
```

Re-running is safe. It checks for `git` and `gh`, clones `octobooth-demos/repo-setup-scripts` to `$HOME\repos\repo-setup-scripts` if it's missing (this needs a logged-in GitHub CLI; see [GitHub CLI login](#github-cli-login)), or, after checking that its `origin` is that repo, fast-forwards it with `git pull --ff-only`. It exits with an error and lists what failed if the clone or pull doesn't work. If a folder with that name exists but isn't a git checkout, the script stops; move the folder aside and re-run.

To update by hand instead:

```powershell
git -C "$HOME\repos\repo-setup-scripts" remote get-url origin   # should be octobooth-demos/repo-setup-scripts
git -C "$HOME\repos\repo-setup-scripts" pull --ff-only
```

Then restart the GitHub Copilot app.

> [!WARNING]
> Copilot reads the files in a project, so only add the `octobooth-demos/repo-setup-scripts` checkout as a project, and don't add other or unknown repos on booth machines. `install-demo-launcher.ps1` only uses that repo, even if `config.json` lists a different one. It also refuses to update a checkout whose `origin` points anywhere else. Updates come straight from that repo's default branch, so review changes there (for example with `git -C "$HOME\repos\repo-setup-scripts" log --oneline -5`) before a booth day.

### Install or update on a macOS or Linux machine that's already set up

Run it from an up-to-date clone, because an old copy installs with old logic:

```bash
git -C ~/repos/machine-setup pull
cd ~/repos/machine-setup
bash install-demo-launcher.sh
```

It's safe to re-run. It:

1. Checks for `gh`, `git`, and `jq` (`brew install gh jq`) and that the GitHub CLI is logged in. Logging in is interactive, so if it isn't, the script prints the `gh auth login` command to run and stops. It also warns if the login is missing the `codespace`/`delete_repo`/`project`/`workflow` scopes (`gh auth refresh -h github.com -s codespace,delete_repo,project,workflow`).
2. Clones `octobooth-demos/repo-setup-scripts` to `~/repos/repo-setup-scripts`, or pulls it if it's already there.
3. Runs `install.sh` to (re)write the loader.

Then restart the GitHub Copilot app (or reload extensions) and ask Copilot to "open the demo launcher" in any session to check it works. To remove it, run `bash install-demo-launcher.sh --uninstall`.

### Two Demo Launchers show up

On Copilot app builds with staff features, the app-wide canvas picker can list two "Demo Launcher" canvases: the installed loader (`user:demo-launcher`) and the project's copy (`project:demo-launcher`). Booth machines run without staff features, so this shouldn't happen there. Both are the same launcher and either one works. To hide one, remove `repo-setup-scripts` from the app's projects and restart the app, but keep the clone in `~/repos/repo-setup-scripts` because the loader imports from it.

For more on the Demo Launcher itself, see the [repo-setup-scripts quick start](https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine).

## Development and Testing

The GitHub Actions workflow validates syntax, linting, configuration shape, and unit tests for both scripts without executing either installer end to end.

### Local checks

#### Bash

```bash
shellcheck -x setup.sh install-demo-launcher.sh
bash -n setup.sh && bash -n install-demo-launcher.sh
bats tests/bash
```

#### PowerShell

```powershell
Invoke-ScriptAnalyzer -Path .\setup.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\install-demo-launcher.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests\powershell
```

The setup and Demo Launcher scripts guard their main entry point so they can be sourced or dot-sourced safely from tests without triggering installs.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.