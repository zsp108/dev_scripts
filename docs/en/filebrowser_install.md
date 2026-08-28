# filebrowser_install.sh Usage Guide

## Introduction
FileBrowser is a lightweight and powerful Web file manager. This script provides automated installation and deeply customizes a **multi-user storage isolation** model (which pairs perfectly with Samba deployments). Additionally, the script features a 3-tier intelligent detection mechanism to automatically register FileBrowser as a system background service (like Systemd).

## Usage Examples

### 1. Interactive Installation (Recommended)
Run the script directly. It will enter interactive mode, guiding you step-by-step to configure the admin account, listening port, etc.
```bash
./scripts/filebrowser_install.sh
```

### 2. Quick Automated Installation
If you wish to use it in automated pipelines or non-interactive environments, pass all necessary arguments:
```bash
# Format: sudo ./filebrowser_install.sh install [admin_dir] [port] [admin_password]
sudo ./scripts/filebrowser_install.sh install /data/filebrowser 8080 mySecretPassword
```

### 3. Service Operations & Management
Once installed, you can control it using standard service management commands (Systemd based):
```bash
sudo systemctl status filebrowser
sudo systemctl restart filebrowser
sudo systemctl stop filebrowser
```

