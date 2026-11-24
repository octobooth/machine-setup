# Booth Machine Setup

Set up a macOS or Windows machine for GitHub booth demos. Setup will:

- install Copilot app, Copilot CLI, VS Code and Insiders, GitHub CLI, Node.js LTS, VLC, and platform tools.
- configure editors and browser tooling.
- install the [Demo Launcher](https://github.com/octobooth/repo-setup-scripts) with demo repositories in `~/repos`.

## Setup instructions

You need an internet connection, administrator credentials, and this machine's booth account (`octobooth-N`). You'll use that account in GitHub CLI, the browser, editors, and Copilot app. Back up any existing VS Code and Insiders settings before running setup.

### macOS setup

1. Open **Terminal**.
2. Paste and run the following:

   ```bash
   ( installer=$(mktemp "${TMPDIR:-/tmp}/machine-setup.XXXXXXXX") || exit 1; trap 'rm -f "$installer"' EXIT; curl -fsSL "https://raw.githubusercontent.com/octobooth/machine-setup/main/bootstrap.sh" -o "$installer" && bash "$installer" --ref main )
   ```

3. Follow any Xcode Command Line Tools, administrator-password, default-browser, and GitHub sign-in prompts.

### Windows setup

1. Open the **Start** menu.
2. Type **Windows PowerShell** in the search box.
3. Select **Run as administrator** for **Windows PowerShell**.
4. Select **Yes** when Windows asks to allow changes to your device. Enter administrator credentials if prompted.
5. Paste and run the following in the PowerShell window:

   ```powershell
   & { $ErrorActionPreference = 'Stop'; $installer = Join-Path ([IO.Path]::GetTempPath()) ("machine-setup-" + [guid]::NewGuid().ToString() + '.ps1'); try { Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/octobooth/machine-setup/main/bootstrap.ps1" -OutFile $installer; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Ref main; if ($LASTEXITCODE -ne 0) { throw "Setup failed (exit $LASTEXITCODE). Review the errors above." } } finally { if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer -Force } } }
   ```

6. Follow any installation and GitHub sign-in prompts.
7. After setup, open a new PowerShell window to pick up the updated `PATH`.

### Check that the machine is ready

1. Read the final readiness results, confirm the displayed GitHub CLI account is this machine's booth account, and confirm setup completed successfully.
2. Sign in to **Copilot**, **VS Code**, **VS Code Insiders**, and the browser as the same booth account. These sign-ins are separate.
3. Fully quit and reopen Copilot, then ask it to **"open the demo launcher"**. On Windows, quit from the system tray; closing the window is not enough.
4. Before an event, complete the [booth readiness checklist](docs/booth-playbook.md#check-that-the-machine-is-ready), including a real demo.

## What setup does

- **Installs apps and developer tools:** Copilot app, Copilot CLI, VS Code, VS Code Insiders, GitHub Desktop, GitHub CLI, Git, Node.js LTS, Python, and VLC. Package lists are in [`config.json`](config.json).
  - **On macOS:** Installs Xcode Command Line Tools, Homebrew, jq, Chrome, iTerm2, and fonts; configures Node.js through nvm; sets Chrome as the default browser; configures iTerm2 light/dark appearance and fonts; and adds the booth apps to the Dock.
  - **On Windows:** Installs PowerShell and Windows Terminal through winget and pins the booth apps to the taskbar when run as administrator.
- **Configures editors:** Installs the configured VS Code extensions in both editors and applies the booth theme.
- **Configures GitHub CLI:** Reuses the active login or prompts for sign-in, requests missing demo scopes, and installs the configured CLI extensions. See [accounts and scopes](docs/setup-reference.md#github-cli-login).
- **Clones demo repositories:** Places the configured repositories in `~/repos` (`$HOME\repos` on Windows), preserving existing checkouts.
- **Installs the Demo Launcher:** Registers the loader from the trusted `repo-setup-scripts` checkout for Copilot sessions. Do not also install it from a URL in Copilot. If you add that checkout as a project, use **Current checkout**, not a new worktree. See [launcher details](docs/setup-reference.md#demo-launcher).
- **Configures VLC:** Enables looping and hides filename/title overlays.
- **Configures Copilot tools:** Registers the Microsoft Learn, Astro, and Svelte MCP servers and downloads a checksum-verified, prebuilt [Playwright MCP server](docs/setup-reference.md#playwright-mcp-server) from GitHub releases, without `npx`.
- **Checks package sources:** Checks existing npm and pip settings and reports NuGet sources without changing configuration or installing packages. Review failures and unverified checks before demos; see [package-source readiness](docs/setup-reference.md#managed-devices-and-package-feeds).
- **Adds booth instructions:** Requires approved sources for package downloads and recommends dependency-free apps or a [Cloud session or Codespace](docs/booth-playbook.md#framework-apps-need-a-cloud-session) when those sources are unavailable. See [Copilot booth instructions](docs/setup-reference.md#copilot-booth-instructions).
- **Supports reruns and releases:** Skips completed installations where supported and can select a tested launcher release. See [rerunning or updating](docs/setup-reference.md#rerunning-or-updating) and [release selection](docs/setup-reference.md#using-a-release).
- **Checks readiness:** Verifies configured packages, Node.js availability, GitHub CLI identity and scopes, read access to configured repositories, local checkout presence, and nonempty Demo Launcher files. Failed checks appear in the final summary and make setup exit unsuccessfully. App sign-ins and running a real demo remain manual.
- **Reports device enrollment:** Checks MDM enrollment without changing management settings. Unknown enrollment does not block setup or establish package-feed access.

## Troubleshooting

- **Failed or skipped steps:** Resolve the reported issue and rerun the same setup command; completed work is normally skipped.
- **GitHub sign-in:** If `gh` is already installed, run `gh auth status --active -h github.com` and [switch to the booth account](docs/setup-reference.md#github-cli-login) if needed. Leave `GH_TOKEN`, `GITHUB_TOKEN`, and `NONINTERACTIVE` unset for normal booth setup.
- **Windows package installs:** See [winget troubleshooting](docs/setup-reference.md#troubleshooting-windows-package-installs). The bootstrap does not repair package sources.
- **PowerShell execution policy:** The setup command bypasses execution policy only for its child processes; organization policy still takes precedence. Windows PowerShell 5.1 is supported.
- **Existing editor settings:** If the theme step cannot parse or write settings, it preserves the original and reports a failure. For [settings containing comments](docs/setup-reference.md#existing-vs-code-settings), select the theme in the editor.
- **Download failures or missing/duplicate launchers:** Use the [setup reference](docs/setup-reference.md#troubleshooting). The bootstrap does not repair network connectivity.

## Development and testing

Package lists and settings live in [`config.json`](config.json). See [script structure](docs/development.md#script-structure), [configuration](docs/development.md#configuration), and [local checks](docs/development.md#local-checks).

For running demos and cleanup, use the [booth playbook](docs/booth-playbook.md).

[MIT license](LICENSE).
