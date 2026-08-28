#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: samba_install.sh
# 描述:     Samba 自动化安装、多用户独立存储隔离、系统服务注册与卸载脚本
# 适用系统: Debian 系列 (Ubuntu, Debian, Deepin, Mint, Kali 等)
#           RedHat 系列 (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora, openEuler 等)
# 适用架构: x86_64, aarch64 (ARM64), armv7l, armhf, i386 等
# 用户隔离: 支持每个用户独立私有存储目录 (0700 权限隔离) + 可选公共共享区
# 服务托管: 智能三级自适应探测 (systemctl ➔ service ➔ direct)
#
# 用法:
#   1. 交互式运行 (自动提权):
#      ./samba_install.sh
#   2. 快速安装 (自动注册服务并启动):
#      sudo ./samba_install.sh install [公共目录路径] [用户私有基目录] [初始用户名] [密码]
#      例如: sudo ./samba_install.sh install /data/share /data/users smbuser 123456
#   3. 服务独立注册与管理:
#      sudo ./samba_install.sh service register    # 注册系统服务并开启自启
#      sudo ./samba_install.sh service unregister  # 注销系统服务
#      sudo ./samba_install.sh start|stop|restart|status # 服务启停状态
#   4. 用户管理 (自动创建隔离私有目录):
#      sudo ./samba_install.sh adduser [用户名] [密码]
#      sudo ./samba_install.sh deluser [用户名]
#   5. 完全卸载:
#      sudo ./samba_install.sh uninstall
# ==============================================================================

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="${SCRIPT_ROOT}/samba_install.log"

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

    # 归类系统家族
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

# 智能探测当前环境服务管理器 (systemd ➔ SysVinit/service ➔ direct)
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

# 安装依赖与 Samba 软件包
function install_packages {
    log info "开始安装 Samba 相关软件包..."

    case "$OS_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y samba samba-common-bin smbclient procps
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                PKG_MGR="dnf"
            else
                PKG_MGR="yum"
            fi
            $PKG_MGR makecache -y || true
            $PKG_MGR install -y samba samba-common samba-client procps-ng policycoreutils-python-utils || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng policycoreutils-python || \
            $PKG_MGR install -y samba samba-common samba-client procps-ng
            ;;
    esac

    log info "Samba 软件包安装完成。"
}

# 配置防火墙规则
function configure_firewall {
    log info "正在检查并配置防火墙..."

    # 1. 针对 firewalld
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-service=samba >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log info "已在 firewalld 中放行 Samba 服务规则。"
    fi

    # 2. 针对 ufw
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

# 配置 SELinux
function configure_selinux {
    local dirs=("$@")
    if command -v getenforce >/dev/null 2>&1; then
        local selinux_status
        selinux_status=$(getenforce)
        if [ "$selinux_status" = "Enforcing" ] || [ "$selinux_status" = "Permissive" ]; then
            log info "检测到 SELinux 状态为: $selinux_status，正在配置 Samba 安全策略..."
            setsebool -P samba_enable_home_dirs on >/dev/null 2>&1 || true
            setsebool -P samba_export_all_rw on >/dev/null 2>&1 || true
            
            for dir in "${dirs[@]}"; do
                if [ -n "$dir" ] && [ -d "$dir" ]; then
                    if command -v semanage >/dev/null 2>&1; then
                        semanage fcontext -a -t samba_share_t "${dir}(/.*)?" >/dev/null 2>&1 || true
                        restorecon -R -v "$dir" >> "$logfile" 2>&1 || true
                    else
                        chcon -t samba_share_t "$dir" >/dev/null 2>&1 || true
                    fi
                fi
            done
            log info "SELinux 规则配置完成。"
        fi
    fi
}

# 创建用户专属私有目录 (严格 0700 权限隔离)
function setup_user_private_dir {
    local user_base_dir="$1"
    local username="$2"

    if [ -n "$user_base_dir" ] && [ -n "$username" ]; then
        local user_dir="${user_base_dir}/${username}"
        mkdir -p "$user_dir"
        chown -R "${username}:${username}" "$user_dir" 2>/dev/null || chown -R "${username}" "$user_dir" 2>/dev/null || true
        chmod 0700 "$user_dir"
        log info "已为用户 [$username] 创建独立私有存储目录: $user_dir (权限: 0700 私有隔离)"
    fi
}

# 创建公共共享目录
function setup_public_directory {
    local share_dir="$1"
    if [ -n "$share_dir" ]; then
        log info "正在设置公共共享目录: $share_dir"
        mkdir -p "$share_dir"
        chmod -R 0777 "$share_dir"
        log info "公共共享目录权限设置完成 (0777)。"
    fi
}

# 创建 Samba 账户并初始化其隔离存储空间
function setup_samba_user {
    local smb_user="$1"
    local smb_pass="$2"
    local user_base_dir="${3:-/data/users}"

    log info "正在配置 Samba 用户 [$smb_user]..."

    # 1. 检查 Samba 工具是否已安装
    if ! command -v smbpasswd >/dev/null 2>&1; then
        log warn "未检测到 smbpasswd 命令，正在为您自动安装 Samba 组件..."
        install_packages
    fi

    # 2. 确保系统用户存在
    if ! id "$smb_user" >/dev/null 2>&1; then
        log info "系统用户 [$smb_user] 不存在，自动创建系统账户（无登录shell）..."
        useradd -M -s /usr/sbin/nologin "$smb_user" 2>/dev/null || \
        useradd -M -s /sbin/nologin "$smb_user" 2>/dev/null || \
        useradd -s /bin/false "$smb_user" 2>/dev/null || \
        useradd "$smb_user"
    fi

    # 3. 将用户添加到 Samba 数据库并设置密码
    (echo "$smb_pass"; echo "$smb_pass") | smbpasswd -s -a "$smb_user"
    smbpasswd -e "$smb_user" >/dev/null 2>&1 || true

    # 4. 创建专属私有隔离目录
    setup_user_private_dir "$user_base_dir" "$smb_user"

    log info "✅ Samba 用户 [$smb_user] 密码设置、启用及私有隔离空间创建成功！"
}

# 写入 Samba 主配置文件 /etc/samba/smb.conf
function configure_smb_conf {
    local public_dir="$1"
    local user_base_dir="$2"

    local smb_conf="/etc/samba/smb.conf"
    local backup_conf="/etc/samba/smb.conf.bak.$(date +%Y%m%d%H%M%S)"

    log info "正在配置 $smb_conf ..."

    if [ -f "$smb_conf" ]; then
        cp "$smb_conf" "$backup_conf"
        log info "已备份原配置文件到: $backup_conf"
    else
        mkdir -p /etc/samba
    fi

    # 写入全局基础配置
    cat << 'EOF' > "$smb_conf"
# ==============================================================================
# Samba Configuration (Generated by samba_install.sh)
# ==============================================================================

[global]
    workgroup = WORKGROUP
    server string = Samba File Server
    netbios name = SambaServer
    security = user
    map to guest = Bad User
    dns proxy = no

    # 性能优化 & 协议支持 (针对 macOS 深度优化)
    min protocol = SMB2
    client min protocol = SMB2
    vfs objects = catia fruit streams_xattr
    fruit:aapl = yes
    fruit:nfs_aces = no
    fruit:copyfile = yes
    fruit:metadata = stream
    fruit:model = Macmini
    fruit:posix_rename = yes
    fruit:veto_appledouble = no
    fruit:wipe_intentionally_left_blank_rfork = yes
    fruit:delete_empty_adfiles = yes

    # 日志配置
    log file = /var/log/samba/log.%m
    max log size = 10000
    logging = file
    panic action = /usr/share/samba/panic-action %d

    # 禁用打印多余日志
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes

EOF

    # 1. 写入用户独立私有空间共享段 (每个用户直接使用自己的用户名访问: \\IP\用户名 或 smb://IP/用户名)
    cat << EOF >> "$smb_conf"
# ------------------------------------------------------------------------------
# 👤 用户独立私有隔离存储空间 (客户端直接连接 \\IP\用户名 或 smb://IP/用户名)
# ------------------------------------------------------------------------------
[homes]
    comment = %S 的专属个人私有空间
    path = ${user_base_dir}/%S
    browseable = yes
    writable = yes
    read only = no
    valid users = %S
    create mask = 0700
    directory mask = 0700
    force create mode = 0700
    force directory mode = 0700
    root preexec = /bin/sh -c '/bin/mkdir -m 0700 -p ${user_base_dir}/%S && /bin/chown %S:%S ${user_base_dir}/%S'

EOF

    # 2. 写入公共共享区段 (如果指定了公共目录)
    if [ -n "$public_dir" ]; then
        cat << EOF >> "$smb_conf"
# ------------------------------------------------------------------------------
# 🌐 团队公共共享区 (所有合法用户均可读写)
# ------------------------------------------------------------------------------
[public]
    comment = 团队公共共享空间
    path = $public_dir
    browseable = yes
    writable = yes
    read only = no
    guest ok = no
    create mask = 0775
    directory mask = 0775
    force create mode = 0775
    force directory mode = 0775

EOF
    fi

    # 语法检测
    if command -v testparm >/dev/null 2>&1; then
        if testparm -s "$smb_conf" >/dev/null 2>&1; then
            log info "Samba 配置文件语法检测通过 (testparm OK)。"
        else
            log warn "Samba 配置文件可能存在警告，请检查 $smb_conf"
        fi
    fi
}

# 生成通用的 SysVinit 服务脚本 (/etc/init.d/samba)
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

# 注册统一系统服务
function register_service {
    log info "开始注册并配置 Samba 系统服务..."
    local s_mgr
    s_mgr="$(detect_service_manager)"

    generate_sysvinit_script

    case "$s_mgr" in
        systemd)
            log info "【方案一：systemd 生效】检测到活跃 systemctl 环境，正在注册统一系统服务 [samba.service]..."

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

# 统一服务控制 (兼容 systemctl 与 service)
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
                    echo "服务状态 ($SYS_SERVICE_NAME / $UNIFIED_SERVICE_NAME):"
                    systemctl status "$SYS_SERVICE_NAME" --no-pager 2>/dev/null || systemctl status "$UNIFIED_SERVICE_NAME" --no-pager 2>/dev/null || true
                    echo "--------------------------------------------------------"
                    if [ -f /etc/samba/smb.conf ]; then
                        echo "当前共享列表 (来自 /etc/samba/smb.conf):"
                        grep -E '^\s*\[.*\]' /etc/samba/smb.conf || true
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
                if [ -f /etc/samba/smb.conf ]; then
                    echo "当前共享列表 (来自 /etc/samba/smb.conf):"
                    grep -E '^\s*\[.*\]' /etc/samba/smb.conf || true
                fi
                echo "--------------------------------------------------------"
            fi
            ;;
    esac
}

# ==============================================================================
# 安装与卸载工作流
# ==============================================================================

# 安装流程汇总
function do_install {
    local input_public_dir="$1"
    local input_user_base_dir="$2"
    local input_user="$3"
    local input_pass="$4"

    echo ""
    echo "========================================================"
    echo "       Samba 多用户独立隔离存储自动化安装向导           "
    echo "========================================================"
    echo ""

    if [ -n "$input_public_dir" ]; then
        PUBLIC_DIR="$input_public_dir"
    else
        read -r -p "请输入团队公共共享目录路径 [默认: /data/share, 回车确认]: " PUBLIC_DIR
        PUBLIC_DIR="${PUBLIC_DIR:-/data/share}"
    fi

    if [ -n "$input_user_base_dir" ]; then
        USER_BASE_DIR="$input_user_base_dir"
    else
        read -r -p "请输入每个用户私有隔离存储根目录 [默认: /data/users, 回车确认]: " USER_BASE_DIR
        USER_BASE_DIR="${USER_BASE_DIR:-/data/users}"
    fi

    if [ -n "$input_user" ]; then
        SMB_USER="$input_user"
    else
        read -r -p "请输入初始管理员/用户账号 [默认: $ORIGINAL_USER]: " SMB_USER
        SMB_USER="${SMB_USER:-$ORIGINAL_USER}"
    fi

    if [ -n "$input_pass" ]; then
        SMB_PASS="$input_pass"
    else
        while true; do
            read -r -s -p "请输入用户 [$SMB_USER] 的 Samba 密码: " SMB_PASS
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
    log info "  团队公共目录: $PUBLIC_DIR"
    log info "  用户隔离根目录: $USER_BASE_DIR (每个用户自动分配 $USER_BASE_DIR/<用户名>)"
    log info "  初始用户账号: $SMB_USER"

    # 执行安装各步骤
    install_packages
    setup_public_directory "$PUBLIC_DIR"
    setup_samba_user "$SMB_USER" "$SMB_PASS" "$USER_BASE_DIR"
    configure_smb_conf "$PUBLIC_DIR" "$USER_BASE_DIR"
    configure_selinux "$PUBLIC_DIR" "$USER_BASE_DIR"
    configure_firewall
    register_service
    get_local_ip

    local s_mgr
    s_mgr="$(detect_service_manager)"

    echo ""
    echo -e "\033[32m========================================================\033[0m"
    echo -e "\033[32m       Samba 多用户独立存储隔离服务部署成功！           \033[0m"
    echo -e "\033[32m========================================================\033[0m"
    echo -e "服务器内网 IP:     \033[36m$LOCAL_IP\033[0m"
    echo -e "公共共享路径:      \033[36m$PUBLIC_DIR (网络共享名: public)\033[0m"
    echo -e "用户隔离存储基目录:\033[36m$USER_BASE_DIR (按用户名挂载专属目录)\033[0m"
    echo -e "已创建初始用户:    \033[36m$SMB_USER (私有空间: ${USER_BASE_DIR}/${SMB_USER})\033[0m"
    if [ "$s_mgr" = "systemd" ]; then
        echo -e "服务托管模式:      \033[36msystemd (systemctl status samba)\033[0m"
    else
        echo -e "服务托管模式:      \033[36mSysVinit (service samba status)\033[0m"
    fi
    echo "--------------------------------------------------------"
    echo "📁 客户端访问方式说明:"
    echo -e " 1. \033[33m访问个人专属私有目录 (仅自己可见/可读写，挂载名显示为用户名)\033[0m:"
    echo -e "    • Windows: \033[32m\\\\${LOCAL_IP}\\${SMB_USER}\033[0m"
    echo -e "    • macOS:   \033[32msmb://${LOCAL_IP}/${SMB_USER}\033[0m"
    echo ""
    echo -e " 2. \033[33m访问团队公共共享区 (所有团队成员共享协作)\033[0m:"
    echo -e "    • Windows: \033[32m\\\\${LOCAL_IP}\\public\033[0m"
    echo -e "    • macOS:   \033[32msmb://${LOCAL_IP}/public\033[0m"
    echo "--------------------------------------------------------"
    echo "👥 添加更多隔离用户:"
    echo "    执行: sudo ./samba_install.sh adduser <新用户名> <密码>"
    echo "    (新用户可直接用 smb://${LOCAL_IP}/<新用户名> 连接其专属空间)"
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
        log info "已清理 /etc/samba 目录。"
    else
        log info "保留配置文件于 /etc/samba。"
    fi

    log info "注意: 用户的私有隔离目录及公共共享数据未被删除以防数据丢失。"
    log info "Samba 服务注销与卸载完成！"
}

# 获取当前配置中的用户基目录
function get_user_base_dir_from_conf {
    local dir
    dir=$(grep -A 5 '\[homes\]' /etc/samba/smb.conf 2>/dev/null | grep 'path =' | head -n 1 | awk '{print $3}' | sed 's|/%S||')
    echo "${dir:-/data/users}"
}

# 添加新用户
function do_adduser {
    local new_user="$1"
    local new_pass="$2"
    local user_base_dir
    user_base_dir=$(get_user_base_dir_from_conf)

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

    setup_samba_user "$new_user" "$new_pass" "$user_base_dir"
}

# 删除用户
function do_deluser {
    local del_user="$1"
    local user_base_dir
    user_base_dir=$(get_user_base_dir_from_conf)

    if [ -z "$del_user" ]; then
        read -r -p "请输入要删除的 Samba 用户名: " del_user
    fi

    log info "正在从 Samba 移除用户 [$del_user]..."
    smbpasswd -x "$del_user" >> "$logfile" 2>&1 || true

    read -r -p "是否同时删除该用户的私有存储数据 (${user_base_dir}/${del_user})? [y/N]: " del_data
    if [[ "$del_data" =~ ^[Yy]$ ]]; then
        rm -rf "${user_base_dir:?}/${del_user}"
        log info "已删除用户数据目录: ${user_base_dir}/${del_user}"
    else
        log info "已保留用户私有数据目录。"
    fi

    read -r -p "是否同时删除 Linux 系统账户 [$del_user]? [y/N]: " del_sys_user
    if [[ "$del_sys_user" =~ ^[Yy]$ ]]; then
        userdel "$del_user" 2>/dev/null || true
        log info "已删除 Linux 系统账户 [$del_user]"
    fi

    log info "用户 [$del_user] 删除完成。"
}

# 主菜单入口
function main_menu {
    while true; do
        echo ""
        echo "========================================================"
        echo "       Samba 多用户独立存储与服务一键管理               "
        echo "========================================================"
        echo " 1. 安装并配置 Samba 服务 (带独立存储隔离)"
        echo " 2. 单独注册系统服务并开启自启 (Service Register)"
        echo " 3. 注销系统服务 (Service Unregister)"
        echo " 4. 查看 Samba 运行状态 (Status)"
        echo " 5. 启动服务 (Start)"
        echo " 6. 停止服务 (Stop)"
        echo " 7. 重启服务 (Restart)"
        echo " 8. 添加新用户 (自动分配独立私有存储空间)"
        echo " 9. 删除用户 (Del User)"
        echo " 10. 完全卸载 Samba (Uninstall)"
        echo " 0. 退出 (Exit)"
        echo "========================================================"
        read -r -p "请输入选项 [0-10]: " choice

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
                do_deluser
                ;;
            10)
                do_uninstall
                ;;
            0)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效输入，请输入 0-10。"
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
        do_adduser "$2" "$3"
        ;;
    deluser|del-user)
        do_deluser "$2"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0                                         # 交互式菜单"
        echo "  sudo $0 install [公共目录] [私有根目录] [用户] [密码] # 安装并配置隔离存储"
        echo "  sudo $0 service register                        # 仅注册系统服务"
        echo "  sudo $0 service unregister                      # 注销系统服务"
        echo "  sudo $0 start|stop|restart|status               # 服务启停状态"
        echo "  sudo $0 adduser [新用户名] [密码]                 # 添加新隔离用户"
        echo "  sudo $0 deluser [用户名]                         # 删除用户"
        echo "  sudo $0 uninstall                               # 卸载 Samba"
        ;;
    "")
        main_menu
        ;;
    *)
        log error "未知命令: $ACTION。使用 '$0 help' 查看帮助。"
        ;;
esac
