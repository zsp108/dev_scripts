# docker_install.sh Usage Guide

## Introduction
This script provides a fast and reliable automated way to install and uninstall Docker and related components (like Docker Compose). It supports customizing the Docker version, release channel, and data root directory to meet various environment needs.

## Parameters
- `[version]`: (Optional) The specific Docker version you want to install (e.g., `24.0.5`). If omitted, installs the latest version.
- `[channel]`: (Optional) The software release channel (e.g., `stable`, `test`, `nightly`). Defaults to `stable`.
- `[data-root]`: (Optional) The root directory where Docker stores its containers and images. Defaults to `/var/lib/docker`.

## Usage Examples

### 1. Default Installation (Recommended)
Run directly to install the latest stable version of Docker with default settings:
```bash
sudo ./scripts/docker_install.sh
```

### 2. Install with Specific Version and Data Directory
If you need a specific version and want to store image data on a larger partition (e.g., `/data/docker`):
```bash
sudo ./scripts/docker_install.sh 24.0.5 stable /data/docker
```

### 3. Standard Uninstall
Uninstall the Docker engine and components, but **keep** all images, containers, and configuration files:
```bash
sudo ./scripts/docker_install.sh uninstall
```

### 4. Complete Uninstall with Data Purge
Uninstall Docker and completely wipe all associated data and containers (**Warning: This action is irreversible, please back up beforehand!**):
```bash
sudo ./scripts/docker_install.sh uninstall --purge-data
```

