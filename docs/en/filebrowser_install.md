# filebrowser_install.sh Usage Guide

## Overview
This is an automated deployment and multi-user isolation management script for FileBrowser Web File Manager across Ubuntu, Debian, CentOS, and RHEL:
1. **Smart Host Detection & Cross-Service Reuse**:
   - Automatically detects private IPs and Cloud ECS public IPs;
   - **Seamless Samba Integration**: If a custom IP or domain was already configured via `samba_install.sh`, FileBrowser automatically detects and defaults to it without manual re-entry!
2. **Multi-User Scope Isolation**: Allows assigning dedicated root directories (scopes) for individual users, while admin has full global view.
3. **Service Management**: Automatically registers and manages systemd or SysVinit background daemon.

---

## Usage Examples

### 1. Interactive Menu (Recommended)
Run the script to open the management panel:
```bash
sudo ./scripts/filebrowser_install.sh
```

### 2. CLI Fast Installation with Custom Host
```bash
# Syntax: sudo ./scripts/filebrowser_install.sh install [root_dir] [port] [admin_pass] [db_path] [--host <ip/domain>]
sudo ./scripts/filebrowser_install.sh install /personal/samba 8080 MyAdminPass123 /etc/filebrowser/filebrowser.db --host 123.56.78.90
```

### 3. User Management & Scope Isolation
```bash
# Add an isolated user
sudo ./scripts/filebrowser_install.sh adduser alice AlicePass123 /personal/samba/alice

# List all users
sudo ./scripts/filebrowser_install.sh lsusers

# Change password
sudo ./scripts/filebrowser_install.sh setpasswd alice NewPass456

# Delete user
sudo ./scripts/filebrowser_install.sh deluser alice
```
