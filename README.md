# Booth Machine Setup

_Last updated by [@filmgirl](https://github.com/filmgirl) on November 5, 2026_

![CI](https://github.com/octobooth-demos/machine-setup/actions/workflows/ci.yml/badge.svg)

> [!IMPORTANT]
> **Setting up or running a booth? Start with the [booth playbook](docs/booth-playbook.md).** It walks through the whole event step by step:
>
> 1. [Before the event: set up each booth machine](docs/booth-playbook.md#part-1-before-the-event-set-up-each-booth-machine) (macOS and Windows, with the commands to type)
> 2. [During the event: run demos](docs/booth-playbook.md#part-2-during-the-event-run-demos)
> 3. [After the event: clean up and reset](docs/booth-playbook.md#part-3-after-the-event-clean-up-and-reset) the booth accounts and machines
>
> Cleaning up demo repos any time: [Clean up demo repos](docs/booth-playbook.md#clean-up-demo-repos). Deleting every repo in the booth accounts (org admins): [How to clean all Octobooth repos](docs/booth-playbook.md#how-to-clean-all-octobooth-repos).

This repository contains setup scripts for configuring booth machines. The scripts install and configure the GitHub Copilot app, Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, Node.js, PowerShell 7 (Windows), iTerm2 (macOS), and related tooling from a shared `config.json`.

## Features

- Installs the GitHub Copilot app (`github-copilot-app` cask / `GitHub.CopilotApp` winget package) and Copilot CLI.
- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI, logs it in with the scopes the booth demos need, and installs a suite of GitHub CLI extensions.
- Installs Node.js LTS on macOS (via `nvm`) and Windows (via `winget`).
- Installs PowerShell 7 (`Microsoft.PowerShell` winget package) on Windows alongside the built-in Windows PowerShell 5.1, so later steps and scripts can call `pwsh`.
- Installs iTerm2 on macOS, sets its default profile to follow the macOS appearance (GitHub Light Default in light mode, GitHub Dark Default in dark mode) with Monaspace Neon Frozen 14 (ligatures on, thin strokes off), and switches it to the Minimal theme.
- Installs the SF Mono, Monaspace (including the Frozen variants), and Mona Sans fonts on macOS.
- Adds Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC to the macOS Dock and hides suggested and recent apps there.
- Pins VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC to the Windows taskbar.
- Makes Google Chrome the default browser on macOS (via `defaultbrowser`), including when Chrome was already installed.
- Configures VLC media player settings.
- Registers shared MCP servers for Copilot CLI: the remote (HTTP) servers in `config.json`, plus a [prebuilt Playwright MCP server](#playwright-mcp-server) downloaded from this repo's releases, because booth machines can't reach the npm registry. Setup also removes the `npx @playwright/mcp` entry that earlier versions registered, since it hangs without npm and leaves Copilot sessions stuck at "busy". A `playwright` entry you set up yourself is left alone.
- Adds [Copilot booth instructions](#copilot-booth-instructions) that keep Copilot from installing npm or Python packages, which booth networks block.
- Clones the demo repos into `~/repos` and installs the Demo Launcher canvas for every Copilot session. `install-demo-launcher.sh` (macOS/Linux) and `install-demo-launcher.ps1` (Windows) do just that step on a machine that is already set up (see [Demo Launcher](#demo-launcher)). Both can pin the demo scripts to a tested [release](#using-a-release).

## Configuration

`config.json` is the single source of truth for both setup scripts.

- `shared`: settings used by both platforms, including VS Code extensions, GitHub CLI extensions, GitHub CLI auth scopes, VLC settings, MCP servers, and repos to clone.
- `mac`: Homebrew packages, editor binaries, iTerm2 theme settings, the Monaspace Frozen font version, Dock apps, and post-install apps for `setup.sh`.
- `windows`: `winget` packages, editor commands, taskbar pins, and post-install apps for `setup.ps1`.

`mac.iterm2` controls iTerm2's look. `light` and `dark` each have a `color_scheme_file` (stored in [`iterm2/`](iterm2/README.md)) and a `color_preset` name. `setup.sh` adds both schemes to iTerm2's Color Presets. It turns on **Use separate colors for light and dark mode** in the default profile and applies the light scheme to its light-mode colors and the dark scheme to its dark-mode colors, so iTerm2 switches with the macOS appearance. The plain colors are set to the dark scheme for older iTerm2 versions without that option. It also applies `font` (a PostScript name and size, such as `MonaspaceNeonFrozen-Regular 14`) to the default profile. If iTerm2 has never been opened, it creates that "Default" profile. `theme` sets **Settings > Appearance > General > Theme** through the `TabStyleWithAutomaticOption` preference. It can be `regular` (4), `minimal` (5), `compact` (6), `light` (0), `dark` (1), `light-high-contrast` (2), or `dark-high-contrast` (3), using the values from iTerm2's `iTermPreferencesTabStyle`. `ligatures` sets the profile's **Use ligatures** option (Settings > Profiles > Text). Monaspace's texture healing and coding ligatures only show when it's on, which iTerm2 doesn't do by default. `thin_strokes` sets **Use thin strokes**: `never` (0), `retina-dark-backgrounds-only` (1), `dark-backgrounds-only` (2), `always` (3), or `retina-only` (4, iTerm2's default), from iTerm2's `iTermThinStrokesSetting`. Quit iTerm2 before running setup, because iTerm2 overwrites preference changes when it quits. Once these settings are applied, later runs leave iTerm2 alone. They apply again if you change either `color_preset`, `font`, `theme`, `ligatures`, or `thin_strokes` in `config.json`, or run with `FORCE_REINSTALL=true`. Machines set up before a setting was tracked get it on their next run.

Fonts: the `font-monaspace` cask installs Monaspace, and `font-mona-sans` installs Mona Sans. The `font-sf-mono` cask installs SF Mono from Apple and asks for an admin password. The cask doesn't include Monaspace's "Frozen" fonts (such as Monaspace Neon Frozen, the iTerm2 font). So `setup.sh` downloads `monaspace-frozen-v<version>.zip` from the [githubnext/monaspace release](https://github.com/githubnext/monaspace/releases) pinned in `mac.monaspace_frozen_version`, and copies its `.ttf` files to `~/Library/Fonts`. Later runs skip this step unless the pinned version changes or `FORCE_REINSTALL=true`.

`mac.dock_apps` lists app names (the `.app` bundle in `/Applications`, without `.app`) that `setup.sh` adds to the Dock with the `dockutil` formula. Apps already in the Dock are skipped, even with `FORCE_REINSTALL=true`, so reruns don't add duplicates. This includes Chrome when it was installed outside Homebrew and already pinned. Setup also turns off **Show suggested and recent apps in Dock** and restarts the Dock once if anything changed. It doesn't remove anything, so Downloads and Trash stay.

`windows.taskbar_pins` lists apps that `setup.ps1` pins to the Windows taskbar, in left-to-right order. Each `app_id` is the **AppID** shown by `Get-StartApps`. IDs that contain `!` are packaged apps (such as Windows Terminal), and the rest are desktop apps. A desktop app that doesn't set its own AppID, such as VLC, is listed by its path, with a known-folder GUID in place of the folder: `{6D809377-6AF0-444B-8957-A3773F02200E}` is Program Files. To check an ID on a set-up machine, run `Get-StartApps | Where-Object Name -like '*VLC*'`. Windows has no API to pin apps directly, so setup uses Microsoft's [taskbar layout policy](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps). It writes a layout XML to `%LOCALAPPDATA%\machine-setup\TaskbarLayout.xml`, points the current user's `StartLayoutFile` policy (`HKCU\Software\Policies\Microsoft\Windows\Explorer`) at it, and restarts Explorer so the pins show up. This needs an elevated (Administrator) prompt. Without one, setup skips the pins with a warning and lists them in the final summary instead of failing. Policy pins appear after the default and manually pinned apps, and Windows may pin them again if they're unpinned. On Windows 10, the policy also locks the Start tiles. Later runs skip this step unless the list changes or `FORCE_REINSTALL` is `"true"`.

`shared.gh_auth_scopes` lists the extra scopes the GitHub CLI login needs: `codespace` (the Tailspin Toys demo creates a Codespace), `delete_repo` (the Demo Launcher's cleanup deletes demo repos), `project` (the Copilot Airways demo creates a GitHub Project, and cleanup deletes it), and `workflow` (demo repos include GitHub Actions workflows, and GitHub rejects pushes that add or change `.github/workflows` files without it). A new login requests them, and an existing login missing any of them is upgraded with `gh auth refresh`, which opens a browser to approve. Both scripts ignore `GH_TOKEN`/`GITHUB_TOKEN` for these steps so the stored login is the one updated. To do it by hand, see [GitHub CLI login](#github-cli-login).

`pwa_sites` currently remains in the schema for future use, but PWA setup is intentionally disabled in both scripts until the booth workflow needs it again.

## Setup Instructions

These are the same steps as [Part 1 of the booth playbook](docs/booth-playbook.md#part-1-before-the-event-set-up-each-booth-machine), which also covers booth day and cleanup. This section adds extra detail on re-running setup and on individual steps.

Clone this repo so you can update the scripts before each run. A ZIP download never updates, so an old copy keeps running old scripts. Both platforms then share the [GitHub CLI login](#github-cli-login) checks and [Check that the machine is ready](#check-that-the-machine-is-ready) below.

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

3. Put the scripts on the [`v1` release](https://github.com/octobooth-demos/machine-setup/releases) the booth uses (see [Using a release](#using-a-release)). Do this again before each booth day, and before re-running `setup.sh` or `install-demo-launcher.sh`:

   ```bash
   git -C ~/repos/machine-setup fetch --tags --force
   git -C ~/repos/machine-setup checkout --detach v1
   ```

   Developers testing changes can track `main` instead: run `git -C ~/repos/machine-setup checkout main`, then `git -C ~/repos/machine-setup pull` (see [Using a release](#using-a-release) for switching the Demo Launcher back too).

**Fallback for a new Mac without Git:** [download the ZIP](https://github.com/octobooth-demos/machine-setup/archive/refs/heads/main.zip) and run commands from the extracted `machine-setup-main` folder. Keep all files together, because the scripts need `config.json` and `setup.sh` also needs the `iterm2/` folder. Setup installs the Xcode Command Line Tools and Git, so switch to a clone afterward. If you stay on the ZIP, download it again before re-running any script.

#### 2. Run setup

1. Quit iTerm2 if it's open. iTerm2 overwrites setup's changes to its settings when it quits.
2. If the GitHub CLI is already installed (for example, you're re-running setup), check which account it's logged in to:

   ```bash
   gh auth status
   ```

   If it shows an account other than this machine's booth account, log it out with `gh auth logout -h github.com`. Setup only logs in when the GitHub CLI isn't logged in, so it would otherwise keep the wrong account. On a new Mac, `gh` isn't installed yet; skip this.
3. Go to the repo (or the extracted `machine-setup-main` folder if you used the ZIP) and run the setup script:

   ```bash
   cd ~/repos/machine-setup
   bash setup.sh --ref v1
   ```

   `--ref v1` (or `BOOTH_RELEASE=v1`) puts `~/repos/repo-setup-scripts` on the same release. Leave it off to track `main`.

4. Answer the prompts as they come up:
   1. **Xcode Command Line Tools.** `git` and Homebrew need them. If they're missing, the installer opens: click **Install**, and the script waits until it finishes (up to 30 minutes; set `XCODE_CLT_TIMEOUT` in seconds to change this). If the install fails or times out, run `xcode-select --install`, finish the installer, and run `bash setup.sh --ref v1` again.
   2. **Your Mac password.** The Homebrew installer and the SF Mono font ask for it. Type it and press Enter (nothing shows while you type). If the Homebrew installer asks you to press RETURN to continue, press Enter.
   3. **GitHub.com in Chrome.** The script opens Chrome and pauses. Sign in to GitHub.com as **the booth account**, then press Enter.
   4. **Default browser.** If Chrome isn't the default browser yet, macOS asks whether to change it. Click **Use “Google Chrome”**, then press Enter. This also works if Chrome was installed before setup ran. If Chrome is already the default, the script skips this step.
   5. **GitHub CLI login.** The GitHub CLI shows a one-time code. Press Enter to open the browser, enter the code, and approve the login (or scope upgrade) while signed in as the booth account. See [GitHub CLI login](#github-cli-login).
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `bash setup.sh --ref v1` again; finished steps are skipped.
6. Setup adds Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC to the Dock. It also adds the [Copilot booth instructions](#copilot-booth-instructions).
7. Store booth videos in `$HOME/Videos` and open them from VLC in the Dock.

#### 3. Set up the Demo Launcher

Setup already cloned `~/repos/repo-setup-scripts` and installed the Demo Launcher for every Copilot session.

1. Open the GitHub Copilot app and sign in with the booth account.
2. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Use the local folder, not the repo's URL: adding it by URL makes the app clone a second copy, and only `~/repos/repo-setup-scripts` is updated by `install-demo-launcher.sh` and used by the installed Demo Launcher.
3. Start a session in the repo-setup-scripts project, choosing **Current checkout** (not **New worktree**). Then right-click that session in the Copilot app and choose **Pin** so it's easy to find on booth day.
4. Ask Copilot to "open the demo launcher" in any chat or session.

More detail: [Demo Launcher](#demo-launcher).

#### 4. Add Chrome bookmarks

In Chrome, still signed in to GitHub.com as the booth account, open each page below and press **Cmd+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth-demos`: the `octobooth-demos` org.

On booth day, you'll also bookmark the security demo repos (AI Security and Security Supply Chain (v4)). You can't add them during setup: they're created within 72 hours of use. Create each demo once, on one machine, then open that same repo in Chrome on every booth machine and press **Cmd+D**. See [Create the security demos ahead of time](docs/booth-playbook.md#create-the-security-demos-ahead-of-time).

#### 5. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 6. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

#### Re-running on a Mac that's already set up

You can run `bash setup.sh --ref v1` again on a configured Mac without resetting it. Keep the release on reruns: without it, setup moves `repo-setup-scripts` off the release and back to `main`. Steps that are already done are skipped, and changed settings in `config.json` are applied:

- Homebrew packages that are already installed are left alone, and so are Chrome and the GitHub Copilot app when they're already in `/Applications`.
- The Monaspace Frozen fonts are skipped when the pinned version is already installed.
- iTerm2 is skipped when its light and dark color presets, font, theme, ligatures, and thin strokes already match `config.json`.
- Dock apps that are already in the Dock are skipped, and Chrome is skipped when it's already the default browser.
- The GitHub CLI login only asks for missing scopes, and repos already in `~/repos` aren't cloned again.
- The GitHub.com sign-in pause in Chrome still runs. Press Enter if you're already signed in.

To redo everything, run `FORCE_REINSTALL=true bash setup.sh --ref v1`. To redo just one step, clear its marker and rerun `bash setup.sh --ref v1`:

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

Right-click **Start** and choose **Terminal (Admin)** (Windows 11) or **Windows PowerShell (Admin)** (Windows 10), then approve the User Account Control prompt. Run every command below in this window. If `setup.ps1` isn't run as an administrator, it shows a warning and pauses: press Enter to continue anyway, or Ctrl+C to stop and reopen **Terminal (Admin)**. Without admin, setup skips the taskbar pins and lists them in the final summary, and some installs can fail.

#### 2. Make sure winget works

`winget` comes with the **App Installer** package from Microsoft Store. On a new machine it can take a few minutes after first sign-in to register. Check it:

```powershell
winget --version
```

If the command isn't found, open Microsoft Store, search for **App Installer**, click **Update** (or **Get**), and open a new administrator window. The first `winget` command may ask you to accept the source agreements; type `Y`.

#### 3. Install Git and get the setup scripts

`setup.ps1` installs Git too, but you need it once now to clone the machine-setup repo:

```powershell
winget install --id Git.Git -e --source winget --accept-source-agreements --accept-package-agreements
```

Close the window and open a new administrator PowerShell so `git` is on your `PATH`, then clone:

```powershell
git clone https://github.com/octobooth-demos/machine-setup.git "$HOME\repos\machine-setup"
cd "$HOME\repos\machine-setup"
```

Put the scripts on the [`v1` release](https://github.com/octobooth-demos/machine-setup/releases) the booth uses (see [Using a release](#using-a-release)). Do this again before each booth day, and before re-running `setup.ps1` or `install-demo-launcher.ps1`:

```powershell
git -C "$HOME\repos\machine-setup" fetch --tags --force
git -C "$HOME\repos\machine-setup" checkout --detach v1
```

Developers testing changes can track `main` instead: run `git -C "$HOME\repos\machine-setup" checkout main`, then `git -C "$HOME\repos\machine-setup" pull` (see [Using a release](#using-a-release) for switching the Demo Launcher back too).

#### 4. Allow the script to run

Windows blocks PowerShell scripts by default. Allow them for this window only (this doesn't change the machine's policy):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

#### 5. Run setup

1. If the GitHub CLI is already installed (for example, you're re-running setup), check which account it's logged in to with `gh auth status`. If it shows an account other than this machine's booth account, log it out with `gh auth logout -h github.com`. Setup only logs in when the GitHub CLI isn't logged in, so it would otherwise keep the wrong account. On a new machine, `gh` isn't installed yet; skip this.
2. Run the setup script:

   ```powershell
   .\setup.ps1 -Ref v1
   ```

   `-Ref v1` (or `$env:BOOTH_RELEASE = "v1"`) puts `$HOME\repos\repo-setup-scripts` on the same release. Leave it off to track `main`.

3. Answer the prompts as they come up:
   1. **Installs.** `winget` installs everything in `windows.packages` in [`config.json`](config.json). PowerShell 7 (`Microsoft.PowerShell`) is installed first, followed by VS Code, VS Code Insiders, Windows Terminal, Git, GitHub CLI, Node.js LTS, Python, VLC, Copilot CLI, the GitHub Copilot app, and GitHub Desktop. This takes a while, and some installers briefly show their own windows. Setup then configures VLC and pins VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC to the taskbar. The taskbar briefly disappears while Explorer restarts.
   2. **GitHub.com in Edge.** The script opens Microsoft Edge and pauses. Sign in to GitHub.com as **the booth account**, then press Enter.
   3. **GitHub CLI login.** The GitHub CLI shows a one-time code. Press Enter to open the browser, enter the code, and approve the login (or scope upgrade) while signed in as the booth account. See [GitHub CLI login](#github-cli-login).
4. Setup then installs GitHub CLI extensions, clones the demo repos into `$HOME\repos`, installs the Demo Launcher for every Copilot chat, adds the [Copilot booth instructions](#copilot-booth-instructions), installs VS Code extensions and the theme, and registers MCP servers for Copilot CLI.
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `.\setup.ps1 -Ref v1` again; finished steps and `winget` packages that are already installed are skipped. For `winget` errors, see [Troubleshooting Windows package installs](#troubleshooting-windows-package-installs).

Set `$env:NONINTERACTIVE = "true"` before running `setup.ps1` to skip GitHub browser login, CLI login, scope refresh, and the pause when setup isn't running as an administrator. Existing CLI credentials (including `GH_TOKEN` or `GITHUB_TOKEN`) are used to install extensions and clone repositories. Without usable credentials, those steps are deferred with warnings; authenticate with `gh auth login` and rerun setup to complete them. Set `$env:FORCE_REINSTALL = "true"` to redo steps that are normally skipped on reruns, including `winget` installs of packages that are already installed. See [Re-running on a Windows machine that's already set up](#re-running-on-a-windows-machine-thats-already-set-up).

#### 6. After setup

- Close the window and open a new terminal so it picks up the updated `PATH`. Check PowerShell 7 with `pwsh --version`. Windows Terminal adds a **PowerShell** profile for it, but its default profile may still be **Windows PowerShell** 5.1, which stays installed alongside it (check with `$PSVersionTable.PSVersion`). The scripts work in either, but use PowerShell 7 from here on: open the **PowerShell** profile, or make it the default in Windows Terminal under **Settings** > **Startup** > **Default profile**.
- Store booth videos in `C:\Users\<YourUsername>\Videos` and open them from VLC on the taskbar.
- To update the Demo Launcher later, run `.\install-demo-launcher.ps1 -Ref v1` (see [Install or update the launcher on Windows](#install-or-update-the-launcher-on-windows)).
- To add the taskbar pins on a machine that ran setup before they existed, or after a run from a window that wasn't elevated, update the scripts to `v1` (see [step 3](#3-install-git-and-get-the-setup-scripts)) and run `.\setup.ps1 -Ref v1` again from **Terminal (Admin)**. You can also run only that step from an Administrator prompt in the repo folder:

  ```powershell
  . .\setup.ps1; Import-Config; Set-TaskbarPins
  ```

  To check it, look for the five icons on the taskbar, and run `Get-ItemProperty HKCU:\Software\Policies\Microsoft\Windows\Explorer` to see `StartLayoutFile` and `LockedStartLayout`. To apply it again after editing the pins, run `$script:ForceReinstall = $true; Set-TaskbarPins` in the same window. To undo it, run `Remove-ItemProperty HKCU:\Software\Policies\Microsoft\Windows\Explorer -Name StartLayoutFile, LockedStartLayout`, restart Explorer, and unpin the icons.

#### 7. Set up the Demo Launcher

Setup already cloned `$HOME\repos\repo-setup-scripts` and installed the Demo Launcher for every Copilot chat.

1. Open the GitHub Copilot app and sign in with the booth account. If it was already open, fully quit it first (right-click its icon in the system tray and choose **Quit**), so it loads the launcher.
2. Ask Copilot to "open the demo launcher" in any chat.
3. Optional, for quick access on booth day: add the existing local folder `$HOME\repos\repo-setup-scripts` as a project (use the local folder, not the repo's URL, which clones a second copy), start a session in it with **Current checkout** (not **New worktree**), then right-click that session and choose **Pin**.

More detail: [Windows: installed loader and project](#windows-installed-loader-and-project).

#### 8. Add Edge favorites

Setup signed in to GitHub.com in Microsoft Edge, and Chrome isn't installed on Windows, so use Edge. Edge calls bookmarks favorites. In Edge, still signed in to GitHub.com as the booth account, open each page below and press **Ctrl+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth-demos`: the `octobooth-demos` org.

On booth day, you'll also bookmark the security demo repos (AI Security and Security Supply Chain (v4)). You can't add them during setup: they're created within 72 hours of use. Create each demo once, on one machine, then open that same repo in Edge on every booth machine and press **Ctrl+D**. See [Create the security demos ahead of time](docs/booth-playbook.md#create-the-security-demos-ahead-of-time).

#### 9. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 10. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

#### Re-running on a Windows machine that's already set up

Run `.\setup.ps1 -Ref v1` again from **Terminal (Admin)**. You don't need to reset the machine first. Keep the release on reruns: without it, setup moves `repo-setup-scripts` off the release and back to `main`. Steps that are already done are skipped:

- Before installing each package in `windows.packages`, setup runs `winget list --id <id> -e --source winget`. If the package is found, setup logs `Already installed: <id>` and moves on without running `winget install`. Like Homebrew on macOS, reruns don't upgrade installed packages. To update one, run `winget upgrade --id <id> -e --source winget`. If `winget list` returns an unexpected error, setup runs `winget install` as before.
- VLC settings are skipped once `%APPDATA%\vlc\vlcrc` has setup's marker. Taskbar pins are skipped when the layout and policy already match `config.json`.
- VS Code and VS Code Insiders extensions, and GitHub CLI extensions, that are already installed are skipped. Repos already in `$HOME\repos` aren't cloned again.
- The GitHub CLI login only asks for missing scopes. The GitHub.com sign-in pause in Edge still runs, so press Enter if you're already signed in.

If you run setup from a window that isn't elevated, it warns and pauses at the start. Press Enter to continue anyway. Setup then skips the taskbar pins instead of failing with `Requested registry access is not allowed`, and its final summary lists them under **Skipped because setup wasn't run as Administrator**. Rerun from **Terminal (Admin)** to finish them.

To redo everything, including reinstalling packages, run:

```powershell
$env:FORCE_REINSTALL = "true"; .\setup.ps1 -Ref v1; Remove-Item Env:\FORCE_REINSTALL
```

### Check that the machine is ready

Check each item on every booth machine. `N` is this machine's booth account number.

1. **GitHub CLI.** Run `gh auth status`. It should show `octobooth-N` as the active account, with `codespace`, `delete_repo`, `project`, and `workflow` in its token scopes. If not, follow [GitHub CLI login](#github-cli-login). If `GH_TOKEN` or `GITHUB_TOKEN` is set, unset it.
2. **Demo repos.** `~/repos` (`$HOME\repos` on Windows) contains `repo-setup-scripts`, `tailspin-toys`, and `security-octo-supply` (the `repos_to_clone` list in [`config.json`](config.json)).
3. **Copilot app.** It's signed in as `octobooth-N`, and "open the demo launcher" opens the launcher from a new chat. If you added the optional repo-setup-scripts project, it's from the local `~/repos/repo-setup-scripts` folder (`$HOME\repos\repo-setup-scripts` on Windows) and its pinned session is a **Current checkout** one.
4. **VS Code and VS Code Insiders.** In each, **Accounts** shows `octobooth-N`, and GitHub Copilot is signed in and active.
5. **Bookmarks.** The browser (Chrome on macOS, Edge on Windows) has bookmarks for `https://github.com/octobooth-N` and `https://github.com/octobooth-demos`.
6. **Dock or taskbar.** On macOS, the Dock has Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC. On Windows, the taskbar has VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC. Machines set up with an older version of the setup scripts may still have a `load-demos.sh` or `load-demos.ps1` script on the Desktop. Setup no longer creates it, and nothing uses it, so you can delete it.
7. **Weekly cleanup.** In a browser signed in as the booth account, open `https://github.com/octobooth-N/demo-cleanup/actions`. It should have a **Weekly demo cleanup** workflow with green runs. If the repo is missing or runs fail, ask an org admin to [set up the weekly cleanup](docs/booth-playbook.md#set-up-or-repair-the-weekly-cleanup) for that account.

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

### Copilot booth instructions

Booth networks block npm and Python package downloads (`registry.npmjs.org` and `files.pythonhosted.org`), so `npm install`, `npx`, `create-*` scaffolders, and `pip install` fail or hang in local Copilot sessions. Setup adds [`copilot/booth-instructions.md`](copilot/booth-instructions.md) to the booth account's user-level Copilot instructions, which every local Copilot session reads:

- macOS: `~/.copilot/copilot-instructions.md`
- Windows: `$HOME\.copilot\copilot-instructions.md`

(`$COPILOT_HOME/copilot-instructions.md` if `COPILOT_HOME` is set.) They tell Copilot to build apps with plain HTML, CSS, and JavaScript, Node.js built-ins, or the Python standard library, and to send framework requests to booth staff, who can start a Cloud session (see the [booth playbook](docs/booth-playbook.md#part-2-during-the-event-run-demos)).

Setup only manages the part of the file between the `BEGIN machine-setup booth instructions` and `END machine-setup booth instructions` lines, and replaces it on every run; anything else in the file is kept. `install-demo-launcher.sh` and `install-demo-launcher.ps1` refresh it too, so the booth-day update picks up changes. To change the text, edit `copilot/booth-instructions.md`. To remove it, delete the lines from `BEGIN` to `END`. If you run setup on a machine that isn't a booth machine, remove the block afterwards. To refresh only this step:

```bash
source setup.sh && install_booth_instructions
```

```powershell
. .\setup.ps1; Install-BoothInstruction
```

## Using a release

`main` of this repo and of [`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) change often, and booth machines would otherwise pick up whatever is on `main` the night before an event. Booth machines use a tested release instead. **Booth machines use `v1`** (first released as `v1.0.0`). See the release notes for [machine-setup](https://github.com/octobooth-demos/machine-setup/releases) and [repo-setup-scripts](https://github.com/octobooth-demos/repo-setup-scripts/releases).

- Each tested release is tagged `vX.Y.Z` (for example `v1.0.0`, `v1.1.0`), with the same version on both repos. A release is tagged only after the setup has been tested on a booth Mac and a Windows machine.
- The major tag (`v1`) moves to the latest tested `v1.x.y`, like GitHub Actions' major tags. Use it on booth machines. Use a full tag (`v1.1.0`) to pin an exact version.
- The major version (`v2`) changes only for breaking changes, such as new manual setup steps, changed paths, or new required `gh` scopes.

Pin both repos to the same release: check out the tag in `machine-setup` (a detached HEAD), then pass it to setup or the launcher install with `--ref` (`-Ref` on Windows) or the `BOOTH_RELEASE` environment variable. The scripts then fetch tags in `repo-setup-scripts` with `--force` (so a moved `v1` follows the remote) and check out the tag there too. They stop with an error, without changing the checkout, if the tag doesn't exist on GitHub (a tag that was withdrawn there is also removed locally) or the checkout has local changes (stash or discard them, then re-run).

Always move to a new release with `install-demo-launcher` (or setup) and the release, not with `git checkout` in `repo-setup-scripts` alone: the scripts also rewrite the installed loader. Then restart the GitHub Copilot app (on Windows, fully quit it from the system tray) so it loads the launcher from that release.

To set up or update a booth machine (before each booth day), check out `v1` and run the launcher install (or setup) with it, then fully restart the GitHub Copilot app:

On macOS:

```bash
git -C ~/repos/machine-setup fetch --tags --force
git -C ~/repos/machine-setup checkout --detach v1
cd ~/repos/machine-setup
bash install-demo-launcher.sh --ref v1     # or for a full setup: bash setup.sh --ref v1
```

On Windows, in PowerShell:

```powershell
git -C "$HOME\repos\machine-setup" fetch --tags --force
git -C "$HOME\repos\machine-setup" checkout --detach v1
cd "$HOME\repos\machine-setup"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-demo-launcher.ps1 -Ref v1        # or for a full setup, from Terminal (Admin): .\setup.ps1 -Ref v1
```

Developers testing changes before a release can track `main` instead: check out `main` in `machine-setup` and run the launcher install without a release. It switches `repo-setup-scripts` back to its default branch (saying so), then pulls:

```bash
git -C ~/repos/machine-setup checkout main
git -C ~/repos/machine-setup pull
cd ~/repos/machine-setup
bash install-demo-launcher.sh
```

```powershell
git -C "$HOME\repos\machine-setup" checkout main
git -C "$HOME\repos\machine-setup" pull
cd "$HOME\repos\machine-setup"
.\install-demo-launcher.ps1
```

`setup.sh` and `setup.ps1` also switch a pinned checkout back to `main` when run without a release. If you set `BOOTH_RELEASE`, clear it first, or the scripts keep using that release: `unset BOOTH_RELEASE` on macOS, or `Remove-Item Env:BOOTH_RELEASE` on Windows (and, if you saved it as a user variable, `[Environment]::SetEnvironmentVariable("BOOTH_RELEASE", $null, "User")`).

To cut a release, after testing on a booth Mac and a Windows machine, tag the same commit you tested in **both** repos and move the major tag:

```bash
git tag v1.1.0 && git push origin v1.1.0
git tag -f v1 v1.1.0 && git push -f origin v1
```

## Demo Launcher

[`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) (cloned to `~/repos/repo-setup-scripts`) ships a **Demo Launcher** canvas for the GitHub Copilot app. It creates booth demos in the background with `create-repo.sh`/`create-repo.ps1`, opens sessions for them in the Copilot app, and cleans up old demo repos (see [From the Demo Launcher](docs/booth-playbook.md#from-the-demo-launcher)). For using it on booth day, see [During the event](docs/booth-playbook.md#part-2-during-the-event-run-demos) in the booth playbook.

> [!IMPORTANT]
> On booth machines, install the launcher only with this repo's scripts: `setup.sh` or `install-demo-launcher.sh` on macOS/Linux, `setup.ps1` or `install-demo-launcher.ps1` on Windows. Don't also install the canvas from a URL in the Copilot app. The launcher reads its demos and `create-repo` scripts from a local clone of repo-setup-scripts, so a clone is needed either way. The scripts clone or update `~/repos/repo-setup-scripts` and write the loader in the same automatic step during machine setup, with no manual per-machine step. Re-running `install-demo-launcher.sh` or `install-demo-launcher.ps1` repairs or updates both (`setup.sh` keeps an existing loader unless `FORCE_REINSTALL=true`). A URL install is named `demo-launcher-loader` even if you ask for `demo-launcher`, so alongside the script's loader you get two "Demo Launcher" canvases labeled Personal (see [Two Demo Launchers show up](#two-demo-launchers-show-up)). The URL install is for running the demos outside the booth; see [Run in your own org](https://github.com/octobooth-demos/repo-setup-scripts/blob/main/docs/run-in-your-own-org.md).

> [!IMPORTANT]
> Pin a **Current checkout** session, not a **New worktree** one. A worktree session works from its own copy under `copilot-worktrees`, so pulls and `install-demo-launcher` never update it and it keeps loading the old launcher. If the pinned session is a worktree, archive it and start a new **Current checkout** session.

### macOS (and Linux): installed loader and project

On booth machines, do both. The loader that `install.sh` writes makes the launcher available in any chat or session (confirmed on regular Copilot app builds). The project is a convenience: it gives you a session, or the canvas, to pin for quick access on booth day.

1. On macOS, run `setup.sh`. On Linux, or a Mac that's already set up, run `install-demo-launcher.sh` (see below). Either one clones the repo to `~/repos/repo-setup-scripts` and runs its `install.sh`.
2. Open the GitHub Copilot app and sign in with the booth/demo account.
3. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Don't add it by URL or clone it again, which makes a second copy: then the loader and the project use the same checkout, and one `bash install-demo-launcher.sh --ref v1` plus an app restart updates both.
4. Start a session in that project with **Current checkout** (not **New worktree**), right-click the session in the Copilot app, and choose **Pin**.
5. Ask Copilot to "open the demo launcher" in any chat or session.

`setup.sh` fast-forwards an existing `~/repos/repo-setup-scripts` checkout (`git pull --ff-only`), or checks out a release with `--ref` (see [Using a release](#using-a-release)), and runs the repo's `.github/extensions/demo-launcher/install.sh` when present. That writes a loader to `${COPILOT_HOME:-~/.copilot}/extensions/demo-launcher/extension.mjs` that imports the launcher from the checkout, so later pulls update it.

### Windows: installed loader and project

On Windows, `setup.ps1` and `install-demo-launcher.ps1` write the loader themselves (`install.sh` is macOS/Linux only), so the launcher opens from any chat. The project is optional: it gives you a session to pin for quick access on booth day.

1. Run `setup.ps1`, or on a machine that's already set up, `install-demo-launcher.ps1` (see below). Neither needs an Administrator prompt for this step.
2. Fully quit the GitHub Copilot app (right-click its icon in the system tray and choose **Quit**), reopen it, and sign in with the booth/demo account.
3. Ask Copilot to "open the demo launcher" in any chat.
4. Optional: add the existing local folder `$HOME\repos\repo-setup-scripts` as a project. Don't add it by URL or clone it again, which makes a second copy. Start a session in it with **Current checkout** (not **New worktree**), right-click the session, and choose **Pin**.

The loader is `$env:COPILOT_HOME\extensions\demo-launcher\extension.mjs` (`$HOME\.copilot\extensions\demo-launcher\extension.mjs` by default). It imports the launcher from `$HOME\repos\repo-setup-scripts`, so later pulls update it. It's repo-setup-scripts' own loader (`.github/extensions/demo-launcher-loader/extension.mjs`, the same file `install.sh` writes on macOS), with the checkout path filled in on its `INSTALLED_REPO` line. The scripts copy it from the checkout, or, if the checkout doesn't have it yet, from [`windows/demo-launcher-loader.mjs`](windows/demo-launcher-loader.mjs) in this repo, a copy of that file to keep in sync with it. In a session whose repo has its own copy of the launcher (such as the repo-setup-scripts project), the loader steps aside so only one Demo Launcher shows up. The `artifacts` folder next to it holds the launcher's run history and is left alone.

#### Install or update the launcher on Windows

Before each booth day, update the checkout and loader, then fully quit and reopen the GitHub Copilot app so it loads the new launcher. From this repo at the release the booth uses (see [Using a release](#using-a-release)), in a regular (non-administrator) PowerShell:

```powershell
git -C "$HOME\repos\machine-setup" fetch --tags --force
git -C "$HOME\repos\machine-setup" checkout --detach v1
cd "$HOME\repos\machine-setup"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-demo-launcher.ps1 -Ref v1
```

Re-running is safe. It checks for `git` and `gh`, clones `octobooth-demos/repo-setup-scripts` to `$HOME\repos\repo-setup-scripts` if it's missing (this needs a logged-in GitHub CLI; see [GitHub CLI login](#github-cli-login)), or, after checking that its `origin` is that repo, fast-forwards it with `git pull --ff-only`. With `-Ref` (or `$env:BOOTH_RELEASE`) it checks out that release instead, and without one it first switches a checkout that's on a release back to its default branch (see [Using a release](#using-a-release)). It then (re)writes the loader, installs the pinned [Playwright MCP server](#playwright-mcp-server) if it's new or changed, and refreshes the MCP servers in `$HOME\.copilot\mcp-config.json` (a failed Playwright download only warns). It exits with an error and lists what failed if the clone, pull, or loader doesn't work. If a folder with that name exists but isn't a git checkout, the script stops; move the folder aside and re-run.

To remove the loader (the checkout and run history are kept), run `.\install-demo-launcher.ps1 -Uninstall`.

If you track `main` (for example, to test changes), you can update by hand instead:

```powershell
git -C "$HOME\repos\repo-setup-scripts" remote get-url origin   # should be octobooth-demos/repo-setup-scripts
git -C "$HOME\repos\repo-setup-scripts" pull --ff-only
```

Then fully quit and reopen the GitHub Copilot app. A pull alone doesn't install the loader the first time; run `install-demo-launcher.ps1` for that.

> [!WARNING]
> The loader runs the launcher's code in every Copilot chat, and Copilot reads the files in a project, so only use the `octobooth-demos/repo-setup-scripts` checkout, and don't add other or unknown repos as projects on booth machines. `setup.ps1` and `install-demo-launcher.ps1` only use that repo, even if `config.json` lists a different one. They, and `setup.sh` and `install-demo-launcher.sh` on macOS/Linux, also refuse to update a checkout (fetch, pull, or check out a release), or install the loader for one, whose `origin` points anywhere else. Without a release, updates come straight from that repo's default branch, so use a [release](#using-a-release) on booth machines, or review changes there (for example with `git -C "$HOME\repos\repo-setup-scripts" log --oneline -5`) before a booth day.

### Install or update on a macOS or Linux machine that's already set up

Run it from an up-to-date clone, because an old copy installs with old logic:

```bash
git -C ~/repos/machine-setup fetch --tags --force
git -C ~/repos/machine-setup checkout --detach v1
cd ~/repos/machine-setup
bash install-demo-launcher.sh --ref v1
```

To track `main` instead, see [Using a release](#using-a-release). It's safe to re-run. It:

1. Checks for `gh`, `git`, and `jq` (`brew install gh jq`) and that the GitHub CLI is logged in. Logging in is interactive, so if it isn't, the script prints the `gh auth login` command to run and stops. It also warns if the login is missing the `codespace`/`delete_repo`/`project`/`workflow` scopes (`gh auth refresh -h github.com -s codespace,delete_repo,project,workflow`).
2. Clones `octobooth-demos/repo-setup-scripts` to `~/repos/repo-setup-scripts`, or pulls it if it's already there. With `--ref` (or `BOOTH_RELEASE`) it checks out that release instead; without one, it first switches a checkout that's on a release back to its default branch.
3. Runs `install.sh` to (re)write the loader.
4. Installs the pinned [Playwright MCP server](#playwright-mcp-server) if it's new or changed, and refreshes the MCP servers in `~/.copilot/mcp-config.json`. If the download fails, it warns and carries on.

Then restart the GitHub Copilot app (or reload extensions) and ask Copilot to "open the demo launcher" in any session to check it works. To remove it, run `bash install-demo-launcher.sh --uninstall`.

### Two Demo Launchers show up

On Copilot app builds with staff features, the app-wide canvas picker can list two "Demo Launcher" canvases: the installed loader (`user:demo-launcher`) and the project's copy (`project:demo-launcher`). Booth machines run without staff features, so this shouldn't happen there. Both are the same launcher and either one works. To hide one, remove `repo-setup-scripts` from the app's projects and restart the app, but keep the clone in `~/repos/repo-setup-scripts` because the loader imports from it.

If two "Demo Launcher" canvases are both labeled Personal, one was installed from a URL (as `demo-launcher-loader`) next to the script's loader (`demo-launcher`). Remove `demo-launcher-loader` from the Copilot app's **Extensions** screen, or delete `~/.copilot/extensions/demo-launcher-loader` (`$HOME\.copilot\extensions\demo-launcher-loader` on Windows). Then re-run `install-demo-launcher.sh` or `install-demo-launcher.ps1` and restart the app.

A "Demo Launcher" labeled "repository: security-octo-supply-v4-…" comes from a demo repo made from the old v4 template, which included a HydraFusion launcher (since removed). Remove that demo project from the Copilot app.

For more on the Demo Launcher itself, see the [repo-setup-scripts quick start](https://github.com/octobooth-demos/repo-setup-scripts#quick-start-booth-machine).

### Copilot sessions stuck at "busy"

Earlier versions of setup registered a Playwright MCP server that runs `npx @playwright/mcp@latest`. Booth machines can't reach the npm registry, so it hangs at startup and keeps Copilot sessions "busy". Rerunning setup or `install-demo-launcher` replaces it with the [prebuilt Playwright MCP server](#playwright-mcp-server). To remove it by hand, run this, then fully quit and reopen the GitHub Copilot app.

macOS:

```bash
f=~/.copilot/mcp-config.json; jq 'del(.mcpServers.playwright)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

Windows (PowerShell):

```powershell
$f = "$HOME\.copilot\mcp-config.json"; $c = Get-Content -Raw $f | ConvertFrom-Json; $c.mcpServers.PSObject.Properties.Remove('playwright'); $c | ConvertTo-Json -Depth 10 | Set-Content $f -Encoding UTF8
```

## Playwright MCP server

Booth machines can't reach the npm registry, so `npx @playwright/mcp` doesn't work there. Instead, setup and `install-demo-launcher` install a prebuilt copy of the [Playwright MCP server](https://github.com/microsoft/playwright-mcp) from this repo's releases. Anyone can use it for their own demos on a booth machine.

### What's installed and where

- The server and its dependencies are in `~/.copilot/mcp-servers/playwright` (`$HOME\.copilot\mcp-servers\playwright` on Windows). `.bundle-version` there shows the version.
- It's registered as `playwright` in `~/.copilot/mcp-config.json`, so every Copilot CLI and GitHub Copilot app session gets its browser tools. It runs with the absolute path to `node` and drives the browser that setup installs: Google Chrome on macOS (`--browser=chrome`), Microsoft Edge on Windows (`--browser=msedge`). No browser download is needed.
- The version is pinned in [`mcp-bundle/package.json`](mcp-bundle/package.json) and its lockfile. Setup downloads `playwright-mcp-<version>.tgz` from the [`playwright-mcp-v<version>` release](https://github.com/octobooth-demos/machine-setup/releases?q=playwright-mcp&expanded=true), checks it against the `.sha256` file, and unpacks it. Later runs skip it until the pinned version changes (or `FORCE_REINSTALL=true`).
- If the download fails, setup warns and skips the Playwright server; nothing else fails. If you already have your own `playwright` entry in `mcp-config.json`, setup leaves it alone.

### Use it in your own demo

In a Copilot session, just ask for browser work, for example "open localhost:4321 and take a screenshot of the home page". The `playwright` tools are already available.

To use it from VS Code or a repo's own MCP config (`.vscode/mcp.json` or `.mcp.json`), point at the installed copy instead of `npx`. Use absolute paths, because MCP configs don't expand `~` or `$HOME`. Copy the `command` and first `args` value from the `playwright` entry in `~/.copilot/mcp-config.json`. For example, in `.vscode/mcp.json` on macOS:

```json
{
  "servers": {
    "playwright": {
      "command": "/Users/<you>/.nvm/versions/node/<version>/bin/node",
      "args": ["/Users/<you>/.copilot/mcp-servers/playwright/node_modules/@playwright/mcp/cli.js", "--browser=chrome"]
    }
  }
}
```

On Windows use `C:\\Program Files\\nodejs\\node.exe`, `C:\\Users\\<you>\\.copilot\\mcp-servers\\playwright\\node_modules\\@playwright\\mcp\\cli.js`, and `--browser=msedge`. Run `node <path to cli.js> --help` for the server's other options, such as `--headless` or `--viewport-size`.

If `node` moves (for example, after `nvm` installs a new Node LTS and removes the old one), run `install-demo-launcher` or setup again to update the path.

### Update the Playwright MCP bundle (maintainers)

Dependabot opens a pull request each month when there's a new `@playwright/mcp`. The [Playwright MCP bundle workflow](.github/workflows/playwright-mcp-bundle.yml) builds the bundle on that pull request (as a downloadable artifact) and tests installing it with `setup.sh` on macOS and `setup.ps1` in Windows PowerShell 5.1.

1. Review and merge the Dependabot pull request. To bump it by hand instead, change the exact version in `mcp-bundle/package.json` and regenerate `mcp-bundle/package-lock.json` against `registry.npmjs.org` (CI rejects a lockfile that points at another registry).
2. On `main`, the workflow publishes the release `playwright-mcp-v<version>` with the `.tgz` and `.sha256`. It's never marked as the latest release, and an existing version's release is never replaced. If publishing fails partway, the next run stops and says so instead of treating a draft or incomplete release as done. Delete that release and its tag (`gh release delete playwright-mcp-v<version> --cleanup-tag --yes`), which is safe because setup can't install an incomplete release, then rerun the workflow from the **Actions** tab (**Run workflow** on `main`).
3. Machines on `main` pick it up the next time they run setup or `install-demo-launcher`. Booth machines pick it up after the next tested [release](#using-a-release) (`vX.Y.Z` plus moving `v1`), when booth staff run their usual update: `bash install-demo-launcher.sh --ref v1` (`.\install-demo-launcher.ps1 -Ref v1` on Windows), then fully restart the GitHub Copilot app.

The bundle has its own `playwright-mcp-v<version>` tags rather than riding on the `vX.Y.Z` releases. That way a version is built once from its lockfile and never changes. Booth releases stay as they are: a `vX.Y.Z` tag only changes which bundle version `mcp-bundle/package.json` asks for. Merging a bump never changes a booth machine until a new `v1` release includes it.

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

Run the PowerShell unit tests on Windows.

```powershell
Invoke-ScriptAnalyzer -Path .\setup.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\install-demo-launcher.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests\powershell
```

The setup and Demo Launcher scripts guard their main entry point so they can be sourced or dot-sourced safely from tests without triggering installs.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.