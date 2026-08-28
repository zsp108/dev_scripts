# go_install.sh Usage Guide

## Introduction
Automatically downloads, configures, and installs the Golang environment. It sets up the global GOPATH and GOROOT, greatly simplifying the setup process for Go development.

## Usage Examples

### 1. Install Default Recommended Version
One-click setup for the Go environment:
```bash
sudo ./scripts/go_install.sh
```

### 2. Install Specific Go Version
If a legacy project depends on a specific Go compiler version (e.g., 1.20.1):
```bash
sudo ./scripts/go_install.sh 1.20.1
```

### 3. View Available Versions List
```bash
./scripts/go_install.sh list
```

### 4. Uninstall Go Environment
Removes the environment configuration and binary files:
```bash
sudo ./scripts/go_install.sh uninstall
```

