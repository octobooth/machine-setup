# Configuration and development

[Installation guide](../README.md) · [Setup reference](setup-reference.md) · [Contributor rules](../AGENTS.md)

## Script structure

[`bootstrap.sh`](../bootstrap.sh) and [`bootstrap.ps1`](../bootstrap.ps1) download and extract the complete machine-setup archive at the requested revision, then run its setup script with terminal input available for prompts. Temporary downloads are removed when the bootstrap finishes. The bootstrap does not install individual packages.

[`setup.sh`](../setup.sh) and [`setup.ps1`](../setup.ps1) contain the provisioning functions and their orchestration entry points, `main` and `Invoke-Main`. Their entry-point guards let tests source or dot-source the files without provisioning the host.

| Phase | macOS | Windows |
| --- | --- | --- |
| Prerequisites and configuration | Install Xcode Command Line Tools, Homebrew, and jq; `load_config` reads `config.json` | `Test-Prerequisites` checks elevation and winget; `Import-Config` reads `config.json` |
| Packages and desktop settings | `install_packages`, VLC, fonts, iTerm2, Dock, and default-browser configuration | `Install-Packages`, `Set-VLCConfiguration`, and `Set-TaskbarPins` |
| GitHub and repositories | `authenticate_gh`, `clone_repos` | `Connect-GH`, `Copy-Repos` |
| Demo Launcher and instructions | `install_demo_launcher`, `install_booth_instructions` | `Sync-DemoLauncherRelease`, `Install-DemoLauncher`, `Install-BoothInstruction` |
| Editors and MCP tools | `configure_editors`, `install_playwright_mcp_bundle`, `register_mcp_servers` | `Initialize-Editors`, `Install-PlaywrightMcpBundle`, `Register-MCPServers` |
| Readiness and summary | `check_setup_readiness`, `print_summary` | `Test-SetupReadiness`, `Write-Summary` |

`try_install` and `Invoke-SafeInstall` collect failures so setup can continue with independent steps and report problems together. Functions that handle their own failures also update `failed_items` or `$script:failedItems`. Readiness checks run before the final summary and add failures to the same collection; a nonempty collection makes setup exit with status 1. Windows separately reports steps skipped for lack of administrator privileges.

Readiness checks query installed packages, resolve Node.js, retrieve the stored GitHub CLI account, inspect its configured scopes, query each configured repository's metadata, and check local checkout and launcher files. Package-source checks use existing npm/pip configuration; NuGet source inspection is read-only. They do not change package settings, sign in apps, restart Copilot, prove repository write permissions or Copilot/Codespaces licensing, or run a demo. Staff confirm the displayed account and complete those manual checks.

Device enrollment is queried by `check_device_enrollment` / `Test-DeviceEnrollment`. macOS requires an explicit MDM result from `profiles status -type enrollment`; automated enrollment alone is not enough. Windows queries the MDM registration API without requesting the user's UPN; it does not infer MDM enrollment from domain join or `dsregcmd` URLs. Query failures are informational unknowns, not unmanaged devices or setup failures. Enrollment never selects a feed or authorizes a credential change.

`check_package_sources` / `Test-PackageSources` preserve all sources and credentials, including when a check fails. Config inspection errors, missing clients, and configurations that cannot be checked populate `readiness_notes` / `$script:readinessNotes`, separately from failed metadata checks in the failure collection. Neither source URLs nor native diagnostics are printed. Feed provisioning and NuGet restore verification are not implemented.

[`install-demo-launcher.sh`](../install-demo-launcher.sh) and [`install-demo-launcher.ps1`](../install-demo-launcher.ps1) reuse setup helpers for launcher-only updates without installing the full environment. On Windows, noninteractive GitHub commands use the native-command helper so normal stderr does not become a terminating error in PowerShell 5.1; interactive login and scope-consent commands remain direct.

## Configuration

[`config.json`](../config.json) drives both platforms. Keep shared behavior in parity and add new keys to the shape check in [CI](../.github/workflows/ci.yml).

| Section | Contents |
| --- | --- |
| `shared` | Editor theme/extensions, GitHub CLI extensions/scopes, VLC settings, MCP servers, demo repositories |
| `mac` | Homebrew packages, editor paths, iTerm2 appearance, Frozen font version, Dock apps, post-install apps |
| `windows` | winget packages, editor commands, taskbar pins, post-install apps |

`pwa_sites` is present in the schema but PWA installation is disabled. Every Windows package ID must be available from the `winget` source.

### macOS appearance

`mac.iterm2.light` and `.dark` select [color-scheme files](../iterm2/README.md) and preset names. `font` is the PostScript font name and size. `theme` accepts `regular`, `minimal`, `compact`, `light`, `dark`, `light-high-contrast`, or `dark-high-contrast`. `ligatures` is a Boolean; `thin_strokes` accepts `never`, `retina-dark-backgrounds-only`, `dark-backgrounds-only`, `always`, or `retina-only`.

Setup configures the default profile and stores a marker for its selected settings. Quit iTerm2 before applying changes. To reapply unchanged values, see [marker resets](setup-reference.md#macos-fonts-iterm2-and-dock).

`mac.monaspace_frozen_version` selects the Frozen font archive from [githubnext/monaspace releases](https://github.com/githubnext/monaspace/releases). Fonts are copied to `~/Library/Fonts`. The Homebrew casks install the other configured fonts.

`mac.dock_apps` names `.app` bundles in `/Applications`, without the extension. Setup adds missing entries, hides recent/suggested apps, and preserves existing items.

### Windows taskbar

`windows.taskbar_pins` contains ordered AppIDs from `Get-StartApps`. Inspect IDs with:

```powershell
Get-StartApps | Where-Object Name -like '*VLC*'
```

Setup writes `%LOCALAPPDATA%\machine-setup\TaskbarLayout.xml`, sets the current user's `StartLayoutFile` policy under `HKCU\Software\Policies\Microsoft\Windows\Explorer`, and restarts Explorer. It requires elevation. Policy pins can reappear when removed; on Windows 10, the policy also locks Start tiles. See [Microsoft's taskbar policy documentation](https://learn.microsoft.com/windows/configuration/taskbar/pinned-apps).

To apply just this step from an elevated PowerShell in a machine-setup checkout:

```powershell
. .\setup.ps1
Import-Config
Set-TaskbarPins
```

## Local checks

Use already-installed test tools or install the missing tools separately before running these commands. Unit tests source or dot-source the scripts without provisioning the host.

### Bash

```bash
shellcheck --severity=warning -x setup.sh install-demo-launcher.sh bootstrap.sh
bash -n setup.sh && bash -n install-demo-launcher.sh && bash -n bootstrap.sh
bats tests/bash
```

### PowerShell

Run on Windows in both PowerShell 7 and Windows PowerShell 5.1:

```powershell
Invoke-ScriptAnalyzer -Path .\setup.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\install-demo-launcher.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\bootstrap.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests\powershell
```

[CI](../.github/workflows/ci.yml) also validates the config shape and PowerShell parsing. Bootstrap tests use fake archives and setup commands. End-to-end testing on a Mac and Windows machine is separate from unit tests and release publication.

## Playwright MCP bundle

[`mcp-bundle/package.json`](../mcp-bundle/package.json) and its lockfile pin the prebuilt server. The [bundle workflow](../.github/workflows/playwright-mcp-bundle.yml) builds and tests version changes, including installation under Windows PowerShell 5.1, and publishes versioned bundle assets on `main`.

Update the dependency and lockfile together, following the workflow's version and registry checks. Review the build and installation results before publishing a bundle.

The `playwright-mcp-v<version>` release is separate from the paired booth release. Setup requires both the archive and checksum. Do not replace/delete a published bundle or manually run its publish workflow without explicit authorization. A failed or partial publication requires maintainer review, not a source-release fallback.

## Releases

Follow the shared [release process](https://github.com/octobooth/repo-setup-scripts/blob/main/docs/releasing.md). Both repositories use matching `vX.Y.Z` versions; only the major alias (`v1`) moves. Never move or delete an immutable version tag. Release/tag changes require explicit authorization.

The [README commands](../README.md#setup-instructions) always download and run `main` so the installation guide and setup scripts stay aligned. Bootstrap tests execute those commands with stubbed downloads and check their requested source and revision.

For testing changes before release, push a branch and pass its full commit SHA to a local bootstrap using `--ref` on macOS or `-Ref` on Windows. The SHA pins machine-setup, not the separate demo repository. Verify the ref's bootstrap files and required archive assets are downloadable before sharing a test command; do not pin the README commands to it.
