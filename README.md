# Booth Machine Setup

This repository contains setup scripts for configuring booth machines. The scripts install and configure Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, and other necessary tools.

## Features

- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs Neovim and automatically sets up the official [GitHub Copilot plugin](https://github.com/github/copilot.vim) (`copilot.vim`).
- Installs a core set of IDEs (PyCharm Professional and Android Studio by default), with more JetBrains IDEs (IntelliJ IDEA Ultimate, Rider, WebStorm, GoLand, CLion, PhpStorm, RubyMine, DataGrip, RustRover) available by uncommenting them in `config.json`.
- Installs GitHub CLI and a suite of GitHub CLI extensions.
- Installs the GitHub Copilot CLI (`copilot`).
- Installs the GitHub Copilot desktop app (via the [`github-copilot-app`](https://formulae.brew.sh/cask/github-copilot-app) Homebrew cask on macOS; direct download from the [`github/app`](https://github.com/github/app) releases on Windows).
- Installs the [Microsoft Aspire](https://aspire.dev) CLI and registers its MCP server with Copilot CLI.
- Installs Visual Studio Enterprise with Web + Azure + .NET desktop workloads (Windows only).
- Registers MCP servers (Playwright, Microsoft Learn, Astro docs, Svelte docs, Aspire, Azure, Azure DevOps) in `~/.copilot/mcp-config.json`. Node-based MCP servers (Playwright, Azure, Azure DevOps) are installed globally via `npm install -g` so they launch from their installed binaries rather than fetching via `npx` at runtime.
- Configures VLC media player settings.
- Sets up Progressive Web Apps (PWAs) for GitHub tools.
- Creates a demo loader script to launch all required applications and sites.

## Configuration

The configuration for the setup scripts is stored in the `config.json` file. You can customize the settings by modifying this file.

### Enabling and disabling packages

Because `config.json` is JSON and can't carry real comments, packages are enabled/disabled with a `# ` prefix convention: **any package entry whose value starts with `# ` is treated as disabled and skipped** by both setup scripts. To disable a package, prefix its id with `# `; to enable a commented-out one, remove the prefix.

This applies to `windows.packages`, `mac.packages.casks`, and `mac.packages.formulas`. For example, a core set of IDEs (PyCharm Professional and Android Studio) ships active, while the other JetBrains IDEs (IntelliJ IDEA Ultimate, Rider, WebStorm, GoLand, CLion, PhpStorm, RubyMine, DataGrip, RustRover) ship commented out - uncomment the ones you want. Out of the box, the active IDEs install and the commented ones don't.

### Choosing whether to install Neovim and the IDEs

Both setup scripts ask two quick yes/no questions early in the run:

- `Install Neovim (and auto-configure its GitHub Copilot plugin)?`
- `Install IDEs (PyCharm, Android Studio)?`

Answering no skips the relevant packages, skips the Neovim Copilot plugin setup, and omits the matching sign-in checklist steps. Pressing Enter accepts the default (yes). These choices apply to the current run only and are never saved.

**Non-interactive runs** (CI, piped input, etc.) skip the prompts and default to installing both groups, so existing unattended behavior is unchanged. To control them without a prompt, set the `INSTALL_NEOVIM` and/or `INSTALL_JETBRAINS` environment variables to a truthy (`1`, `true`, `yes`, `y`, `on`) or falsy (`0`, `false`, `no`, `n`, `off`) value before running setup - for example, `INSTALL_JETBRAINS=no` to skip the IDEs (`INSTALL_JETBRAINS` gates every IDE, including Android Studio). The `# ` comment-out convention above still applies on top of these choices, so you can disable individual IDEs while keeping the rest.

### Neovim + GitHub Copilot

Neovim is installed alongside the editors, and its GitHub Copilot plugin (`github/copilot.vim`) is cloned automatically into Neovim's native package path (`%LOCALAPPDATA%\nvim-data\site\pack\github\start` on Windows, `${XDG_DATA_HOME:-~/.local/share}/nvim/site/pack/github/start` on macOS/Linux). The plugin requires a Node.js runtime, which both scripts now install (`OpenJS.NodeJS.LTS` on Windows, the `node` formula on macOS). Authentication is handled interactively by the sign-in checklist (below), not at install time.

### Sign-in checklist

The interactive sign-in checklist walks you through signing in to each GitHub surface one at a time. It now also covers Neovim and each active IDE:

- **Neovim** (only shown if you chose to install Neovim and `nvim` is on `PATH`): run `:Copilot setup` inside Neovim. If you already signed in to the Copilot CLI earlier in the checklist, Neovim *may* already be signed in via the shared Copilot token (`%LOCALAPPDATA%\github-copilot` on Windows, `~/.config/github-copilot` on macOS/Linux) - this isn't guaranteed, so confirm inside the editor.
- **IDEs** (one step per active IDE, including Android Studio, shown only if you chose to install them; derived from `config.json` - commenting an IDE out also removes its step): open the IDE, install the GitHub Copilot plugin (Settings/Preferences > Plugins > Marketplace > search "GitHub Copilot"), then sign in to Copilot inside the IDE. Android Studio uses the same JetBrains plugin marketplace, and JetBrains IDEs generally require their own in-IDE sign-in.

## Setup Instructions

### macOS

1. Open a terminal and navigate to the repository directory.
2. Run the setup script to configure the machine:

    ```bash
    ./setup.sh
    ```
3. A script will be created on the Desktop to load up the necessary applications.
4. Store any booth videos in the `$HOME/videos` folder for easier loading from VLC.

### Windows

1. Open PowerShell as an administrator.
2. Navigate to the repository directory.
3. Run the setup script to configure the machine:

    ```powershell
    .\setup.ps1
    ```
4. A script will be created on the Desktop to load up the necessary applications.
5. Store any booth videos in the `C:\Users\<YourUsername>\Videos` folder for easier loading from VLC.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Post-setup configuration

Some integrations require values that the setup script can't guess for you:

### Azure DevOps MCP server

The Azure DevOps MCP server needs your organization slug (e.g. `contoso` for `https://dev.azure.com/contoso`). Setup will prompt you for it once and cache the answer.

**During setup:**

```
Azure DevOps organization name (leave blank to skip the Azure DevOps MCP server)
> contoso
```

- Enter your org slug to register the server.
- Leave it blank to skip the server entirely (the rest of setup continues).
- On re-runs, the prompt shows your cached value; press Enter to keep it, type a new value to change it, or `-` to clear it.

**Non-interactive runs** (CI, piped input, etc.) skip the prompt and either use the cached value or skip the server. To set the org without a prompt, export `ADO_ORG=contoso` (or `ADO_ORG=` to explicitly skip) before running setup.

**State file:** the cached value lives at `${COPILOT_HOME:-~/.copilot}/machine-setup-state.json` (Mac/Linux) or `%COPILOT_HOME%\machine-setup-state.json` / `%USERPROFILE%\.copilot\machine-setup-state.json` (Windows). Edit or delete this file to change the cached answer outside setup.

### Demo video subfolder

The demo loader opens VLC pointed at your `~/Videos` folder. If you copy the same full set of videos to every machine but organize them into subfolders (e.g. `~/Videos/booth-keynote`, `~/Videos/booth-security`), setup can point this machine's loader at just one of them. Setup prompts you for the subfolder once and caches the answer.

**During setup:**

```
Video subfolder under ~/Videos to play (blank to play ~/Videos directly)
> booth-keynote
```

- Enter a subfolder name to play only `~/Videos/<subfolder>`.
- Leave it blank to play `~/Videos` directly (the default; identical to previous behavior).
- On re-runs, the prompt shows your cached value; press Enter to keep it, type a new value to change it, or `-` to clear it back to the `~/Videos` root.
- If `~/Videos` already contains subfolders, their names are listed in the prompt as a hint.

This is a free-text prompt on purpose: the videos do not need to exist on disk when setup runs (you can drag them in later). If the chosen subfolder isn't present yet, setup warns but continues - just make sure the videos are in place before you run the demo loader.

**Non-interactive runs** use the cached value, or the `~/Videos` root if none is cached. To set the subfolder without a prompt, export `VIDEO_SUBFOLDER=booth-keynote` (or `VIDEO_SUBFOLDER=` for the root) before running setup. The cached value lives in the same state file described above, under `inputs.video_subfolder`.

### Visual Studio (Windows)

Visual Studio is installed via the official Microsoft bootstrapper (`vs_enterprise.exe`) — not via winget — because winget only publishes manifests for VS 2017/2019/2022. The script downloads the latest Visual Studio 2026 Enterprise bootstrapper from `https://aka.ms/vs/stable/vs_enterprise.exe` (per the [official command-line install docs](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio)) and runs it with the configured workloads.

To switch channels or editions, edit `config.windows.visual_studio` in `config.json`:

- **Insiders preview** instead of stable: change `bootstrapper_url` to `https://aka.ms/vs/insiders/vs_enterprise.exe`
- **Different edition**: swap to `vs_professional.exe` or `vs_community.exe` and update `edition` accordingly
- **Add/remove workloads**: edit the `workloads` array using [official workload IDs](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-enterprise)

`install_path` is used for the idempotency check; update it if you change edition (e.g. `…\\2026\\Professional`).