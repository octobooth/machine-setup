# Setup reference

[Installation commands](../README.md#setup-instructions) · [Booth playbook](booth-playbook.md) · [Developer reference](development.md)

## GitHub CLI login

Setup uses the active stored GitHub CLI account. It requests a web login over HTTPS if needed and refreshes only missing scopes. Check the browser's account before approving OAuth, SSO, or two-factor authentication.

Check or switch a saved account, replacing `octobooth-N` with this machine's account:

```bash
gh auth status --active -h github.com
gh auth switch -h github.com -u octobooth-N
```

If the account is not saved, sign in and add the demo scopes:

```bash
gh auth login --web --git-protocol https -h github.com
gh auth refresh -h github.com -s codespace,delete_repo,project,workflow
gh auth status --active -h github.com
```

| Scope | Used for |
| --- | --- |
| `codespace` | Tailspin Toys Codespaces |
| `delete_repo` | Demo cleanup |
| `project` | Copilot Airways Projects and cleanup |
| `workflow` | Pushing demo repositories containing Actions workflows |

Unset `GH_TOKEN` and `GITHUB_TOKEN` on booth machines: they override stored credentials in ordinary `gh` commands. Interactive setup ignores them for its stored-login checks. Browser, editor, and Copilot sign-ins remain separate.

The booth account needs access to [octobooth](https://github.com/octobooth), permission to create demo repositories, and access to the internal [Tailspin Toys](https://github.com/octobooth/tailspin-toys) and [Octo Supply](https://github.com/octobooth/security-octo-supply) templates. Verify Copilot licensing, Codespaces/billing, and security-demo features as that account. A successful CLI login does not prove those permissions.

## Managed devices and package feeds

Setup reports MDM enrollment as **enrolled**, **not enrolled**, or **unknown** for information only. Unknown enrollment does not fail setup or prevent package checks. On macOS, setup reads `profiles status -type enrollment`; on Windows, it calls [IsDeviceRegisteredWithManagement](https://learn.microsoft.com/windows/win32/api/mdmregistration/nf-mdmregistration-isdeviceregisteredwithmanagement). Domain membership or an advertised MDM URL alone is not proof of enrollment.

Setup checks existing npm and pip sources first, using their current credentials, proxy, and certificate settings. Working settings are retained. The npm check reads `create-vite` metadata with a fresh temporary cache; the pip check reads package-index metadata without a cache or interactive login. Neither installs a package. Network requests use a 15-second timeout and no retries. Source URLs and native diagnostics are withheld because they can contain credentials.

Failed metadata checks add an error to the final summary without changing package settings. Check the existing source's network access and effective configuration, including environment, project, or command-specific overrides. Missing clients and configurations that cannot be inspected or checked are listed separately as **unverified**. Resolve access with device support; setup does not provision feeds, replace a registry or index, or change VPN, identity, or security controls.

NuGet checks list enabled sources through `dotnet nuget list source --format short`, without changing configuration or credentials. Authenticated restore remains unverified. Use the existing [Azure Artifacts Credential Provider](https://github.com/microsoft/artifacts-credprovider) and a trusted project to validate restore separately; setup does not install a provider or introduce a corporate login.

Metadata success is not proof of policy approval, archive downloads, or a successful demo. Public-style configuration can route through managed controls; its URL alone is not evidence of a bypass. npm configuration also controls `npx` and `npm create vite`, but project settings, pinned artifact URLs, and tools' separate binary downloads need their own checks. Keep machine-specific sources and credentials out of public repository configuration and lockfiles. Do not sign in with a staff account, copy tokens between machines, or switch to public registries after a feed failure. If an approved package route is unavailable, use the [cloud-session workflow](booth-playbook.md#framework-apps-need-a-cloud-session).

## Using a release

The paired [machine-setup v1.3.0](https://github.com/octobooth/machine-setup/releases/tag/v1.3.0) and [repo-setup-scripts v1.3.0](https://github.com/octobooth/repo-setup-scripts/releases/tag/v1.3.0) releases are published. Use a matching full version for both repositories. `v1` is a moving major tag, not a separate installation mode.

To use the released scripts, download and extract the [v1.3.0 ZIP](https://github.com/octobooth/machine-setup/archive/refs/tags/v1.3.0.zip), keeping all files together. Open a terminal in the extracted folder and run:

macOS:

```bash
bash setup.sh --ref v1.3.0
```

Windows, from **Terminal (Admin)**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 -Ref v1.3.0
```

Use the [README prerequisites and readiness checks](../README.md#setup-instructions) with either installation path. Verify the setup and demos on the intended machines before an event.

### Ref behavior

| Entry point | What `--ref` / `-Ref` selects |
| --- | --- |
| `bootstrap.sh` / `bootstrap.ps1` with a release tag | Downloads that machine-setup release and passes the same tag to repo-setup-scripts. The tag must contain the bootstrap files. |
| Bootstrap with a full 40-character commit SHA | Downloads that exact machine-setup commit. Clears an inherited `BOOTH_RELEASE`; does not pass the SHA to the separate demo repository. |
| Bootstrap with `main` | Downloads machine-setup `main` and runs demo setup in development mode. Requires bootstrap files on `main`. |
| Local `setup` or `install-demo-launcher` script | Selects the repo-setup-scripts release only; does not change the machine-setup folder you are running. |

For the bootstrap, an explicit ref wins over `BOOTH_RELEASE`; with neither, the default is `main`. Only `main`, `vN`, `vX.Y.Z`, and full commit SHAs are accepted, not arbitrary branch names. Use the same ref in the raw bootstrap URL and its argument, as the [README commands](../README.md#setup-instructions) do.

Without a release, a demo checkout pinned to a tag returns to its default branch. Existing branch checkouts can be retained; development mode is not a reproducible pin of both repositories. Release selection checks that the tag exists on GitHub and refuses tracked local changes. Keep untracked files safe too.

## Rerunning or updating

Rerunning the same bootstrap command downloads fresh temporary files and skips already-completed setup work. It does not create a persistent machine-setup checkout. A downloaded ZIP also has no update mechanism: download it again when selecting a different revision.

Existing Homebrew/winget packages are normally left alone, not upgraded. Editor and CLI extensions, settings markers, and existing demo clones are checked before repeating work. Use the package manager's upgrade command when you intend to upgrade an app.

`FORCE_REINSTALL=true` bypasses most skip checks. Windows `NONINTERACTIVE=true` skips CLI login, scope refresh, and the non-admin pause; it is not a way to complete first-time authentication. Missing credentials defer extension/repository work. Leave it unset for normal interactive setup.

### Existing clones

Before updating a checkout, inspect `git remote -v`, `git status --short --untracked-files=all`, and `git worktree list` in it. Preserve all local work and linked worktrees. If the origin, repository history, or existing folder is unexpected, stop for maintainer review; do not reset, force-pull, or change origins as a troubleshooting shortcut.

The Demo Launcher only accepts a checkout whose origin is [octobooth/repo-setup-scripts](https://github.com/octobooth/repo-setup-scripts). Setup does not redirect an existing clone from another organization.

## Demo Launcher

Setup installs a loader under `~/.copilot/extensions/demo-launcher` (`$HOME\.copilot\extensions\demo-launcher` on Windows), or under `COPILOT_HOME` if set. It loads the launcher from `~/repos/repo-setup-scripts`. Keep that checkout; removing it breaks the launcher.

After installation, fully quit and reopen Copilot. On Windows, quit from the system tray. Ask **"open the demo launcher"** in a chat. To pin a session, add the existing local repo-setup-scripts folder as a project and choose **Current checkout**, not **New worktree**.

### Launcher-only updates

Use a complete machine-setup archive or checkout at the version you want. From that folder, update the launcher with the same release version:

```bash
bash install-demo-launcher.sh --ref v1.3.0
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\install-demo-launcher.ps1 -Ref v1.3.0
```

These commands require Git and an authenticated GitHub CLI; Bash also needs `jq`. The Windows launcher-only installer does not need elevation. The Bash launcher-only installer supports macOS and Linux; full machine setup supports macOS and Windows only.

The installer clones or updates the trusted demo checkout, refreshes the loader, booth instructions, and MCP configuration, and installs the pinned Playwright bundle. Restart Copilot afterward. Running a local installer without a ref uses development behavior unless `BOOTH_RELEASE` is set. Do not pass a machine-setup commit SHA to these local installers.

To remove only the loader, use `bash install-demo-launcher.sh --uninstall` or `.\install-demo-launcher.ps1 -Uninstall`. The demo checkout and run history are kept.

## Troubleshooting

### Download failures

The bootstrap needs HTTPS access to `raw.githubusercontent.com`, `github.com`, and `codeload.github.com`. A failed download or extraction stops before setup. Fix the network/proxy issue, then rerun the same command. Do not disable TLS validation.

### Troubleshooting Windows package installs

If `winget` is missing, update **App Installer** in Microsoft Store and reopen Terminal. Test the actual source, not just `winget --version`:

```powershell
winget show --id Git.Git -e --source winget
```

If it reports `0x8a15000f` ("Data required by the source is missing"), repair App Installer/source access before rerunning setup. A GitHub connection timeout is a separate network failure; check HTTPS connectivity before retrying.

Setup explicitly selects `--source winget` to avoid unrelated Microsoft Store certificate errors such as [`microsoft/winget-cli#3109` (pinned certificate mismatch)](https://github.com/microsoft/winget-cli/issues/3109). Do not disable certificate checks or reset all sources blindly. Check App Installer updates and whether a proxy/security product intercepts HTTPS.

For a failed package, retry that package using its ID from [`config.json`](../config.json), for example:

```powershell
winget install --id Microsoft.VisualStudioCode -e --source winget --accept-source-agreements --accept-package-agreements
```

Without administrator privileges, full Windows setup skips taskbar pins and some installs may fail. Rerun from **Terminal (Admin)** and check the final summary.

### Editor extension installation failures

The final summary names failed extensions; the earlier `Failed: ... extension: ... (exit code: ...)` block includes the editor CLI's output. Keep that whole block when reporting a failure. A summary alone does not distinguish Marketplace connectivity, editor compatibility, permissions, or other CLI errors.

For a VS Code Insiders failure, these read-only commands show which CLI is selected, its version/architecture, and whether the extension is already installed:

```powershell
Get-Command code-insiders -All | Select-Object CommandType, Source
code-insiders --version
code-insiders --list-extensions --show-versions
```

Check for the failed extension's ID in the list. Its absence does not identify why installation failed. If the run used a revision that suppressed the CLI output, inspect VS Code Insiders' **Developer: Open Logs Folder** for entries around the setup time and extension ID. Share the relevant error lines, with credentials and sensitive paths redacted. See the [VS Code CLI reference](https://code.visualstudio.com/docs/configure/command-line).

### Existing VS Code settings

Theme updates are prepared in a temporary file beside the editor's `settings.json` and replace it only after parsing and serialization succeed. Parsing or writing failures preserve the original file and appear in the final setup failure summary. Back up existing settings before setup.

The macOS JSON parser and Windows PowerShell 5.1 reject JSONC comments. If setup reports a theme parsing failure, keep your settings and use the editor's **Preferences: Color Theme** command to select the theme named in [`config.json`](../config.json). Do not remove unrelated settings or comments just to make setup pass.

### Two Demo Launchers show up

If both are labeled **Personal**, remove the URL-installed `demo-launcher-loader` from Copilot's **Extensions** screen. Keep the script-installed `demo-launcher`; rerun the launcher installer and restart Copilot.

If one is project-scoped, it comes from an added repository. Remove the duplicate project from Copilot if unnecessary, but preserve its files and any work. A pinned worktree session can also retain an old launcher; preserve its work and replace it with a **Current checkout** session.

### Copilot sessions stuck at "busy"

Check `~/.copilot/mcp-config.json` (`$HOME\.copilot\mcp-config.json` on Windows). A Playwright entry using `npx` can hang on booth networks. Rerun setup or the launcher installer to replace the managed `npx @playwright/mcp` entry with the prebuilt bundle, then restart Copilot. Custom Playwright entries are left alone.

### macOS fonts, iTerm2, and Dock

Quit iTerm2 before running setup; it can overwrite changed preferences when it quits. Setup skips matching configuration markers. To reapply one setting, clear only its marker, then rerun setup:

```bash
defaults delete com.googlecode.iterm2 MachineSetupITerm2Settings
rm ~/Library/Fonts/.monaspace-frozen-version
```

The first command resets iTerm2's setup marker; the second resets the Frozen font-version marker. Run only the one you need. Dock entries are added without removing existing items. Default-browser consent remains an interactive macOS step.

## Copilot booth instructions

Setup manages a block in `~/.copilot/copilot-instructions.md`, or `COPILOT_HOME/copilot-instructions.md`. Its content comes from [`copilot/booth-instructions.md`](../copilot/booth-instructions.md) and requires approved package sources for local downloads, with dependency-free demos or Cloud sessions when those sources are unavailable. Content outside the `BEGIN machine-setup booth instructions` / `END machine-setup booth instructions` markers is preserved.

Setup and launcher-only updates refresh the block. For framework demos without working approved package access, use the [Cloud/Codespaces workflow](booth-playbook.md#framework-apps-need-a-cloud-session).

## Playwright MCP server

The bundle version is pinned in [`mcp-bundle/package.json`](../mcp-bundle/package.json). Setup downloads the `.tgz` and `.sha256` from the matching [Playwright bundle release](https://github.com/octobooth/machine-setup/releases?q=playwright-mcp&expanded=true), verifies the checksum, and installs to `~/.copilot/mcp-servers/playwright`. Windows uses `$HOME\.copilot`; `COPILOT_HOME` overrides either location.

The `playwright` entry in `mcp-config.json` uses absolute Node.js and server paths, with Chrome on macOS and Edge on Windows. No npm or browser download is needed. `.bundle-version` records the installed version.

A download failure warns and skips the server; do not treat setup's exit status alone as proof that browser tools work. Ask Copilot to open a page as a readiness check. If Node moves, rerun setup or the launcher installer to refresh its path.

For VS Code or repository-specific MCP configuration, copy the installed entry's `command` and `args` into the appropriate config. Use absolute paths rather than `~` or `$HOME`, and do not replace the entry with `npx`.
