#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: samba_install.sh
# 描述:     Samba 自动化安装部署、自定义端口、多用户存储隔离与全平台挂载运维管理脚本
# 适用系统: Debian 系列 (Ubuntu, Debian, Deepin, Mint, Kali 等)
#           RedHat 系列 (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora, openEuler 等)
#           Arch 系列 (Arch Linux, Manjaro) / Alpine Linux 等
# 适用架构: x86_64 (amd64), aarch64 (arm64), armv7l, armhf, i386
# 存储模型: 多用户严格存储隔离 (默认基目录: /personal/samba/<用户名>)
# 端口支持: 支持自定义监听端口 (默认 445，支持任意自定义端口如 10445)
# 跨端优化: macOS (Finder 侧边栏/Fruit 优化/即时推出/Avahi 自适应广播)
#           Windows (SMB2/3 高速传输/网络驱动器映射/端口转发指引)
#           Linux (CIFS 原生自定义端口挂载/权限映射)
# 服务托管: 智能三级自适应探测 (systemctl ➔ service ➔ direct)
#
# 用法:
#   1. 交互式运行 (自动提权):
#      ./samba_install.sh
#   2. 快速安装 (自动初始化配置并启动):
#      sudo ./samba_install.sh install [共享根目录] [端口] [初始用户名] [初始密码]
#      例如: sudo ./samba_install.sh install /personal/samba 445 spz 123456
#      例如: sudo ./samba_install.sh install /personal/samba 10445 spz 123456
#   3. 用户管理 (专属目录隔离 /personal/samba/<用户名>):
#      sudo ./samba_install.sh adduser [用户名] [密码] [专属根目录]
#      sudo ./samba_install.sh deluser [用户名]
#      sudo ./samba_install.sh lsusers
#      sudo ./samba_install.sh passwd [用户名] [新密码]
#   4. 端口管理:
#      sudo ./samba_install.sh setport [新端口号]
#   5. 服务管理:
#      sudo ./samba_install.sh start|stop|restart|status
#      sudo ./samba_install.sh service register|unregister
#   6. 查看挂载指南:
#      sudo ./samba_install.sh guide [用户名]
#   7. 完全卸载:
#      sudo ./samba_install.sh uninstall
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
if [ -d "$SCRIPT_DIR/../scripts" ]; then
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
else
    PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
fi
LOG_DIR="$PROJECT_ROOT/logs"

if [ -d "$LOG_DIR" ]; then
    [ ! -w "$LOG_DIR" ] && { sudo chmod 777 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"; }
else
    mkdir -p "$LOG_DIR" 2>/dev/null && chmod 777 "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
fi
logfile="${LOG_DIR}/$(basename "${BASH_SOURCE[0]}" .sh).log"

DEFAULT_BASE_DIR="/personal/samba"
DEFAULT_PORT="445"
HOST_RECORD_FILE="/etc/samba/.server_host"
CUSTOM_HOST=""
SMB_CONF="/etc/samba/smb.conf"
AVAHI_DIR="/etc/avahi/services"
AVAHI_CONF="${AVAHI_DIR}/samba.service"

UNIFIED_SERVICE_NAME="samba"
SYSTEMD_FILE="/etc/systemd/system/${UNIFIED_SERVICE_NAME}.service"
SYSVINIT_FILE="/etc/init.d/${UNIFIED_SERVICE_NAME}"

# 日志函数，记录操作并格式化输出
function log {
    local logtype="$1"
    local msg="$2"
    local datetime
    datetime=$(date +'%F %H:%M:%S')
    local logformat="${datetime} ${FUNCNAME[*]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"
    
    case "$logtype" in
        debug)
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        info)
            echo -e "\033[32m${datetime} [INFO]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        warn)
            echo -e "\033[33m${datetime} [WARN]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            ;;
        error)
            echo -e "\033[31m${datetime} [ERROR] ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>/dev/null || echo "${logformat}" >> "/tmp/$(basename "${BASH_SOURCE[0]}" .sh).log" 2>/dev/null || true || true
            exit 1
            ;;
    esac
}

# 检查用户权限并自动提权 (Self-Elevation)
function check_permission {
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            log info "检测到非 root 用户执行，正在自动切换为 sudo 权限执行..."
            exec sudo bash "$0" "$@"
        else
            log error "当前不是 root 用户且系统中未找到 sudo 命令，请使用 root 用户执行此脚本。"
        fi
    fi
}

# 获取原始用户信息（当使用 sudo 执行时）
function get_original_user {
    if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
        ORIGINAL_USER="$SUDO_USER"
        ORIGINAL_HOME=$(eval echo "~$SUDO_USER")
    else
        ORIGINAL_USER="$USER"
        ORIGINAL_HOME="$HOME"
    fi
}

# 检测系统与架构
function detect_system {
    RAW_ARCH=$(uname -m)
    log info "检测到 CPU 架构: $RAW_ARCH"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID,,}"
        OS_LIKE="${ID_LIKE,,}"
        VERSION_ID="${VERSION_ID}"
    else
        log error "无法读取 /etc/os-release，不支持此操作系统。"
    fi

    if [[ "$OS_ID" =~ ^(ubuntu|debian|deepin|uos|linuxmint|kali|raspbian)$ ]] || [[ "$OS_LIKE" =~ (debian|ubuntu) ]]; then
        OS_FAMILY="debian"
        SYS_SERVICE_NAME="smbd"
        NMB_SERVICE_NAME="nmbd"
        PKG_MGR="apt-get"
    elif [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|anolis|openeuler|kylin)$ ]] || [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
        OS_FAMILY="redhat"
        SYS_SERVICE_NAME="smb"
        NMB_SERVICE_NAME="nmb"
        if command -v dnf >/dev/null 2>&1; then
            PKG_MGR="dnf"
        else
            PKG_MGR="yum"
        fi
    elif [[ "$OS_ID" =~ ^(arch|manjaro)$ ]]; then
        OS_FAMILY="arch"
        SYS_SERVICE_NAME="smb"
        NMB_SERVICE_NAME="nmb"
        PKG_MGR="pacman"
    elif [[ "$OS_ID" == "alpine" ]]; then
        OS_FAMILY="alpine"
        SYS_SERVICE_NAME="samba"
        NMB_SERVICE_NAME=""
        PKG_MGR="apk"
    else
        log error "不支持的操作系统系列: $OS_ID ($OS_LIKE)"
    fi

    log info "检测到操作系统: $OS_ID $VERSION_ID (归类为 $OS_FAMILY 系列)"
}

# 智能探测当前环境服务管理器
function detect_service_manager {
    if [ "$EUID" -eq 0 ] && command -v systemctl >/dev/null 2>&1; then
        local systemctl_test
        systemctl_test="$(systemctl is-system-running 2>&1 || true)"
        if [ -d "/run/systemd/system" ] && [[ "$systemctl_test" != *"Failed to connect to bus"* && "$systemctl_test" != *"not been booted with systemd"* && "$systemctl_test" != *"offline"* && "$systemctl_test" != *"Host is down"* ]]; then
            echo "systemd"
            return 0
        fi
    fi

    if [ -d "/etc/init.d" ] || command -v service >/dev/null 2>&1; then
        echo "sysvinit"
        return 0
    fi

    echo "direct"
}

# 多源智能探测服务器 IP / 域名 (内网 IP + 公网 IP + 历史记录)
function detect_server_hosts {
    # 1. 探测内网 IP
    PRIVATE_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}')
    
    # 2. 探测公网 IP (针对阿里云/腾讯云 ECS 等云主机，设置 2 秒超时防卡顿)
    PUBLIC_IP=""
    if command -v curl >/dev/null 2>&1; then
        PUBLIC_IP=$(curl -fsSL --connect-timeout 2 "https://api.ipify.org" 2>/dev/null ||                     curl -fsSL --connect-timeout 2 "http://ip.sb" 2>/dev/null ||                     curl -fsSL --connect-timeout 2 "http://ifconfig.me" 2>/dev/null || true)
    fi

    # 3. 决定默认推荐候选
    if [ -f "$HOST_RECORD_FILE" ] && [ -s "$HOST_RECORD_FILE" ]; then
        RECOMMENDED_HOST=$(cat "$HOST_RECORD_FILE" | tr -d ' \n\r')
    elif [ -n "$PUBLIC_IP" ] && [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        RECOMMENDED_HOST="$PUBLIC_IP"
    elif [ -n "$PRIVATE_IP" ]; then
        RECOMMENDED_HOST="$PRIVATE_IP"
    else
        RECOMMENDED_HOST="<服务器IP/域名>"
    fi
    
    SERVER_HOST="$RECOMMENDED_HOST"
}

# 获取当前配置的服务器连接地址
function get_server_host {
    if [ -n "$CUSTOM_HOST" ]; then
        SERVER_HOST="$CUSTOM_HOST"
        return 0
    fi
    if [ -f "$HOST_RECORD_FILE" ] && [ -s "$HOST_RECORD_FILE" ]; then
        SERVER_HOST=$(cat "$HOST_RECORD_FILE" | tr -d ' \n\r')
        return 0
    fi
    detect_server_hosts
}

# 交互式确认或手动输入服务器 IP / 域名 (完美适配 ECS 云服务器与自定义域名)
function prompt_server_host {
    if [ -n "$CUSTOM_HOST" ]; then
        SERVER_HOST="$CUSTOM_HOST"
        mkdir -p /etc/samba 2>/dev/null || true
        mkdir -p /etc/dev_scripts 2>/dev/null || true
    echo "$SERVER_HOST" > /etc/dev_scripts/.server_host 2>/dev/null || true
    echo "$SERVER_HOST" > "$HOST_RECORD_FILE" 2>/dev/null || true
        return 0
    fi

    detect_server_hosts

    echo ""
    echo -e "\033[36m------------------------------------------------------------------------------\033[0m"
    echo -e "\033[33m🌐 服务器访问地址 (IP / 域名) 探测与确认:\033[0m"
    [ -n "$PRIVATE_IP" ] && echo -e "   • 检测到内网局域网 IP: \033[36m${PRIVATE_IP}\033[0m"
    [ -n "$PUBLIC_IP" ]  && echo -e "   • 检测到公网外网 IP:   \033[32m${PUBLIC_IP}\033[0m (推荐用于云服务器 ECS / 外网挂载)"

    local default_prompt="${RECOMMENDED_HOST}"
    echo -n "请输入客户端连接使用的 服务器IP 或 解析域名 [回车默认使用: ${default_prompt}]: "
    read -r user_input_host

    if [ -n "$user_input_host" ]; then
        SERVER_HOST="$user_input_host"
    else
        SERVER_HOST="$RECOMMENDED_HOST"
    fi

    mkdir -p /etc/samba 2>/dev/null || true
    mkdir -p /etc/dev_scripts 2>/dev/null || true
    echo "$SERVER_HOST" > /etc/dev_scripts/.server_host 2>/dev/null || true
    echo "$SERVER_HOST" > "$HOST_RECORD_FILE" 2>/dev/null || true
    echo -e "\033[36m------------------------------------------------------------------------------\033[0m"
    log info "已设置客户端连接目标地址为: $SERVER_HOST"
}

# 从当前 smb.conf 获取共享基目录 (默认 /personal/samba)
function get_base_share_dir {
    local dir
    dir=$(grep -m 1 'path =' "$SMB_CONF" 2>/dev/null | awk '{print $3}' | sed -E 's|/[^/]+$||' || true)
    echo "${dir:-$DEFAULT_BASE_DIR}"
}

# 从当前 smb.conf 获取当前监听端口 (默认 445)
function get_current_port {
    local p
    p=$(grep -E '^\s*smb ports\s*=' "$SMB_CONF" 2>/dev/null | awk -F'=' '{print $2}' | awk '{print $1}' || true)
    echo "${p:-$DEFAULT_PORT}"
}

# 彻底终结所有残留的 smbd 进程与端口占用 (不依赖单一外部命令，多级强力清场)
function kill_smbd_processes {
    local port="${1:-}"
    
    # 1. 尝试使用服务管理器停止
    local mgr
    mgr=$(detect_service_manager)
    if [ "$mgr" = "systemd" ]; then
        systemctl stop "${UNIFIED_SERVICE_NAME}" 2>/dev/null || true
        systemctl stop "$SYS_SERVICE_NAME" 2>/dev/null || true
    elif [ "$mgr" = "sysvinit" ] && command -v service >/dev/null 2>&1; then
        service "${UNIFIED_SERVICE_NAME}" stop 2>/dev/null || true
        service "$SYS_SERVICE_NAME" stop 2>/dev/null || true
    fi

    # 2. 如果指定了端口，尝试释放该端口占用 (fuser / ss)
    if [ -n "$port" ] && command -v fuser >/dev/null 2>&1; then
        fuser -k -n tcp "$port" 2>/dev/null || true
    fi

    # 3. 递进式终止所有 smbd 进程 (SIGTERM 15)
    if command -v pkill >/dev/null 2>&1; then
        pkill -15 -x smbd 2>/dev/null || true
    fi
    if command -v killall >/dev/null 2>&1; then
        killall -15 smbd 2>/dev/null || true
    fi
    local pids
    pids=$(pidof smbd 2>/dev/null || pgrep -x smbd 2>/dev/null || ps -ef | grep '[s]mbd' | awk '{print $2}' || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -15 "$pid" 2>/dev/null || true
        done
    fi

    # 4. 轮询等待进程平稳退出 (最多等 2 秒)
    local count=0
    while pidof smbd >/dev/null 2>&1; do
        sleep 0.5
        count=$((count + 1))
        if [ "$count" -ge 4 ]; then
            # 超过 2 秒仍未退出，执行强杀 (SIGKILL -9)
            if command -v pkill >/dev/null 2>&1; then
                pkill -9 -x smbd 2>/dev/null || true
            fi
            if command -v killall >/dev/null 2>&1; then
                killall -9 smbd 2>/dev/null || true
            fi
            pids=$(pidof smbd 2>/dev/null || pgrep -x smbd 2>/dev/null || ps -ef | grep '[s]mbd' | awk '{print $2}' || true)
            if [ -n "$pids" ]; then
                for pid in $pids; do
                    kill -9 "$pid" 2>/dev/null || true
                done
            fi
            if [ -n "$port" ] && command -v fuser >/dev/null 2>&1; then
                fuser -k -9 -n tcp "$port" 2>/dev/null || true
            fi
            break
        fi
    done

    # 5. 清理残留的死锁 PID 文件
    rm -f /run/samba/smbd.pid /var/run/samba/smbd.pid /var/run/smbd.pid 2>/dev/null || true
}

# 安装依赖与 Samba 软件包
function install_packages {
    log info "正在检查并安装 Samba 及 Bonjour 广播依赖包..."

    case "$OS_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y samba samba-common-bin smbclient procps psmisc net-tools attr avahi-daemon
            ;;
        redhat)
            $PKG_MGR makecache -y || true
            $PKG_MGR install -y epel-release || true
            $PKG_MGR install -y samba samba-common samba-client procps-ng psmisc net-tools attr avahi policycoreutils-python-utils || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng avahi policycoreutils-python || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng avahi || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng
            ;;
        arch)
            pacman -Sy --noconfirm samba avahi
            ;;
        alpine)
            apk update
            apk add samba samba-common-tools avahi
            ;;
    esac

    log info "Samba 与 Bonjour 相关软件包安装完成。"
}

# 配置 macOS Bonjour (mDNS / Avahi) 网络广播 (动态绑定自定义端口)
function configure_avahi {
    local port="${1:-$DEFAULT_PORT}"
    log info "正在配置 macOS 访达 / Windows 局域网 Bonjour (mDNS / Avahi) 广播 (端口: $port)..."

    mkdir -p "$AVAHI_DIR"
    cat << EOF_AVAHI > "$AVAHI_CONF"
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h (Samba)</name>
  <service>
    <type>_smb._tcp</type>
    <port>$port</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=Macmini</txt-record>
  </service>
</service-group>
EOF_AVAHI

    local mgr
    mgr=$(detect_service_manager)
    if [ "$mgr" = "systemd" ]; then
        systemctl restart avahi-daemon 2>/dev/null || true
        systemctl enable avahi-daemon 2>/dev/null || true
    elif [ "$mgr" = "sysvinit" ] && command -v service >/dev/null 2>&1; then
        service avahi-daemon restart 2>/dev/null || true
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=mdns >/dev/null 2>&1 || firewall-cmd --permanent --add-port=5353/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow 5353/udp >/dev/null 2>&1 || true
    fi

    log info "macOS Bonjour 广播服务配置完成 (Avahi 运行中，广播端口: $port)。"
}

# 配置防火墙规则 (支持自定义端口放行)
function configure_firewall {
    local port="${1:-$DEFAULT_PORT}"
    log info "正在检查并配置防火墙放行规则 (Samba 端口: $port)..."

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log info "已在 firewalld 中放行端口: ${port}/tcp 与 samba 服务。"
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 || true
        ufw allow 137/udp >/dev/null 2>&1 || true
        ufw allow 138/udp >/dev/null 2>&1 || true
        ufw allow 139/tcp >/dev/null 2>&1 || true
        ufw allow 445/tcp >/dev/null 2>&1 || true
        log info "已在 ufw 中放行端口: ${port}/tcp 与相关规则。"
    fi
}

# 配置 SELinux 安全策略
function configure_selinux {
    local target_dir="$1"
    local port="${2:-$DEFAULT_PORT}"

    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            log info "检测到 SELinux 状态为: $selinux_status，正在配置 Samba 安全策略..."
            setsebool -P samba_enable_home_dirs on >/dev/null 2>&1 || true
            setsebool -P samba_export_all_rw on >/dev/null 2>&1 || true
            
            # 放行自定义端口 SELinux 端口类型
            if [ "$port" != "445" ] && command -v semanage >/dev/null 2>&1; then
                semanage port -a -t smbd_port_t -p tcp "$port" 2>/dev/null || \
                semanage port -m -t smbd_port_t -p tcp "$port" 2>/dev/null || true
            fi

            if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
                if command -v semanage >/dev/null 2>&1; then
                    semanage fcontext -a -t samba_share_t "${target_dir}(/.*)?" >/dev/null 2>&1 || true
                    restorecon -R -v "$target_dir" >> "$logfile" 2>&1 || true
                else
                    chcon -R -t samba_share_t "$target_dir" >/dev/null 2>&1 || true
                fi
            fi
            log info "SELinux 规则配置完成。"
        fi
    fi
}

# 智能探测底层共享存储的文件系统类型与 xattr (扩展属性) 支持能力
function detect_storage_features {
    local target_dir="${1:-$DEFAULT_BASE_DIR}"
    mkdir -p "$target_dir" 2>/dev/null || true

    FS_TYPE=$(df -T "$target_dir" 2>/dev/null | awk 'NR==2 {print $2}')
    [ -z "$FS_TYPE" ] && FS_TYPE="unknown"

    SUPPORTS_XATTR="false"
    local test_file="${target_dir}/.samba_xattr_test_$$"
    if touch "$test_file" 2>/dev/null; then
        if command -v setfattr >/dev/null 2>&1; then
            if setfattr -n user.test_samba_ea -v 'ok' "$test_file" 2>/dev/null; then
                SUPPORTS_XATTR="true"
            fi
        elif command -v attr >/dev/null 2>&1; then
            if attr -s test_samba_ea -V 'ok' "$test_file" 2>/dev/null; then
                SUPPORTS_XATTR="true"
            fi
        elif command -v xattr >/dev/null 2>&1; then
            if xattr -w user.test_samba_ea 'ok' "$test_file" 2>/dev/null; then
                SUPPORTS_XATTR="true"
            fi
        else
            case "$FS_TYPE" in
                ext3|ext4|xfs|btrfs|zfs|apfs)
                    SUPPORTS_XATTR="true"
                    ;;
                *)
                    SUPPORTS_XATTR="false"
                    ;;
            esac
        fi
        rm -f "$test_file" 2>/dev/null || true
    fi

    # 网络文件系统或虚拟分卷，即使偶尔通过也强制以安全高兼容模式运行
    case "$FS_TYPE" in
        nfs|nfs4|cifs|smbfs|fuse|fuseblk|overlay|9p)
            SUPPORTS_XATTR="false"
            ;;
    esac

    log info "底层存储特性探测: 共享根目录 [$target_dir] | 文件系统类型 [$FS_TYPE] | 原生 xattr 支持: [$SUPPORTS_XATTR]"
}

# 初始化 /etc/samba/smb.conf 全局模板 (支持自定义端口、macOS Fruit、Windows SMB2/3 与 Linux 深度优化)
function init_smb_global_conf {
    local port="${1:-$DEFAULT_PORT}"
    local backup_conf="/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
    log info "正在生成 Samba 全局基础配置 ($SMB_CONF，监听端口: $port)..."

    mkdir -p /etc/samba
    if [ -f "$SMB_CONF" ]; then
        cp "$SMB_CONF" "$backup_conf"
        log info "已备份原配置文件到: $backup_conf"
    fi

    cat << EOF_SMB > "$SMB_CONF"
# ==============================================================================
# Universal Multi-User Isolated Samba Configuration
# ==============================================================================

[global]
    workgroup = WORKGROUP
    server string = Universal Samba Server
    netbios name = SambaServer
    security = user
    map to guest = Bad User
    dns proxy = no

    # 监听端口配置 (自定义端口)
    smb ports = $port

    # 协议与传输性能优化 (全平台高速读写)
    min protocol = SMB2
    max protocol = SMB3
    use sendfile = yes
    aio read size = 16384
    aio write size = 16384
    # 针对底层 NFS / 阿里云 NAS / 本地非 xattr 存储的兼容性优化 (彻底杜绝 macOS 写入 100093 扩展属性错误)
    ea support = no
    store dos attributes = no

    # 连接断开与锁即时释放优化 (解决 macOS 推出卡顿/文件句柄残留)
    deadtime = 10
    reset on zero vc = yes

    # macOS 原生兼容模块 (适配 NFS / 本地存储无扩展属性环境)
    vfs objects = catia fruit
    fruit:metadata = netatalk
    fruit:resource = file
    fruit:locking = none
    fruit:nfs_aces = no
    fruit:model = Macmini
    fruit:posix_rename = yes
    fruit:veto_appledouble = no
    fruit:wipe_intentionally_left_blank_rfork = yes
    fruit:delete_empty_adfiles = yes
    fruit:time machine = no

    # 日志与打印机配置
    log file = /var/log/samba/log.%m
    max log size = 10000
    logging = file
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes

EOF_SMB

    log info "Samba 全局基础配置写入完成。"
}

# 修改/设置 Samba 监听端口
function do_setport {
    local new_port="$1"
    local current_port
    current_port="$(get_current_port)"

    if [ -z "$new_port" ]; then
        echo -n "请输入新的 Samba 监听端口号 [当前: ${current_port}]: "
        read -r new_port
    fi

    if [ -z "$new_port" ]; then
        log warn "未输入端口号，保持当前端口不变: $current_port"
        return 0
    fi

    # 校验端口格式 (1-65535)
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log error "无效的端口号: $new_port (端口范围必须在 1-65535 之间)！"
    fi

    log info "正在将 Samba 监听端口从 [$current_port] 修改为 [$new_port]..."

    if [ ! -f "$SMB_CONF" ]; then
        log error "配置文件不存在 ($SMB_CONF)，请先安装初始化 Samba！"
    fi

    # 修改 smb.conf 中的 smb ports
    if grep -q "^\s*smb ports\s*=" "$SMB_CONF"; then
        sed -i "s/^\s*smb ports\s*=.*/    smb ports = ${new_port}/" "$SMB_CONF"
    else
        sed -i "/\[global\]/a \    smb ports = ${new_port}" "$SMB_CONF"
    fi

    # 更新 Avahi 广播端口与防火墙
    configure_avahi "$new_port"
    configure_firewall "$new_port"
    local base_dir
    base_dir="$(get_base_share_dir)"
    configure_selinux "$base_dir" "$new_port"

    # 先彻底清场旧端口残留进程，防止新端口启动冲突
    kill_smbd_processes "$current_port"
    # 重启服务
    service_control restart

    log info "✅ Samba 端口已成功切换为: $new_port"
    print_mount_guide
}

# 注册/追加单个用户的专属隔离存储目录 (/personal/samba/<用户名>)
function add_user_to_samba {
    local username="$1"
    local password="$2"
    local base_dir="${3:-$DEFAULT_BASE_DIR}"
    local user_dir="${base_dir}/${username}"

    log info "正在配置用户 [$username] 专属隔离存储空间..."

    # 1. 确保系统用户存在 (禁止直接交互登录 shell)
    if ! id "$username" >/dev/null 2>&1; then
        log info "创建系统用户 [$username]..."
        useradd -M -s /usr/sbin/nologin "$username" 2>/dev/null || \
        useradd -M -s /sbin/nologin "$username" 2>/dev/null || \
        useradd -s /bin/false "$username" 2>/dev/null || \
        useradd "$username"
    fi

    # 2. 将用户添加到 Samba 数据库并设置密码
    (echo "$password"; echo "$password") | smbpasswd -s -a "$username" >> "$logfile" 2>&1
    smbpasswd -e "$username" >/dev/null 2>&1 || true

    # 3. 创建专属子目录并设置 0777 权限 (保证 Mac/Windows/Linux 可自由写入并严格通过 Samba 鉴权隔离)
    mkdir -p "$user_dir"
    chown -R "${username}:${username}" "$user_dir" 2>/dev/null || chown -R "${username}" "$user_dir" 2>/dev/null || true
    chmod 0777 "$user_dir"
    log info "用户专属目录已就绪: $user_dir (归属: $username)"

    # 4. 在 smb.conf 中注册显式专属共享块 [$username]
    local user_vfs="catia fruit"
    if grep -q "streams_xattr" "$SMB_CONF" 2>/dev/null; then
        user_vfs="catia fruit streams_xattr"
    fi

    if ! grep -q "^\[$username\]" "$SMB_CONF" 2>/dev/null; then
        log info "在 $SMB_CONF 中写入独立磁盘块 [$username]..."
        cat << EOF_USER >> "$SMB_CONF"

# ------------------------------------------------------------------------------
# 👤 用户 [$username] 专属存储磁盘 (目录: $user_dir)
# ------------------------------------------------------------------------------
[$username]
    comment = $username Private Storage
    path = $user_dir
    browseable = yes
    writable = yes
    read only = no
    guest ok = no
    valid users = $username
    force user = $username
    create mask = 0666
    directory mask = 0777
    force create mode = 0666
    force directory mode = 0777
    vfs objects = $user_vfs
    fruit:locking = none

EOF_USER
    else
        log info "用户 [$username] 的磁盘块已存在于 $SMB_CONF 中，跳过重复写入。"
    fi

    # 5. 语法检测与服务重载
    if command -v testparm >/dev/null 2>&1; then
        testparm -s "$SMB_CONF" >/dev/null 2>&1 || true
    fi

    service_control reload || service_control restart || true

    log info "✅ 用户 [$username] 专属独立磁盘卷 [$username] 配置并生效成功！"
}

# 从 smb.conf 移除用户专属共享块
function remove_user_from_samba {
    local username="$1"
    local base_dir
    base_dir="$(get_base_share_dir)"
    local user_dir="${base_dir}/${username}"

    log info "正在删除用户 [$username] 的 Samba 共享权限与配置..."

    # 从 Samba 用户数据库删除
    smbpasswd -x "$username" >> "$logfile" 2>&1 || true

    # 从 smb.conf 中删除配置段
    if [ -f "$SMB_CONF" ]; then
        sed -i "/# 👤 用户 \[${username}\]/,/^$/d" "$SMB_CONF" 2>/dev/null || true
        sed -i "/^\[${username}\]/,/^$/d" "$SMB_CONF" 2>/dev/null || true
    fi

    # 热重载服务
    service_control reload || service_control restart || true

    log info "用户 [$username] 已从 Samba 服务中注销。"
    if [ -d "$user_dir" ]; then
        log warn "用户物理数据目录保留未删: $user_dir (如需彻底清理请手动执行 rm -rf $user_dir)"
    fi
}

# 重置用户密码
function set_user_password {
    local username="$1"
    local password="$2"

    log info "正在修改用户 [$username] 的 Samba 访问密码..."
    (echo "$password"; echo "$password") | smbpasswd -s -a "$username" >> "$logfile" 2>&1
    smbpasswd -e "$username" >/dev/null 2>&1 || true
    log info "用户 [$username] 密码修改成功。"
}

# 列出当前所有配置的 Samba 隔离用户
function list_samba_users {
    log info "========== 当前 Samba 注册用户列表 =========="
    local count=0
    local base_dir
    base_dir="$(get_base_share_dir)"

    if [ -f "$SMB_CONF" ]; then
        while read -r line; do
            local user
            user=$(echo "$line" | sed 's/\[//;s/\]//')
            if [ "$user" != "global" ] && [ -n "$user" ]; then
                local u_path
                u_path=$(grep -A 10 "^\[$user\]" "$SMB_CONF" | grep 'path =' | awk '{print $3}' | head -n 1)
                echo -e "  \033[36m• 用户名:\033[0m ${user}  \033[33m| 映射目录:\033[0m ${u_path:-$base_dir/$user}"
                count=$((count + 1))
            fi
        done < <(grep -E '^\[[a-zA-Z0-9_-]+\]' "$SMB_CONF")
    fi

    if [ "$count" -eq 0 ]; then
        echo "  (暂未配置任何共享用户)"
    fi
    log info "============================================="
}

# 注册统一服务托管
function register_service {
    local mgr
    mgr=$(detect_service_manager)
    log info "正在为 Samba 注册系统服务 (托管方式: $mgr)..."

    if [ "$mgr" = "systemd" ]; then
        cat << EOF_SYS > "$SYSTEMD_FILE"
[Unit]
Description=Samba SMB Daemon (Universal Service)
After=network.target network-online.target nmbd.service winbind.service avahi-daemon.service
Wants=network-online.target

[Service]
Type=forking
PIDFile=/run/samba/smbd.pid
LimitNOFILE=16384
ExecStart=/usr/sbin/smbd -D
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=multi-user.target
EOF_SYS
        systemctl daemon-reload
        systemctl enable "${UNIFIED_SERVICE_NAME}" >> "$logfile" 2>&1 || true
        systemctl enable "$SYS_SERVICE_NAME" >> "$logfile" 2>&1 || true
        [ -n "$NMB_SERVICE_NAME" ] && systemctl enable "$NMB_SERVICE_NAME" >> "$logfile" 2>&1 || true
        log info "已注册 systemd 服务: ${UNIFIED_SERVICE_NAME}.service"
    elif [ "$mgr" = "sysvinit" ]; then
        cat << 'EOF_SYSV' > "$SYSVINIT_FILE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          samba
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Start Samba daemon
### END INIT INFO

stop_smbd() {
    pkill -15 -x smbd 2>/dev/null || true
    killall -15 smbd 2>/dev/null || true
    pids=$(pidof smbd 2>/dev/null || ps -ef | grep '[s]mbd' | awk '{print $2}' || true)
    if [ -n "$pids" ]; then
        for pid in $pids; do
            kill -15 "$pid" 2>/dev/null || true
        done
    fi
    sleep 0.5
    if pidof smbd >/dev/null 2>&1; then
        pkill -9 -x smbd 2>/dev/null || true
        killall -9 smbd 2>/dev/null || true
        pids=$(pidof smbd 2>/dev/null || ps -ef | grep '[s]mbd' | awk '{print $2}' || true)
        if [ -n "$pids" ]; then
            for pid in $pids; do
                kill -9 "$pid" 2>/dev/null || true
            done
        fi
    fi
    rm -f /run/samba/smbd.pid /var/run/samba/smbd.pid /var/run/smbd.pid 2>/dev/null || true
}

case "$1" in
    start)
        rm -f /run/samba/smbd.pid /var/run/samba/smbd.pid 2>/dev/null || true
        smbd -D 2>/dev/null || /usr/sbin/smbd -D
        ;;
    stop)
        stop_smbd
        ;;
    restart|reload)
        stop_smbd
        sleep 1
        smbd -D 2>/dev/null || /usr/sbin/smbd -D
        ;;
    status)
        pidof smbd >/dev/null && echo "samba is running" || echo "samba is stopped"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|reload|status}"
        exit 1
        ;;
esac
exit 0
EOF_SYSV
        chmod +x "$SYSVINIT_FILE"
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d "${UNIFIED_SERVICE_NAME}" defaults >> "$logfile" 2>&1 || true
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig --add "${UNIFIED_SERVICE_NAME}" >> "$logfile" 2>&1 || true
        fi
        log info "已生成 SysVinit 启动脚本: $SYSVINIT_FILE"
    fi
}

# 注销服务
function unregister_service {
    local mgr
    mgr=$(detect_service_manager)
    log info "正在注销 Samba 系统服务..."

    if [ "$mgr" = "systemd" ]; then
        systemctl disable "${UNIFIED_SERVICE_NAME}" 2>/dev/null || true
        systemctl disable "$SYS_SERVICE_NAME" 2>/dev/null || true
        rm -f "$SYSTEMD_FILE"
        systemctl daemon-reload
    elif [ "$mgr" = "sysvinit" ]; then
        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d -f "${UNIFIED_SERVICE_NAME}" remove 2>/dev/null || true
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig --del "${UNIFIED_SERVICE_NAME}" 2>/dev/null || true
        fi
        rm -f "$SYSVINIT_FILE"
    fi
    log info "服务注销完成。"
}

# 服务启停与状态控制 (三级自适应探测)
function service_control {
    local action="$1"
    local mgr
    mgr=$(detect_service_manager)
    local current_port
    current_port="$(get_current_port)"

    case "$action" in
        start)
            log info "正在启动 Samba 服务..."
            # 检查是否有僵死 pid 文件，有则清理
            if [ -f /run/samba/smbd.pid ]; then
                local old_pid
                old_pid=$(cat /run/samba/smbd.pid 2>/dev/null)
                if [ -n "$old_pid" ] && ! kill -0 "$old_pid" 2>/dev/null; then
                    rm -f /run/samba/smbd.pid 2>/dev/null || true
                fi
            fi
            if [ "$mgr" = "systemd" ]; then
                systemctl start "${UNIFIED_SERVICE_NAME}" 2>/dev/null || systemctl start "$SYS_SERVICE_NAME" 2>/dev/null || smbd -D
            elif [ "$mgr" = "sysvinit" ]; then
                service "${UNIFIED_SERVICE_NAME}" start 2>/dev/null || service "$SYS_SERVICE_NAME" start 2>/dev/null || "$SYSVINIT_FILE" start 2>/dev/null || smbd -D
            else
                smbd -D
            fi
            sleep 1
            service_control status
            ;;
        stop)
            log info "正在停止 Samba 服务..."
            kill_smbd_processes "$current_port"
            log info "Samba 服务已停止。"
            ;;
        restart)
            log info "正在重启 Samba 服务..."
            kill_smbd_processes "$current_port"
            sleep 1
            if [ "$mgr" = "systemd" ]; then
                systemctl restart "${UNIFIED_SERVICE_NAME}" 2>/dev/null || systemctl start "${UNIFIED_SERVICE_NAME}" 2>/dev/null || smbd -D
            elif [ "$mgr" = "sysvinit" ]; then
                service "${UNIFIED_SERVICE_NAME}" start 2>/dev/null || service "$SYS_SERVICE_NAME" start 2>/dev/null || "$SYSVINIT_FILE" start 2>/dev/null || smbd -D
            else
                smbd -D
            fi
            sleep 1
            service_control status
            ;;
        reload)
            log info "正在热重载 Samba 配置..."
            if [ "$mgr" = "systemd" ]; then
                systemctl reload "${UNIFIED_SERVICE_NAME}" 2>/dev/null || systemctl reload "$SYS_SERVICE_NAME" 2>/dev/null || smbcontrol smbd reload-config 2>/dev/null || true
            elif [ "$mgr" = "sysvinit" ]; then
                service "${UNIFIED_SERVICE_NAME}" reload 2>/dev/null || service "$SYS_SERVICE_NAME" reload 2>/dev/null || smbcontrol smbd reload-config 2>/dev/null || true
            else
                smbcontrol smbd reload-config 2>/dev/null || true
            fi
            ;;
        status)
            local current_port
            current_port="$(get_current_port)"
            log info "检查 Samba 服务运行状态 (监听端口: $current_port):"
            if [ "$mgr" = "systemd" ]; then
                if systemctl is-active --quiet "${UNIFIED_SERVICE_NAME}" 2>/dev/null || systemctl is-active --quiet "$SYS_SERVICE_NAME" 2>/dev/null; then
                    echo -e "  \033[32m● Samba 服务正在运行 (systemd: active | 端口: ${current_port})\033[0m"
                else
                    echo -e "  \033[31m● Samba 服务未运行\033[0m"
                fi
            else
                if pidof smbd >/dev/null 2>&1; then
                    echo -e "  \033[32m● Samba 服务正在运行 (PID: $(pidof smbd | tr '\n' ' ') | 端口: ${current_port})\033[0m"
                else
                    echo -e "  \033[31m● Samba 服务未运行\033[0m"
                fi
            fi
            ;;
    esac
}

# 打印多端挂载连接指南
function print_mount_guide {
    local target_user="${1:-<用户名>}"
    local custom_h="${2:-}"
    local port
    port="$(get_current_port)"
    if [ -n "$custom_h" ]; then
        SERVER_HOST="$custom_h"
    else
        get_server_host
    fi

    echo ""
    echo -e "\033[36m==============================================================================\033[0m"
    echo -e "\033[32m  🎉 全平台客户端连接与挂载指南 (主机: ${SERVER_HOST} | 端口: ${port} | 用户: ${target_user})\033[0m"
    echo -e "\033[36m==============================================================================\033[0m"
    echo -e "\033[33m🍏 1. macOS 访达 (Finder) 挂载:\033[0m"
    echo -e "   • 打开访达，按快捷键 \033[32m⌘ + K\033[0m (或顶部菜单: 前往 ➔ 连接服务器)"
    if [ "$port" = "445" ]; then
        echo -e "   • 服务器地址输入: \033[36msmb://${SERVER_HOST}/${target_user}\033[0m"
    else
        echo -e "   • 服务器地址输入 (带自定义端口): \033[36msmb://${SERVER_HOST}:${port}/${target_user}\033[0m"
    fi
    echo -e "   • 选择「注册用户」，输入用户名 \033[32m${target_user}\033[0m 和对应密码即可。"
    echo -e "   • \033[35m(已配置 Bonjour/Avahi 自动广播端口，局域网/访达侧边栏'网络/位置'可直接双击发现与推出)\033[0m"
    echo ""
    echo -e "\033[33m🪟 2. Windows 资源管理器挂载:\033[0m"
    if [ "$port" = "445" ]; then
        echo -e "   • 打开文件资源管理器地址栏 (或按 \033[32mWin + R\033[0m)，输入: \033[36m\\\\${SERVER_HOST}\\${target_user}\033[0m"
        echo -e "   • 映射为本地网络驱动器 (CMD 执行):"
        echo -e "     \033[32mnet use Z: \\\\${SERVER_HOST}\\${target_user} /user:${target_user} <密码> /persistent:yes\033[0m"
    else
        echo -e "   • \033[31m[注意]\033[0m Windows 资源管理器原生仅直连 445 端口。连接自定义端口 [${port}] 推荐方式:"
        echo -e "     \033[32m① 本地端口转发 (以管理员身份打开 CMD 执行):\033[0m"
        echo -e "        netsh interface portproxy add v4tov4 listenaddress=127.0.0.1 listenport=445 connectaddress=${SERVER_HOST} connectport=${port}"
        echo -e "        然后按 Win + R 输入: \033[36m\\\\127.0.0.1\\${target_user}\033[0m 即可无缝访问！"
        echo -e "     \033[32m② 或使用第三方挂载工具 (如 RaiDrive / Cyberduck)，在界面中指定端口 ${port} 挂载。\033[0m"
    fi
    echo ""
    echo -e "\033[33m🐧 3. Linux 系统客户端挂载 (CIFS):\033[0m"
    echo -e "   • 临时挂载命令:"
    echo -e "     \033[32msudo mkdir -p /mnt/samba_${target_user}\033[0m"
    if [ "$port" = "445" ]; then
        echo -e "     \033[32msudo mount -t cifs //${SERVER_HOST}/${target_user} /mnt/samba_${target_user} -o username=${target_user},password='<密码>',vers=3.0,uid=\$(id -u),gid=\$(id -g),iocharset=utf8\033[0m"
    else
        echo -e "     \033[32msudo mount -t cifs //${SERVER_HOST}/${target_user} /mnt/samba_${target_user} -o port=${port},username=${target_user},password='<密码>',vers=3.0,uid=\$(id -u),gid=\$(id -g),iocharset=utf8\033[0m"
    fi
    echo -e "   • 开机自动挂载 (/etc/fstab 追加):"
    if [ "$port" = "445" ]; then
        echo -e "     \033[32m//${SERVER_HOST}/${target_user}  /mnt/samba_${target_user}  cifs  username=${target_user},password='<密码>',vers=3.0,uid=\$(id -u),gid=\$(id -g),iocharset=utf8,_netdev  0  0\033[0m"
    else
        echo -e "     \033[32m//${SERVER_HOST}/${target_user}  /mnt/samba_${target_user}  cifs  port=${port},username=${target_user},password='<密码>',vers=3.0,uid=\$(id -u),gid=\$(id -g),iocharset=utf8,_netdev  0  0\033[0m"
    fi
    echo -e "   • \033[35m(提示: 若 Linux 客户端使用域名遇到 'No route to host'，请直接将域名替换为对应服务器 IP 直连挂载)\033[0m"
    echo -e "\033[36m==============================================================================\033[0m"
    echo ""
}

# 完整安装流程
function do_install {
    local base_dir="${1:-$DEFAULT_BASE_DIR}"
    local port="${2:-$DEFAULT_PORT}"
    local init_user="${3:-}"
    local init_pass="${4:-}"

    # 如果第2个参数不是纯数字（用户可能省略了端口直接传入用户名），则自动修正
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        init_pass="$init_user"
        init_user="$port"
        port="$DEFAULT_PORT"
    fi

    log info "开始自动化部署 Samba 文件服务器..."
    log info "设置共享根基目录为: $base_dir | 监听端口: $port"

    install_packages
    configure_avahi "$port"
    init_smb_global_conf "$port" "$base_dir"
    configure_firewall "$port"
    configure_selinux "$base_dir" "$port"
    register_service
    service_control start

    if [ -n "$init_user" ] && [ -n "$init_pass" ]; then
        add_user_to_samba "$init_user" "$init_pass" "$base_dir"
        print_mount_guide "$init_user"
    else
        log info "未指定初始用户，您可以随时执行 '$0 adduser <用户名> <密码>' 创建专属隔离空间。"
        print_mount_guide
    fi

    log info "✅ Samba 服务端自动化安装与配置全部完成 (端口: $port)！"
}

# 添加用户流程
function do_adduser {
    local u="$1"
    local p="$2"
    local d="${3:-$(get_base_share_dir)}"

    if [ -z "$u" ] || [ -z "$p" ]; then
        echo -n "请输入要创建的隔离用户名: "
        read -r u
        echo -n "请输入该用户的访问密码: "
        read -r p
    fi

    [ -z "$u" ] || [ -z "$p" ] && log error "用户名或密码不能为空！"

    add_user_to_samba "$u" "$p" "$d"
    print_mount_guide "$u"
}

# 删除用户流程
function do_deluser {
    local u="$1"
    if [ -z "$u" ]; then
        echo -n "请输入要删除的用户名: "
        read -r u
    fi
    [ -z "$u" ] && log error "用户名不能为空！"
    remove_user_from_samba "$u"
}

# 修改密码流程
function do_passwd {
    local u="$1"
    local p="$2"
    if [ -z "$u" ] || [ -z "$p" ]; then
        echo -n "请输入要修改密码的用户名: "
        read -r u
        echo -n "请输入新密码: "
        read -r p
    fi
    [ -z "$u" ] || [ -z "$p" ] && log error "用户名或密码不能为空！"
    set_user_password "$u" "$p"
}

# 彻底卸载流程
function do_uninstall {
    log warn "正在执行 Samba 服务彻底卸载..."
    kill_smbd_processes || true
    service_control stop || true
    unregister_service || true

    log info "清理配置文件与 Avahi 广播..."
    rm -f "$AVAHI_CONF" "$HOST_RECORD_FILE"
    if [ -f "$SMB_CONF" ]; then
        mv "$SMB_CONF" "/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    fi

    log info "卸载 Samba 软件包..."
    case "$OS_FAMILY" in
        debian)
            apt-get remove --purge -y samba samba-common-bin smbclient >> "$logfile" 2>&1 || true
            apt-get autoremove -y >> "$logfile" 2>&1 || true
            ;;
        redhat)
            $PKG_MGR remove -y samba samba-common samba-client >> "$logfile" 2>&1 || true
            ;;
        arch)
            pacman -Rns --noconfirm samba >> "$logfile" 2>&1 || true
            ;;
        alpine)
            apk del samba samba-common-tools >> "$logfile" 2>&1 || true
            ;;
    esac

    local base_dir
    base_dir="$(get_base_share_dir)"
    log info "Samba 软件包与服务已成功卸载。"
    if [ -d "$base_dir" ]; then
        log warn "用户数据目录保留未动: $base_dir"
    fi
}

# 交互式菜单
function main_menu {
    while true; do
        get_server_host
        local base_dir
        base_dir="$(get_base_share_dir)"
        local current_port
        current_port="$(get_current_port)"

        echo ""
        echo -e "\033[36m==============================================================================\033[0m"
        echo -e "\033[32m        Samba 多用户隔离共享管理面板 (主机: ${SERVER_HOST} | 端口: ${current_port})\033[0m"
        echo -e "\033[36m==============================================================================\033[0m"
        echo -e "  \033[33m1)\033[0m 安装并初始化 Samba (默认根目录: ${DEFAULT_BASE_DIR} | 默认端口: ${DEFAULT_PORT})"
        echo -e "  \033[33m2)\033[0m 添加专属隔离用户 (自动分配 /personal/samba/<用户名>)"
        echo -e "  \033[33m3)\033[0m 修改用户密码"
        echo -e "  \033[33m4)\033[0m 查看所有已配置用户"
        echo -e "  \033[33m5)\033[0m 删除用户权限"
        echo -e "  \033[33m6)\033[0m 修改 Samba 监听端口 (当前: \033[36m${current_port}\033[0m)"
        echo -e "  \033[33m7)\033[0m 服务状态与启停管理"
        echo -e "  \033[33m8)\033[0m 查看全平台挂载指南 (macOS / Windows / Linux)"
        echo -e "  \033[33m9)\033[0m 彻底卸载 Samba 服务"
        echo -e "  \033[33m0)\033[0m 退出"
        echo -e "\033[36m==============================================================================\033[0m"
        echo -n "请输入操作选项 [0-9]: "
        read -r choice

        case "$choice" in
            1)
                prompt_server_host
                echo -n "请输入共享根目录 [回车默认 ${DEFAULT_BASE_DIR}]: "
                read -r input_dir
                input_dir="${input_dir:-$DEFAULT_BASE_DIR}"
                echo -n "请输入 Samba 监听端口 [回车默认 ${DEFAULT_PORT}]: "
                read -r input_port
                input_port="${input_port:-$DEFAULT_PORT}"
                echo -n "请输入初始用户名 (可留空跳过): "
                read -r init_u
                init_p=""
                if [ -n "$init_u" ]; then
                    echo -n "请输入初始用户密码: "
                    read -r init_p
                fi
                do_install "$input_dir" "$input_port" "$init_u" "$init_p"
                ;;
            2)
                do_adduser "" ""
                ;;
            3)
                do_passwd "" ""
                ;;
            4)
                list_samba_users
                ;;
            5)
                do_deluser ""
                ;;
            6)
                do_setport ""
                ;;
            7)
                echo "  a) 启动服务   b) 停止服务   c) 重启服务   d) 查看状态"
                echo -n "  请选择服务操作 [a-d]: "
                read -r s_opt
                case "$s_opt" in
                    a|start)   service_control start ;;
                    b|stop)    service_control stop ;;
                    c|restart) service_control restart ;;
                    d|status|*) service_control status ;;
                esac
                ;;
            8)
                echo -n "请输入要查询指南的用户名 [回车默认显示通用]: "
                read -r q_user
                echo -n "当前客户端连接目标地址为 [${SERVER_HOST}]，按回车直接使用，或输入新IP/域名: "
                read -r input_new_h
                if [ -n "$input_new_h" ]; then
                    SERVER_HOST="$input_new_h"
                    mkdir -p /etc/dev_scripts 2>/dev/null || true
    echo "$SERVER_HOST" > /etc/dev_scripts/.server_host 2>/dev/null || true
    echo "$SERVER_HOST" > "$HOST_RECORD_FILE" 2>/dev/null || true
                fi
                print_mount_guide "$q_user" "$SERVER_HOST"
                ;;
            9)
                echo -n "确认要彻底卸载 Samba 吗? [y/N]: "
                read -r confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    do_uninstall
                else
                    log info "取消卸载。"
                fi
                ;;
            0)
                log info "退出程序。"
                exit 0
                ;;
            *)
                log warn "无效输入，请重新选择。"
                ;;
        esac
    done
}

# ==============================================================================
# 脚本入口
# ==============================================================================
check_permission
get_original_user
detect_system

# 解析全局选项 (例如 --host 指定 IP / 域名)
POSITIONAL_ARGS=()
while [ $# -gt 0 ]; do
    case "$1" in
        -H|--host)
            CUSTOM_HOST="$2"
            mkdir -p /etc/samba 2>/dev/null || true
            mkdir -p /etc/dev_scripts 2>/dev/null || true
            echo "$CUSTOM_HOST" > /etc/dev_scripts/.server_host 2>/dev/null || true
            echo "$CUSTOM_HOST" > "$HOST_RECORD_FILE" 2>/dev/null || true
            shift 2
            ;;
        *)
            POSITIONAL_ARGS+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL_ARGS[@]}"

ACTION="${1:-}"

case "$ACTION" in
    install|-i|--install)
        do_install "$2" "$3" "$4" "$5"
        ;;
    uninstall|-u|--uninstall)
        do_uninstall
        ;;
    service)
        case "${2:-register}" in
            register|enable)
                register_service
                ;;
            unregister|disable)
                unregister_service
                ;;
            *)
                log error "未知服务命令: $2。支持 register | unregister"
                ;;
        esac
        ;;
    status|-s|--status)
        service_control status
        ;;
    start)
        service_control start
        ;;
    stop)
        service_control stop
        ;;
    restart)
        service_control restart
        ;;
    adduser|add-user)
        do_adduser "$2" "$3" "$4"
        ;;
    lsusers|ls-users|users|listusers)
        list_samba_users
        ;;
    deluser|del-user)
        do_deluser "$2"
        ;;
    passwd|setpasswd)
        do_passwd "$2" "$3"
        ;;
    setport|port)
        do_setport "$2"
        ;;
    guide|mount)
        print_mount_guide "$2"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0                                            # 交互式菜单"
        echo "  sudo $0 install [根目录] [端口] [用户名] [密码]      # 一键完整安装部署 (支持自定义端口)"
        echo "  sudo $0 adduser [用户名] [密码] [根目录]             # 添加多用户隔离空间"
        echo "  sudo $0 setport [新端口号]                          # 修改 Samba 监听端口"
        echo "  sudo $0 lsusers                                    # 查看所有已配置用户"
        echo "  sudo $0 passwd [用户名] [新密码]                     # 修改用户密码"
        echo "  sudo $0 deluser [用户名]                            # 删除用户权限"
        echo "  sudo $0 guide [用户名]                              # 查看全平台客户端挂载指南"
        echo "  sudo $0 service register                           # 注册系统服务与开机自启"
        echo "  sudo $0 service unregister                         # 注销系统服务"
        echo "  sudo $0 start|stop|restart|status                  # 服务启停状态管理"
        echo "  sudo $0 uninstall                                  # 彻底卸载 Samba 服务"
        ;;
    "")
        main_menu
        ;;
    *)
        log error "未知命令: $ACTION。使用 '$0 help' 查看帮助。"
        ;;
esac
