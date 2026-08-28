# nodejs_install.sh Usage Guide

## Introduction
Used for automatically installing and uninstalling Node.js and its package manager npm. The script is optimized specifically for LTS (Long Term Support) versions and supports setting up domestic npm mirrors to accelerate package downloads in restricted network environments.

## Usage Examples

### 1. Install Latest LTS Version (Recommended)
Automatically pulls the currently recommended long-term support version by officials (like Node.js 20 or 22):
```bash
sudo ./scripts/nodejs_install.sh lts
```

### 2. Install Specific Major Version
If you explicitly need Node 18:
```bash
sudo ./scripts/nodejs_install.sh 18
```

### 3. List Available Node.js Versions
```bash
./scripts/nodejs_install.sh list
```

### 4. Uninstall Node.js Environment
Completely removes Node binaries and global node_modules:
```bash
sudo ./scripts/nodejs_install.sh uninstall
```

