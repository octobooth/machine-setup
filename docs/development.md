# Configuration and development

[Installation guide](../README.md) · [Setup reference](setup-reference.md) · [Contributor rules](../AGENTS.md)

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

For testing changes before release, push a branch and use its full commit SHA in the [bootstrap commands](../README.md#run-setup-without-cloning). The SHA pins machine-setup, not the separate demo repository. Verify the ref's bootstrap files and required archive assets are downloadable before sharing a command.
