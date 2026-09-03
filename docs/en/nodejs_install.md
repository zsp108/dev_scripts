# nodejs_install.sh Usage Guide

## Overview
An automated installation and lifecycle management script for Node.js and optional developer AI CLI tools across multiple platforms:
1. **Full Platform Support**: Supports Ubuntu / Debian, CentOS / RHEL / Rocky / AlmaLinux, and macOS (via Homebrew).
2. **Flexible Versioning**: Supports installing specific major versions (e.g. `20`, `22`) or defaults to latest LTS.
3. **Optional Developer AI Tools (Interactive Selection)**: After Node.js is installed, users can interactively decide whether to install `@openai/codex` and `@google/gemini-cli`.
4. **Version Discovery & Clean Uninstallation**: Includes online version lookup and clean reverse removal.

---

## Usage Examples

### 1. Interactive Installation (Recommended)
Prompts whether to install optional AI CLI tools upon completion:
```bash
sudo ./scripts/nodejs_install.sh
```

### 2. Non-interactive Installation with CLI Flags
```bash
# Install Node.js 22 with all AI tools:
sudo ./scripts/nodejs_install.sh 22 --with-ai

# Install Node.js 20 with only Codex CLI:
sudo ./scripts/nodejs_install.sh 20 --codex

# Install Node.js 22 with only Gemini CLI:
sudo ./scripts/nodejs_install.sh 22 --gemini
```

### 3. List Official Available Releases
```bash
./scripts/nodejs_install.sh list
```

### 4. Uninstall Node.js, npm, and AI Tools
```bash
sudo ./scripts/nodejs_install.sh uninstall
```
