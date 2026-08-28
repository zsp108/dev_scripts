# vim_go_install.sh Usage Guide

## Introduction
Vim-go is the classic Go development powerhouse for the Vim environment. This script is responsible for cloning the vim-go plugin code and automatically injecting relevant `.vimrc` configurations, quickly setting up a smooth Go coding environment for heavy terminal users.

## Usage Examples

### 1. Default Installation
Install vim-go to the system using the latest master branch by default:
```bash
./scripts/vim_go_install.sh
```

### 2. Install Specific Branch or Tag
```bash
./scripts/vim_go_install.sh v1.28
```

### 3. Uninstall Configurations
Automatically remove vim plugins and configuration file changes added by this script:
```bash
./scripts/vim_go_install.sh uninstall
```

