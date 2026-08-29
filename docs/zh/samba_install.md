# samba_install.sh 使用说明

## 脚本简介
这是一个功能完备的 Samba 多用户隔离文件服务器自动化部署脚本，支持跨平台（Ubuntu / Debian / CentOS / RHEL）环境：
1. **多用户严格存储隔离**：默认基目录为 `/personal/samba/<用户名>`，每个用户仅能访问并写入属于自己的专属私人磁盘卷。
2. **底层存储智能自适应（双模板机制）**：
   - **本地物理盘 / 高性能云盘（ext4/xfs/btrfs）**：自动启用 **xattr 原生扩展属性模板**，macOS 标签/元数据直接写入 inode，目录下不产生任何 `._` 辅助隐藏文件；
   - **网络文件系统 / 阿里云 NAS / NFS 卷**：自动检测并启用 **Netatalk 高兼容模板**，彻底杜绝 macOS 写入时报 100093 扩展属性错误。
3. **自定义端口支持**：能够突破运营商对 445 端口的封锁，支持自定义监听端口（如 5001 / 50001 / 10445 等）。
4. **ECS 云服务器与多 IP 智能感知**：自动探测内网 IP 与公网外网 IP，支持在安装过程中手动确认或自定义输入云服务器公网 IP / 域名。
5. **macOS Bonjour 局域网广播**：配置 Avahi 自动广播服务，支持在 macOS 访达侧边栏直接发现与连接。

---

## 常用命令示例

### 1. 交互式菜单与安装（推荐）
直接运行脚本进入交互式管理面板。脚本会自动探测底层磁盘类型与公网/内网 IP，并提示您确认：
```bash
sudo ./scripts/samba_install.sh
```

### 2. 命令行快速安装（支持指定公网 IP / 域名）
支持传入 `--host` 参数直接指定服务器公网 IP 或域名：
```bash
# 格式：sudo ./scripts/samba_install.sh install [共享根目录] [端口] [初始用户名] [初始密码] [--host IP或域名]
sudo ./scripts/samba_install.sh install /personal/samba 50001 spz MyPassword123 --host 123.56.78.90
```

### 3. 多用户管理
```bash
# 注册/追加新用户专属磁盘
sudo ./scripts/samba_install.sh adduser alice AlicePassword

# 重置用户密码
sudo ./scripts/samba_install.sh passwd alice NewPassword

# 列出所有已注册用户
sudo ./scripts/samba_install.sh list

# 注销用户权限
sudo ./scripts/samba_install.sh deluser alice
```

### 4. 端口与挂载指南
```bash
# 动态修改 Samba 监听端口
sudo ./scripts/samba_install.sh setport 50001

# 打印全平台挂载指南（可查看指定用户的挂载连接命令）
sudo ./scripts/samba_install.sh guide spz
```

---

## 跨平台客户端挂载指南

### 🍏 macOS 访达 (Finder)
- 快捷键 `⌘ + K` ➔ 输入 `smb://<服务器IP或域名>:50001/<用户名>` ➔ 输入账号密码连接。

### 🪟 Windows 资源管理器
- 若使用非 445 自定义端口，可通过本地端口转发：
  ```cmd
  netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=445 connectaddress=<服务器IP或域名> connectport=50001
  ```
  然后按 `Win + R` 输入 `\\127.0.0.1\<用户名>` 即可直连。

### 🐧 Linux CIFS
```bash
sudo mount -t cifs //<服务器IP或域名>/<用户名> /mnt/samba -o port=50001,username=<用户名>,password=<密码>,uid=$(id -u),gid=$(id -g),iocharset=utf8
```
