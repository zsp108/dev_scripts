# samba_install.sh Usage Guide

## Introduction
This is an incredibly powerful Samba automated deployment script. It doesn't just install basic Samba services; it applies deep optimizations:
1. **Strict Multi-user Storage Isolation**: Default base directory is `/personal/samba/<username>`, providing private spaces for users.
2. **Custom Port Support**: Bypasses ISP blocks on port 445 by supporting custom listening ports (e.g., 10445).
3. **Cross-Platform Access Optimization**: Features native optimization for macOS Finder and high-speed transfer tuning for Windows.

## Usage Examples

### 1. Interactive Automated Deployment
Upon execution, the script will prompt you for configuration parameters and automatically handle system service registration, firewall rules, etc:
```bash
sudo ./scripts/samba_install.sh
```

### 2. Operations Guide
After installation, you can manage user passwords during daily use with the following commands:
```bash
# Add a new user or modify existing user's password
sudo smbpasswd -a <username>
```

Control service startup/stop:
```bash
sudo systemctl restart smbd
sudo systemctl enable smbd
```

