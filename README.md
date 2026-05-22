# Booth Machine Setup

This repository contains setup scripts for configuring booth machines. The scripts install and configure Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, and other necessary tools.

## Features

- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
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

The Azure DevOps MCP server entry in `config.json` is registered with a literal placeholder organization (`<YOUR-ADO-ORG>`). The setup scripts detect this placeholder and **skip registering the server** until you supply a real value, so your `~/.copilot/mcp-config.json` won't contain a broken entry.

To enable it:

1. Edit `config.json` and replace `<YOUR-ADO-ORG>` in the `azure-devops` entry under `shared.mcp_servers` with your Azure DevOps organization slug (e.g. `contoso` for `https://dev.azure.com/contoso`).
2. Re-run the setup script. The MCP server will be added to `~/.copilot/mcp-config.json`.

Alternatively, edit `~/.copilot/mcp-config.json` directly.

### Visual Studio (Windows)

Visual Studio is installed via the official Microsoft bootstrapper (`vs_enterprise.exe`) — not via winget — because winget only publishes manifests for VS 2017/2019/2022. The script downloads the latest Visual Studio 2026 Enterprise bootstrapper from `https://aka.ms/vs/stable/vs_enterprise.exe` (per the [official command-line install docs](https://learn.microsoft.com/en-us/visualstudio/install/use-command-line-parameters-to-install-visual-studio)) and runs it with the configured workloads.

To switch channels or editions, edit `config.windows.visual_studio` in `config.json`:

- **Insiders preview** instead of stable: change `bootstrapper_url` to `https://aka.ms/vs/insiders/vs_enterprise.exe`
- **Different edition**: swap to `vs_professional.exe` or `vs_community.exe` and update `edition` accordingly
- **Add/remove workloads**: edit the `workloads` array using [official workload IDs](https://learn.microsoft.com/en-us/visualstudio/install/workload-component-id-vs-enterprise)

`install_path` is used for the idempotency check; update it if you change edition (e.g. `…\\2026\\Professional`).