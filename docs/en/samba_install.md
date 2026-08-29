# samba_install.sh Usage Guide

## Overview
This is a comprehensive automated deployment script for Samba multi-user isolated file servers across Ubuntu, Debian, CentOS, and RHEL:
1. **Multi-User Storage Isolation**: Default directory `/personal/samba/<username>`, ensuring strict permission separation between users.
2. **Custom Port Support**: Allows configuring custom listening ports (e.g., 5001 or 10445) to bypass ISP 445 port blocks.
3. **Cloud ECS & Public IP / Domain Support**: Automatically detects private and public IPs, allowing users to confirm or manually input public IPs/domain names for seamless client mounting.
4. **macOS Bonjour (mDNS) Broadcast**: Enables Avahi auto-discovery in macOS Finder sidebar.

---

## Usage Examples

### 1. Interactive Menu (Recommended)
Run the script directly to open the management panel with guided setup and IP confirmation:
```bash
sudo ./scripts/samba_install.sh
```

### 2. CLI Fast Installation with Custom Host
```bash
# Syntax: sudo ./scripts/samba_install.sh install [base_dir] [port] [username] [password] [--host <ip/domain>]
sudo ./scripts/samba_install.sh install /personal/samba 5001 spz MyPassword123 --host 123.56.78.90
```

### 3. User & Port Management
```bash
# Add a private user disk
sudo ./scripts/samba_install.sh adduser alice AlicePassword

# Change user password
sudo ./scripts/samba_install.sh passwd alice NewPassword

# List configured users
sudo ./scripts/samba_install.sh list

# Change listening port
sudo ./scripts/samba_install.sh setport 5001

# View cross-platform connection guide
sudo ./scripts/samba_install.sh guide spz
```
