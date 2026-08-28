# scan_ip 网段扫描工具使用说明

## 脚本简介
在局域网运维中，经常需要确认哪些 IP 存活。`scan_ip.sh` 提供了基础的 ICMP (Ping) 并发扫描；而 `scan_ip2.sh` 则是一个进阶版本，额外支持了 ARP 和 TCP 探测机制，可有效应对目标机器“禁 Ping”等复杂网络场景。

## 使用示例

### 1. 基础快速网段扫描 (基于 scan_ip.sh)
扫描 `192.168.1.1` 到 `192.168.1.254` 之间的存活主机：
```bash
./scripts/tools/scan_ip.sh 192.168.1
```

### 2. 进阶多协议扫描 (基于 scan_ip2.sh)

**使用 ARP 协议探测（同网段最准，无视防火墙禁 Ping）**：
```bash
./scripts/tools/scan_ip2.sh 10.10.90 arp
```

**使用 TCP 协议探测（适合跨网段检测）**：
```bash
./scripts/tools/scan_ip2.sh 10.10.90 tcp
```

**默认 Ping 探测**：
```bash
./scripts/tools/scan_ip2.sh 10.10.90 ping
```

