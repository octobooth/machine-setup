# Booth playbook

_Last updated by [@filmgirl](https://github.com/filmgirl) on November 8, 2026_

A step-by-step walkthrough for running a booth: set up each booth machine before the event, run demos on booth day, then clean up and reset the booth accounts afterwards. You can read this without logging in to anything. Each step lists the access and tools it needs.

[Machine setup reference (README)](../README.md) · [Demo Launcher](../README.md#demo-launcher) · [Troubleshooting](#troubleshooting)

## At a glance

1. **[Before the event](#part-1-before-the-event-set-up-each-booth-machine)**: on each machine, sign in as its booth account, run setup, check the Demo Launcher opens, add browser bookmarks, sign in to VS Code and VS Code Insiders, and [check the machine is ready](#check-that-the-machine-is-ready).
2. **[Each booth day](#before-each-booth-day-update-the-machine)**: update the scripts to the tested release (currently `v1`) and update the Demo Launcher, then [create the security demos ahead of time](#create-the-security-demos-ahead-of-time) once on one machine, and bookmark their repos on every machine.
3. **[During the event](#part-2-during-the-event-run-demos)**: open the pinned apps and the Demo Launcher, and create demos.
4. **[After the event](#part-3-after-the-event-clean-up-and-reset)**: delete the demo repos in the booth accounts and the org, clear the booth machines' demo folders, and have an org admin reset the booth accounts.

Any time, [Clean up demo repos](#clean-up-demo-repos) covers the everyday cleanups: the Demo Launcher, the weekly cleanup in each booth account, and the org's nightly cleanup and `/cleanup` command. [How to clean all Octobooth repos](#how-to-clean-all-octobooth-repos) is for org admins.

> [!IMPORTANT]
> **Booth machines can't download npm or Python packages.** Booth networks block `registry.npmjs.org` and `files.pythonhosted.org`, so `npm install`, `npx`, scaffolders like `npm create vite`, and `pip install` fail or hang in local Copilot sessions. (`pypi.org` loads, but package downloads don't.)
>
> - Setup adds [Copilot booth instructions](../README.md#copilot-booth-instructions) that steer local sessions to plain HTML/CSS/JavaScript, Node.js built-ins, or the Python standard library.
> - For anything that needs packages (React, Next.js, Vite, Flask, etc.), use a **Cloud** session in a GitHub repo, such as one made with the Demo Launcher's **GitHub Copilot Fusion: Blank Prompt** demo, or a Codespace. See [Framework apps need a Cloud session](#framework-apps-need-a-cloud-session).
> - Setup doesn't register any MCP server that runs through `npx`. See [Copilot sessions stuck at "busy"](../README.md#copilot-sessions-stuck-at-busy).

## Where things live

| What | Where | Who can see it |
| --- | --- | --- |
| Machine setup scripts and this playbook | [`octobooth-demos/machine-setup`](https://github.com/octobooth-demos/machine-setup) | Anyone (public) |
| Demo scripts, templates, and the Demo Launcher | [`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts) | Members of the `octobooth-demos` org (internal) |
| Admin scripts (wiping accounts, installing the weekly cleanup) | [`octobooth-demos/admin-tasks`](https://github.com/octobooth-demos/admin-tasks) | `octobooth-demos` org members (private) |
| Booth accounts | `octobooth-1` … `octobooth-10`, one per booth machine | |
| Org demo repos (ChatOps and the security demos) | the `octobooth-demos` org | |

## Part 1: Before the event: set up each booth machine

Do this once on every booth machine. The steps below are the same as the [Setup Instructions](../README.md#setup-instructions) in the README, which also has extra detail on re-running setup and on each setting.

### What you need

- **One booth account per machine.** Pick the account for this machine (for example `octobooth-1`) and have its password ready. Use it everywhere below, never your personal account. It must be a member of the `octobooth-demos` org and allowed to create repositories there, and it needs a Copilot seat.
- **An administrator account on the machine.** Setup installs apps and asks for the password.
- **An internet connection.** Setup downloads a lot, so allow time.

Then follow the steps for [macOS](#set-up-a-mac) or [Windows](#set-up-a-windows-machine).

### Set up a Mac

#### 1. Get the setup scripts

1. Open Terminal. On a new Mac, `git` doesn't work until the Xcode Command Line Tools are installed. Install them first: run the command below, click **Install** in the dialog, and wait for it to finish. If it says they're already installed, move on.

   ```bash
   xcode-select --install
   ```

2. Clone the repo:

   ```bash
   git clone https://github.com/octobooth-demos/machine-setup.git ~/repos/machine-setup
   ```

3. Put the scripts on the tested [`v1` release](https://github.com/octobooth-demos/machine-setup/releases) the booth uses (see [Using a release](../README.md#using-a-release)). Do this again before each booth day, and before re-running `setup.sh` or `install-demo-launcher.sh`:

   ```bash
   git -C ~/repos/machine-setup fetch --tags --force
   git -C ~/repos/machine-setup checkout --detach v1
   ```

If `git` still doesn't work, the README has a [ZIP fallback](../README.md#1-get-the-setup-scripts).

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

4. Answer the prompts as they come up:
   1. **Xcode Command Line Tools.** `git` and Homebrew need them. If they're missing, the installer opens: click **Install**, and the script waits until it finishes (up to 30 minutes; set `XCODE_CLT_TIMEOUT` in seconds to change this). If the install fails or times out, run `xcode-select --install`, finish the installer, and run `bash setup.sh --ref v1` again.
   2. **Your Mac password.** The Homebrew installer and the SF Mono font ask for it. Type it and press Enter (nothing shows while you type). If the Homebrew installer asks you to press RETURN to continue, press Enter.
   3. **GitHub.com in Chrome.** The script opens Chrome and pauses. Sign in to GitHub.com as **the booth account**, then press Enter.
   4. **Default browser.** If Chrome isn't the default browser yet, macOS asks whether to change it. Click **Use “Google Chrome”**, then press Enter. This also works if Chrome was installed before setup ran. If Chrome is already the default, the script skips this step.
   5. **GitHub CLI login.** The GitHub CLI shows a one-time code. Press Enter to open the browser, enter the code, and approve the login (or scope upgrade) while signed in as the booth account. See [GitHub CLI login](../README.md#github-cli-login).
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `bash setup.sh --ref v1` again; finished steps are skipped.
6. Setup adds Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC to the Dock.
7. Store booth videos in `$HOME/Videos` and open them from VLC in the Dock.

#### 3. Set up the Demo Launcher

Setup already cloned `~/repos/repo-setup-scripts` and installed the Demo Launcher for every Copilot session. Don't also install the launcher from a URL in the Copilot app: that adds a second "Demo Launcher" (see [Troubleshooting](#troubleshooting)). To repair or update it, re-run `install-demo-launcher.sh`. [Why the script](../README.md#demo-launcher).

1. Open the GitHub Copilot app and sign in with the booth account.
2. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Use the local folder, not the repo's URL: adding it by URL makes the app clone a second copy, and only `~/repos/repo-setup-scripts` is updated by `install-demo-launcher.sh` and used by the installed Demo Launcher.
3. Start a session in the repo-setup-scripts project, choosing **Current checkout** (not **New worktree**). Then right-click that session in the Copilot app and choose **Pin** so it's easy to find on booth day.
4. Ask Copilot to "open the demo launcher" in any chat or session.

More detail: [Demo Launcher](../README.md#demo-launcher).

#### 4. Add Chrome bookmarks

In Chrome, still signed in to GitHub.com as the booth account, open each page below and press **Cmd+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth-demos`: the `octobooth-demos` org.

On booth day, you'll also bookmark the security demo repos (AI Security and Security Supply Chain (v4)). You can't add them during setup: they're created within 72 hours of use. Create each demo once, on one machine, then open that same repo in Chrome on every booth machine and press **Cmd+D**. See [Create the security demos ahead of time](#create-the-security-demos-ahead-of-time).

#### 5. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 6. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

### Set up a Windows machine

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

Put the scripts on the tested [`v1` release](https://github.com/octobooth-demos/machine-setup/releases) the booth uses (see [Using a release](../README.md#using-a-release)). Do this again before each booth day, and before re-running `setup.ps1` or `install-demo-launcher.ps1`:

```powershell
git -C "$HOME\repos\machine-setup" fetch --tags --force
git -C "$HOME\repos\machine-setup" checkout --detach v1
```

#### 4. Allow the script to run

Windows blocks PowerShell scripts by default. Allow them for this window only (this doesn't change the machine's policy):

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
```

#### 5. Run setup

1. If the GitHub CLI is already installed (for example, you're re-running setup), check which account it's logged in to with `gh auth status`. If it shows an account other than this machine's booth account, log it out with `gh auth logout -h github.com`. Setup only logs in when the GitHub CLI isn't logged in, so it would otherwise keep the wrong account. On a new machine, `gh` isn't installed yet; skip this.
2. Run the setup script with the same release:

   ```powershell
   .\setup.ps1 -Ref v1
   ```

3. Answer the prompts as they come up:
   1. **Installs.** `winget` installs everything in `windows.packages` in [`config.json`](../config.json). PowerShell 7 (`Microsoft.PowerShell`) is installed first, followed by VS Code, VS Code Insiders, Windows Terminal, Git, GitHub CLI, Node.js LTS, Python, VLC, Copilot CLI, the GitHub Copilot app, and GitHub Desktop. This takes a while, and some installers briefly show their own windows. Setup then configures VLC and pins VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC to the taskbar. The taskbar briefly disappears while Explorer restarts.
   2. **GitHub.com in Edge.** The script opens Microsoft Edge and pauses. Sign in to GitHub.com as **the booth account**, then press Enter.
   3. **GitHub CLI login.** The GitHub CLI shows a one-time code. Press Enter to open the browser, enter the code, and approve the login (or scope upgrade) while signed in as the booth account. See [GitHub CLI login](../README.md#github-cli-login).
4. Setup then installs GitHub CLI extensions, clones the demo repos into `$HOME\repos`, installs the Demo Launcher for every Copilot chat, installs VS Code extensions and the theme, and registers MCP servers for Copilot CLI.
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `.\setup.ps1 -Ref v1` again; finished steps and `winget` packages that are already installed are skipped. For `winget` errors, see [Troubleshooting Windows package installs](../README.md#troubleshooting-windows-package-installs).

#### 6. After setup

- Close the window and open a new terminal so it picks up the updated `PATH`. Check PowerShell 7 with `pwsh --version`. Windows Terminal adds a **PowerShell** profile for it, but its default profile may still be **Windows PowerShell** 5.1, which stays installed alongside it (check with `$PSVersionTable.PSVersion`). The scripts work in either, but use PowerShell 7 from here on: open the **PowerShell** profile, or make it the default in Windows Terminal under **Settings** > **Startup** > **Default profile**.
- To update the Demo Launcher later, see [Before each booth day: update the machine](#before-each-booth-day-update-the-machine).
- Store booth videos in `C:\Users\<YourUsername>\Videos` and open them from VLC on the taskbar.

#### 7. Set up the Demo Launcher

Setup already cloned `$HOME\repos\repo-setup-scripts` and installed the Demo Launcher for every Copilot chat. Don't also install the launcher from a URL in the Copilot app: that adds a second "Demo Launcher" (see [Troubleshooting](#troubleshooting)). To repair or update it, re-run `.\install-demo-launcher.ps1 -Ref v1`. [Why the script](../README.md#demo-launcher).

1. Open the GitHub Copilot app and sign in with the booth account. If it was already open, fully quit it first (right-click its icon in the system tray and choose **Quit**), so it loads the launcher.
2. Ask Copilot to "open the demo launcher" in any chat.
3. Optional, for quick access on booth day: add the existing local folder `$HOME\repos\repo-setup-scripts` as a project (use the local folder, not the repo's URL, which clones a second copy), start a session in it with **Current checkout** (not **New worktree**), then right-click that session and choose **Pin**.

More detail: [Windows: installed loader and project](../README.md#windows-installed-loader-and-project).

#### 8. Add Edge favorites

Setup signed in to GitHub.com in Microsoft Edge, and Chrome isn't installed on Windows, so use Edge. Edge calls bookmarks favorites. In Edge, still signed in to GitHub.com as the booth account, open each page below and press **Ctrl+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth-demos`: the `octobooth-demos` org.

On booth day, you'll also bookmark the security demo repos (AI Security and Security Supply Chain (v4)). You can't add them during setup: they're created within 72 hours of use. Create each demo once, on one machine, then open that same repo in Edge on every booth machine and press **Ctrl+D**. See [Create the security demos ahead of time](#create-the-security-demos-ahead-of-time).

#### 9. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 10. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

### Check that the machine is ready

Check each item on every booth machine. `N` is this machine's booth account number.

1. **GitHub CLI.** Run `gh auth status`. It should show `octobooth-N` as the active account, with `codespace`, `delete_repo`, `project`, and `workflow` in its token scopes. If not, follow [GitHub CLI login](../README.md#github-cli-login). If `GH_TOKEN` or `GITHUB_TOKEN` is set, unset it.
2. **Demo repos.** `~/repos` (`$HOME\repos` on Windows) contains `repo-setup-scripts`, `tailspin-toys`, and `security-octo-supply` (the `repos_to_clone` list in [`config.json`](../config.json)).
3. **Copilot app.** It's signed in as `octobooth-N`, and "open the demo launcher" opens the launcher from a new chat. If you added the optional repo-setup-scripts project, it's from the local `~/repos/repo-setup-scripts` folder (`$HOME\repos\repo-setup-scripts` on Windows) and its pinned session is a **Current checkout** one.
4. **VS Code and VS Code Insiders.** In each, **Accounts** shows `octobooth-N`, and GitHub Copilot is signed in and active.
5. **Bookmarks.** The browser (Chrome on macOS, Edge on Windows) has bookmarks for `https://github.com/octobooth-N` and `https://github.com/octobooth-demos`.
6. **Dock or taskbar.** On macOS, the Dock has Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC. On Windows, the taskbar has VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC. Machines set up with an older version of the setup scripts may still have a `load-demos.sh` or `load-demos.ps1` script on the Desktop. Setup no longer creates it, and nothing uses it, so you can delete it.
7. **Weekly cleanup.** In a browser signed in as the booth account, open `https://github.com/octobooth-N/demo-cleanup/actions`. It should have a **Weekly demo cleanup** workflow with green runs. If the repo is missing or runs fail, ask an org admin to [set up the weekly cleanup](#set-up-or-repair-the-weekly-cleanup) for that account.

### Before each booth day: update the machine

Update the setup scripts and the Demo Launcher to the tested release the booth uses, currently `v1`, then fully restart the GitHub Copilot app so it loads the new launcher: on macOS, quit it with **Cmd+Q**; on Windows, right-click its system tray icon and choose **Quit**. Then reopen it.

On macOS:

```bash
git -C ~/repos/machine-setup fetch --tags --force
git -C ~/repos/machine-setup checkout --detach v1
cd ~/repos/machine-setup
bash install-demo-launcher.sh --ref v1
```

On Windows, in a regular (non-administrator) PowerShell:

```powershell
git -C "$HOME\repos\machine-setup" fetch --tags --force
git -C "$HOME\repos\machine-setup" checkout --detach v1
cd "$HOME\repos\machine-setup"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
.\install-demo-launcher.ps1 -Ref v1
```

`v1` always points at the latest tested `v1.x.y` release of both repos, so this picks up fixes without taking untested changes from `main`. It also installs the [Playwright MCP server](../README.md#playwright-mcp-server) version that release pins, if it changed. If the script says the tag doesn't exist or the checkout has local changes, fix that before the booth opens; see [Using a release](../README.md#using-a-release). Developers testing changes before a release can track `main` instead: run `git -C ~/repos/machine-setup checkout main`, pull, and run the install without `--ref` / `-Ref`.

The install script also refreshes the booth's Copilot instructions (see [Copilot booth instructions](../README.md#copilot-booth-instructions)).

Both are safe to re-run. To also pick up changes in `config.json` (new apps, extensions, or repos), run setup again with the same release (`bash setup.sh --ref v1` or `.\setup.ps1 -Ref v1`) in addition to the launcher update above. Already-finished steps and already-installed packages are skipped. On Windows, run `.\setup.ps1` from **Terminal (Admin)**; otherwise it skips the taskbar pins. See [Re-running on a Windows machine that's already set up](../README.md#re-running-on-a-windows-machine-thats-already-set-up) for details, and [Demo Launcher](../README.md#demo-launcher) for what the install scripts do.

#### Create the security demos ahead of time

Two demos take too long to create while a visitor waits: **AI Security** (about 20 minutes until it's fully ready) and **Security Supply Chain (v4)** (about 10 minutes). Create each one once, on one machine, before the booth opens. Every booth machine can share it:

1. On one machine, signed in to the Copilot app as its booth account, ask Copilot to "open the demo launcher", and create **AI Security** and **Security Supply Chain (v4)**.
2. When each is ready, open its demo repo in the browser (Chrome on macOS, Edge on Windows) and bookmark it (**Cmd+D** in Chrome, **Ctrl+D** in Edge).
3. On each of the other booth machines, open the same repo URLs and bookmark them there. Don't create the demos again on every machine.

Both demos create repos in the `octobooth-demos` org, where the [nightly cleanup](#org-nightly-cleanup) deletes them once they're more than 72 hours old. Create them within 72 hours of when you'll use them; one of each can serve every machine for the whole day. Before-the-demo checks: [AI Security](https://github.com/octobooth-demos/repo-setup-scripts#ai-security-ai-scan--agentic-autofix) and [Security Supply Chain (v4)](https://github.com/octobooth-demos/repo-setup-scripts#security-supply-chain-v4) in the `repo-setup-scripts` README.

## Part 2: During the event: run demos

1. **Open the demo apps.** Open the GitHub Copilot app, VS Code, VS Code Insiders, and VLC from the Dock (macOS) or taskbar (Windows). Open your booth videos in VLC from `~/Videos` (`C:\Users\<YourUsername>\Videos` on Windows). In the browser (Chrome on macOS, Edge on Windows), use the bookmarks for the booth account, `octobooth-demos`, and the [security demo repos you created ahead of time](#create-the-security-demos-ahead-of-time).
2. **Open the Demo Launcher.** Ask Copilot to "open the demo launcher" in any chat.
3. **Create demos from the launcher.** It creates each demo repo in the background and opens a session for it. The launcher, the demo list, and per-demo notes are documented in the `repo-setup-scripts` README (org members only).
4. **Send framework requests to a Cloud session.** See [Framework apps need a Cloud session](#framework-apps-need-a-cloud-session).

Each demo repo gets the `demo-generated` topic, which is how every cleanup finds it. Old demo repos are deleted automatically, but you can clear them out sooner (for example, at the end of a booth day): see [Clean up demo repos](#clean-up-demo-repos).

### Framework apps need a Cloud session

Booth networks block npm and Python package downloads, so local sessions can't install packages. Setup adds [Copilot booth instructions](../README.md#copilot-booth-instructions) that tell Copilot to build plain HTML/CSS/JavaScript apps (or use only Node.js built-ins or the Python standard library) and to send framework requests to you. If an attendee wants a React, Next.js, Vite, Flask, or other framework app:

1. Create a repo: in the Demo Launcher, create **GitHub Copilot Fusion: Blank Prompt** (or use any GitHub repo the booth account can push to).
2. Start a new session in that repo and select **Cloud** before sending the prompt. Cloud sessions run on GitHub, where packages install normally.

You can also open the repo in a GitHub Codespace (**Code** > **Codespaces** > **Create codespace on main**), which can install packages too.

## Part 3: After the event: clean up and reset

Do these in order.

### Step 1: Delete the demo repos

Booth staff can do this; see [Clean up demo repos](#clean-up-demo-repos) for each option.

1. **Each booth account.** On each booth machine, use the Demo Launcher's [Clean up](#from-the-demo-launcher) section with **Any age**, and tick **Also delete local clones**. Or, from a browser signed in as that account, [run the weekly cleanup](#run-it-sooner-just-a-browser) with `older_than_days` set to `0`.
2. **The `octobooth-demos` org.** Open an issue in `repo-setup-scripts` and comment `/cleanup --all --confirm`. See [Org nightly cleanup](#org-nightly-cleanup).

### Step 2: Clear the booth machines' demo folders

Local clones of deleted demo repos in `~/repos` stay on each booth machine unless you ticked **Also delete local clones** in the launcher. Remove those demo folders explicitly; rerunning [setup](../README.md#setup-instructions) does not remove or reset them. Keep shared checkouts such as `machine-setup`, `repo-setup-scripts`, `tailspin-toys`, and `security-octo-supply`.

### Step 3: Reset the booth accounts (org admins)

To delete **every** repo in the booth accounts, not just demo repos, an org admin follows [How to clean all Octobooth repos](#how-to-clean-all-octobooth-repos).

## Clean up demo repos

Every demo repo has the `demo-generated` topic. These cleanups only delete repos with that topic, so other repos are safe. Use them during the event or after it.

| Where the demo repos are | Automatic cleanup | To clean up sooner |
| --- | --- | --- |
| Each booth account (`octobooth-1` … `octobooth-10`), the default | [Weekly cleanup](#weekly-cleanup-in-each-booth-account): Mondays 08:00 UTC, repos more than 7 days old | The [Demo Launcher](#from-the-demo-launcher) on that machine, or [run the weekly cleanup](#run-it-sooner-just-a-browser) from a browser signed in as that account |
| The `octobooth-demos` org (ChatOps and the security demos) | [Org nightly cleanup](#org-nightly-cleanup): nightly 08:00 UTC, repos more than 72 hours old | A `/cleanup` comment or the **Clean up demos** workflow in `repo-setup-scripts` (org members with write access) |

08:00 UTC is midnight Pacific (1 AM during daylight saving time).

### From the Demo Launcher

The Demo Launcher on each booth machine can delete that booth account's demo repos. Deleting needs the `delete_repo` scope, which setup adds to the GitHub CLI login.

1. Ask Copilot to "open the demo launcher" and scroll to **Clean up**.
2. Leave **Owner** empty to clean up the booth account that's logged in.
3. Set **Older than** (default 72 hours), or click **Any age** to include every demo repo, however new.
4. Click **Find demo repos** and review the list. Untick any repo you want to keep.
5. Optionally tick **Also delete local clones** to remove their folders in `~/repos` too.
6. Click **Delete** and then click it again to confirm.

The same cleanup runs in a terminal on that machine. It lists the matching repos and asks before deleting:

```bash
cd ~/repos/repo-setup-scripts
bash ./create-repo.sh --cleanup          # demo repos more than 72 hours old
bash ./create-repo.sh --cleanup --all    # every demo repo, however new
```

On Windows, use `.\create-repo.ps1 -Cleanup` (add `-All` for every demo repo). Add `--dry-run` (`-DryRun`) to only list what it would delete. The `repo-setup-scripts` README (org members only) has every option.

For org demos, use the [org cleanup](#org-nightly-cleanup) instead. If you type `octobooth-demos` as the launcher's owner, the list includes demos from every booth and ChatOps.

### Weekly cleanup in each booth account

Each booth account has a private repo, `octobooth-N/demo-cleanup`, with a workflow named **Weekly demo cleanup**. It runs as that account, using that account's own token, and only touches that account's repos:

- It deletes repos the account owns that have the `demo-generated` topic and are more than 7 days old.
- It never deletes repos without that topic, or the `demo-cleanup` repo itself.
- Nothing runs from the org, and no admin is needed once it's set up.

#### Run it sooner (just a browser)

1. Sign in to github.com as the booth account and go to `https://github.com/octobooth-N/demo-cleanup/actions`, using that account's number.
2. Click **Weekly demo cleanup** in the left sidebar.
3. Click **Run workflow** on the right.
4. Set **older_than_days**:
   - `7` (the default) deletes the same repos as the Monday run.
   - `0` deletes **every** demo repo in the account, however new.
   - Any other number means "older than that many days".
5. Optionally tick **dry_run** to only list what it would delete.
6. Click the green **Run workflow** button. The run appears after a few seconds; open it to see what was deleted.

#### Check that it's working

Open the account's `demo-cleanup` **Actions** tab. Each Monday should have a green run. If a run fails, GitHub emails the booth account, and the run's log says what's wrong. The usual cause is a revoked or deleted token; ask an org admin to [set up that account again](#set-up-or-repair-the-weekly-cleanup).

### Org nightly cleanup

Demo repos created in the `octobooth-demos` org (ChatOps and the security demos) are deleted by the **Clean up demos** workflow in `repo-setup-scripts` once they're more than 72 hours old. To run it sooner, org members with write access to `repo-setup-scripts` can either:

- open an issue in `repo-setup-scripts` and comment `/cleanup 24 --confirm` (any number of hours), or `/cleanup --all --confirm` after an event; or
- run **Clean up demos** from that repo's **Actions** tab.

Comments without `--confirm` are dry runs. These cleanups can't see repos in the booth accounts.

## How to clean all Octobooth repos

This section should be run by someone with admin access to the `octobooth-demos` org, such as [@geektrainer](https://github.com/geektrainer), [@jdooley-clt](https://github.com/jdooley-clt), or someone else on the GitHub DevRel team. For everyday cleanup of demo repos, use [Clean up demo repos](#clean-up-demo-repos) instead.

The scripts are in the private [`octobooth-demos/admin-tasks`](https://github.com/octobooth-demos/admin-tasks) repo, and its README has every option. You need a Mac or Linux machine, the GitHub CLI, and access to `admin-tasks`.

### Get the admin scripts

1. On a fresh Mac, install [Homebrew](https://brew.sh), then the GitHub CLI: `brew install gh`.
2. Log in as yourself (an `octobooth-demos` org member) so you can download the admin scripts:

   ```bash
   gh auth login -h github.com
   gh repo clone octobooth-demos/admin-tasks && cd admin-tasks
   ```

   If `admin-tasks` is already on the machine, run `cd admin-tasks && git pull` instead.

### Wipe every repo in the booth accounts

`admin-tasks/scripts/wipe-accounts.sh` deletes **every** repo in each booth account, demo or not, except `demo-cleanup`. It goes one account at a time: log in (or switch) → list that account's repos → you confirm → delete → next account. It doesn't touch the org's repos or the booth machines' local folders.

```bash
bash scripts/wipe-accounts.sh --dry-run    # list what would be deleted, change nothing
bash scripts/wipe-accounts.sh              # walk through octobooth-1..10
bash scripts/wipe-accounts.sh --from 5     # resume at octobooth-5
```

- **Logins.** For each booth account the GitHub CLI isn't logged in to yet, the script walks you through a browser login. Sign in to github.com as that account (a private window is easiest), press Enter, and paste the one-time code it shows. Type `s` to skip an account. Logins are remembered, so later runs don't ask again.
- **Confirming.** For each account it lists the repos, numbered. Type:
  - `WIPE` (in capitals) to delete them.
  - `k` to keep some, by number or name.
  - `s` to skip the account.
  - `q` to stop.

  Anything else, including lowercase `wipe`, shows a warning and asks again.
- **Finishing up.** At the end it prints a summary and, if anything was skipped or failed, the exact command to finish it.

### Set up or repair the weekly cleanup

Needed for a new booth account, or when an account's cleanup reports a token problem. You need a Mac (or Linux), the GitHub CLI logged in to your own GitHub account, access to `admin-tasks`, and a browser where you can sign in as the booth account(s).

```bash
gh repo clone octobooth-demos/admin-tasks && cd admin-tasks   # or: cd admin-tasks && git pull
bash scripts/setup-weekly-cleanup.sh --accounts 3             # one account
bash scripts/setup-weekly-cleanup.sh                          # all of octobooth-1..10
bash scripts/setup-weekly-cleanup.sh --from 6                 # resume at octobooth-6
```

For each account, the script:

1. Prints and copies a link that creates a **classic** token with `repo`, `delete_repo`, and `workflow` ticked. The token's note names the account.
2. You open the link in a browser or profile signed in as **that** account, then check the avatar in the top right. Press `o` to open the link in your default browser instead.
3. You set **Expiration** to **No expiration**, generate the token, and paste it into the script. Your typing is hidden.
4. The script checks the token (right account, classic, right scopes, doesn't expire), creates the `demo-cleanup` repo if needed, adds the workflow, and saves the token as the `CLEANUP_TOKEN` secret.
5. It runs a dry-run test in Actions and shows what it found.

Rerunning is safe; it replaces the token. The token belongs to the booth account, not to you, so it keeps working whoever set it up and whatever machines are logged in. It stops working only if someone deletes or regenerates it in that account's **Settings → Developer settings → Personal access tokens (classic)**, where its note is `demo-cleanup weekly cleanup (octobooth-N)`.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `gh auth status` shows your personal account (or another booth account) | Run `gh auth logout -h github.com`, then `gh auth login -h github.com` as this machine's booth account and add the scopes. See [GitHub CLI login](../README.md#github-cli-login). |
| Setup ends with "The following items failed to install" | Fix the cause shown for each item and run setup again; finished steps are skipped. On Windows, see [Troubleshooting Windows package installs](../README.md#troubleshooting-windows-package-installs). |
| "open the demo launcher" doesn't work | [Update the Demo Launcher](#before-each-booth-day-update-the-machine), which also reinstalls its loader, then fully quit and reopen the GitHub Copilot app (on Windows, right-click its tray icon and choose **Quit**). If it still doesn't open, ask from a session in the repo-setup-scripts project. |
| The pinned session still shows the old launcher after an update | It's probably a **New worktree** session, which keeps its own copy. Archive it and start a new **Current checkout** session in the repo-setup-scripts project. |
| Two "Demo Launcher" canvases, both labeled Personal | One was installed from a URL (it's named `demo-launcher-loader`). Remove `demo-launcher-loader` from the Copilot app's **Extensions** screen, or delete `~/.copilot/extensions/demo-launcher-loader` (`$HOME\.copilot\extensions\demo-launcher-loader` on Windows). Then re-run `install-demo-launcher.sh` or `install-demo-launcher.ps1` and restart the app. |
| A "Demo Launcher" labeled "repository: security-octo-supply-v4-…" | It comes from a demo repo made from the old v4 template, which included a HydraFusion launcher (since removed). Remove that demo project from the Copilot app. |
| Setup warns "Couldn't download Playwright MCP" | The machine couldn't reach github.com, or that bundle release isn't published yet. Everything else still works. Run the [update](#before-each-booth-day-update-the-machine) again later. See [Playwright MCP server](../README.md#playwright-mcp-server). |
| The launcher's **Clean up** says your `gh` login can't delete repos | Run `gh auth refresh -h github.com -s delete_repo` in a terminal as the booth account, then click **Delete** again. |
| Copilot sessions stay "busy" and never answer | An old Playwright MCP server (`npx @playwright/mcp`) is hanging because npm is blocked. Run the [update](#before-each-booth-day-update-the-machine), which replaces it with the prebuilt one, or remove it by hand with the command in [Copilot sessions stuck at "busy"](../README.md#copilot-sessions-stuck-at-busy). Then fully quit and reopen the GitHub Copilot app. |
| A booth account's weekly cleanup run failed | Open the failed run. If it mentions `CLEANUP_TOKEN`, ask an org admin to [set up that account again](#set-up-or-repair-the-weekly-cleanup). |
| Demo repos in a booth account aren't being deleted | Check they're more than 7 days old and have the `demo-generated` topic (shown under **About** on the repo page). To delete them now, use the launcher's [Clean up](#from-the-demo-launcher) with **Any age**, or [run the weekly cleanup](#run-it-sooner-just-a-browser) with `older_than_days` set to `0`. |
| (Admins) The weekly cleanup setup script says a token belongs to the wrong account | The browser was signed in as another account. Delete that stray token in the other account's token settings, switch the browser to the right account, and make a new one. |
| (Admins) `gh repo clone octobooth-demos/admin-tasks` says "Could not resolve" | Log in to the GitHub CLI as your own org-member account: `gh auth login -h github.com`. |
| (Admins) The wipe script asks for `delete_repo` | Approve it in the browser while signed in as that booth account. |
