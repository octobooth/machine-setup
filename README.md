# Booth Machine Setup

This repository contains setup scripts for configuring booth machines. The scripts install and configure Visual Studio Code, Visual Studio Code Insiders, GitHub CLI, VLC media player, and other necessary tools.

## Features

- Installs and configures Visual Studio Code and Visual Studio Code Insiders.
- Installs GitHub CLI and a suite of GitHub CLI extensions.
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