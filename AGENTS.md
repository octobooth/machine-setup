# AGENTS.md

Guide for AI coding agents and new maintainers. It summarizes the practices to follow and links to the docs that have the details. Don't duplicate those docs here; update them instead.

## What this repo is

Booth machine setup for GitHub event booths. It's public and MIT-licensed.

- **macOS:** [`setup.sh`](setup.sh), [`install-demo-launcher.sh`](install-demo-launcher.sh) (also works on Linux), and iTerm2 color schemes in [`iterm2/`](iterm2/).
- **Windows:** [`setup.ps1`](setup.ps1), [`install-demo-launcher.ps1`](install-demo-launcher.ps1), and [`windows/demo-launcher-loader.mjs`](windows/demo-launcher-loader.mjs) (a fallback copy of repo-setup-scripts' loader; keep it in sync).
- **[`config.json`](config.json)** drives both: packages, editors, VS Code extensions, `gh` extensions and scopes, MCP servers, Dock/taskbar apps, and `repos_to_clone`.
- Setup clones the demo repos to `~/repos` (`$HOME\repos` on Windows) and installs the Demo Launcher loader for [`octobooth-demos/repo-setup-scripts`](https://github.com/octobooth-demos/repo-setup-scripts), which holds the demos and the launcher itself.

Docs to read first:

- [README](README.md): [macOS setup](README.md#macos-setup), [Windows setup](README.md#windows-setup-clean-machine), [GitHub CLI login](README.md#github-cli-login), [Using a release](README.md#using-a-release), [Demo Launcher](README.md#demo-launcher), [Development and Testing](README.md#development-and-testing).
- [Booth playbook](docs/booth-playbook.md): before, during, and after an event.
- [Releasing](https://github.com/octobooth-demos/repo-setup-scripts/blob/main/docs/releasing.md) (in repo-setup-scripts): the shared release process for both repos.

## Branches and releases

- Changes land on `main` through pull requests, and are tested there. Maintainer and dev machines track `main`.
- Booth machines run the moving major tag **`v1`** of this repo *and* repo-setup-scripts: `--ref v1` (`-Ref v1` on Windows) or the `BOOTH_RELEASE` environment variable. Merging to `main` never changes a booth machine.
- A release tags **both** repos with the same `vX.Y.Z`, at the commits that were tested on a booth Mac and a Windows machine, then moves the matching major tag (`v1`) to it.
- Never move or delete a pushed `vX.Y.Z` tag. Only the major tag moves.
- **Agents must not create, move, or delete tags, or publish releases, unless explicitly asked.**

## Change rules

Follow these when changing the scripts, and check for them when reviewing a pull request.

- **Parity.** When a feature applies to both platforms, change `setup.sh`/`install-demo-launcher.sh` and `setup.ps1`/`install-demo-launcher.ps1` together, with matching behavior and messages.
- **Windows PowerShell 5.1.** Fresh Windows machines only have 5.1, so the `.ps1` scripts must run there. No PowerShell 7-only syntax (`??`, `?.`, ternary `? :`, `&&`/`||` pipeline chains, `ForEach-Object -Parallel`, etc.).
- **Native commands on Windows.** Run `git`, `gh`, `winget`, and editor CLIs through the native-command helper (`Invoke-NativeCommand` in `setup.ps1`, shared with `install-demo-launcher.ps1`). In 5.1, `2>&1` turns normal stderr progress into red `ErrorRecord`s, and under `$ErrorActionPreference = 'Stop'` it throws even with `2>$null`. The helper prints stderr as plain text and leaves success to `$LASTEXITCODE`. Interactive `gh auth login`/`refresh` stay direct.
- **Admin.** `install-demo-launcher.ps1` must not require an Administrator prompt. `setup.ps1` needs Terminal (Admin) for some steps; it warns and skips them when not elevated (`Test-IsAdmin`, `Write-NotAdminWarning`).
- **Trusted origin.** Keep the checks that only fetch, pull, check out, or install the loader for a checkout whose `origin` is `octobooth-demos/repo-setup-scripts` (`demo_launcher_remote_trusted` in `setup.sh`, `Test-DemoLauncherRemote` in `setup.ps1`). The loader runs that code in every Copilot chat.
- **Release tag check.** Keep the `git ls-remote` check that a release tag exists on GitHub before checking it out (`checkout_booth_release` in `setup.sh`, `Switch-DemoLauncherRelease` in `setup.ps1`). The scripts stop without changing the checkout if the tag is missing or the checkout has local changes.
- **Testable scripts.** The scripts guard their main entry point so tests can source or dot-source them without installing anything. Keep that guard.
- **Tests and CI.** Update the bats tests (`tests/bash`) and Pester tests (`tests/powershell`) with behavior changes, and keep [CI](.github/workflows/ci.yml) green, including the Windows PowerShell 5.1 job. When adding a `config.json` key, add it to the CI shape check.
- **Docs.** Update the README and booth playbook in the same PR as the behavior change. Write for booth staff: short steps with the exact commands to type.
- **Tags.** Never move or delete a pushed `vX.Y.Z` tag; only the major tag moves (see [Branches and releases](#branches-and-releases)).

## Accounts

- Booth machines use the booth account (`octobooth-N`) for the GitHub Copilot app, the browser, VS Code, VS Code Insiders, and `gh`.
- The `gh` scopes the demos need are in `config.json` `shared.gh_auth_scopes` (see [GitHub CLI login](README.md#github-cli-login)). Unset `GH_TOKEN`/`GITHUB_TOKEN` on booth machines.
- Never use personal or staff accounts on booth machines.

## Demo Launcher gotchas

- Booth machines install the launcher with this repo's scripts, not the URL installer in the Copilot app. Never both: that gives two "Demo Launcher" canvases ([Two Demo Launchers show up](README.md#two-demo-launchers-show-up)).
- A pinned repo-setup-scripts session must use **Current checkout**, not **New worktree**, or it keeps loading the old launcher.
- Rerunning `setup.sh` without a release keeps an existing loader (unless `FORCE_REINSTALL=true`). Use `install-demo-launcher.sh` or `install-demo-launcher.ps1` to repair or update it.
- Fully quit and reopen the Copilot app to load a new launcher. On Windows, quit it from the system tray icon; closing the window isn't enough.

## Testing changes

Run the local checks that match CI (see [Local checks](README.md#local-checks)):

```bash
shellcheck --severity=warning -x setup.sh install-demo-launcher.sh
bash -n setup.sh && bash -n install-demo-launcher.sh
bats tests/bash
```

```powershell
Invoke-ScriptAnalyzer -Path .\setup.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-ScriptAnalyzer -Path .\install-demo-launcher.ps1 -Settings .\PSScriptAnalyzerSettings.psd1
Invoke-Pester -Path .\tests\powershell          # in pwsh and in powershell.exe (5.1)
```

`jq` validates the `config.json` shape in CI ([`ci.yml`](.github/workflows/ci.yml)). Unit tests don't run the installers end to end, so before a release, test the setup on a real booth Mac and a real Windows machine, at the commits you'll tag.
