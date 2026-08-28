# gitlint_install.sh Usage Guide

## Introduction
Standardized Git Commit Messages are crucial in team collaborations. This script automatically installs the `gitlint` tool and configures relevant pre-checks (Pre-commit/Commit-msg Hook) to ensure all commit messages strictly adhere to popular community specification systems.

## Usage Examples

### 1. One-click Installation and Configuration
```bash
./scripts/gitlint_install.sh
```
Once executed, you can combine this with Makefile targets like `make pre-commit` to bind the hooks.

### 2. Uninstall
```bash
./scripts/gitlint_install.sh uninstall
```

