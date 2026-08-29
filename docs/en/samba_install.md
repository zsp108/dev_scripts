# samba_install.sh Usage Guide

## Overview
This is a comprehensive automated deployment script for Samba multi-user isolated file servers across Ubuntu, Debian, CentOS, and RHEL:
1. **Multi-User Storage Isolation**: Default directory `/personal/samba/<username>`, ensuring strict permission separation between users.
2. **Smart Storage Adaptation (Dual-Template System)**:
   - **Local Fast Disks (ext4/xfs/btrfs)**: Uses **Native xattr Stream Template**, storing macOS tags/metadata inside inodes without generating `._` auxiliary hidden files.
   - **NFS / Cloud NAS / Virtual Shares**: Automatically detects and switches to **Netatalk Compatible Template**, eliminating macOS 100093 extended attribute errors.
3. **Custom Port Support**: Allows configuring custom listening ports (e.g., 5001, 50001) to bypass ISP 445 port blocks.
4. **Cloud ECS & Public IP / Domain Support**: Automatically detects private and public IPs with interactive confirmation.
5. **macOS Bonjour (mDNS) Broadcast**: Enables Avahi auto-discovery in macOS Finder sidebar.

---

## Usage Examples

### 1. Interactive Menu (Recommended)
Run the script directly to open the management panel with guided setup:
```bash
sudo ./scripts/samba_install.sh
```

### 2. CLI Fast Installation with Custom Host
```bash
# Syntax: sudo ./scripts/samba_install.sh install [base_dir] [port] [username] [password] [--host <ip/domain>]
sudo ./scripts/samba_install.sh install /personal/samba 50001 spz MyPassword123 --host 123.56.78.90
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
sudo ./scripts/samba_install.sh setport 50001

# View cross-platform connection guide
sudo ./scripts/samba_install.sh guide spz
```
