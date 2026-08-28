#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: samba_install.sh
# 描述:     Samba 自动化安装部署与多用户存储隔离管理脚本 (参考 iStoreOS / OpenWrt 规范架构)
# 适用系统: Debian 系列 (Ubuntu, Debian, Deepin, Mint, Kali 等)
#           RedHat 系列 (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora, openEuler 等)
# 适用架构: x86_64, aarch64 (ARM64), armv7l, armhf, i386 等
# 存储模型: 基于 Base 目录动态分配专属子目录 (/data/share/<用户名>)
#           每个用户对应独立的显式磁盘块 [用户名]，完美支持 macOS 访达侧边栏挂载与推出
# 服务托管: 智能三级自适应探测 (systemctl ➔ service ➔ direct) + Bonjour(Avahi) 原生广播
#
# 用法:
#   1. 交互式运行 (自动提权):
#      ./samba_install.sh
#   2. 快速安装:
#      sudo ./samba_install.sh install [共享根目录] [初始用户名] [初始密码]
#      例如: sudo ./samba_install.sh install /data/share spz 123456
#   3. 用户管理 (自动在 /data/share/<用户名> 创建专属隔离空间并配置独立磁盘块):
#      sudo ./samba_install.sh adduser [用户名] [密码]
#      sudo ./samba_install.sh deluser [用户名]
#      sudo ./samba_install.sh lsusers
#   4. 服务运维:
#      sudo ./samba_install.sh start|stop|restart|status
#   5. 完全卸载:
#      sudo ./samba_install.sh uninstall
# ==============================================================================

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="${SCRIPT_ROOT}/samba_install.log"
SMB_CONF="/etc/samba/smb.conf"

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
            echo "${logformat}" >> "$logfile" 2>&1 || true
            ;;
        info)
            echo -e "\033[32m${datetime} [INFO]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 || true
            ;;
        warn)
            echo -e "\033[33m${datetime} [WARN]  ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 || true
            ;;
        error)
            echo -e "\033[31m${datetime} [ERROR] ${msg}\033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 || true
            exit 1
            ;;
    esac
}

# 检查权限并自动提权 (Self-Elevation)
function check_permission {
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo >/dev/null 2>&1; then
            log info "检测到非 root 用户执行，正在自动通过 sudo 提权..."
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
    ARCH=$(uname -m)
    log info "检测到系统架构: $ARCH"

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
    elif [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|anolis|openeuler|kylin)$ ]] || [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
        OS_FAMILY="redhat"
        SYS_SERVICE_NAME="smb"
        NMB_SERVICE_NAME="nmb"
    else
        log error "不支持的操作系统系列: $OS_ID ($OS_LIKE)，目前仅支持 Debian/Ubuntu 和 RHEL/CentOS 系列。"
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

    if [ -d "/etc/init.d" ] || command -v service >/dev/null 2>&1 || command -v update-rc.d >/dev/null 2>&1 || command -v chkconfig >/dev/null 2>&1; then
        echo "sysvinit"
        return 0
    fi

    echo "direct"
}

# 获取本机局域网 IP
function get_local_ip {
    LOCAL_IP=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$LOCAL_IP" ]; then
        LOCAL_IP="<服务器IP>"
    fi
}

# 从当前 smb.conf 获取共享基目录 (默认 /data/share)
function get_base_share_dir {
    local dir
    dir=$(grep -m 1 'path =' "$SMB_CONF" 2>/dev/null | awk '{print $3}' | sed -E 's|/[^/]+$||' || true)
    echo "${dir:-/data/share}"
}

# 安装依赖与 Samba 软件包
function install_packages {
    log info "检查并安装 Samba 及 Bonjour 广播依赖包..."

    case "$OS_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y samba samba-common-bin smbclient procps avahi-daemon
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            $PKG_MGR makecache -y || true
            $PKG_MGR install -y samba samba-common samba-client procps-ng avahi policycoreutils-python-utils || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng avahi policycoreutils-python || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng avahi || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng
            ;;
    esac

    log info "Samba 与 Bonjour 相关软件包安装完成。"
}

# 配置 macOS Bonjour (mDNS / Avahi) 网络广播 (让 Mac 侧边栏自动常驻服务器并支持推出)
function configure_avahi {
    log info "正在配置 macOS Bonjour (mDNS / Avahi) 网络广播服务..."

    mkdir -p /etc/avahi/services
    cat << 'EOF' > /etc/avahi/services/samba.service
<?xml version="1.0" standalone="no"?>
<!DOCTYPE service-group SYSTEM "avahi-service.dtd">
<service-group>
  <name replace-wildcards="yes">%h (Samba)</name>
  <service>
    <type>_smb._tcp</type>
    <port>445</port>
  </service>
  <service>
    <type>_device-info._tcp</type>
    <port>0</port>
    <txt-record>model=Macmini</txt-record>
  </service>
</service-group>
EOF

    if command -v systemctl >/dev/null 2>&1 && systemctl is-system-running >/dev/null 2>&1; then
        systemctl restart avahi-daemon 2>/dev/null || true
        systemctl enable avahi-daemon 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        service avahi-daemon restart 2>/dev/null || true
    fi

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=mdns >/dev/null 2>&1 || firewall-cmd --permanent --add-port=5353/udp >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
    fi
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow 5353/udp >/dev/null 2>&1 || true
    fi

    log info "macOS Bonjour 广播服务配置完成 (Avahi 运行中)。"
}

# 配置防火墙规则
function configure_firewall {
    log info "正在检查并配置防火墙放行规则..."

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log info "已在 firewalld 中放行 Samba 服务规则。"
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow samba >/dev/null 2>&1 || {
            ufw allow 137/udp
            ufw allow 138/udp
            ufw allow 139/tcp
            ufw allow 445/tcp
        }
        log info "已在 ufw 中放行 Samba 规则。"
    fi
}

# 配置 SELinux 安全策略
function configure_selinux {
    local target_dir="$1"
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            log info "检测到 SELinux 状态为: $selinux_status，正在配置 Samba 安全策略..."
            setsebool -P samba_enable_home_dirs on >/dev/null 2>&1 || true
            setsebool -P samba_export_all_rw on >/dev/null 2>&1 || true
            
            if [ -n "$target_dir" ] && [ -d "$target_dir" ]; then
                if command -v semanage >/dev/null 2>&1; then
                    semanage fcontext -a -t samba_share_t "${target_dir}(/.*)?" >/dev/null 2>&1 || true
                    restorecon -R -v "$target_dir" >> "$logfile" 2>&1 || true
                else
                    chcon -t samba_share_t "$target_dir" >/dev/null 2>&1 || true
                fi
            fi
            log info "SELinux 规则配置完成。"
        fi
    fi
}

# 初始化 /etc/samba/smb.conf 全局模板 (严格参考 iStoreOS 苹果优化架构)
function init_smb_global_conf {
    local backup_conf="/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"
    log info "正在生成 Samba 全局基础配置 ($SMB_CONF)..."

    mkdir -p /etc/samba
    if [ -f "$SMB_CONF" ]; then
        cp "$SMB_CONF" "$backup_conf"
        log info "已备份原配置文件到: $backup_conf"
    fi

    cat << 'EOF' > "$SMB_CONF"
# ==============================================================================
# Samba Configuration (Generated by samba_install.sh - iStoreOS/OpenWrt Style)
# ==============================================================================

[global]
    workgroup = WORKGROUP
    server string = Samba File Server
    netbios name = SambaServer
    security = user
    map to guest = Bad User
    dns proxy = no

    # 协议与性能优化 (参考 iStoreOS / OpenWrt 生产级参数)
    min protocol = SMB2
    max protocol = SMB3
    use sendfile = yes
    aio read size = 16384
    aio write size = 16384

    # macOS 原生兼容模块 (支持 Finder 磁盘侧边栏、推出图标、元数据读写)
    vfs objects = catia fruit streams_xattr
    fruit:metadata = stream
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

EOF

    log info "Samba 全局基础配置写入完成。"
}

# 注册/追加单个用户的专属独立磁盘卷 [用户名] (对应 /data/share/<用户名>)
function add_user_to_samba {
    local username="$1"
    local password="$2"
    local base_dir="${3:-/data/share}"
    local user_dir="${base_dir}/${username}"

    log info "正在配置用户 [$username] 专属隔离存储..."

    # 1. 确保系统用户存在 (无 shell 登录权限)
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

    # 3. 创建专属子目录并设置 0777 权限 (保证 Mac/Windows/Linux 可自由创建 .DS_Store 及写入文件)
    mkdir -p "$user_dir"
    chown -R "${username}:${username}" "$user_dir" 2>/dev/null || chown -R "${username}" "$user_dir" 2>/dev/null || true
    chmod 0777 "$user_dir"
    log info "用户专属目录已就绪: $user_dir (权限: 0777 / 归属: $username)"

    # 4. 在 smb.conf 中注册显式专属共享块 [用户名] (按 iStoreOS 规范)
    if ! grep -q "^\[$username\]" "$SMB_CONF" 2>/dev/null; then
        log info "在 $SMB_CONF 中写入独立磁盘块 [$username]..."
        cat << EOF >> "$SMB_CONF"

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
    create mask = 0666
    directory mask = 0777
    force create mode = 0666
    force directory mode = 0777
    vfs objects = catia fruit streams_xattr

EOF
    else
        log info "用户 [$username] 的磁盘块已存在于 $SMB_CONF 中，跳过重复写入。"
    fi

    # 5. 语法检测与服务热重载
    if command -v testparm >/dev/null 2>&1; then
        testparm -s "$SMB_CONF" >/dev/null 2>&1 || true
    fi

    if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SYS_SERVICE_NAME" 2>/dev/null; then
        systemctl reload "$SYS_SERVICE_NAME" 2>/dev/null || systemctl restart "$SYS_SERVICE_NAME" 2>/dev/null || true
    elif command -v service >/dev/null 2>&1; then
        service "$UNIFIED_SERVICE_NAME" reload 2>/dev/null || service "$UNIFIED_SERVICE_NAME" restart 2>/dev/null || true
    fi

    log info "✅ 用户 [$username] 专属独立磁盘卷 [$username] 配置并生效成功！"
}

# 从 smb.conf 移除用户专属共享块
function remove_user_from_samba {
    local username="$1"
    local base_dir
    base_dir="$(get_base_share_dir)"
    local user_dir="${base_dir}/${username}"

    log info "正在从 Samba 中移除用户 [$username]..."
    smbpasswd -x "$username" >> "$logfile" 2>&1 || true

    if [ -f "$SMB_CONF" ] && grep -q "^\[$username\]" "$SMB_CONF"; then
        log info "正在从 $SMB_CONF 清理 [$username] 磁盘块..."
        sed -i "/^#.*$username.*专属存储磁盘/,/^\[$username\]/,/^vfs objects =/d" "$SMB_CONF" 2>/dev/null || \
        sed -i "/^\[$username\]/,/^$/d" "$SMB_CONF" 2>/dev/null || true
        
        if command -v systemctl >/dev/null 2>&1 && systemctl is-active --quiet "$SYS_SERVICE_NAME" 2>/dev/null; then
            systemctl reload "$SYS_SERVICE_NAME" 2>/dev/null || true
        elif command -v service >/dev/null 2>&1; then
            service "$UNIFIED_SERVICE_NAME" reload 2>/dev/null || true
        fi
    fi

    read -r -p "是否同时删除该用户的实际物理数据目录 ($user_dir)? [y/N]: " del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        rm -rf "${user_dir:?}"
        log info "已删除用户数据目录: $user_dir"
    else
        log info "已保留用户实际数据目录: $user_dir"
    fi

    read -r -p "是否同时删除 Linux 系统账户 [$username]? [y/N]: " del_sys_user
    if [[ "$del_sys_user" =~ ^[Yy]$ ]]; then
        userdel "$username" 2>/dev/null || true
        log info "已删除 Linux 系统账户 [$username]"
    fi

    log info "用户 [$username] 删除完成。"
}

# 生成 SysVinit 脚本 (/etc/init.d/samba)
function generate_sysvinit_script {
    mkdir -p /etc/init.d
    cat << 'EOF' > "$SYSVINIT_FILE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          samba
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: Samba SMB/CIFS daemon
# Description:       Unified Samba Service Managed by samba_install.sh
### END INIT INFO

SMBD_BIN="$(command -v smbd 2>/dev/null || echo "/usr/sbin/smbd")"
NMBD_BIN="$(command -v nmbd 2>/dev/null || echo "/usr/sbin/nmbd")"
PID_DIR="/var/run/samba"
SMBD_PID="$PID_DIR/smbd.pid"
NMBD_PID="$PID_DIR/nmbd.pid"

mkdir -p "$PID_DIR" 2>/dev/null || true

start() {
    echo "Starting Samba services..."
    if [ -x "/etc/init.d/smbd" ] && [ "/etc/init.d/smbd" != "/etc/init.d/samba" ]; then
        /etc/init.d/smbd start 2>/dev/null || true
        [ -x "/etc/init.d/nmbd" ] && /etc/init.d/nmbd start 2>/dev/null || true
    elif [ -x "/etc/init.d/smb" ] && [ "/etc/init.d/smb" != "/etc/init.d/samba" ]; then
        /etc/init.d/smb start 2>/dev/null || true
        [ -x "/etc/init.d/nmb" ] && /etc/init.d/nmb start 2>/dev/null || true
    else
        [ -x "$SMBD_BIN" ] && "$SMBD_BIN" -D
        [ -x "$NMBD_BIN" ] && "$NMBD_BIN" -D 2>/dev/null || true
    fi
    sleep 1
    status
}

stop() {
    echo "Stopping Samba services..."
    if [ -x "/etc/init.d/smbd" ] && [ "/etc/init.d/smbd" != "/etc/init.d/samba" ]; then
        /etc/init.d/smbd stop 2>/dev/null || true
        [ -x "/etc/init.d/nmbd" ] && /etc/init.d/nmbd stop 2>/dev/null || true
    elif [ -x "/etc/init.d/smb" ] && [ "/etc/init.d/smb" != "/etc/init.d/samba" ]; then
        /etc/init.d/smb stop 2>/dev/null || true
        [ -x "/etc/init.d/nmb" ] && /etc/init.d/nmb stop 2>/dev/null || true
    fi

    killall smbd 2>/dev/null || true
    killall nmbd 2>/dev/null || true
    rm -f "$SMBD_PID" "$NMBD_PID" 2>/dev/null || true
    echo "Samba services stopped."
}

status() {
    if pgrep -x smbd >/dev/null 2>&1 || pgrep smbd >/dev/null 2>&1; then
        local pids
        pids=$(pgrep smbd 2>/dev/null | tr '\n' ' ')
        echo "🟢 Samba (smbd) 正在运行 (PID: $pids)"
        return 0
    else
        echo "🔴 Samba (smbd) 未运行"
        return 1
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)
        echo "Usage: service samba {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOF
    chmod +x "$SYSVINIT_FILE"
}

# 注册统一系统服务 (支持 systemctl 与 service 双模自适应)
function register_service {
    log info "开始注册并配置 Samba 系统服务..."
    local s_mgr
    s_mgr="$(detect_service_manager)"

    generate_sysvinit_script

    case "$s_mgr" in
        systemd)
            log info "【方案一：systemd 生效】正在注册统一服务 [${UNIFIED_SERVICE_NAME}.service]..."

            cat << EOF > "$SYSTEMD_FILE"
[Unit]
Description=Samba Service (Unified Service Managed by samba_install.sh)
After=network.target network-online.target nss-lookup.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'systemctl start $SYS_SERVICE_NAME $NMB_SERVICE_NAME 2>/dev/null || systemctl start $SYS_SERVICE_NAME 2>/dev/null || /etc/init.d/samba start'
ExecStop=/bin/sh -c 'systemctl stop $SYS_SERVICE_NAME $NMB_SERVICE_NAME 2>/dev/null || systemctl stop $SYS_SERVICE_NAME 2>/dev/null || /etc/init.d/samba stop'
ExecReload=/bin/sh -c 'systemctl reload-or-restart $SYS_SERVICE_NAME 2>/dev/null || /etc/init.d/samba restart'

[Install]
WantedBy=multi-user.target
EOF
            chmod 644 "$SYSTEMD_FILE"
            systemctl daemon-reload

            systemctl enable "$SYS_SERVICE_NAME" 2>/dev/null || true
            systemctl enable "$NMB_SERVICE_NAME" 2>/dev/null || true
            systemctl enable "$UNIFIED_SERVICE_NAME" 2>/dev/null || true

            systemctl restart "$SYS_SERVICE_NAME" 2>/dev/null || true
            systemctl restart "$NMB_SERVICE_NAME" 2>/dev/null || true
            systemctl restart "$UNIFIED_SERVICE_NAME" 2>/dev/null || true

            log info "✅ systemd 服务注册并自启成功！"
            log info "   • 运维命令: systemctl {start|stop|restart|status} samba"
            ;;

        sysvinit|direct)
            log warn "ℹ️ 未检测到活跃的 systemd 守护进程 (常见于 Docker / 容器 / WSL1 环境)。"
            log info "【方案二：service 生效】正在注册为 SysVinit (service) 系统服务..."

            if command -v update-rc.d >/dev/null 2>&1; then
                update-rc.d "$UNIFIED_SERVICE_NAME" defaults 2>/dev/null || true
            elif command -v chkconfig >/dev/null 2>&1; then
                chkconfig --add "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
                chkconfig "$UNIFIED_SERVICE_NAME" on 2>/dev/null || true
            fi

            if command -v service >/dev/null 2>&1; then
                service "$UNIFIED_SERVICE_NAME" restart || "$SYSVINIT_FILE" restart
            else
                "$SYSVINIT_FILE" restart
            fi

            log info "✅ SysVinit (service) 服务注册并启动成功！"
            log info "   • 运维命令: service samba {start|stop|restart|status}"
            ;;
    esac
}

# 注销系统服务
function unregister_service {
    log info "正在注销 Samba 系统服务..."

    if [ -f "$SYSTEMD_FILE" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
        fi
        rm -f "$SYSTEMD_FILE"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        log info "已移除 systemd 服务: $SYSTEMD_FILE"
    fi

    if [ -f "$SYSVINIT_FILE" ]; then
        if command -v service >/dev/null 2>&1; then
            service "$UNIFIED_SERVICE_NAME" stop 2>/dev/null || true
        else
            "$SYSVINIT_FILE" stop 2>/dev/null || true
        fi

        if command -v update-rc.d >/dev/null 2>&1; then
            update-rc.d -f "$UNIFIED_SERVICE_NAME" remove 2>/dev/null || true
        elif command -v chkconfig >/dev/null 2>&1; then
            chkconfig --del "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
        fi
        rm -f "$SYSVINIT_FILE"
        log info "已移除 SysVinit 服务: $SYSVINIT_FILE"
    fi
}

# 服务控制
function service_control {
    local action="$1"
    local s_mgr
    s_mgr="$(detect_service_manager)"

    log info "正在执行服务操作: $action ..."

    case "$s_mgr" in
        systemd)
            case "$action" in
                start|stop|restart)
                    systemctl "$action" "$SYS_SERVICE_NAME" 2>/dev/null || true
                    systemctl "$action" "$NMB_SERVICE_NAME" 2>/dev/null || true
                    systemctl "$action" "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
                    log info "Samba 服务 [$action] 完成。"
                    ;;
                status)
                    get_local_ip
                    echo "--------------------------------------------------------"
                    echo "内网 IP: $LOCAL_IP"
                    echo "服务运行状态 ($SYS_SERVICE_NAME):"
                    systemctl status "$SYS_SERVICE_NAME" --no-pager 2>/dev/null || true
                    echo "--------------------------------------------------------"
                    if [ -f "$SMB_CONF" ]; then
                        echo "当前已注册的共享磁盘卷:"
                        grep -E '^\s*\[.*\]' "$SMB_CONF" | grep -v '\[global\]' || echo "无"
                    fi
                    ;;
            esac
            ;;

        sysvinit|direct)
            if [ -f "$SYSVINIT_FILE" ]; then
                if command -v service >/dev/null 2>&1; then
                    service "$UNIFIED_SERVICE_NAME" "$action"
                else
                    "$SYSVINIT_FILE" "$action"
                fi
            else
                case "$action" in
                    start)
                        smbd -D 2>/dev/null || /usr/sbin/smbd -D 2>/dev/null
                        nmbd -D 2>/dev/null || /usr/sbin/nmbd -D 2>/dev/null || true
                        log info "Samba 守护进程已启动。"
                        ;;
                    stop)
                        killall smbd 2>/dev/null || true
                        killall nmbd 2>/dev/null || true
                        log info "Samba 守护进程已停止。"
                        ;;
                    restart)
                        killall smbd 2>/dev/null || true
                        killall nmbd 2>/dev/null || true
                        sleep 1
                        smbd -D 2>/dev/null || /usr/sbin/smbd -D 2>/dev/null
                        nmbd -D 2>/dev/null || /usr/sbin/nmbd -D 2>/dev/null || true
                        log info "Samba 守护进程已重启。"
                        ;;
                    status)
                        if pgrep smbd >/dev/null 2>&1; then
                            echo "🟢 Samba (smbd) 正在运行 (PID: $(pgrep smbd | tr '\n' ' '))"
                        else
                            echo "🔴 Samba (smbd) 未运行"
                        fi
                        ;;
                esac
            fi

            if [ "$action" = "status" ]; then
                get_local_ip
                echo "--------------------------------------------------------"
                echo "内网 IP: $LOCAL_IP"
                if [ -f "$SMB_CONF" ]; then
                    echo "当前已注册的共享磁盘卷:"
                    grep -E '^\s*\[.*\]' "$SMB_CONF" | grep -v '\[global\]' || echo "无"
                fi
                echo "--------------------------------------------------------"
            fi
            ;;
    esac
}

# 列出当前所有 Samba 共享用户
function do_lsusers {
    echo ""
    echo "========================================================"
    echo "            Samba 已注册共享磁盘列表                    "
    echo "========================================================"
    if [ -f "$SMB_CONF" ]; then
        grep -E '^\s*\[.*\]' "$SMB_CONF" | grep -v '\[global\]' | while read -r line; do
            local sname
            sname=$(echo "$line" | tr -d '[]')
            local spath
            spath=$(grep -A 4 "\[$sname\]" "$SMB_CONF" 2>/dev/null | grep 'path =' | awk '{print $3}')
            local suser
            suser=$(grep -A 7 "\[$sname\]" "$SMB_CONF" 2>/dev/null | grep 'valid users =' | awk '{print $4}')
            echo "• 共享磁盘: [$sname] ➔ 物理路径: $spath (授权用户: ${suser:-所有人})"
        done
    else
        echo "暂未发现 Samba 配置文件 ($SMB_CONF)"
    fi
    echo "========================================================"
    echo ""
}

# 安装流程汇总
function do_install {
    local input_base_dir="$1"
    local input_user="$2"
    local input_pass="$3"

    echo ""
    echo "========================================================"
    echo "      Samba 独立存储隔离服务部署向导 (iStoreOS 架构)    "
    echo "========================================================"
    echo ""

    if [ -n "$input_base_dir" ]; then
        BASE_DIR="$input_base_dir"
    else
        read -r -p "请输入共享根目录 [默认: /data/share, 回车确认]: " BASE_DIR
        BASE_DIR="${BASE_DIR:-/data/share}"
    fi

    if [ -n "$input_user" ]; then
        SMB_USER="$input_user"
    else
        read -r -p "请输入初始专属用户账号 [默认: $ORIGINAL_USER]: " SMB_USER
        SMB_USER="${SMB_USER:-$ORIGINAL_USER}"
    fi

    if [ -n "$input_pass" ]; then
        SMB_PASS="$input_pass"
    else
        while true; do
            read -r -s -p "请输入用户 [$SMB_USER] 的 Samba 访问密码: " SMB_PASS
            echo ""
            if [ -z "$SMB_PASS" ]; then
                echo "密码不能为空，请重新输入！"
                continue
            fi
            read -r -s -p "请再次确认密码: " SMB_PASS_CONFIRM
            echo ""
            if [ "$SMB_PASS" != "$SMB_PASS_CONFIRM" ]; then
                echo "两次输入的密码不一致，请重新输入！"
            else
                break
            fi
        done
    fi

    log info "配置参数确认:"
    log info "  共享根目录: $BASE_DIR"
    log info "  初始用户:   $SMB_USER (专属物理存储: ${BASE_DIR}/${SMB_USER})"

    # 1. 安装软件包
    install_packages
    
    # 2. 生成全新全局基础配置 (写入 Apple 兼容及性能参数)
    init_smb_global_conf
    
    # 3. 注册初始用户专属磁盘块 [用户名] (对应 /data/share/<用户名>)
    add_user_to_samba "$SMB_USER" "$SMB_PASS" "$BASE_DIR"
    
    # 4. 配置 SELinux 与防火墙
    configure_selinux "$BASE_DIR"
    configure_firewall
    
    # 5. 配置 Bonjour (Avahi) 网络广播 (让 Mac 侧边栏自动发现并支持推出)
    configure_avahi
    
    # 6. 注册并启动系统服务
    register_service
    get_local_ip

    local s_mgr
    s_mgr="$(detect_service_manager)"

    echo ""
    echo -e "\033[32m========================================================\033[0m"
    echo -e "\033[32m       Samba 专属独立存储隔离服务部署成功！             \033[0m"
    echo -e "\033[32m========================================================\033[0m"
    echo -e "服务器内网 IP:     \033[36m$LOCAL_IP\033[0m"
    echo -e "用户专属磁盘名:    \033[36m$SMB_USER\033[0m"
    echo -e "对应物理存储目录:  \033[36m${BASE_DIR}/${SMB_USER}\033[0m"
    if [ "$s_mgr" = "systemd" ]; then
        echo -e "服务托管模式:      \033[36msystemd (systemctl status samba)\033[0m"
    else
        echo -e "服务托管模式:      \033[36mSysVinit (service samba status)\033[0m"
    fi
    echo "--------------------------------------------------------"
    echo "📁 客户端连接方式:"
    echo -e " 1. \033[33mmacOS 访达 (Cmd + K)\033[0m:"
    echo -e "    输入地址: \033[32msmb://${LOCAL_IP}/${SMB_USER}\033[0m"
    echo "    (挂载后将在 Mac 侧边栏显示独立磁盘卷，并自带 ⏏ 推出按钮)"
    echo ""
    echo -e " 2. \033[33mWindows 运行 (Win + R)\033[0m:"
    echo -e "    输入地址: \033[32m\\\\${LOCAL_IP}\\${SMB_USER}\033[0m"
    echo "--------------------------------------------------------"
    echo "👥 添加更多独立隔离用户 (如 zsc):"
    echo "    执行: sudo ./samba_install.sh adduser <新用户名> <密码>"
    echo "    (系统将自动创建 ${BASE_DIR}/<新用户名> 并注册独立磁盘块)"
    echo "========================================================"
    echo ""
}

# 卸载流程
function do_uninstall {
    echo ""
    echo "========================================================"
    echo "                 Samba 卸载向导                         "
    echo "========================================================"
    echo ""

    read -r -p "确定要彻底卸载 Samba 吗？此操作将注销系统服务并删除安装包 (y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log info "用户取消卸载操作。"
        exit 0
    fi

    unregister_service

    log info "正在卸载 Samba 软件包..."
    case "$OS_FAMILY" in
        debian)
            apt-get purge -y samba samba-common samba-common-bin smbclient || apt-get remove -y samba samba-common
            apt-get autoremove -y
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf remove -y samba samba-common samba-client
            else
                yum remove -y samba samba-common samba-client
            fi
            ;;
    esac

    read -r -p "是否清理 Samba 配置文件目录 (/etc/samba)? [y/N]: " clean_conf
    if [[ "$clean_conf" =~ ^[Yy]$ ]]; then
        rm -rf /etc/samba
        rm -f /etc/avahi/services/samba.service 2>/dev/null || true
        log info "已清理 /etc/samba 及 Bonjour 服务配置。"
    else
        log info "保留配置文件于 /etc/samba。"
    fi

    log info "注意: 用户的实际数据存储目录未被删除以防数据丢失。"
    log info "Samba 服务注销与卸载完成！"
}

# 添加新用户
function do_adduser {
    local new_user="$1"
    local new_pass="$2"
    local base_dir
    base_dir="$(get_base_share_dir)"

    if [ -z "$new_user" ]; then
        read -r -p "请输入要添加的 Samba 用户名: " new_user
    fi

    if [ -z "$new_pass" ]; then
        while true; do
            read -r -s -p "请输入 [$new_user] 的密码: " new_pass
            echo ""
            if [ -z "$new_pass" ]; then
                echo "密码不能为空！"
                continue
            fi
            read -r -s -p "请再次确认密码: " new_pass_confirm
            echo ""
            if [ "$new_pass" != "$new_pass_confirm" ]; then
                echo "两次密码不一致，请重试！"
            else
                break
            fi
        done
    fi

    add_user_to_samba "$new_user" "$new_pass" "$base_dir"
}

# 删除用户
function do_deluser {
    local del_user="$1"
    if [ -z "$del_user" ]; then
        read -r -p "请输入要删除的 Samba 用户名: " del_user
    fi
    remove_user_from_samba "$del_user"
}

# 主菜单入口
function main_menu {
    while true; do
        echo ""
        echo "========================================================"
        echo "       Samba 独立存储与服务一键管理 (iStoreOS 架构)     "
        echo "========================================================"
        echo " 1. 安装并配置 Samba 服务 (带用户独立专属存储)"
        echo " 2. 单独注册系统服务并开启自启 (Service Register)"
        echo " 3. 注销系统服务 (Service Unregister)"
        echo " 4. 查看 Samba 运行状态 (Status)"
        echo " 5. 启动服务 (Start)"
        echo " 6. 停止服务 (Stop)"
        echo " 7. 重启服务 (Restart)"
        echo " 8. 添加新专属用户 (自动在 /data/share/<用户> 创建并隔离)"
        echo " 9. 查看所有已注册磁盘与用户 (List Users)"
        echo " 10. 删除用户与专属磁盘 (Delete User)"
        echo " 11. 完全卸载 Samba (Uninstall)"
        echo " 0. 退出 (Exit)"
        echo "========================================================"
        read -r -p "请输入选项 [0-11]: " choice

        case "$choice" in
            1)
                do_install
                ;;
            2)
                register_service
                ;;
            3)
                unregister_service
                ;;
            4)
                service_control status
                ;;
            5)
                service_control start
                ;;
            6)
                service_control stop
                ;;
            7)
                service_control restart
                ;;
            8)
                do_adduser
                ;;
            9)
                do_lsusers
                ;;
            10)
                do_deluser
                ;;
            11)
                do_uninstall
                ;;
            0)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效输入，请输入 0-11。"
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

ACTION="${1:-}"

case "$ACTION" in
    install|-i|--install)
        do_install "$2" "$3" "$4"
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
        do_adduser "$2" "$3"
        ;;
    deluser|del-user)
        do_deluser "$2"
        ;;
    lsusers|users)
        do_lsusers
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0                                   # 交互式菜单"
        echo "  sudo $0 install [共享根目录] [用户] [密码]  # 一键安装"
        echo "  sudo $0 adduser [新用户名] [密码]           # 添加新隔离用户"
        echo "  sudo $0 lsusers                           # 查看所有用户磁盘"
        echo "  sudo $0 deluser [用户名]                   # 删除用户与磁盘"
        echo "  sudo $0 start|stop|restart|status         # 服务启停状态"
        echo "  sudo $0 service register                  # 仅注册系统服务"
        echo "  sudo $0 service unregister                # 注销系统服务"
        echo "  sudo $0 uninstall                         # 卸载 Samba"
        ;;
    "")
        main_menu
        ;;
    *)
        log error "未知命令: $ACTION。使用 '$0 help' 查看帮助。"
        ;;
esac
