# git_install.sh Usage Guide

## Introduction
Since package managers (like apt, yum) on many Linux distributions offer outdated Git versions, this script helps you automatically download the latest official Git source code, compile it locally, and install it, ensuring you have access to the latest Git features.

## Usage Examples

### 1. Compile and Install Default Version
Installs the default stable version defined in the script (usually 2.42.0 or newer):
```bash
sudo ./scripts/git_install.sh
```

### 2. Compile and Install Specific Version
If you need to align with a specific version used by your team:
```bash
sudo ./scripts/git_install.sh 2.43.0
```

### 3. List Available Git Source Versions
Fetches the official version list from the network to help you decide which version to install:
```bash
./scripts/git_install.sh list
```

### 4. Uninstall Compiled Git
Cleanly uninstalls the Git instance compiled and installed via this script:
```bash
sudo ./scripts/git_install.sh uninstall
```

