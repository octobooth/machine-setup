# Booth Machine Setup

Set up a macOS or Windows machine for GitHub booth demos. Setup installs Copilot, VS Code and Insiders, GitHub CLI, Node.js LTS, VLC, and platform tools; configures editors and browser tooling; and installs the [Demo Launcher](https://github.com/octobooth/repo-setup-scripts) with demo repositories in `~/repos`.

## Setup instructions

You need an internet connection, administrator credentials, and this machine's booth account (`octobooth-N`). Use that account in GitHub CLI, the browser, editors, and Copilot. If `gh` is already installed, check `gh auth status --active -h github.com` before starting; [switch accounts](docs/setup-reference.md#github-cli-login) if needed. Leave `GH_TOKEN`, `GITHUB_TOKEN`, and `NONINTERACTIVE` unset for normal booth setup.

### Run setup without cloning

Paste the block for your platform. It downloads all setup files, runs setup with terminal input available for prompts, and removes the temporary download afterward. No manual Git installation or clone is needed.

> [!NOTE]
> These commands test the published [cross-platform setup branch](https://github.com/octobooth/machine-setup/tree/geektrainer/clone-free-booth-installation), pinned to [`d8d2910`](https://github.com/octobooth/machine-setup/commit/d8d291093ecb999c95c73728aabcacc3950fd2c5). The bootstrap files are not on `main` or `v1.3.0`. To use the released scripts instead, follow [release installation](docs/setup-reference.md#using-a-release).

### macOS setup

Quit iTerm2, open **Terminal** as your normal user, and paste:

```bash
(
  ref=d8d291093ecb999c95c73728aabcacc3950fd2c5
  installer=$(mktemp "${TMPDIR:-/tmp}/machine-setup.XXXXXXXX") || exit 1
  trap 'rm -f "$installer"' EXIT
  curl -fsSL "https://raw.githubusercontent.com/octobooth/machine-setup/$ref/bootstrap.sh" -o "$installer" &&
    bash "$installer" --ref "$ref"
)
```

Follow any Xcode Command Line Tools, administrator-password, default-browser, and GitHub sign-in prompts. Setup reuses a valid active GitHub CLI login and asks only for missing scopes.

<a id="windows-setup-clean-machine"></a>

### Windows setup

Open **Terminal (Admin)** or **Windows PowerShell (Admin)**, approve UAC, and use a **PowerShell** tab. Windows PowerShell 5.1 is supported. First check that the package source works:

```powershell
winget show --id Git.Git -e --source winget
```

If that fails, fix [App Installer or the winget source](docs/setup-reference.md#troubleshooting-windows-package-installs) before continuing.

> [!WARNING]
> On an existing Windows machine, back up VS Code and Insiders settings before testing. The theme step can overwrite settings containing comments under PowerShell 5.1. A clean test VM avoids this [known JSONC issue](docs/setup-reference.md#existing-vs-code-settings).

Paste the whole block; use `curl.exe`, not PowerShell's `curl` alias:

```powershell
& {
    $ErrorActionPreference = 'Stop'
    $ref = 'd8d291093ecb999c95c73728aabcacc3950fd2c5'
    $installer = Join-Path ([IO.Path]::GetTempPath()) ("machine-setup-" + [guid]::NewGuid().ToString() + '.ps1')
    try {
        curl.exe -fsSL "https://raw.githubusercontent.com/octobooth/machine-setup/$ref/bootstrap.ps1" -o $installer
        if ($LASTEXITCODE -ne 0) { throw "Bootstrap download failed (exit $LASTEXITCODE)." }
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $installer -Ref $ref
        if ($LASTEXITCODE -ne 0) { throw "Setup failed (exit $LASTEXITCODE). Review the errors above." }
    } finally {
        if (Test-Path -LiteralPath $installer) { Remove-Item -LiteralPath $installer -Force }
    }
}
```

Follow any installation and GitHub sign-in prompts. Execution-policy bypass applies only to the child processes; organization policy still takes precedence. After setup, open a new terminal to pick up the updated `PATH`.

### Check that the machine is ready

1. Read the final summary and resolve failed or skipped steps. Rerun the same block to retry; completed work is normally skipped.
2. Run `gh auth status --active -h github.com`. Confirm the booth account and the `codespace`, `delete_repo`, `project`, and `workflow` scopes.
3. Sign in to **Copilot**, **VS Code**, **VS Code Insiders**, and the browser as the same booth account. These sign-ins are separate.
4. Fully quit and reopen Copilot, then ask it to **"open the demo launcher"**. On Windows, quit from the system tray; closing the window is not enough.
5. Before an event, complete the [booth readiness checklist](docs/booth-playbook.md#check-that-the-machine-is-ready), including template access and a real demo.

## Additional details

### Demo Launcher

Setup installs it automatically from `~/repos/repo-setup-scripts` (`$HOME\repos\repo-setup-scripts` on Windows). Do not also install it from a URL in Copilot. If you add the repository as a project, use that existing local folder and a **Current checkout** session, not a new worktree. See [launcher updates and troubleshooting](docs/setup-reference.md#demo-launcher).

### GitHub CLI login

A valid active login is reused; missing scopes prompt for consent. Setup does not sign in the browser, editors, or Copilot for you. See [account switching, scopes, and access checks](docs/setup-reference.md#github-cli-login).

### Using a release

Use the same release version for machine-setup and repo-setup-scripts. A full tag such as `v1.3.0` pins a version; `v1` can move. The commit-pinned commands above select only machine-setup and leave the demo repository in development mode. See [release installation and ref behavior](docs/setup-reference.md#using-a-release).

<a id="re-running-on-a-mac-thats-already-set-up"></a>
<a id="re-running-on-a-windows-machine-thats-already-set-up"></a>
<a id="upgrade-an-existing-machine-to-octobooth"></a>

### Rerunning or updating

Rerun the same installation command to retry setup. Existing packages are generally left alone, not upgraded. Preserve local work; setup does not rewrite existing repositories' origins. See [reruns, launcher-only updates, and existing clones](docs/setup-reference.md#rerunning-or-updating).

<a id="copilot-booth-instructions"></a>

### Booth network limits

Booth networks block public npm and Python package downloads. Use plain HTML/CSS/JavaScript locally, or a [Cloud session or Codespace](docs/booth-playbook.md#framework-apps-need-a-cloud-session) for framework apps. Setup adds [Copilot instructions](docs/setup-reference.md#copilot-booth-instructions) for this environment.

### Playwright MCP server

Setup downloads a prebuilt browser-tools bundle from [GitHub releases](https://github.com/octobooth/machine-setup/releases?q=playwright-mcp&expanded=true), without `npx`. Check warnings: a failed bundle download can leave browser tools unavailable even when other setup steps finish. See [installed paths and configuration](docs/setup-reference.md#playwright-mcp-server).

<a id="troubleshooting-windows-package-installs"></a>
<a id="two-demo-launchers-show-up"></a>
<a id="copilot-sessions-stuck-at-busy"></a>

### Troubleshooting

For download failures, winget errors, editor settings, or missing/duplicate launchers, use the [setup reference](docs/setup-reference.md#troubleshooting). The bootstrap does not repair network connectivity or package sources.

<a id="configuration"></a>
<a id="local-checks"></a>

### Development and testing

Package lists and settings live in [`config.json`](config.json). See [configuration and local checks](docs/development.md). The test-branch scripts still need end-to-end testing on macOS and Windows; publishing a branch or release does not provision or validate a machine.

For running demos and cleanup, use the [booth playbook](docs/booth-playbook.md). [MIT license](LICENSE).
