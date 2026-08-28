#!/usr/bin/env bash
# ==============================================================================
# 脚本名称: filebrowser_install.sh
# 描述:     FileBrowser 轻量级 Web 文件管理器自动化安装、多用户存储隔离与运维管理脚本
# 适用系统: Debian 系列 (Ubuntu, Debian, Deepin, Mint, Kali 等)
#           RedHat 系列 (RHEL, CentOS, Rocky Linux, AlmaLinux, Fedora, openEuler 等)
# 适用架构: x86_64 (amd64), aarch64 (arm64), armv7l, armv6l, i386 (386)
# 用户隔离: 支持多用户空间隔离 (每个用户绑定独立的 Scope 存储目录，完美协同 Samba)
# 服务托管: 智能三级自适应探测 (systemctl ➔ service ➔ direct)
#
# 用法:
#   1. 交互式运行 (自动提权):
#      ./filebrowser_install.sh
#   2. 快速安装 (自动注册服务并启动):
#      sudo ./filebrowser_install.sh install [管理目录路径] [监听端口] [管理员密码]
#      例如: sudo ./filebrowser_install.sh install /data 8080 admin123
#   3. 用户管理 (支持独立目录 Scope 隔离):
#      sudo ./filebrowser_install.sh adduser [用户名] [密码] [专属目录路径]
#      例如: sudo ./filebrowser_install.sh adduser alice 123456 /data/users/alice
#      sudo ./filebrowser_install.sh deluser [用户名]
#      sudo ./filebrowser_install.sh lsusers
#   4. 服务独立注册与管理:
#      sudo ./filebrowser_install.sh service register    # 注册系统服务并开启自启
#      sudo ./filebrowser_install.sh service unregister  # 注销系统服务
#      sudo ./filebrowser_install.sh start|stop|restart|status # 服务启停状态
#   5. 完全卸载:
#      sudo ./filebrowser_install.sh uninstall
# ==============================================================================

set -e

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="${SCRIPT_ROOT}/filebrowser_install.log"

INSTALL_BIN="/usr/local/bin/filebrowser"
CONFIG_DIR="/etc/filebrowser"
DB_FILE="${CONFIG_DIR}/filebrowser.db"
LOG_PATH="/var/log/filebrowser.log"
PID_FILE="/var/run/filebrowser.pid"

UNIFIED_SERVICE_NAME="filebrowser"
SYSTEMD_FILE="/etc/systemd/system/${UNIFIED_SERVICE_NAME}.service"
SYSVINIT_FILE="/etc/init.d/${UNIFIED_SERVICE_NAME}"

# 默认版本
DEFAULT_VERSION="v2.63.23"

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
    case "$RAW_ARCH" in
        x86_64|amd64)
            TARGET_ARCH="amd64"
            ;;
        aarch64|arm64)
            TARGET_ARCH="arm64"
            ;;
        armv7l|armhf)
            TARGET_ARCH="armv7"
            ;;
        armv6l)
            TARGET_ARCH="armv6"
            ;;
        i386|i686)
            TARGET_ARCH="386"
            ;;
        *)
            log error "不支持的 CPU 架构: $RAW_ARCH"
            ;;
    esac
    log info "检测到系统 CPU 架构: $RAW_ARCH (适配下载包: $TARGET_ARCH)"

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
    elif [[ "$OS_ID" =~ ^(rhel|centos|fedora|rocky|almalinux|ol|anolis|openeuler|kylin)$ ]] || [[ "$OS_LIKE" =~ (rhel|fedora|centos) ]]; then
        OS_FAMILY="redhat"
    else
        OS_FAMILY="linux-generic"
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

# 安装基础解压与下载依赖
function install_dependencies {
    log info "检查并安装基础依赖包 (curl, wget, tar, procps)..."
    case "$OS_FAMILY" in
        debian)
            export DEBIAN_FRONTEND=noninteractive
            apt-get update -y
            apt-get install -y curl wget tar procps
            ;;
        redhat)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y curl wget tar procps-ng
            else
                yum install -y curl wget tar procps-ng
            fi
            ;;
        *)
            if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
                log error "系统中缺少 curl 或 wget，请手动安装后重试。"
            fi
            if ! command -v tar >/dev/null 2>&1; then
                log error "系统中缺少 tar 解压工具，请手动安装后重试。"
            fi
            ;;
    esac
    log info "基础依赖检查完成。"
}

# 下载并安装 FileBrowser 二进制文件
function download_filebrowser {
    log info "正在获取 FileBrowser 安装包..."

    local pkg_name="linux-${TARGET_ARCH}-filebrowser.tar.gz"
    local tmp_dir="/tmp/filebrowser_install_$$"
    rm -rf "$tmp_dir"
    mkdir -p "$tmp_dir"

    # 1. 检查本地是否存在离线安装包或二进制
    local local_search_paths=(
        "${SCRIPT_ROOT}/${pkg_name}"
        "./${pkg_name}"
        "/tmp/${pkg_name}"
        "${SCRIPT_ROOT}/filebrowser"
        "./filebrowser"
        "/tmp/filebrowser"
    )
    for p in "${local_search_paths[@]}"; do
        if [ -f "$p" ]; then
            if [[ "$p" == *.tar.gz ]] && tar -tzf "$p" >/dev/null 2>&1; then
                log info "检测到本地有效离线安装包: $p，直接使用本地文件..."
                cp -f "$p" "${tmp_dir}/${pkg_name}"
                tar -xzf "${tmp_dir}/${pkg_name}" -C "$tmp_dir" || true
                if [ -f "${tmp_dir}/filebrowser" ]; then
                    cp -f "${tmp_dir}/filebrowser" "$INSTALL_BIN"
                    chmod +x "$INSTALL_BIN"
                    rm -rf "$tmp_dir"
                    log info "FileBrowser 二进制安装成功 (离线包): $("$INSTALL_BIN" version 2>/dev/null || echo "$p")"
                    return 0
                fi
            elif [[ "$p" == *filebrowser ]] && [ -x "$p" ]; then
                log info "检测到本地有效可执行文件: $p，直接复制使用..."
                cp -f "$p" "$INSTALL_BIN"
                chmod +x "$INSTALL_BIN"
                rm -rf "$tmp_dir"
                log info "FileBrowser 二进制安装成功 (本地文件): $("$INSTALL_BIN" version 2>/dev/null || echo "$p")"
                return 0
            fi
        fi
    done

    # 2. 版本探测 (支持 API 直连与加速镜像探测，超时快速 Fallback)
    local version="$DEFAULT_VERSION"
    local latest_ver=""
    local api_urls=(
        "https://api.github.com/repos/filebrowser/filebrowser/releases/latest"
        "https://gh-proxy.com/https://api.github.com/repos/filebrowser/filebrowser/releases/latest"
    )
    for ver_url in "${api_urls[@]}"; do
        latest_ver=$(curl -s --connect-timeout 3 -m 5 "$ver_url" 2>/dev/null | grep '"tag_name":' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' | tr -d '[:space:]' || true)
        if [ -n "$latest_ver" ] && [[ "$latest_ver" =~ ^v?[0-9] ]]; then
            version="$latest_ver"
            log info "检测到 FileBrowser 最新版本: $version"
            break
        fi
    done

    if [ -z "$latest_ver" ] || [[ ! "$latest_ver" =~ ^v?[0-9] ]]; then
        version="$DEFAULT_VERSION"
        log info "使用预设稳定版本: $version"
    fi

    # 3. 构造加速下载源列表 (涵盖高可用国内 CDN 与镜像代理)
    local download_urls=()
    if [ -n "$FILEBROWSER_DOWNLOAD_URL" ]; then
        download_urls+=("$FILEBROWSER_DOWNLOAD_URL")
    fi
    download_urls+=(
        "https://gh-proxy.com/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh.ddlc.top/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://ghproxy.cc/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://gh.llkk.cc/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://github.chenby.cn/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://ghfast.top/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://mirror.ghproxy.com/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://ghproxy.net/https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
        "https://github.com/filebrowser/filebrowser/releases/download/${version}/${pkg_name}"
    )

    local download_success=false
    local target_file="${tmp_dir}/${pkg_name}"

    for url in "${download_urls[@]}"; do
        log info "尝试从下载源获取: $url"
        rm -f "$target_file"
        
        if command -v curl >/dev/null 2>&1; then
            curl -f -L --connect-timeout 5 --max-time 60 --retry 1 -o "$target_file" "$url" 2>>"$logfile" || true
        elif command -v wget >/dev/null 2>&1; then
            wget -q --timeout=20 --tries=2 -O "$target_file" "$url" 2>>"$logfile" || true
        fi

        # 严格验证是否为有效的 tar.gz 文件（大小 > 1MB 且 tar -tzf 测试正常）
        local f_size=0
        if [ -f "$target_file" ]; then
            f_size=$(stat -c%s "$target_file" 2>/dev/null || wc -c < "$target_file" 2>/dev/null || echo 0)
        fi

        if [ "$f_size" -gt 1000000 ] && tar -tzf "$target_file" >/dev/null 2>&1; then
            log info "安装包下载成功且完整性校验通过 (大小: $((f_size / 1024 / 1024)) MB)！"
            download_success=true
            break
        else
            log warn "当前源下载速度过慢、超时或文件校验失败，切换下一个加速源..."
            rm -f "$target_file"
        fi
    done

    if [ "$download_success" = false ]; then
        log error "无法下载 FileBrowser 安装包，请检查网络连接或手动下载 ${pkg_name} 放置于脚本目录。"
    fi

    log info "解压并安装二进制文件到 $INSTALL_BIN ..."
    tar -xzf "${tmp_dir}/${pkg_name}" -C "$tmp_dir" || log error "安装包解压失败！"
    
    if [ ! -f "${tmp_dir}/filebrowser" ]; then
        log error "解压后未找到 filebrowser 二进制文件！"
    fi

    cp -f "${tmp_dir}/filebrowser" "$INSTALL_BIN"
    chmod +x "$INSTALL_BIN"
    rm -rf "$tmp_dir"

    log info "FileBrowser 二进制安装成功: $("$INSTALL_BIN" version 2>/dev/null || echo "$version")"
}

# 配置数据库与初始化参数
function init_filebrowser_config {
    local root_dir="$1"
    local port="$2"
    local admin_pass="$3"

    mkdir -p "$CONFIG_DIR"
    mkdir -p "$root_dir"
    chmod -R 0777 "$root_dir" 2>/dev/null || true

    log info "正在初始化 FileBrowser 数据库 ($DB_FILE)..."

    if [ ! -f "$DB_FILE" ]; then
        "$INSTALL_BIN" config init -d "$DB_FILE" >> "$logfile" 2>&1
    fi

    "$INSTALL_BIN" config set -d "$DB_FILE" \
        --address "0.0.0.0" \
        --port "$port" \
        --root "$root_dir" \
        --log "$LOG_PATH" \
        --locale "zh-cn" \
        --branding.name "云端文件管理器" >> "$logfile" 2>&1

    log info "正在配置默认管理员账户 (admin)..."
    if "$INSTALL_BIN" users ls -d "$DB_FILE" 2>/dev/null | grep -qw "admin"; then
        "$INSTALL_BIN" users update admin -p "$admin_pass" --perm.admin=true --scope "." -d "$DB_FILE" >> "$logfile" 2>&1
    else
        "$INSTALL_BIN" users add admin "$admin_pass" --perm.admin=true --scope "." -d "$DB_FILE" >> "$logfile" 2>&1
    fi

    log info "FileBrowser 基础配置与管理员账户配置完成。"
}

# 配置防火墙放行
function configure_firewall {
    local port="$1"
    log info "正在检查并配置防火墙放行端口: $port ..."

    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state >/dev/null 2>&1; then
        firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
        firewall-cmd --reload >/dev/null 2>&1 || true
        log info "已在 firewalld 中放行 TCP ${port} 端口。"
    fi

    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qw "active"; then
        ufw allow "${port}/tcp" >/dev/null 2>&1 || true
        log info "已在 ufw 中放行 TCP ${port} 端口。"
    fi
}

# 生成 SysVinit 启动脚本
function generate_sysvinit_script {
    mkdir -p /etc/init.d
    cat << 'EOF' > "$SYSVINIT_FILE"
#!/bin/sh
### BEGIN INIT INFO
# Provides:          filebrowser
# Required-Start:    $network $local_fs $remote_fs
# Required-Stop:     $network $local_fs $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: FileBrowser Web File Manager Daemon
# Description:       FileBrowser Service Managed by filebrowser_install.sh
### END INIT INFO

BIN="/usr/local/bin/filebrowser"
DB_FILE="/etc/filebrowser/filebrowser.db"
PID_FILE="/var/run/filebrowser.pid"
LOG_FILE="/var/log/filebrowser.log"

start() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "FileBrowser is already running (PID: $(cat "$PID_FILE"))."
        return 0
    fi
    echo "Starting FileBrowser..."
    nohup "$BIN" -d "$DB_FILE" >> "$LOG_FILE" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 1
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "FileBrowser started successfully (PID: $(cat "$PID_FILE"))."
    else
        echo "Failed to start FileBrowser, check log: $LOG_FILE"
        return 1
    fi
}

stop() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        local pid=$(cat "$PID_FILE")
        echo "Stopping FileBrowser (PID: $pid)..."
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "FileBrowser stopped."
    else
        killall filebrowser 2>/dev/null || true
        rm -f "$PID_FILE"
        echo "FileBrowser is not running."
    fi
}

status() {
    if [ -f "$PID_FILE" ] && kill -0 $(cat "$PID_FILE") 2>/dev/null; then
        echo "🟢 FileBrowser is running (PID: $(cat "$PID_FILE"))"
        return 0
    elif pgrep -x filebrowser >/dev/null 2>&1; then
        echo "🟢 FileBrowser is running (PID: $(pgrep filebrowser | tr '\n' ' '))"
        return 0
    else
        echo "🔴 FileBrowser is stopped."
        return 1
    fi
}

case "$1" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; sleep 1; start ;;
    status)  status ;;
    *)
        echo "Usage: service filebrowser {start|stop|restart|status}"
        exit 1
        ;;
esac
exit 0
EOF
    chmod +x "$SYSVINIT_FILE"
}

# 注册系统服务
function register_service {
    log info "开始注册 FileBrowser 系统服务..."
    local s_mgr
    s_mgr="$(detect_service_manager)"

    generate_sysvinit_script

    case "$s_mgr" in
        systemd)
            log info "【方案一：systemd 生效】检测到 systemctl 环境，正在注册 [${UNIFIED_SERVICE_NAME}.service]..."

            cat << EOF > "$SYSTEMD_FILE"
[Unit]
Description=FileBrowser Web File Manager Service
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=${INSTALL_BIN} -d ${DB_FILE}
Restart=always
RestartSec=3s
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
            chmod 644 "$SYSTEMD_FILE"
            systemctl daemon-reload
            systemctl enable "${UNIFIED_SERVICE_NAME}.service" 2>/dev/null || true
            systemctl restart "${UNIFIED_SERVICE_NAME}.service"

            log info "✅ systemd 服务注册并自启成功！"
            log info "   • 服务名称: ${UNIFIED_SERVICE_NAME}.service"
            log info "   • 运维命令: systemctl {start|stop|restart|status} filebrowser"
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
            log info "   • 服务入口: $SYSVINIT_FILE"
            log info "   • 运维命令: service filebrowser {start|stop|restart|status}"
            ;;
    esac
}

# 注销系统服务
function unregister_service {
    log info "正在注销 FileBrowser 系统服务..."

    if [ -f "$SYSTEMD_FILE" ]; then
        if command -v systemctl >/dev/null 2>&1; then
            systemctl stop "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
            systemctl disable "$UNIFIED_SERVICE_NAME" 2>/dev/null || true
        fi
        rm -f "$SYSTEMD_FILE"
        if command -v systemctl >/dev/null 2>&1; then
            systemctl daemon-reload 2>/dev/null || true
        fi
        log info "已清理 systemd 单元: $SYSTEMD_FILE"
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
        log info "已清理 SysVinit 服务文件: $SYSVINIT_FILE"
    fi

    killall filebrowser 2>/dev/null || true
    rm -f "$PID_FILE"
}

# 统一服务控制
function service_control {
    local action="$1"
    local s_mgr
    s_mgr="$(detect_service_manager)"

    log info "正在执行服务操作: $action ..."

    case "$s_mgr" in
        systemd)
            case "$action" in
                start|stop|restart)
                    systemctl "$action" "$UNIFIED_SERVICE_NAME"
                    log info "FileBrowser 服务 [$action] 完成。"
                    ;;
                status)
                    get_local_ip
                    echo "--------------------------------------------------------"
                    echo "内网 IP: $LOCAL_IP"
                    echo "systemd 服务状态:"
                    systemctl status "$UNIFIED_SERVICE_NAME" --no-pager 2>/dev/null || true
                    echo "--------------------------------------------------------"
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
                        nohup "$INSTALL_BIN" -d "$DB_FILE" >> "$LOG_PATH" 2>&1 &
                        echo $! > "$PID_FILE"
                        log info "FileBrowser 已在后台启动。"
                        ;;
                    stop)
                        killall filebrowser 2>/dev/null || true
                        rm -f "$PID_FILE"
                        log info "FileBrowser 已停止。"
                        ;;
                    restart)
                        killall filebrowser 2>/dev/null || true
                        rm -f "$PID_FILE"
                        sleep 1
                        nohup "$INSTALL_BIN" -d "$DB_FILE" >> "$LOG_PATH" 2>&1 &
                        echo $! > "$PID_FILE"
                        log info "FileBrowser 已重启。"
                        ;;
                    status)
                        if pgrep filebrowser >/dev/null 2>&1; then
                            echo "🟢 FileBrowser 正在运行 (PID: $(pgrep filebrowser | tr '\n' ' '))"
                        else
                            echo "🔴 FileBrowser 未运行"
                        fi
                        ;;
                esac
            fi

            if [ "$action" = "status" ]; then
                get_local_ip
                echo "--------------------------------------------------------"
                echo "内网 IP: $LOCAL_IP"
                echo "日志文件: $LOG_PATH"
                echo "--------------------------------------------------------"
            fi
            ;;
    esac
}

# 添加多用户 (Scope 隔离)
function do_adduser {
    local username="$1"
    local password="$2"
    local user_scope="$3"

    if [ ! -f "$INSTALL_BIN" ] || [ ! -f "$DB_FILE" ]; then
        log warn "未检测到已安装的 FileBrowser，请先运行选项 1 完成初次安装！"
        return 0
    fi

    if [ -z "$username" ]; then
        read -r -p "请输入要创建的用户名: " username
    fi

    if [ -z "$password" ]; then
        while true; do
            read -r -s -p "请输入 [$username] 的登录密码: " password
            echo ""
            if [ -z "$password" ]; then
                echo "密码不能为空！"
                continue
            fi
            read -r -s -p "请再次确认密码: " password_confirm
            echo ""
            if [ "$password" != "$password_confirm" ]; then
                echo "两次输入的密码不一致，请重试！"
            else
                break
            fi
        done
    fi

    if [ -z "$user_scope" ]; then
        read -r -p "请输入该用户的私有隔离目录 [默认: /data/users/${username}]: " user_scope
        user_scope="${user_scope:-/data/users/${username}}"
    fi

    if [ ! -d "$user_scope" ]; then
        mkdir -p "$user_scope"
        chmod 0777 "$user_scope" 2>/dev/null || true
        log info "已自动创建用户隔离物理目录: $user_scope"
    fi

    if "$INSTALL_BIN" users ls -d "$DB_FILE" 2>/dev/null | grep -qw "$username"; then
        log warn "用户 [$username] 已存在，正在更新其密码与 Scope 隔离路径..."
        "$INSTALL_BIN" users update "$username" \
            --password "$password" \
            --scope "$user_scope" \
            --database "$DB_FILE" >> "$logfile" 2>&1
    else
        "$INSTALL_BIN" users add "$username" "$password" \
            --scope "$user_scope" \
            --locale "zh-cn" \
            --perm.create=true \
            --perm.delete=true \
            --perm.download=true \
            --perm.modify=true \
            --perm.share=true \
            --perm.admin=false \
            --database "$DB_FILE" >> "$logfile" 2>&1
    fi

    log info "✅ 用户 [$username] 创建成功！"
    log info "   • 隔离目录 (Scope): $user_scope (用户登录 Web 后只能访问此目录)"
}

# 列出所有用户
function do_lsusers {
    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi
    echo "========================================================"
    echo "            FileBrowser 用户列表                        "
    echo "========================================================"
    "$INSTALL_BIN" users ls -d "$DB_FILE"
    echo "========================================================"
}

# 删除用户
function do_deluser {
    local username="$1"
    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    if [ -z "$username" ]; then
        read -r -p "请输入要删除的用户名: " username
    fi

    if [ "$username" = "admin" ]; then
        log error "不能删除默认管理员账户 admin！"
    fi

    "$INSTALL_BIN" users rm "$username" -d "$DB_FILE" >> "$logfile" 2>&1
    log info "用户 [$username] 已从 FileBrowser 数据库中移除。"
}

# 重置密码
function do_setpasswd {
    local target_user="${1:-admin}"
    local new_pass="$2"

    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    if [ -z "$new_pass" ]; then
        while true; do
            read -r -s -p "请输入用户 [$target_user] 的新密码: " new_pass
            echo ""
            if [ -z "$new_pass" ]; then
                echo "密码不能为空！"
                continue
            fi
            read -r -s -p "请再次确认新密码: " new_pass_confirm
            echo ""
            if [ "$new_pass" != "$new_pass_confirm" ]; then
                echo "两次输入的密码不一致，请重试！"
            else
                break
            fi
        done
    fi

    "$INSTALL_BIN" users update "$target_user" -p "$new_pass" -d "$DB_FILE" >> "$logfile" 2>&1
    log info "用户 [$target_user] 密码修改成功！"
}

# 修改监听端口
function do_setport {
    local new_port="$1"

    if [ ! -f "$DB_FILE" ]; then
        log error "数据库文件不存在 ($DB_FILE)，请先安装 FileBrowser！"
    fi

    if [ -z "$new_port" ]; then
        read -r -p "请输入新的监听端口 [1-65535]: " new_port
    fi

    if [[ ! "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        log error "无效的端口号: $new_port"
    fi

    "$INSTALL_BIN" config set -p "$new_port" -d "$DB_FILE" >> "$logfile" 2>&1
    configure_firewall "$new_port"
    service_control restart
    log info "端口已修改为 $new_port 并已重启服务！"
}

# 安装流程汇总
function do_install {
    local input_root_dir="$1"
    local input_port="$2"
    local input_admin_pass="$3"

    echo ""
    echo "========================================================"
    echo "            FileBrowser 自动化安装向导                  "
    echo "========================================================"
    echo ""

    if [ -n "$input_root_dir" ]; then
        ROOT_DIR="$input_root_dir"
    else
        read -r -p "请输入 Web 全局文件根目录 [默认: /data, 回车确认]: " ROOT_DIR
        ROOT_DIR="${ROOT_DIR:-/data}"
    fi

    if [ -n "$input_port" ]; then
        PORT="$input_port"
    else
        read -r -p "请输入 Web 访问端口 [默认: 8080]: " PORT
        PORT="${PORT:-8080}"
    fi

    if [ -n "$input_admin_pass" ]; then
        ADMIN_PASS="$input_admin_pass"
    else
        while true; do
            read -r -s -p "请输入管理员 (admin) 的登录密码 [默认: admin]: " ADMIN_PASS
            echo ""
            ADMIN_PASS="${ADMIN_PASS:-admin}"
            if [ "$ADMIN_PASS" = "admin" ]; then
                log warn "您使用了默认密码 'admin'，建议上线后在控制台及时修改！"
                break
            fi
            read -r -s -p "请再次确认密码: " ADMIN_PASS_CONFIRM
            echo ""
            if [ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]; then
                echo "两次输入的密码不一致，请重新输入！"
            else
                break
            fi
        done
    fi

    log info "配置参数确认:"
    log info "  全局根目录: $ROOT_DIR (管理员可俯瞰全部，普通用户通过 Scope 隔离)"
    log info "  监听端口:   $PORT"
    log info "  默认管理员: admin"

    install_dependencies
    download_filebrowser
    init_filebrowser_config "$ROOT_DIR" "$PORT" "$ADMIN_PASS"
    configure_firewall "$PORT"
    register_service
    get_local_ip

    local s_mgr
    s_mgr="$(detect_service_manager)"

    echo ""
    echo -e "\033[32m========================================================\033[0m"
    echo -e "\033[32m          FileBrowser Web 文件管理器部署成功！          \033[0m"
    echo -e "\033[32m========================================================\033[0m"
    echo -e "Web 访问地址:  \033[36mhttp://${LOCAL_IP}:${PORT}\033[0m"
    echo -e "超级管理员:    \033[36madmin\033[0m"
    echo -e "管理员密码:    \033[36m${ADMIN_PASS}\033[0m"
    echo -e "全局数据根目录:\033[36m${ROOT_DIR}\033[0m"
    if [ "$s_mgr" = "systemd" ]; then
        echo -e "服务托管模式:  \033[36msystemd (systemctl status filebrowser)\033[0m"
    else
        echo -e "服务托管模式:  \033[36mSysVinit (service filebrowser status)\033[0m"
    fi
    echo "--------------------------------------------------------"
    echo "👥 添加隔离普通用户:"
    echo "    执行: sudo ./filebrowser_install.sh adduser <用户名> <密码> [隔离目录]"
    echo "    (支持与 Samba 隔离目录 /data/users/<用户名> 协同)"
    echo "========================================================"
    echo ""
}

# 卸载流程
function do_uninstall {
    echo ""
    echo "========================================================"
    echo "            FileBrowser 卸载向导                        "
    echo "========================================================"
    echo ""

    read -r -p "确定要彻底卸载 FileBrowser 吗？此操作将注销服务并清理配置 (y/N): " confirm_uninstall
    if [[ ! "$confirm_uninstall" =~ ^[Yy]$ ]]; then
        log info "用户取消卸载操作。"
        exit 0
    fi

    unregister_service

    log info "正在删除二进制文件与配置..."
    rm -f "$INSTALL_BIN"

    read -r -p "是否删除数据库与配置文件目录 (/etc/filebrowser)? [y/N]: " clean_conf
    if [[ "$clean_conf" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        rm -f "$LOG_PATH"
        log info "已清理 /etc/filebrowser 及运行日志。"
    else
        log info "已保留配置文件与数据库于 /etc/filebrowser。"
    fi

    log info "注意: 您的实际文件数据目录未被删除以防数据丢失。"
    log info "FileBrowser 卸载完成！"
}

# 主菜单入口
function main_menu {
    while true; do
        echo ""
        echo "========================================================"
        echo "       FileBrowser 一键管理脚本 (带多用户隔离)          "
        echo "========================================================"
        echo " 1. 安装并配置 FileBrowser (Install)"
        echo " 2. 单独注册系统服务并开启自启 (Service Register)"
        echo " 3. 注销系统服务 (Service Unregister)"
        echo " 4. 查看运行状态 (Status)"
        echo " 5. 启动服务 (Start)"
        echo " 6. 停止服务 (Stop)"
        echo " 7. 重启服务 (Restart)"
        echo " 8. 添加新用户 (指定独立隔离目录 Scope)"
        echo " 9. 查看所有用户列表 (List Users)"
        echo " 10. 删除用户 (Delete User)"
        echo " 11. 重置用户密码 (Set Password)"
        echo " 12. 修改监听端口 (Set Port)"
        echo " 13. 完全卸载 FileBrowser (Uninstall)"
        echo " 0. 退出 (Exit)"
        echo "========================================================"
        read -r -p "请输入选项 [0-13]: " choice

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
                do_setpasswd
                ;;
            12)
                do_setport
                ;;
            13)
                do_uninstall
                ;;
            0)
                echo "已退出。"
                exit 0
                ;;
            *)
                echo "无效输入，请输入 0-13。"
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
        do_adduser "$2" "$3" "$4"
        ;;
    lsusers|ls-users|users)
        do_lsusers
        ;;
    deluser|del-user)
        do_deluser "$2"
        ;;
    setpasswd|passwd)
        do_setpasswd "$2" "$3"
        ;;
    setport|port)
        do_setport "$2"
        ;;
    help|-h|--help)
        echo "用法:"
        echo "  sudo $0                                            # 交互式菜单"
        echo "  sudo $0 install [全局目录] [端口] [管理员密码]       # 完整安装与注册"
        echo "  sudo $0 adduser [用户名] [密码] [隔离目录]           # 添加隔离用户"
        echo "  sudo $0 lsusers                                    # 查看所有用户"
        echo "  sudo $0 deluser [用户名]                            # 删除用户"
        echo "  sudo $0 service register                           # 仅注册系统服务"
        echo "  sudo $0 service unregister                         # 注销系统服务"
        echo "  sudo $0 start|stop|restart|status                  # 服务启停状态"
        echo "  sudo $0 setpasswd [用户名] [新密码]                  # 重置密码"
        echo "  sudo $0 setport [新端口号]                          # 修改 Web 端口"
        echo "  sudo $0 uninstall                                  # 卸载 FileBrowser"
        ;;
    "")
        main_menu
        ;;
    *)
        log error "未知命令: $ACTION。使用 '$0 help' 查看帮助。"
        ;;
esac
