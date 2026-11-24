# Booth playbook

A step-by-step walkthrough for running a booth: set up each booth machine before the event, run demos on booth day, then clean up and reset the booth accounts afterwards. You can read this without logging in to anything. Each step lists the access and tools it needs.

[Machine setup reference (README)](../README.md) · [Demo Launcher](setup-reference.md#demo-launcher) · [Troubleshooting](#troubleshooting)

## At a glance

1. **[Before the event](#part-1-before-the-event-set-up-each-booth-machine)**: on each machine, sign in as its booth account, run setup, check the Demo Launcher opens, add browser bookmarks, sign in to VS Code and VS Code Insiders, and [check the machine is ready](#check-that-the-machine-is-ready).
2. **[Each booth day](#before-each-booth-day-update-the-machine)**: use matching releases of both script repositories and refresh the Demo Launcher, then [create the security demos ahead of time](#create-the-security-demos-ahead-of-time) once on one machine and bookmark their repos on every machine.
3. **[During the event](#part-2-during-the-event-run-demos)**: open the pinned apps and the Demo Launcher, and create demos.
4. **[After the event](#part-3-after-the-event-clean-up-and-reset)**: retain demo environments for one week after the event ends, document the DevRel review, then delete only approved environments and reset eligible accounts.

[Clean up demo repos](#clean-up-demo-repos) covers reviewed deletion and the limits of age-based cleanup tools. [How to clean all Octobooth repos](#how-to-clean-all-octobooth-repos) is for org admins; it does not bypass retention or review.

> [!IMPORTANT]
> **Use approved package sources.** Setup checks existing npm and pip routes without changing configuration. Review the [package-source results](setup-reference.md#managed-devices-and-package-feeds); metadata success alone does not verify package downloads or a demo.
>
> - Setup adds [Copilot booth instructions](setup-reference.md#copilot-booth-instructions) that keep working feed settings and never switch to public registries after a failure.
> - If approved local package access is unavailable, use plain HTML/CSS/JavaScript, Node.js built-ins, the Python standard library, or a **Cloud** session/Codespace. See [Framework apps need a Cloud session](#framework-apps-need-a-cloud-session).
> - Setup doesn't register any MCP server that runs through `npx`. See [Copilot sessions stuck at "busy"](setup-reference.md#copilot-sessions-stuck-at-busy).

## Where things live

| What | Where | Who can see it |
| --- | --- | --- |
| Machine setup scripts and this playbook | [`octobooth/machine-setup`](https://github.com/octobooth/machine-setup) | Anyone (public) |
| Demo scripts and the Demo Launcher | [`octobooth/repo-setup-scripts`](https://github.com/octobooth/repo-setup-scripts) | Anyone (public) |
| Templates cloned by setup | [`octobooth/tailspin-toys`](https://github.com/octobooth/tailspin-toys), [`octobooth/security-octo-supply`](https://github.com/octobooth/security-octo-supply) | Authorized enterprise accounts (internal); verify booth-account access |
| Admin scripts (wiping accounts, installing the weekly cleanup) | [`octobooth/admin-tasks`](https://github.com/octobooth/admin-tasks) | Explicitly authorized accounts (private) |
| Booth accounts | `octobooth-1` … `octobooth-10`, one per booth machine | |
| Org demo repos (ChatOps and the security demos) | the [octobooth organization](https://github.com/octobooth) | Depends on repository visibility and account permissions |

## Part 1: Before the event: set up each booth machine

Start with the [short installation guide](../README.md#setup-instructions), then complete the [readiness checklist](#check-that-the-machine-is-ready). The walkthroughs below are an alternative for staff maintaining a local machine-setup clone.

### What you need

- **One booth account per machine.** Pick the account for this machine (for example `octobooth-1`) and have its password ready. Use it everywhere below, never your personal account. Verify its access to the internal templates, permission to create repositories in [octobooth](https://github.com/octobooth), Copilot features, Codespaces and billing, and required security features. These permissions are not established by copying the repositories; see [GitHub CLI login and access prerequisites](setup-reference.md#github-cli-login).
- **An administrator account on the machine.** Setup installs apps and asks for the password.
- **An internet connection.** Setup downloads a lot, so allow time.

Setup reports device enrollment for information only. An **unknown** result does not block setup. Review operational package-source results instead; see [managed devices and package feeds](setup-reference.md#managed-devices-and-package-feeds).

Use the [setup command](#run-the-setup-command), or follow the local-checkout steps for [macOS](#set-up-a-mac) or [Windows](#set-up-a-windows-machine).

<a id="set-up-without-cloning"></a>

### Run the setup command

Use the [copy/paste setup commands](../README.md#setup-instructions). For a specific release, see [release installation](setup-reference.md#using-a-release).

For testing a published branch revision, use a local bootstrap with its full commit SHA; see [testing a revision](development.md#releases). Keep the README commands on `main`. A machine-setup SHA does not pin the separate demo repository to that SHA.

On macOS, quit iTerm2 and paste the Bash command in Terminal. On Windows, open **Windows PowerShell** as administrator, [check winget](#2-make-sure-winget-works), and paste the PowerShell command. If `gh` is already installed, check `gh auth status --active -h github.com` and switch to this machine's booth account before starting.

Answer the normal installation and booth-account sign-in prompts. Download failures stop without running setup; connectivity and winget source problems still need to be fixed separately. Temporary setup files are removed afterward, so rerun the same bootstrap block to retry rather than looking for a local machine-setup checkout.

When setup finishes, continue at [Set up the Demo Launcher on macOS](#3-set-up-the-demo-launcher) or [After setup on Windows](#6-after-setup), then complete bookmarks, editor sign-in, and readiness checks. For later commands that use local scripts, download a fresh archive or use the clone-based instructions below.

### Set up a Mac

#### 1. Get the setup scripts

1. Open Terminal. On a new Mac, `git` doesn't work until the Xcode Command Line Tools are installed. Install them first: run the command below, click **Install** in the dialog, and wait for it to finish. If it says they're already installed, move on.

   ```bash
   xcode-select --install
   ```

2. Clone the repo:

   ```bash
   git clone https://github.com/octobooth/machine-setup.git ~/repos/machine-setup
   ```

3. Put the scripts on the tested [`v1` release](https://github.com/octobooth/machine-setup/releases) the booth uses (see [Using a release](setup-reference.md#using-a-release)). Do this again before each booth day, and before re-running `setup.sh` or `install-demo-launcher.sh`:

   ```bash
   git -C ~/repos/machine-setup fetch --tags --force
   git -C ~/repos/machine-setup checkout --detach v1
   ```

If `git` still doesn't work, use the [release ZIP](setup-reference.md#using-a-release) instead.

#### 2. Run setup

1. Quit iTerm2 if it's open. iTerm2 overwrites setup's changes to its settings when it quits.
2. If the GitHub CLI is already installed (for example, you're re-running setup), check which account it's logged in to:

   ```bash
   gh auth status --active -h github.com
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
   3. **Default browser.** If Chrome isn't the default browser yet, setup opens Chrome and macOS asks whether to change it. Select **Use “Google Chrome”**, then press Enter. This also works if Chrome was installed before setup ran. If Chrome is already the default, the script skips this step.
   4. **GitHub CLI login, if needed.** Setup reuses the active login and requests only missing scopes. For a new login or scope upgrade, follow the one-time-code prompt and approve access in the browser as **the booth account**. OAuth, SSO, and two-factor authentication still require you. The browser, editors, and Copilot app have separate sign-ins; check each uses the same booth account. See [GitHub CLI login](setup-reference.md#github-cli-login).
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `bash setup.sh --ref v1` again; finished steps are skipped.
6. Setup adds Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC to the Dock.
7. Store booth videos in `$HOME/Videos` and open them from VLC in the Dock.

#### 3. Set up the Demo Launcher

Setup already cloned `~/repos/repo-setup-scripts` and installed the Demo Launcher for every Copilot session. Don't also install the launcher from a URL in the Copilot app: that adds a second "Demo Launcher" (see [Troubleshooting](#troubleshooting)). To repair or update it, re-run `install-demo-launcher.sh`. [Why the script](setup-reference.md#demo-launcher).

1. Open the GitHub Copilot app and sign in with the booth account.
2. Add the existing local folder `~/repos/repo-setup-scripts` as a project. Use the local folder, not the repo's URL: adding it by URL makes the app clone a second copy, and only `~/repos/repo-setup-scripts` is updated by `install-demo-launcher.sh` and used by the installed Demo Launcher.
3. Start a session in the repo-setup-scripts project, choosing **Current checkout** (not **New worktree**). Then right-click that session in the Copilot app and choose **Pin** so it's easy to find on booth day.
4. Ask Copilot to "open the demo launcher" in any chat or session.

More detail: [Demo Launcher](setup-reference.md#demo-launcher).

#### 4. Add Chrome bookmarks

In Chrome, sign in to GitHub.com as the booth account if needed, then open each page below and press **Cmd+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth`: the `octobooth` org.

Before booth use, bookmark the security demo repos (AI Security and Security Supply Chain (v4)). Create each demo once, on one machine, then open that same repo in Chrome on every booth machine and press **Cmd+D**. See [Create the security demos ahead of time](#create-the-security-demos-ahead-of-time).

#### 5. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 6. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

### Set up a Windows machine

These steps assume a brand-new Windows 10 or 11 machine with nothing installed beyond what ships with Windows. Sign in to Windows and connect to the internet first. Until setup finishes, you only have the built-in **Windows PowerShell 5.1**. `setup.ps1` is written to run there, and it installs PowerShell 7 for later use.

On an existing machine, back up editor settings before running setup; see [existing VS Code settings](setup-reference.md#existing-vs-code-settings).

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
git clone https://github.com/octobooth/machine-setup.git "$HOME\repos\machine-setup"
cd "$HOME\repos\machine-setup"
```

Put the scripts on the tested [`v1` release](https://github.com/octobooth/machine-setup/releases) the booth uses (see [Using a release](setup-reference.md#using-a-release)). Do this again before each booth day, and before re-running `setup.ps1` or `install-demo-launcher.ps1`:

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

1. If the GitHub CLI is already installed (for example, you're re-running setup), check which account it's logged in to with `gh auth status --active -h github.com`. If it shows an account other than this machine's booth account, switch accounts with `gh auth switch -h github.com -u octobooth-N` or log it out with `gh auth logout -h github.com`. Setup reuses the active login, so it would otherwise keep the wrong account. On a new machine, `gh` isn't installed yet; skip this.
2. Run the setup script with the same release:

   ```powershell
   .\setup.ps1 -Ref v1
   ```

3. Answer the prompts as they come up:
   1. **Installs.** `winget` installs everything in `windows.packages` in [`config.json`](../config.json). PowerShell 7 (`Microsoft.PowerShell`) is installed first, followed by VS Code, VS Code Insiders, Windows Terminal, Git, GitHub CLI, Node.js LTS, Python, VLC, Copilot CLI, the GitHub Copilot app, and GitHub Desktop. This takes a while, and some installers briefly show their own windows. Setup then configures VLC and pins VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC to the taskbar. The taskbar briefly disappears while Explorer restarts.
   2. **GitHub CLI login, if needed.** Setup reuses the active login and requests only missing scopes. For a new login or scope upgrade, follow the one-time-code prompt and approve access in the browser as **the booth account**. OAuth, SSO, and two-factor authentication still require you. The browser, editors, and Copilot app have separate sign-ins; check each uses the same booth account. See [GitHub CLI login](setup-reference.md#github-cli-login).
4. Setup then installs GitHub CLI extensions, clones the demo repos into `$HOME\repos`, installs the Demo Launcher for every Copilot chat, installs VS Code extensions and the theme, and registers MCP servers for Copilot CLI.
5. At the end, setup prints a summary of anything that failed. Fix the cause and run `.\setup.ps1 -Ref v1` again; finished steps and `winget` packages that are already installed are skipped. For `winget` errors, see [Troubleshooting Windows package installs](setup-reference.md#troubleshooting-windows-package-installs).

#### 6. After setup

- Close the window and open a new terminal so it picks up the updated `PATH`. Check PowerShell 7 with `pwsh --version`. Windows Terminal adds a **PowerShell** profile for it, but its default profile may still be **Windows PowerShell** 5.1, which stays installed alongside it (check with `$PSVersionTable.PSVersion`). The scripts work in either, but use PowerShell 7 from here on: open the **PowerShell** profile, or make it the default in Windows Terminal under **Settings** > **Startup** > **Default profile**.
- To update the Demo Launcher later, see [Before each booth day: update the machine](#before-each-booth-day-update-the-machine).
- Store booth videos in `C:\Users\<YourUsername>\Videos` and open them from VLC on the taskbar.

#### 7. Set up the Demo Launcher

Setup already cloned `$HOME\repos\repo-setup-scripts` and installed the Demo Launcher for every Copilot chat. Don't also install the launcher from a URL in the Copilot app: that adds a second "Demo Launcher" (see [Troubleshooting](#troubleshooting)). To repair or update it, re-run `.\install-demo-launcher.ps1 -Ref v1`. [Why the script](setup-reference.md#demo-launcher).

1. Open the GitHub Copilot app and sign in with the booth account. If it was already open, fully quit it first (right-click its icon in the system tray and choose **Quit**), so it loads the launcher.
2. Ask Copilot to "open the demo launcher" in any chat.
3. Optional, for quick access on booth day: add the existing local folder `$HOME\repos\repo-setup-scripts` as a project (use the local folder, not the repo's URL, which clones a second copy), start a session in it with **Current checkout** (not **New worktree**), then right-click that session and choose **Pin**.

More detail: [installed loader and project](setup-reference.md#demo-launcher).

#### 8. Add Edge favorites

Use Microsoft Edge on Windows; Chrome isn't installed by setup. Edge calls bookmarks favorites. In Edge, sign in to GitHub.com as the booth account if needed, then open each page below and press **Ctrl+D** to bookmark it:

- `https://github.com/octobooth-N`: the booth account's profile, using this machine's number (for example `https://github.com/octobooth-1`).
- `https://github.com/octobooth`: the `octobooth` org.

Before booth use, bookmark the security demo repos (AI Security and Security Supply Chain (v4)). Create each demo once, on one machine, then open that same repo in Edge on every booth machine and press **Ctrl+D**. See [Create the security demos ahead of time](#create-the-security-demos-ahead-of-time).

#### 9. Sign in to VS Code and VS Code Insiders

Do this in both VS Code and VS Code Insiders, so GitHub Copilot uses the booth account:

1. Open the app and click the **Accounts** icon at the bottom of the Activity Bar (the left edge). Sign in with GitHub, and approve it in the browser while signed in as the booth account.
2. Click **Accounts** again and check it shows `octobooth-N`, not a personal account. If it shows another account, sign out of that account there and sign in again as the booth account.
3. Check that GitHub Copilot is signed in and active: the Copilot icon in the Status Bar (the bottom edge) doesn't show a sign-in or error warning, and Copilot Chat answers a message.

#### 10. Check the machine is ready

Go through [Check that the machine is ready](#check-that-the-machine-is-ready).

### Check that the machine is ready

Check each item on every booth machine. `N` is this machine's booth account number.

1. **Setup readiness.** Confirm setup's final checks pass and its displayed GitHub CLI account is `octobooth-N`. Setup checks installed packages, Node.js, GitHub scopes, read access to the configured demo repositories, local checkout presence, and Demo Launcher files. If needed, follow [GitHub CLI troubleshooting](setup-reference.md#github-cli-login). Leave `GH_TOKEN` and `GITHUB_TOKEN` unset.
2. **Demo access.** Repository read access alone does not establish permission to create demo repositories, use private templates, or use Copilot and Codespaces. Verify those permissions as the booth account and run a real demo.
3. **Copilot app.** It's signed in as `octobooth-N`, and "open the demo launcher" opens the launcher from a new chat. If you added the optional repo-setup-scripts project, it's from the local `~/repos/repo-setup-scripts` folder (`$HOME\repos\repo-setup-scripts` on Windows) and its pinned session is a **Current checkout** one.
4. **VS Code and VS Code Insiders.** In each, **Accounts** shows `octobooth-N`, and GitHub Copilot is signed in and active.
5. **Bookmarks.** The browser (Chrome on macOS, Edge on Windows) has bookmarks for `https://github.com/octobooth-N` and `https://github.com/octobooth`.
6. **Dock or taskbar.** On macOS, the Dock has Google Chrome, the GitHub Copilot app, VS Code, VS Code Insiders, iTerm2, and VLC. On Windows, the taskbar has VS Code, VS Code Insiders, the GitHub Copilot app, Windows Terminal, and VLC. Machines set up with an older version of the setup scripts may still have a `load-demos.sh` or `load-demos.ps1` script on the Desktop. Setup no longer creates it, and nothing uses it, so you can delete it.
7. **Retention protection.** Have an org admin verify the [cleanup rollout](#cleanup-rollout) for each participating account before the event. Confirm event records, designated reviewers, and a dry-run result; a green run alone does not prove retention compliance.

### Before each booth day: update the machine

For an existing checkout, [inspect its origin and local work](setup-reference.md#existing-clones) before updating. Setup does not rewrite remotes or discard work.

Update the setup scripts and Demo Launcher to the same release, then fully restart Copilot: **Cmd+Q** on macOS, or **Quit** from the Windows system tray. If you installed without a clone, use [launcher-only updates from a fresh archive](setup-reference.md#launcher-only-updates) instead of the Git commands below.

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

`v1` is a moving major tag; use a full version such as `v1.3.0` for an exact pin. The installer also refreshes the [Playwright MCP server](setup-reference.md#playwright-mcp-server). Resolve download warnings, missing tags, or local-change errors before booth use; see [release behavior](setup-reference.md#using-a-release). Verify the launcher and a real demo on each machine rather than relying on release publication or exit status alone.

The install script also refreshes the booth's Copilot instructions (see [Copilot booth instructions](setup-reference.md#copilot-booth-instructions)).

Both are safe to re-run. To also pick up changes in `config.json` (new apps, extensions, or repos), run setup again with the same release (`bash setup.sh --ref v1` or `.\setup.ps1 -Ref v1`) in addition to the launcher update above. Already-finished steps and already-installed packages are skipped. On Windows, run `.\setup.ps1` from **Terminal (Admin)**; otherwise it skips the taskbar pins. See [Rerunning or updating](setup-reference.md#rerunning-or-updating) for details, and [Demo Launcher](setup-reference.md#demo-launcher) for what the install scripts do.

#### Create the security demos ahead of time

> [!WARNING]
> Before using [Security Supply Chain (v4)](https://github.com/octobooth/security-octo-supply-v4), maintainers must validate its destination local build workflow and security features. Open-secret-alert examples remain unresolved; do not assume the copied repository contains demonstration alerts. AI Security also requires verified destination security-feature access. The steps below describe use after those prerequisites are met; do not silently substitute a different template.

Two demos take too long to create while a visitor waits: **AI Security** (about 20 minutes until it's fully ready) and **Security Supply Chain (v4)** (about 10 minutes). Create each one once, on one machine, before the booth opens. Every booth machine can share it:

1. On one machine, signed in to the Copilot app as its booth account, ask Copilot to "open the demo launcher", and create **AI Security** and **Security Supply Chain (v4)**.
2. When each is ready, open its demo repo in the browser (Chrome on macOS, Edge on Windows) and bookmark it (**Cmd+D** in Chrome, **Ctrl+D** in Edge).
3. On each of the other booth machines, open the same repo URLs and bookmark them there. Don't create the demos again on every machine.

Both demos create repos in the [octobooth organization](https://github.com/octobooth). One of each can serve every machine for the whole day. Record their event association and retain them through one week after event end and the DevRel review. Use the [org cleanup](#org-nightly-cleanup) after its gates are satisfied. Before-the-demo checks: [AI Security](https://github.com/octobooth/repo-setup-scripts#ai-security-ai-scan--agentic-autofix) and [Security Supply Chain (v4)](https://github.com/octobooth/repo-setup-scripts#security-supply-chain-v4) in the public `repo-setup-scripts` README.

## Part 2: During the event: run demos

1. **Open the demo apps.** Open the GitHub Copilot app, VS Code, VS Code Insiders, and VLC from the Dock (macOS) or taskbar (Windows). Open your booth videos in VLC from `~/Videos` (`C:\Users\<YourUsername>\Videos` on Windows). In the browser (Chrome on macOS, Edge on Windows), use the bookmarks for the booth account, `octobooth`, and the [security demo repos you created ahead of time](#create-the-security-demos-ahead-of-time).
2. **Open the Demo Launcher.** Ask Copilot to "open the demo launcher" in any chat.
3. **Create demos from the launcher.** It creates each demo repo in the background and opens a session for it. The launcher, the demo list, and per-demo notes are documented in the public [repo-setup-scripts README](https://github.com/octobooth/repo-setup-scripts). Individual templates and features can require additional access.
4. **Use Cloud when local package access is unavailable.** See [Framework apps need a Cloud session](#framework-apps-need-a-cloud-session).

Each generated demo repo gets the `demo-generated` topic, which is how cleanup finds it. Never add that topic to canonical templates or tooling repositories. Before deletion, complete event-end retention and the DevRel review; see [Clean up demo repos](#clean-up-demo-repos). A booth day ending is not permission to remove retained environments.

### Framework apps need a Cloud session

Use this workflow when the machine does not have working approved package access. Setup adds [Copilot booth instructions](setup-reference.md#copilot-booth-instructions) that prefer dependency-free local apps and ask staff before using package downloads. For a React, Next.js, Vite, Flask, or other framework app that cannot run locally:

1. Create a repo: in the Demo Launcher, create **GitHub Copilot Fusion: Blank Prompt** (or use any GitHub repo the booth account can push to).
2. Start a new session in that repo and select **Cloud** before sending the prompt. Cloud sessions run on GitHub, where packages install normally.

You can also open the repo in a GitHub Codespace (**Code** > **Codespaces** > **Create codespace on main**), which can install packages too.

## Part 3: After the event: clean up and reset

Retain event demo environments for 168 hours after the event ends. This includes remote demo repositories and the local state needed to review them. Repository creation time is not the event end time, and reaching an age cutoff is not approval to delete.

### Step 1: Record retention and complete the DevRel review

The event DRI records the event identifier, event end time in UTC, earliest deletion time (168 hours later), and exact repository inventory, including repository IDs and full names. Keep this inventory with the event closeout and in the control repository's default-branch `cleanup-events.json`. Use the shared [event cleanup record format](https://github.com/octobooth/repo-setup-scripts#event-cleanup-record). Repositories without an unambiguous event assignment must be retained.

DevRel reviews the inventory with the DRI through the pull request recorded as `review_pr`. After the 168-hour deadline, a reviewer listed in the control repository's `CLEANUP_REVIEWERS` Actions variable approves that PR's exact head commit. The reviewer must currently have write, maintain, or admin access. The PR must be merged, and its manifest must match the current manifest bytes. Editing the inventory requires a matching review; a pasted URL or verbal approval is not enough. Follow [review and run cleanup](https://github.com/octobooth/repo-setup-scripts#review-and-run-cleanup) and the [DevRel booth coordination guide](https://github.com/github/devrel/blob/main/playbooks/events/booths.md#after-the-event) (staff access required).

Do not delete before the retention deadline or without valid review. Keep environments still needed for follow-up. Have an admin verify the [cleanup rollout](#cleanup-rollout) before relying on automated gates; machine setup does not deploy cleanup workflows or change live schedules.

### Step 2: Delete only approved environments

After both gates are satisfied, preview the event's candidates, then run its reviewed [account workflow](#weekly-cleanup-in-each-booth-account) or [org workflow](#org-nightly-cleanup). Inspect the dry run before requesting deletion. Remove local demo folders only if the review also approves that removal. Keep shared checkouts such as `machine-setup`, `repo-setup-scripts`, `tailspin-toys`, and `security-octo-supply`. Rerunning [setup](../README.md#setup-instructions) does not remove or reset them.

### Step 3: Reset the booth accounts (org admins)

Reset an account only after its retained environments have been reviewed and no protected work remains. Account-wide cleanup must use the same event and review gates; see [How to clean all Octobooth repos](#how-to-clean-all-octobooth-repos).

## Clean up demo repos

The `demo-generated` topic identifies candidates, not deletion permission. Before deletion, verify each candidate's exact repository identity, event end time, 168-hour retention deadline, and current review approval. Missing or duplicate event assignments are reasons to retain a repository, not to infer its event from its creation date.

### Cleanup rollout

The procedures below require the event-aware [repo-setup-scripts cleanup](https://github.com/octobooth/repo-setup-scripts#cleanup-rollout) and [admin-tasks account template](https://github.com/octobooth/admin-tasks) to be merged and deployed. Each existing booth account's cleanup repository is a separate deployed copy and needs a deliberate reinstall; changing the template does not update those copies. Administrators must verify the deployed version, event records, designated reviewers, and a dry-run result for each account and the organization. Older age-only workflows must not delete retained environments.

Merging a pull request or running machine setup does not enable a schedule, update account copies, or prove live enforcement. Workflow deployment, credentials, and schedule changes require their own authorization.

| Cleanup location | Control repository | Review setup |
| --- | --- | --- |
| [Account weekly template](https://github.com/octobooth/admin-tasks/blob/main/templates/demo-cleanup/.github/workflows/cleanup.yml) | That account's `demo-cleanup` repository | Default-branch event manifest and `CLEANUP_REVIEWERS` |
| [Org cleanup workflow](https://github.com/octobooth/repo-setup-scripts/blob/main/.github/workflows/cleanup-demos.yml) | `octobooth/repo-setup-scripts` | Default-branch event manifest and `CLEANUP_REVIEWERS` |

Scheduled and manual runs use the same event-end and live-review gates. Repository age, confirmation flags, and an event filter cannot bypass them.

### From the Demo Launcher

Use the updated Demo Launcher to preview candidates before running the reviewed workflow.

1. Ask Copilot to "open the demo launcher" and scroll to **Clean up**.
2. Select the owner and its cleanup control repository. For a booth account, the control repository is that account's `demo-cleanup`; for org demos, it is `octobooth/repo-setup-scripts`.
3. Filter to the recorded event and preview the candidates.
4. Compare the preview with the approved inventory, then follow [review and run cleanup](https://github.com/octobooth/repo-setup-scripts#review-and-run-cleanup). Retained or ineligible entries must not be deleted manually to bypass the gate.

For a read-only candidate list from a terminal:

```bash
cd ~/repos/repo-setup-scripts
bash ./create-repo.sh --cleanup --dry-run
```

On Windows, use `.\create-repo.ps1 -Cleanup -DryRun`. These commands require the updated scripts and an existing Node.js runtime. Check the preview's eligibility results, not just repository age. The [cleanup guide](https://github.com/octobooth/repo-setup-scripts#review-and-run-cleanup) documents control-repository and event selection.

For org demos, use the [org cleanup](#org-nightly-cleanup) instead. If you type `octobooth` as the launcher's owner, the list includes demos from every booth and ChatOps.

### Weekly cleanup in each booth account

The [weekly cleanup template](https://github.com/octobooth/admin-tasks/blob/main/templates/demo-cleanup/.github/workflows/cleanup.yml) installs **Weekly demo cleanup** into `octobooth-N/demo-cleanup` and pins the shared cleanup engine to a specific commit. Each account needs its own event manifest, designated reviewers, and authorized credentials. Existing account copies require a deliberate reinstall.

<a id="run-it-sooner-just-a-browser"></a>

#### Inspect candidates without deleting

Sign in as the booth account, open its `demo-cleanup` repository's **Actions** tab, and verify the deployed workflow supports event-based cleanup. Select **Weekly demo cleanup** > **Run workflow**, enter the event identifier, keep **dry_run** enabled, and review the output against the event inventory. After the retention and review gates pass, run the same event with **dry_run** disabled to request deletion. No age or all-repositories override is supported.

#### Check that it's working

Have an admin inspect the account's deployed engine version, event manifest, reviewer configuration, and dry-run output. A green run with no eligible repositories can be correct: missing assignments, unmet retention, or invalid reviews must retain environments. Investigate the reported reason rather than bypassing it.

### Org nightly cleanup

> [!IMPORTANT]
> Verify the event-aware workflow is deployed before using this procedure. Repository-level Actions being enabled does not mean this workflow or its schedule is enabled.

In [repo-setup-scripts Actions](https://github.com/octobooth/repo-setup-scripts/actions/workflows/cleanup-demos.yml), select **Clean up demos**, enter the event identifier, and run with **dry_run** enabled. Review the result, then request execution with **dry_run** disabled only when the event record and live approval satisfy the gates. The org control repository is `octobooth/repo-setup-scripts`; account-owned environments use their own account control repositories.

## How to clean all Octobooth repos

> [!WARNING]
> Account cleanup must preserve the same event retention and live-review gates. Verify account permissions and dry-run output. Do not reuse credentials from another account or use an older wipe tool to bypass the reviewed workflow.

This section should be run by someone with admin access to the `octobooth` org, such as [@geektrainer](https://github.com/geektrainer), [@jdooley-clt](https://github.com/jdooley-clt), or someone else on the GitHub DevRel team. For everyday cleanup of demo repos, use [Clean up demo repos](#clean-up-demo-repos) instead.

The scripts are in the private [`octobooth/admin-tasks`](https://github.com/octobooth/admin-tasks) repo, and its README has every option. You need a Mac or Linux machine, the GitHub CLI, and access to `admin-tasks`.

### Get the admin scripts

1. On a fresh Mac, install [Homebrew](https://brew.sh), then the GitHub CLI: `brew install gh`.
2. Log in as yourself (an `octobooth` org member) so you can download the admin scripts:

   ```bash
   gh auth login -h github.com
   gh repo clone octobooth/admin-tasks && cd admin-tasks
   ```

   If `admin-tasks` is already on the machine, run `cd admin-tasks && git pull` instead.

### Wipe every repo in the booth accounts

Use each account's [reviewed cleanup workflow](#weekly-cleanup-in-each-booth-account), not blanket repository deletion. Environments without a valid event record and current review must remain. Keep canonical templates, tooling repositories, and local state that was not approved for removal. See [admin-tasks](https://github.com/octobooth/admin-tasks) for the account-maintenance entry points and rollout instructions.

### Set up or repair the weekly cleanup

Use the updated [setup script](https://github.com/octobooth/admin-tasks/blob/main/scripts/setup-weekly-cleanup.sh) only after the shared engine and account template are available and an administrator has authorized deployment. Deliberately reinstall each existing account copy, preserving its event manifest and reviewer configuration, then inspect a dry run. Credential repairs and schedule activation need separate approval; machine setup does neither.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| `gh auth status` shows your personal account (or another booth account) | Run `gh auth logout -h github.com`, then `gh auth login -h github.com` as this machine's booth account and add the scopes. See [GitHub CLI login](setup-reference.md#github-cli-login). |
| Setup ends with "The following setup items need attention" | Keep the earlier error output for each item. See [Windows package errors](setup-reference.md#troubleshooting-windows-package-installs) or [editor extension diagnostics](setup-reference.md#editor-extension-installation-failures), fix the cause, then rerun; finished steps are skipped. |
| "open the demo launcher" doesn't work | [Update the Demo Launcher](#before-each-booth-day-update-the-machine), which also reinstalls its loader, then fully quit and reopen the GitHub Copilot app (on Windows, right-click its tray icon and choose **Quit**). If it still doesn't open, ask from a session in the repo-setup-scripts project. |
| The pinned session still shows the old launcher after an update | It's probably a **New worktree** session, which keeps its own copy. Archive it and start a new **Current checkout** session in the repo-setup-scripts project. |
| Two "Demo Launcher" canvases, both labeled Personal | One was installed from a URL (it's named `demo-launcher-loader`). Remove `demo-launcher-loader` from the Copilot app's **Extensions** screen, or delete `~/.copilot/extensions/demo-launcher-loader` (`$HOME\.copilot\extensions\demo-launcher-loader` on Windows). Then re-run `install-demo-launcher.sh` or `install-demo-launcher.ps1` and restart the app. |
| A "Demo Launcher" labeled "repository: security-octo-supply-v4-…" | It comes from a demo repo made from the old v4 template, which included a HydraFusion launcher (since removed). Remove that demo project from the Copilot app. |
| Setup warns "Couldn't download Playwright MCP" | Check network access and the configured bundle's release assets, then rerun the [update](#before-each-booth-day-update-the-machine). Verify browser tools work before booth use; see [Playwright MCP server](setup-reference.md#playwright-mcp-server). |
| Cleanup reports insufficient permissions | Confirm the booth account and required scopes, then follow the [reviewed workflow](https://github.com/octobooth/repo-setup-scripts#review-and-run-cleanup). Permission changes do not replace event retention or review approval. |
| Copilot sessions stay "busy" and never answer | An `npx` Playwright MCP entry can hang because npm is blocked. See [Copilot sessions stuck at "busy"](setup-reference.md#copilot-sessions-stuck-at-busy), refresh the managed entry, then fully quit and reopen Copilot. |
| A booth account's weekly cleanup run failed | Ask an admin to inspect the failure and the retention/review gates before [repairing credentials or the workflow](#set-up-or-repair-the-weekly-cleanup). |
| Demo repos in a booth account aren't being deleted | Check the event assignment, 168-hour deadline, current manifest, reviewer access, and exact-head approval timing. Review the dry-run reason; do not use an age-only override. |
| (Admins) The weekly cleanup setup script says a token belongs to the wrong account | The browser was signed in as another account. Delete that stray token in the other account's token settings, switch the browser to the right account, and make a new one. |
| (Admins) `gh repo clone octobooth/admin-tasks` says "Could not resolve" | Log in to the GitHub CLI as your own org-member account: `gh auth login -h github.com`. |
| (Admins) The wipe script asks for `delete_repo` | Approve it in the browser while signed in as that booth account. |
