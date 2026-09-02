# samba_install.sh Usage Guide

## Overview
This is a comprehensive automated deployment script for Samba multi-user isolated file servers across Ubuntu, Debian, CentOS, and RHEL:
1. **Multi-User Storage Isolation**: Default directory `/personal/samba/<username>`, ensuring strict permission separation between users.
2. **Smart Storage Adaptation (Dual-Template System)**:
   - **Local Fast Disks (ext4/xfs/btrfs)**: Uses **Native xattr Stream Template**, storing macOS tags/metadata inside inodes without generating `._` auxiliary hidden files.
   - **NFS / Cloud NAS / Virtual Shares**: Automatically detects and switches to **Netatalk Compatible Template**, eliminating macOS 100093 extended attribute errors.
3. **Custom Port Support**: Allows configuring custom listening ports (e.g., 5001, 50001) to bypass ISP 445 port blocks.
4. **Cloud ECS & Public IP / Domain Support**: Automatically detects private and public IPs with interactive confirmation and seamless reuse with `filebrowser_install.sh`.
5. **macOS Bonjour (mDNS) Broadcast**: Enables Avahi auto-discovery in macOS Finder sidebar.

---

## Cross-Platform Mounting Guide

### 🍏 macOS Finder
- Shortcut `⌘ + K` ➔ Enter `smb://<ip_or_domain>:50001/<username>` ➔ Connect with credentials.

### 🪟 Windows Explorer (Custom Port Forwarding)
```cmd
netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=445 connectaddress=<ip_or_domain> connectport=50001
```
Then press `Win + R` and enter `\\127.0.0.1\<username>`.

### 🐧 Linux CIFS
```bash
sudo mount -t cifs //<ip_or_domain>/<username> /mnt/samba -o port=50001,username=<username>,password='<password>',vers=3.0,uid=$(id -u),gid=$(id -g),iocharset=utf8
```
*(Note: If Linux CIFS reports "No route to host" with custom domain names, connect directly using the server IP)*
