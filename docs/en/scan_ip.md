# scan_ip Tools Usage Guide

## Introduction
During LAN operations, confirming which IPs are alive is a frequent task. `scan_ip.sh` offers basic concurrent ICMP (Ping) scanning; meanwhile, `scan_ip2.sh` is an advanced version that additionally supports ARP and TCP detection mechanisms, effectively dealing with complex network scenarios like target machines ignoring Pings.

## Usage Examples

### 1. Basic Quick Subnet Scan (via scan_ip.sh)
Scan alive hosts from `192.168.1.1` to `192.168.1.254`:
```bash
./scripts/tools/scan_ip.sh 192.168.1
```

### 2. Advanced Multi-protocol Scan (via scan_ip2.sh)

**Using ARP protocol (Most accurate in the same subnet, ignores firewall Ping blocks)**:
```bash
./scripts/tools/scan_ip2.sh 10.10.90 arp
```

**Using TCP protocol (Suitable for cross-subnet detection)**:
```bash
./scripts/tools/scan_ip2.sh 10.10.90 tcp
```

**Default Ping Detection**:
```bash
./scripts/tools/scan_ip2.sh 10.10.90 ping
```

