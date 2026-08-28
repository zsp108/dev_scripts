# 实用工具脚本使用说明 / Utility Tools Usage

本文档提供了 `scripts/tools/` 目录下各类日常开发与运维辅助工具的使用说明。
This document provides usage instructions for the utility and ops scripts in the `scripts/tools/` directory.

---

### `scan_ip.sh` & `scan_ip2.sh`
- **中**：IP网段扫描工具。`scan_ip2.sh` 支持多种探测方式（ping, arp, tcp）。
- **EN**：IP segment scanning tools. `scan_ip2.sh` supports multiple detection methods (ping, arp, tcp).
- **Usage (用法)**:
  ```bash
  ./scripts/tools/scan_ip.sh <IP_SEGMENT>
  ./scripts/tools/scan_ip2.sh <IP_SEGMENT> [ping|arp|tcp]
  ```

### `v2ray_conf_setting.sh`
- **中**：V2Ray 客户端 (Client) 配置文件生成脚本。
- **EN**：V2Ray client configuration generator script.
- **Usage (用法)**:
  ```bash
  ./scripts/tools/v2ray_conf_setting.sh
  ```

### `codex_switch.sh`
- **中**：Codex 账号与配置切换管理工具。
- **EN**：Codex account and configuration switching management tool.
- **Usage (用法)**:
  ```bash
  ./scripts/tools/codex_switch.sh <组件/component> <命令/command> [参数/args]
  ```
