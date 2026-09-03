# nodejs_install.sh Usage Guide

## Overview
An automated installation and lifecycle management script for Node.js and developer AI CLI tools across multiple platforms:
1. **Full Platform Support**: Supports Ubuntu / Debian, CentOS / RHEL / Rocky / AlmaLinux, and macOS (via Homebrew).
2. **Flexible Versioning**: Supports installing specific major versions (e.g. `20`, `22`) or defaults to latest LTS.
3. **Integrated Developer AI Tools**: Automatically installs `@openai/codex` and `@google/gemini-cli` global npm packages.
4. **Version Discovery & Uninstallation**: Includes an online version lookup feature and a clean uninstallation command.

---

## Usage Examples

### 1. Install Latest LTS (Recommended)
```bash
sudo ./scripts/nodejs_install.sh
# or explicitly:
sudo ./scripts/nodejs_install.sh lts
```

### 2. Install Specific Major Version
```bash
sudo ./scripts/nodejs_install.sh 22
sudo ./scripts/nodejs_install.sh 20
```

### 3. List Official Available Releases
```bash
./scripts/nodejs_install.sh list
```

### 4. Uninstall Node.js, npm, and AI Tools
```bash
sudo ./scripts/nodejs_install.sh uninstall
```
