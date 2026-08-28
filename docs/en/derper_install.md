# derper_install.sh Usage Guide

## Introduction
Automated deployment and management script for Tailscale DERP relay nodes.
DERP (Designated Encrypted Relay for Packets) nodes provide strongly encrypted relay communication when Tailscale P2P direct connections fail. This script automatically configures your domain, port, and uses SysV services for persistent management.

## Usage Examples

### 1. Default Installation (Based on script's internal variables)
If you have already modified the default parameters within the script, run directly:
```bash
sudo ./scripts/derper_install.sh
```

### 2. Run with Positional Parameters
The sequence is `Domain` -> `Port` -> `Install Path` -> `Log File`:
```bash
sudo ./scripts/derper_install.sh derp.my-domain.com 50003 /opt/derp /var/log/derper.log
```

### 3. Run based on Environment Variables (Recommended for automated ops)
```bash
export DOMAIN="derp.my-domain.com"
export PORT="50003"
sudo -E ./scripts/derper_install.sh
```

