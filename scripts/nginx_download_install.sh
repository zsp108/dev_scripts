#!/bin/bash
#
# 安装并配置 Nginx 下载站点，自动生成下载目录 index.html
# 用法：sudo ./nginx_download_install.sh [download-root] [listen-port]
# 示例：
#   sudo ./nginx_download_install.sh
#   sudo ./nginx_download_install.sh /data/downloads
#   sudo ./nginx_download_install.sh --root /data/downloads --port 80

set -e
set -o pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/" && pwd -P)"
logfile="$SCRIPT_ROOT/init.log"

DOWNLOAD_ROOT="/data/downloads"
LISTEN_PORT="80"
SERVER_NAME="_"
ASSUME_YES="false"
DEPLOY_NGINX="true"
DEPLOY_FILEBROWSER="false"
DEPLOY_URL_DOWNLOADER="auto"
FILEBROWSER_PORT="8080"
FILEBROWSER_IMAGE="filebrowser/filebrowser:v2.32.0"
FILEBROWSER_NAME="filebrowser"
FILEBROWSER_CONFIG_DIR="/opt/filebrowser"
URL_DOWNLOADER_PORT="8081"
URL_DOWNLOADER_BIND="0.0.0.0"

show_help() {
    cat <<'EOF'
用法:
  sudo ./nginx_download_install.sh [download-root] [listen-port]
  sudo ./nginx_download_install.sh --root /data/downloads --port 80
  sudo ./nginx_download_install.sh --with-filebrowser
  sudo ./nginx_download_install.sh --only-filebrowser --root /data/downloads
  sudo ./nginx_download_install.sh --with-url-downloader
  sudo ./nginx_download_install.sh --only-url-downloader --root /data/downloads

参数:
  download-root  下载文件根目录，默认 /data/downloads
  listen-port    Nginx 监听端口，默认 80

选项:
  -r, --root              指定下载文件根目录
  -p, --port              指定 Nginx 监听端口
  -s, --server-name       指定 server_name，默认 _
  --with-filebrowser      部署 nginx 后同时部署 File Browser
  --only-nginx            只部署 nginx 下载页
  --only-filebrowser      只部署 File Browser，不安装或改动 nginx
  --skip-nginx            跳过 nginx 安装配置
  --skip-filebrowser      跳过 File Browser 部署
  --with-url-downloader   部署 URL 下载 Web 服务（默认随 nginx 下载页一起部署）
  --only-url-downloader   只部署 URL 下载 Web 服务
  --skip-url-downloader   跳过 URL 下载 Web 服务
  --filebrowser-port      指定 File Browser 监听端口，默认 8080
  --filebrowser-image     指定 File Browser 镜像，默认 filebrowser/filebrowser:v2.32.0
  --filebrowser-name      指定 File Browser 容器名，默认 filebrowser
  --filebrowser-config    指定 File Browser 配置目录，默认 /opt/filebrowser
  --url-downloader-port   指定 URL 下载服务端口，默认 8081
  --url-downloader-bind   指定 URL 下载服务监听地址，默认 0.0.0.0
  -y, --yes               覆盖 nginx.conf 或重建容器前不再二次确认
  -h, --help              显示帮助

说明:
  脚本会安装 nginx，配置下载根目录，生成 index.html，并通过 systemd.path
  监听下载根目录下新增、删除、重命名文件或目录后自动刷新 index.html。
  File Browser 使用 Docker 部署，文件根目录与 nginx 下载根目录保持一致。
  如果未安装 Docker，会提示并跳过 File Browser 部署。
  URL 下载服务提供刷新文件列表和 URL 下载能力，默认随 nginx 下载页一起部署。
EOF
}

function log {
    local msg
    local logtype
    logtype=$1
    msg=$2
    datetime=$(date +'%F %H:%M:%S')
    logformat="${datetime} ${FUNCNAME[@]/log/} [line:${BASH_LINENO[0]}] ${logtype}:${msg}"
    {
    case $logtype in
        debug)
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        info)
            echo -e "\033[32m ${datetime} [info] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        warn)
            echo -e "\033[33m ${datetime} [WARN] ${msg} \t \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1 ;;
        error)
            echo -e "\033[31m ${datetime} [ERROR] ${msg} \033[0m"
            echo "${logformat}" >> "$logfile" 2>&1
            exit 1 ;;
    esac
    }
}

parse_args() {
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help|help)
                show_help
                exit 0
                ;;
            -r|--root|--download-root)
                [ -n "${2:-}" ] || log error "$1 需要一个目录参数"
                DOWNLOAD_ROOT="$2"
                shift
                ;;
            -p|--port)
                [ -n "${2:-}" ] || log error "$1 需要一个端口参数"
                LISTEN_PORT="$2"
                shift
                ;;
            -s|--server-name)
                [ -n "${2:-}" ] || log error "$1 需要一个 server_name 参数"
                SERVER_NAME="$2"
                shift
                ;;
            --with-filebrowser|--filebrowser)
                DEPLOY_FILEBROWSER="true"
                ;;
            --with-url-downloader|--url-downloader)
                DEPLOY_URL_DOWNLOADER="true"
                ;;
            --only-nginx)
                DEPLOY_NGINX="true"
                DEPLOY_FILEBROWSER="false"
                DEPLOY_URL_DOWNLOADER="false"
                ;;
            --only-filebrowser)
                DEPLOY_NGINX="false"
                DEPLOY_FILEBROWSER="true"
                DEPLOY_URL_DOWNLOADER="false"
                ;;
            --only-url-downloader)
                DEPLOY_NGINX="false"
                DEPLOY_FILEBROWSER="false"
                DEPLOY_URL_DOWNLOADER="true"
                ;;
            --skip-nginx)
                DEPLOY_NGINX="false"
                ;;
            --skip-filebrowser)
                DEPLOY_FILEBROWSER="false"
                ;;
            --skip-url-downloader)
                DEPLOY_URL_DOWNLOADER="false"
                ;;
            --filebrowser-port)
                [ -n "${2:-}" ] || log error "$1 需要一个端口参数"
                FILEBROWSER_PORT="$2"
                shift
                ;;
            --filebrowser-image)
                [ -n "${2:-}" ] || log error "$1 需要一个镜像参数"
                FILEBROWSER_IMAGE="$2"
                shift
                ;;
            --filebrowser-name)
                [ -n "${2:-}" ] || log error "$1 需要一个容器名参数"
                FILEBROWSER_NAME="$2"
                shift
                ;;
            --filebrowser-config)
                [ -n "${2:-}" ] || log error "$1 需要一个目录参数"
                FILEBROWSER_CONFIG_DIR="$2"
                shift
                ;;
            --url-downloader-port)
                [ -n "${2:-}" ] || log error "$1 需要一个端口参数"
                URL_DOWNLOADER_PORT="$2"
                shift
                ;;
            --url-downloader-bind)
                [ -n "${2:-}" ] || log error "$1 需要一个监听地址参数"
                URL_DOWNLOADER_BIND="$2"
                shift
                ;;
            -y|--yes)
                ASSUME_YES="true"
                ;;
            -*)
                log error "未知参数: $1"
                ;;
            *)
                if [ "$DOWNLOAD_ROOT" = "/data/downloads" ]; then
                    DOWNLOAD_ROOT="$1"
                elif [ "$LISTEN_PORT" = "80" ]; then
                    LISTEN_PORT="$1"
                else
                    log error "无法识别参数: $1"
                fi
                ;;
        esac
        shift
    done

    case "$DOWNLOAD_ROOT" in
        /*) ;;
        *) log error "下载根目录必须是绝对路径: $DOWNLOAD_ROOT" ;;
    esac

    if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -lt 1 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
        log error "监听端口不合法: $LISTEN_PORT"
    fi

    if ! [[ "$FILEBROWSER_PORT" =~ ^[0-9]+$ ]] || [ "$FILEBROWSER_PORT" -lt 1 ] || [ "$FILEBROWSER_PORT" -gt 65535 ]; then
        log error "File Browser 监听端口不合法: $FILEBROWSER_PORT"
    fi

    if ! [[ "$URL_DOWNLOADER_PORT" =~ ^[0-9]+$ ]] || [ "$URL_DOWNLOADER_PORT" -lt 1 ] || [ "$URL_DOWNLOADER_PORT" -gt 65535 ]; then
        log error "URL 下载服务监听端口不合法: $URL_DOWNLOADER_PORT"
    fi

    case "$FILEBROWSER_CONFIG_DIR" in
        /*) ;;
        *) log error "File Browser 配置目录必须是绝对路径: $FILEBROWSER_CONFIG_DIR" ;;
    esac
}

parse_args "$@"

if [ "$DEPLOY_URL_DOWNLOADER" = "auto" ]; then
    if [ "$DEPLOY_NGINX" = "true" ]; then
        DEPLOY_URL_DOWNLOADER="true"
    else
        DEPLOY_URL_DOWNLOADER="false"
    fi
fi

if [ "$EUID" -ne 0 ]; then
    if ! sudo -n true 2>/dev/null; then
        log error "当前用户没有sudo权限，请以root用户或使用sudo命令执行此脚本"
    else
        log info "检测到非root用户但有sudo权限，继续执行..."
    fi
else
    log info "检测到root用户执行，继续执行..."
fi

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    OS_NAME=$PRETTY_NAME
else
    log error "无法确定操作系统类型。"
fi

log info "检测到操作系统: $OS_NAME ($OS)"
log info "下载根目录: $DOWNLOAD_ROOT"
log info "监听端口: $LISTEN_PORT"
log info "server_name: $SERVER_NAME"
log info "部署 nginx: $DEPLOY_NGINX"
log info "部署 File Browser: $DEPLOY_FILEBROWSER"
log info "部署 URL 下载服务: $DEPLOY_URL_DOWNLOADER"
if [ "$DEPLOY_FILEBROWSER" = "true" ]; then
    log info "File Browser 端口: $FILEBROWSER_PORT"
    log info "File Browser 镜像: $FILEBROWSER_IMAGE"
    log info "File Browser 容器名: $FILEBROWSER_NAME"
    log info "File Browser 配置目录: $FILEBROWSER_CONFIG_DIR"
fi
if [ "$DEPLOY_URL_DOWNLOADER" = "true" ]; then
    log info "URL 下载服务监听: $URL_DOWNLOADER_BIND:$URL_DOWNLOADER_PORT"
fi

install_nginx_debian() {
    log info "开始安装 nginx (Debian/Ubuntu系列)"
    apt-get update || log error "无法更新包索引"
    apt-get install -y nginx || log error "无法安装 nginx"
}

install_nginx_rhel() {
    log info "开始安装 nginx (RHEL/CentOS系列)"
    if command -v dnf >/dev/null 2>&1; then
        dnf install -y nginx || log error "无法安装 nginx"
    else
        yum install -y epel-release || true
        yum install -y nginx || log error "无法安装 nginx"
    fi
}

install_nginx() {
    if command -v nginx >/dev/null 2>&1; then
        log info "nginx 已安装: $(nginx -v 2>&1)"
        return
    fi

    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            install_nginx_debian
            ;;
        centos|rhel|rocky|almalinux|ol|fedora|anolis|openEuler|openeuler|kylin)
            install_nginx_rhel
            ;;
        *)
            if command -v apt-get >/dev/null 2>&1; then
                install_nginx_debian
            elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
                install_nginx_rhel
            else
                log error "不支持的系统: $OS，请手动安装 nginx 后重试"
            fi
            ;;
    esac
}

detect_nginx_user() {
    if id nginx >/dev/null 2>&1; then
        NGINX_USER="nginx"
    elif id www-data >/dev/null 2>&1; then
        NGINX_USER="www-data"
    else
        NGINX_USER="nginx"
    fi
    log info "nginx 运行用户: $NGINX_USER"
}

ensure_download_root() {
    if [ ! -d "$DOWNLOAD_ROOT" ]; then
        log info "创建下载根目录: $DOWNLOAD_ROOT"
        mkdir -p "$DOWNLOAD_ROOT" || log error "无法创建目录: $DOWNLOAD_ROOT"
    fi

    chmod 755 "$DOWNLOAD_ROOT" || log error "无法设置目录权限: $DOWNLOAD_ROOT"
}

configure_selinux() {
    if ! command -v getenforce >/dev/null 2>&1; then
        return
    fi

    if [ "$(getenforce 2>/dev/null || echo Disabled)" != "Enforcing" ]; then
        return
    fi

    log info "检测到 SELinux Enforcing，配置 nginx 可读目录上下文"
    if command -v semanage >/dev/null 2>&1; then
        semanage fcontext -a -t httpd_sys_content_t "${DOWNLOAD_ROOT}(/.*)?" 2>/dev/null || \
            semanage fcontext -m -t httpd_sys_content_t "${DOWNLOAD_ROOT}(/.*)?" || true
        restorecon -RF "$DOWNLOAD_ROOT" || log warn "restorecon 失败，请手动检查 SELinux 上下文"
    elif command -v chcon >/dev/null 2>&1; then
        chcon -R -t httpd_sys_content_t "$DOWNLOAD_ROOT" || log warn "chcon 失败，请手动检查 SELinux 上下文"
    else
        log warn "未找到 semanage/chcon，请手动允许 nginx 读取 $DOWNLOAD_ROOT"
    fi
}

write_nginx_config() {
    local conf="/etc/nginx/nginx.conf"
    local backup="${conf}.bak.$(date +%Y%m%d%H%M%S)"

    if [ -f "$conf" ]; then
        if [ "$ASSUME_YES" != "true" ]; then
            log warn "即将备份并覆盖 $conf"
            read -p "确认继续吗？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log info "用户取消配置 nginx"
                exit 0
            fi
        fi
        cp "$conf" "$backup" || log error "无法备份 $conf"
        log info "已备份 nginx 配置: $backup"
    fi

    cat > "$conf" <<EOF
# For more information on configuration, see:
#   * Official English Documentation: http://nginx.org/en/docs/

user $NGINX_USER;
worker_processes auto;
error_log /var/log/nginx/error.log;
pid /run/nginx.pid;

include /usr/share/nginx/modules/*.conf;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 1024;
}

http {
    log_format  main  '\$remote_addr - \$remote_user [\$time_local] "\$request" '
                      '\$status \$body_bytes_sent "\$http_referer" '
                      '"\$http_user_agent" "\$http_x_forwarded_for"';

    access_log  /var/log/nginx/access.log  main;

    sendfile            on;
    tcp_nopush          on;
    tcp_nodelay         on;
    keepalive_timeout   65;
    types_hash_max_size 4096;

    include             /etc/nginx/mime.types;
    default_type        application/octet-stream;

    include /etc/nginx/conf.d/*.conf;

    server {
        listen       $LISTEN_PORT;
        listen       [::]:$LISTEN_PORT;
        server_name  $SERVER_NAME;
        charset utf-8;
        root "$DOWNLOAD_ROOT";
        index index.html;
        autoindex on;
        autoindex_exact_size off;
        autoindex_localtime on;

        include /etc/nginx/default.d/*.conf;

        location / {
            try_files \$uri \$uri/ =404;
        }

        location /url-download {
            proxy_pass http://127.0.0.1:$URL_DOWNLOADER_PORT;
            proxy_http_version 1.1;
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_connect_timeout 10s;
            proxy_send_timeout 1h;
            proxy_read_timeout 1h;
        }

        error_page 404 /404.html;
        location = /404.html {
            internal;
        }

        error_page 500 502 503 504 /50x.html;
        location = /50x.html {
            internal;
        }
    }
}
EOF

    nginx -t || log error "nginx 配置检查失败"
}

write_index_generator() {
    local generator="/usr/local/bin/generate_download_index.sh"
    local env_file="/etc/default/download-index"

    mkdir -p /etc/default
    cat > "$env_file" <<EOF
DOWNLOAD_ROOT="$DOWNLOAD_ROOT"
URL_DOWNLOADER_ENABLED="$DEPLOY_URL_DOWNLOADER"
EOF

    cat > "$generator" <<'EOF'
#!/bin/bash
set -e
set -o pipefail

DOWNLOAD_ROOT="${1:-${DOWNLOAD_ROOT:-/data/downloads}}"
URL_DOWNLOADER_ENABLED="${URL_DOWNLOADER_ENABLED:-true}"
INDEX_FILE="$DOWNLOAD_ROOT/index.html"

if [ ! -d "$DOWNLOAD_ROOT" ]; then
    echo "下载根目录不存在: $DOWNLOAD_ROOT" >&2
    exit 1
fi

tmp=$(mktemp /tmp/download-index.XXXXXX)
cleanup() {
    rm -f "$tmp"
}
trap cleanup EXIT

if command -v python3 >/dev/null 2>&1; then
    python3 - "$DOWNLOAD_ROOT" "$tmp" <<'PY'
import datetime
import html
import json
import os
import sys
from urllib.parse import quote

root, output = sys.argv[1], sys.argv[2]
url_downloader_enabled = os.environ.get("URL_DOWNLOADER_ENABLED", "true").lower() == "true"
exclude = {"index.html", "generate_html.sh"}

entries = []
for name in os.listdir(root):
    if name in exclude or name.startswith("."):
        continue
    path = os.path.join(root, name)
    entries.append((not os.path.isdir(path), name, path))

entries.sort(key=lambda item: (item[0], item[1].lower()))

directories = []
for dirpath, dirnames, _ in os.walk(root):
    dirnames[:] = sorted(name for name in dirnames if not name.startswith("."))
    rel = os.path.relpath(dirpath, root)
    if rel == ".":
        continue
    directories.append(rel.replace(os.sep, "/"))

def human_size(size):
    units = ["B", "KB", "MB", "GB", "TB", "PB"]
    value = float(size)
    index = 0
    while value >= 1024 and index < len(units) - 1:
        value /= 1024
        index += 1
    if index == 0:
        return f"{int(value)} B"
    return f"{value:.1f} {units[index]}"

with open(output, "w", encoding="utf-8") as f:
    f.write("<!DOCTYPE html>\n")
    f.write('<html lang="zh-CN">\n<head>\n')
    f.write('<meta charset="UTF-8">\n')
    f.write('<meta name="viewport" content="width=device-width, initial-scale=1.0">\n')
    f.write("<title>Downloads</title>\n")
    f.write("<style>\n")
    f.write("body{font-family:Arial,'Microsoft YaHei',sans-serif;margin:32px;color:#1f2937;background:#f8fafc;}\n")
    f.write("h1{font-size:28px;margin:0 0 8px;} .meta{color:#64748b;margin-bottom:24px;}\n")
    f.write(".downloader{background:#fff;border:1px solid #e5e7eb;margin:0 0 24px;padding:16px;}\n")
    f.write(".downloader h2{font-size:18px;margin:0;}\n")
    f.write(".downloader-header{display:flex;align-items:center;justify-content:space-between;gap:12px;cursor:pointer;}\n")
    f.write(".downloader-body{margin-top:12px;}.downloader-body.hidden{display:none;}\n")
    f.write(".downloader label{display:block;font-weight:700;margin:10px 0 6px;}\n")
    f.write(".downloader input{box-sizing:border-box;width:100%;padding:9px;border:1px solid #cbd5e1;font-size:14px;}\n")
    f.write(".downloader button{margin-top:12px;padding:9px 14px;border:0;background:#2563eb;color:#fff;font-weight:700;cursor:pointer;}.downloader-header button{margin-top:0;}\n")
    f.write(".dir-picker{position:relative;}.dir-button{box-sizing:border-box;width:100%;margin:0!important;padding:9px!important;border:1px solid #cbd5e1!important;background:#fff!important;color:#1f2937!important;text-align:left!important;font-weight:400!important;}.dir-menu{display:none;position:absolute;z-index:20;top:40px;left:0;max-width:100%;background:#fff;border:1px solid #cbd5e1;box-shadow:0 8px 18px rgba(15,23,42,.12);}.dir-menu.open{display:flex;}.dir-level{list-style:none;margin:0;padding:6px 0;min-width:220px;max-height:280px;overflow:auto;border-right:1px solid #e5e7eb;}.dir-level:last-child{border-right:0;}.dir-item{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:8px 12px;cursor:pointer;white-space:nowrap;}.dir-item:hover,.dir-item.active{background:#eff6ff;color:#1d4ed8;}.dir-item span:last-child{color:#64748b;}\n")
    f.write(".actions{display:flex;gap:10px;align-items:center;margin:0 0 16px;}.actions button{padding:8px 12px;border:0;background:#475569;color:#fff;font-weight:700;cursor:pointer;}.actions button:disabled{opacity:.6;cursor:not-allowed;}\n")
    f.write(".download-status{border:1px solid #e5e7eb;background:#f8fafc;margin-top:12px;padding:10px;min-height:46px;}\n")
    f.write(".progress{height:12px;background:#e5e7eb;margin-top:8px;overflow:hidden;}\n")
    f.write(".progress-bar{height:100%;width:0;background:#2563eb;transition:width .2s;}\n")
    f.write(".download-status.ok{border-color:#86efac;background:#f0fdf4;}.download-status.err{border-color:#fca5a5;background:#fef2f2;}\n")
    f.write("table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e5e7eb;}\n")
    f.write("th,td{text-align:left;padding:10px 12px;border-bottom:1px solid #e5e7eb;} th{background:#f1f5f9;}\n")
    f.write("a{color:#2563eb;text-decoration:none;} a:hover{text-decoration:underline;} .dir{font-weight:700;}\n")
    f.write("</style>\n</head>\n<body>\n")
    f.write("<h1>Downloads</h1>\n")
    f.write(f'<div class="meta">Generated at {html.escape(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))}</div>\n')
    if url_downloader_enabled:
        f.write('<div class="actions"><button id="refresh-list" type="button">刷新文件列表</button><span id="refresh-status" class="meta"></span></div>\n')
        f.write('<section class="downloader">\n')
        f.write('<div class="downloader-header"><h2>URL 下载</h2><button id="toggle-url-download" type="button" aria-expanded="false">展开</button></div>\n')
        f.write('<div id="url-download-body" class="downloader-body hidden">\n')
        f.write('<form id="url-download-form">\n')
        f.write('<label for="download-url">下载链接</label>\n')
        f.write('<input id="download-url" name="url" type="url" placeholder="https://example.com/file.tar.gz" required>\n')
        f.write('<label for="download-filename">保存文件名（可选）</label>\n')
        f.write('<input id="download-filename" name="filename" type="text" placeholder="留空则自动使用 URL 文件名">\n')
        f.write('<label for="download-dir">保存目录（相对下载根目录，可选）</label>\n')
        f.write('<input id="download-dir" name="directory" type="hidden" value="">\n')
        f.write('<div id="download-dir-picker" class="dir-picker">\n')
        f.write('<button id="download-dir-button" class="dir-button" type="button">保存目录: /</button>\n')
        f.write('<div id="download-dir-menu" class="dir-menu"></div>\n')
        f.write("</div>\n")
        f.write("<button type=\"submit\">开始下载</button>\n")
        f.write("</form>\n")
        f.write('<div id="download-status" class="download-status">等待提交下载任务。</div>\n')
        f.write('<div class="progress"><div id="download-progress" class="progress-bar"></div></div>\n')
        f.write("</div>\n")
        f.write("</section>\n")
    f.write("<table>\n<thead><tr><th>Name</th><th>Type</th><th>Size</th><th>Modified</th></tr></thead>\n<tbody>\n")
    for is_file_sort, name, path in entries:
        is_dir = os.path.isdir(path)
        display = html.escape(name + ("/" if is_dir else ""))
        href = quote(name + ("/" if is_dir else ""))
        stat = os.stat(path)
        size = "-" if is_dir else human_size(stat.st_size)
        mtime = datetime.datetime.fromtimestamp(stat.st_mtime).strftime("%Y-%m-%d %H:%M:%S")
        css = ' class="dir"' if is_dir else ""
        kind = "Directory" if is_dir else "File"
        f.write(f'<tr><td><a{css} href="{href}">{display}</a></td><td>{kind}</td><td>{size}</td><td>{mtime}</td></tr>\n')
    f.write("</tbody>\n</table>\n")
    if url_downloader_enabled:
        f.write("<script>\n")
        f.write("const form=document.getElementById('url-download-form');const statusBox=document.getElementById('download-status');const bar=document.getElementById('download-progress');const refreshBtn=document.getElementById('refresh-list');const refreshStatus=document.getElementById('refresh-status');const toggleBtn=document.getElementById('toggle-url-download');const downloadBody=document.getElementById('url-download-body');const downloadHeader=document.querySelector('.downloader-header');const downloaderSection=document.querySelector('.downloader');\n")
        f.write(f"const directoryList={json.dumps(directories, ensure_ascii=False)};const dirInput=document.getElementById('download-dir');const dirPicker=document.getElementById('download-dir-picker');const dirButton=document.getElementById('download-dir-button');const dirMenu=document.getElementById('download-dir-menu');\n")
        f.write("function fmt(n){if(!n&&n!==0)return '-';const u=['B','KB','MB','GB','TB'];let i=0;while(n>=1024&&i<u.length-1){n/=1024;i++;}return (i?n.toFixed(1):n.toFixed(0))+' '+u[i];}\n")
        f.write("function buildDirTree(paths){const root=[];for(const path of paths){let level=root;let current='';for(const name of path.split('/').filter(Boolean)){current=current?current+'/'+name:name;let node=level.find(item=>item.name===name);if(!node){node={name,path:current,children:[]};level.push(node);}level=node.children;}}return root;}\n")
        f.write("const dirTree=buildDirTree(directoryList);function setDirectory(path){dirInput.value=path;dirButton.textContent='保存目录: '+(path?path+'/':'/');dirMenu.classList.remove('open');}\n")
        f.write("function renderDirLevel(nodes,depth){while(dirMenu.children.length>depth){dirMenu.removeChild(dirMenu.lastChild);}if(!nodes.length)return;const list=document.createElement('ul');list.className='dir-level';if(depth===0){const rootItem=document.createElement('li');rootItem.className='dir-item';rootItem.innerHTML='<strong>/</strong>';rootItem.addEventListener('click',()=>setDirectory(''));list.appendChild(rootItem);}for(const node of nodes){const item=document.createElement('li');item.className='dir-item';item.innerHTML='<strong>'+node.name+'/</strong><span>'+(node.children.length?'›':'')+'</span>';item.addEventListener('mouseenter',()=>{for(const el of list.children){el.classList.remove('active');}item.classList.add('active');renderDirLevel(node.children,depth+1);});item.addEventListener('click',event=>{event.stopPropagation();setDirectory(node.path);});list.appendChild(item);}dirMenu.appendChild(list);}\n")
        f.write("dirButton.addEventListener('click',()=>{if(dirMenu.classList.toggle('open')){dirMenu.innerHTML='';renderDirLevel(dirTree,0);}});document.addEventListener('click',event=>{if(!dirPicker.contains(event.target)){dirMenu.classList.remove('open');}});\n")
        f.write("async function jsonFetch(url,opts){const r=await fetch(url,opts);const ct=r.headers.get('content-type')||'';if(!ct.includes('application/json')){throw new Error('服务未返回 JSON，请确认 url-downloader.service 已启动且 nginx 反向代理已生效');}const j=await r.json();return {r,j};}\n")
        f.write("function show(s,cls){statusBox.className='download-status '+(cls||'');statusBox.textContent=s;}\n")
        f.write("function setDownloadExpanded(expanded){downloadBody.classList.toggle('hidden',!expanded);toggleBtn.textContent=expanded?'收起':'展开';toggleBtn.setAttribute('aria-expanded',String(expanded));try{localStorage.setItem('urlDownloadExpanded',expanded?'true':'false');}catch(err){}}\n")
        f.write("function toggleDownload(){setDownloadExpanded(downloadBody.classList.contains('hidden'));}\n")
        f.write("downloadHeader.addEventListener('click',toggleDownload);toggleBtn.addEventListener('click',event=>{event.stopPropagation();toggleDownload();});downloaderSection.addEventListener('click',event=>{if(event.target===downloaderSection&&downloadBody.classList.contains('hidden'))setDownloadExpanded(true);});try{if(localStorage.getItem('urlDownloadExpanded')==='true')setDownloadExpanded(true);}catch(err){}\n")
        f.write("async function poll(id){const {r,j}=await jsonFetch('/url-download/status?id='+encodeURIComponent(id));const pct=j.total?Math.floor(j.downloaded*100/j.total):0;bar.style.width=(j.total?pct:0)+'%';show(j.message+' | '+fmt(j.downloaded)+(j.total?' / '+fmt(j.total)+' ('+pct+'%)':''),j.status==='done'?'ok':(j.status==='error'?'err':''));if(j.status==='done'){bar.style.width='100%';setDownloadExpanded(true);setTimeout(()=>location.reload(),1200);return;}if(j.status==='error')return;setTimeout(()=>poll(id),1000);}\n")
        f.write("form.addEventListener('submit',async e=>{e.preventDefault();bar.style.width='0';show('正在创建下载任务...');try{const body=new URLSearchParams(new FormData(form));const {r,j}=await jsonFetch('/url-download',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'},body});if(!r.ok){show(j.error||'创建下载任务失败','err');return;}show('下载任务已开始');poll(j.id);}catch(err){show('创建下载任务失败: '+err.message,'err');}});\n")
        f.write("refreshBtn.addEventListener('click',async()=>{refreshBtn.disabled=true;refreshStatus.textContent='正在刷新...';try{const {r,j}=await jsonFetch('/url-download/refresh',{method:'POST'});if(!r.ok){refreshStatus.textContent=j.error||'刷新失败';refreshBtn.disabled=false;return;}refreshStatus.textContent='刷新完成，正在重新加载页面...';setTimeout(()=>location.reload(),500);}catch(err){refreshStatus.textContent='刷新失败: '+err.message;refreshBtn.disabled=false;}});\n")
        f.write("</script>\n")
    f.write("</body>\n</html>\n")
PY
else
    {
        echo '<!DOCTYPE html>'
        echo '<html lang="zh-CN">'
        echo '<head><meta charset="UTF-8"><title>Downloads</title></head>'
        echo '<body><h1>Downloads</h1>'
        if [ "$URL_DOWNLOADER_ENABLED" = "true" ]; then
            echo '<p><form method="POST" action="/url-download/refresh"><button type="submit">刷新文件列表</button></form></p>'
            echo '<section>'
            echo '<details><summary><strong>URL 下载</strong></summary>'
            echo '<form method="POST" action="/url-download">'
            echo '<p><input name="url" type="url" placeholder="https://example.com/file.tar.gz" required style="width:80%"></p>'
            echo '<p><input name="filename" type="text" placeholder="保存文件名（可选）" style="width:80%"></p>'
            echo '<p><input name="directory" type="text" placeholder="保存目录，例如 iso/ubuntu（可选）" style="width:80%"></p>'
            echo '<button type="submit">开始下载</button>'
            echo '</form>'
            echo '<p>当前系统没有 python3，首页不会显示异步下载进度。</p>'
            echo '</details>'
            echo '</section>'
        fi
        echo '<ul>'
        cd "$DOWNLOAD_ROOT"
        for entry in *; do
            [ "$entry" = "*" ] && continue
            [ "$entry" = "index.html" ] && continue
            [ "$entry" = "generate_html.sh" ] && continue
            case "$entry" in .*) continue ;; esac
            escaped=$(printf '%s' "$entry" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g; s/"/\&quot;/g')
            if [ -d "$entry" ]; then
                echo "<li><a href=\"$escaped/\"><strong>$escaped/</strong></a></li>"
            elif [ -f "$entry" ]; then
                echo "<li><a href=\"$escaped\">$escaped</a></li>"
            fi
        done
        echo '</ul></body></html>'
    } > "$tmp"
fi

if [ ! -f "$INDEX_FILE" ] || ! cmp -s "$tmp" "$INDEX_FILE"; then
    mv "$tmp" "$INDEX_FILE"
    chmod 644 "$INDEX_FILE"
    trap - EXIT
    echo "index.html generated: $INDEX_FILE"
else
    chmod 644 "$INDEX_FILE"
    echo "index.html unchanged: $INDEX_FILE"
fi
EOF

    chmod +x "$generator" || log error "无法设置生成脚本执行权限"
    ln -sf "$generator" "$DOWNLOAD_ROOT/generate_html.sh"
    log info "已安装 index.html 生成脚本: $generator"
}

write_systemd_units() {
    if ! command -v systemctl >/dev/null 2>&1; then
        log warn "未检测到 systemctl，跳过自动刷新服务配置"
        return
    fi

    cat > /etc/systemd/system/download-index.service <<'EOF'
[Unit]
Description=Generate nginx downloads index.html

[Service]
Type=oneshot
EnvironmentFile=-/etc/default/download-index
ExecStart=/usr/local/bin/generate_download_index.sh
EOF

    cat > /etc/systemd/system/download-index.path <<EOF
[Unit]
Description=Watch downloads root and refresh index.html

[Path]
PathChanged=$DOWNLOAD_ROOT
PathModified=$DOWNLOAD_ROOT
Unit=download-index.service

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload || log error "systemd daemon-reload 失败"
    systemctl enable --now download-index.path || log error "启动 download-index.path 失败"
    systemctl start download-index.service || log error "首次生成 index.html 失败"
    log info "已启用自动刷新: download-index.path"
}

start_nginx() {
    systemctl enable nginx || log warn "无法设置 nginx 开机启动"
    systemctl restart nginx || log error "无法启动 nginx"
    log info "nginx 已启动"
}

ensure_download_root

deploy_nginx_download_site() {
    install_nginx
    detect_nginx_user
    configure_selinux
    write_nginx_config
    write_index_generator
    write_systemd_units
    start_nginx
}

ensure_python3() {
    if command -v python3 >/dev/null 2>&1; then
        return
    fi

    log warn "python3 未安装，开始安装 python3"
    case "$OS" in
        ubuntu|debian|linuxmint|pop)
            apt-get update || log error "无法更新包索引"
            apt-get install -y python3 || log error "无法安装 python3"
            ;;
        centos|rhel|rocky|almalinux|ol|fedora|anolis|openEuler|openeuler|kylin)
            if command -v dnf >/dev/null 2>&1; then
                dnf install -y python3 || log error "无法安装 python3"
            else
                yum install -y python3 || log error "无法安装 python3"
            fi
            ;;
        *)
            log error "不支持自动安装 python3 的系统: $OS"
            ;;
    esac
}

deploy_filebrowser() {
    if ! command -v docker >/dev/null 2>&1; then
        log warn "未检测到 Docker，跳过 File Browser 部署"
        log warn "可先安装 Docker 后重新执行: sudo ./nginx_download_install.sh --only-filebrowser --root $DOWNLOAD_ROOT"
        return
    fi

    if ! docker info >/dev/null 2>&1; then
        log warn "Docker 服务不可用，跳过 File Browser 部署"
        log warn "请确认 Docker 已启动后重新执行: sudo ./nginx_download_install.sh --only-filebrowser --root $DOWNLOAD_ROOT"
        return
    fi

    log info "开始部署 File Browser"
    mkdir -p "$FILEBROWSER_CONFIG_DIR/config" "$FILEBROWSER_CONFIG_DIR/database" || \
        log error "无法创建 File Browser 配置目录: $FILEBROWSER_CONFIG_DIR"

    if ! docker image inspect "$FILEBROWSER_IMAGE" >/dev/null 2>&1; then
        log info "本地未找到镜像，开始拉取: $FILEBROWSER_IMAGE"
        if ! docker pull "$FILEBROWSER_IMAGE"; then
            log warn "File Browser 镜像拉取失败，跳过 File Browser 部署"
            log warn "可检查网络或提前手动导入镜像后重新执行: sudo ./nginx_download_install.sh --only-filebrowser --root $DOWNLOAD_ROOT"
            return
        fi
    fi

    if docker ps -a --format '{{.Names}}' | grep -Fxq "$FILEBROWSER_NAME"; then
        if [ "$ASSUME_YES" != "true" ]; then
            log warn "容器 $FILEBROWSER_NAME 已存在，即将删除并重新创建"
            read -p "确认继续吗？(y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log info "用户取消 File Browser 部署"
                return
            fi
        fi

        if ! docker rm -f "$FILEBROWSER_NAME"; then
            log warn "无法删除已有容器，跳过 File Browser 部署: $FILEBROWSER_NAME"
            return
        fi
    fi

    if ! docker run -d \
        --name "$FILEBROWSER_NAME" \
        --restart unless-stopped \
        -p "$FILEBROWSER_PORT:80" \
        -v "$DOWNLOAD_ROOT:/srv" \
        -v "$FILEBROWSER_CONFIG_DIR/config:/config" \
        -v "$FILEBROWSER_CONFIG_DIR/database:/database" \
        "$FILEBROWSER_IMAGE" \
        --address 0.0.0.0 \
        --port 80 \
        --root /srv \
        --database /database/filebrowser.db \
        --config /config/settings.json; then
        log warn "File Browser 容器启动失败，已跳过"
        return
    fi

    log info "File Browser 部署完成: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$FILEBROWSER_PORT/"
    log warn "File Browser 默认账号通常为 admin/admin，请首次登录后立即修改密码"
}

deploy_url_downloader() {
    if ! command -v systemctl >/dev/null 2>&1; then
        log warn "未检测到 systemctl，跳过 URL 下载服务部署"
        return
    fi

    ensure_python3

    local app="/usr/local/bin/url_downloader.py"
    local env_file="/etc/default/url-downloader"

    mkdir -p /etc/default
    cat > "$env_file" <<EOF
DOWNLOAD_ROOT="$DOWNLOAD_ROOT"
URL_DOWNLOADER_BIND="$URL_DOWNLOADER_BIND"
URL_DOWNLOADER_PORT="$URL_DOWNLOADER_PORT"
EOF

    cat > "$app" <<'PY'
#!/usr/bin/env python3
import datetime
import html
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.request
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

DOWNLOAD_ROOT = os.environ.get("DOWNLOAD_ROOT", "/data/downloads")
BIND = os.environ.get("URL_DOWNLOADER_BIND", "0.0.0.0")
PORT = int(os.environ.get("URL_DOWNLOADER_PORT", "8081"))
MAX_FORM_BYTES = 64 * 1024
JOBS = {}
JOBS_LOCK = threading.Lock()


def set_job(job_id, **kwargs):
    with JOBS_LOCK:
        job = JOBS.setdefault(job_id, {})
        job.update(kwargs)
        job["updated_at"] = time.time()
        return dict(job)


def safe_filename(url, requested):
    name = requested.strip()
    if not name:
        parsed = urllib.parse.urlparse(url)
        name = urllib.parse.unquote(os.path.basename(parsed.path.rstrip("/")))
    if not name:
        name = "download-" + datetime.datetime.now().strftime("%Y%m%d%H%M%S")
    name = os.path.basename(urllib.parse.unquote(name))
    name = name.replace("\x00", "").strip()
    if not name or name in {".", ".."}:
        raise ValueError("文件名不合法")
    return name


def safe_directory(requested):
    directory = requested.strip().strip("/")
    if not directory:
        return DOWNLOAD_ROOT
    if "\x00" in directory:
        raise ValueError("保存目录不合法")
    parts = [part for part in directory.split("/") if part not in {"", "."}]
    if any(part == ".." for part in parts):
        raise ValueError("保存目录不能包含 ..")
    target = os.path.realpath(os.path.join(DOWNLOAD_ROOT, *parts))
    root = os.path.realpath(DOWNLOAD_ROOT)
    if target != root and not target.startswith(root + os.sep):
        raise ValueError("保存目录超出下载根目录")
    return target


def unique_path(root, name):
    base, ext = os.path.splitext(name)
    candidate = os.path.join(root, name)
    index = 1
    while os.path.exists(candidate):
        candidate = os.path.join(root, f"{base}.{index}{ext}")
        index += 1
    return candidate


def download(job_id, url, filename, directory):
    parsed = urllib.parse.urlparse(url)
    if parsed.scheme not in {"http", "https"}:
        raise ValueError("只支持 http/https 链接")
    if not parsed.netloc:
        raise ValueError("下载链接不合法")

    target_dir = safe_directory(directory)
    os.makedirs(target_dir, exist_ok=True)
    name = safe_filename(url, filename)
    dest = unique_path(target_dir, name)
    tmp_fd, tmp_path = tempfile.mkstemp(prefix=".url-download-", dir=target_dir)
    os.close(tmp_fd)

    req = urllib.request.Request(url, headers={"User-Agent": "dev-scripts-url-downloader/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=30) as response, open(tmp_path, "wb") as output:
            total = int(response.headers.get("Content-Length") or 0)
            downloaded = 0
            set_job(job_id, status="running", total=total, downloaded=0, message="正在下载")
            while True:
                chunk = response.read(1024 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                downloaded += len(chunk)
                set_job(job_id, downloaded=downloaded, total=total, message="正在下载")
        os.chmod(tmp_path, 0o644)
        os.replace(tmp_path, dest)
    except Exception:
        try:
            os.remove(tmp_path)
        except OSError:
            pass
        raise
    saved = os.path.relpath(dest, DOWNLOAD_ROOT)
    set_job(job_id, status="done", downloaded=os.path.getsize(dest), message=f"下载完成: {saved}", file=saved)


def run_download(job_id, url, filename, directory):
    try:
        download(job_id, url, filename, directory)
    except Exception as exc:
        set_job(job_id, status="error", message=f"下载失败: {exc}")


def refresh_index():
    generator = "/usr/local/bin/generate_download_index.sh"
    if not os.path.exists(generator):
        raise RuntimeError(f"刷新脚本不存在: {generator}")
    result = subprocess.run([generator], capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        message = (result.stderr or result.stdout or "刷新失败").strip()
        raise RuntimeError(message)
    return (result.stdout or "index.html refreshed").strip()


def list_directories():
    directories = []
    for dirpath, dirnames, _ in os.walk(DOWNLOAD_ROOT):
        dirnames[:] = sorted(name for name in dirnames if not name.startswith("."))
        rel = os.path.relpath(dirpath, DOWNLOAD_ROOT)
        if rel == ".":
            continue
        directories.append(rel.replace(os.sep, "/"))
    return directories


def app_page():
    root = html.escape(DOWNLOAD_ROOT)
    directory_json = json.dumps(list_directories(), ensure_ascii=False)
    return f"""<!DOCTYPE html>
<html lang="zh-CN">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>URL Downloader</title>
  <style>
    body{{font-family:Arial,'Microsoft YaHei',sans-serif;margin:32px;color:#1f2937;background:#f8fafc;}}
    main{{max-width:860px;margin:0 auto;background:#fff;border:1px solid #e5e7eb;padding:20px;}}
    h1{{font-size:28px;margin:0 0 8px;}}
    .meta{{color:#64748b;margin-bottom:18px;}}
    .downloader-header{{display:flex;align-items:center;justify-content:space-between;gap:12px;border-top:1px solid #e5e7eb;padding-top:16px;cursor:pointer;}}
    .downloader-header h2{{font-size:18px;margin:0;}}
    .downloader-body{{margin-top:12px;}}
    .downloader-body.hidden{{display:none;}}
    label{{display:block;font-weight:700;margin:12px 0 6px;}}
    input{{box-sizing:border-box;width:100%;padding:9px;border:1px solid #cbd5e1;font-size:14px;}}
    button{{margin-top:12px;padding:9px 14px;border:0;background:#2563eb;color:#fff;font-weight:700;cursor:pointer;}}
    .downloader-header button{{margin-top:0;}}
    .dir-picker{{position:relative;}}
    .dir-button{{box-sizing:border-box;width:100%;margin:0!important;padding:9px!important;border:1px solid #cbd5e1!important;background:#fff!important;color:#1f2937!important;text-align:left!important;font-weight:400!important;}}
    .dir-menu{{display:none;position:absolute;z-index:20;top:40px;left:0;max-width:100%;background:#fff;border:1px solid #cbd5e1;box-shadow:0 8px 18px rgba(15,23,42,.12);}}
    .dir-menu.open{{display:flex;}}
    .dir-level{{list-style:none;margin:0;padding:6px 0;min-width:220px;max-height:280px;overflow:auto;border-right:1px solid #e5e7eb;}}
    .dir-level:last-child{{border-right:0;}}
    .dir-item{{display:flex;align-items:center;justify-content:space-between;gap:16px;padding:8px 12px;cursor:pointer;white-space:nowrap;}}
    .dir-item:hover,.dir-item.active{{background:#eff6ff;color:#1d4ed8;}}
    .dir-item span:last-child{{color:#64748b;}}
    .row{{display:flex;gap:10px;align-items:center;margin-top:10px;}}
    .secondary{{background:#475569;}}
    .status{{border:1px solid #e5e7eb;background:#f8fafc;margin-top:14px;padding:10px;min-height:46px;}}
    .status.ok{{border-color:#86efac;background:#f0fdf4;}} .status.err{{border-color:#fca5a5;background:#fef2f2;}}
    .progress{{height:12px;background:#e5e7eb;margin-top:8px;overflow:hidden;}}
    .progress-bar{{height:100%;width:0;background:#2563eb;transition:width .2s;}}
  </style>
</head>
<body>
  <main>
    <h1>URL Downloader</h1>
    <div class="meta">下载根目录: {root}</div>
    <div class="downloader-header">
      <h2>URL 下载</h2>
      <button id="toggle-url-download" type="button" aria-expanded="false">展开</button>
    </div>
    <div id="url-download-body" class="downloader-body hidden">
      <form id="url-download-form">
        <label for="download-url">下载链接</label>
        <input id="download-url" name="url" type="url" placeholder="https://example.com/file.tar.gz" required>
        <label for="download-filename">保存文件名（可选）</label>
        <input id="download-filename" name="filename" type="text" placeholder="留空则自动使用 URL 文件名">
        <label for="download-dir">保存目录（相对下载根目录，可选）</label>
        <input id="download-dir" name="directory" type="hidden" value="">
        <div id="download-dir-picker" class="dir-picker">
          <button id="download-dir-button" class="dir-button" type="button">保存目录: /</button>
          <div id="download-dir-menu" class="dir-menu"></div>
        </div>
        <div class="row">
          <button type="submit">开始下载</button>
          <button id="refresh-list" class="secondary" type="button">刷新文件列表</button>
          <span id="refresh-status" class="meta"></span>
        </div>
      </form>
      <div id="download-status" class="status">等待提交下载任务。</div>
      <div class="progress"><div id="download-progress" class="progress-bar"></div></div>
    </div>
  </main>
  <script>
    const form=document.getElementById('url-download-form');
    const statusBox=document.getElementById('download-status');
    const bar=document.getElementById('download-progress');
    const refreshBtn=document.getElementById('refresh-list');
    const refreshStatus=document.getElementById('refresh-status');
    const toggleBtn=document.getElementById('toggle-url-download');
    const downloadBody=document.getElementById('url-download-body');
    const downloadHeader=document.querySelector('.downloader-header');
    const directoryList={directory_json};
    const dirInput=document.getElementById('download-dir');
    const dirPicker=document.getElementById('download-dir-picker');
    const dirButton=document.getElementById('download-dir-button');
    const dirMenu=document.getElementById('download-dir-menu');
    function fmt(n){{if(!n&&n!==0)return '-';const u=['B','KB','MB','GB','TB'];let i=0;while(n>=1024&&i<u.length-1){{n/=1024;i++;}}return (i?n.toFixed(1):n.toFixed(0))+' '+u[i];}}
    function buildDirTree(paths){{const root=[];for(const path of paths){{let level=root;let current='';for(const name of path.split('/').filter(Boolean)){{current=current?current+'/'+name:name;let node=level.find(item=>item.name===name);if(!node){{node={{name,path:current,children:[]}};level.push(node);}}level=node.children;}}}}return root;}}
    const dirTree=buildDirTree(directoryList);
    function setDirectory(path){{dirInput.value=path;dirButton.textContent='保存目录: '+(path?path+'/':'/');dirMenu.classList.remove('open');}}
    function renderDirLevel(nodes,depth){{while(dirMenu.children.length>depth){{dirMenu.removeChild(dirMenu.lastChild);}}if(!nodes.length)return;const list=document.createElement('ul');list.className='dir-level';if(depth===0){{const rootItem=document.createElement('li');rootItem.className='dir-item';rootItem.innerHTML='<strong>/</strong>';rootItem.addEventListener('click',()=>setDirectory(''));list.appendChild(rootItem);}}for(const node of nodes){{const item=document.createElement('li');item.className='dir-item';item.innerHTML='<strong>'+node.name+'/</strong><span>'+(node.children.length?'›':'')+'</span>';item.addEventListener('mouseenter',()=>{{for(const el of list.children){{el.classList.remove('active');}}item.classList.add('active');renderDirLevel(node.children,depth+1);}});item.addEventListener('click',event=>{{event.stopPropagation();setDirectory(node.path);}});list.appendChild(item);}}dirMenu.appendChild(list);}}
    dirButton.addEventListener('click',()=>{{if(dirMenu.classList.toggle('open')){{dirMenu.innerHTML='';renderDirLevel(dirTree,0);}}}});
    document.addEventListener('click',event=>{{if(!dirPicker.contains(event.target)){{dirMenu.classList.remove('open');}}}});
    function show(s,cls){{statusBox.className='status '+(cls||'');statusBox.textContent=s;}}
    function setDownloadExpanded(expanded){{downloadBody.classList.toggle('hidden',!expanded);toggleBtn.textContent=expanded?'收起':'展开';toggleBtn.setAttribute('aria-expanded',String(expanded));try{{localStorage.setItem('urlDownloadExpanded',expanded?'true':'false');}}catch(err){{}}}}
    function toggleDownload(){{setDownloadExpanded(downloadBody.classList.contains('hidden'));}}
    downloadHeader.addEventListener('click',toggleDownload);
    toggleBtn.addEventListener('click',event=>{{event.stopPropagation();toggleDownload();}});
    try{{if(localStorage.getItem('urlDownloadExpanded')==='true')setDownloadExpanded(true);}}catch(err){{}}
    async function poll(id){{const r=await fetch('/url-download/status?id='+encodeURIComponent(id));const j=await r.json();const pct=j.total?Math.floor(j.downloaded*100/j.total):0;bar.style.width=(j.total?pct:0)+'%';show(j.message+' | '+fmt(j.downloaded)+(j.total?' / '+fmt(j.total)+' ('+pct+'%)':''),j.status==='done'?'ok':(j.status==='error'?'err':''));if(j.status==='done'){{bar.style.width='100%';return;}}if(j.status==='error')return;setTimeout(()=>poll(id),1000);}}
    form.addEventListener('submit',async e=>{{e.preventDefault();bar.style.width='0';show('正在创建下载任务...');try{{const body=new URLSearchParams(new FormData(form));const r=await fetch('/url-download',{{method:'POST',headers:{{'Content-Type':'application/x-www-form-urlencoded;charset=UTF-8'}},body}});const j=await r.json();if(!r.ok){{show(j.error||'创建下载任务失败','err');return;}}show('下载任务已开始');poll(j.id);}}catch(err){{show('创建下载任务失败: '+err,'err');}}}});
    refreshBtn.addEventListener('click',async()=>{{refreshBtn.disabled=true;refreshStatus.textContent='正在刷新...';try{{const r=await fetch('/url-download/refresh',{{method:'POST'}});const j=await r.json();if(!r.ok){{refreshStatus.textContent=j.error||'刷新失败';refreshBtn.disabled=false;return;}}refreshStatus.textContent='刷新完成';}}catch(err){{refreshStatus.textContent='刷新失败: '+err;}}finally{{refreshBtn.disabled=false;}}}});
  </script>
</body>
</html>""".encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    def send_html(self, body, code=200):
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def send_json(self, payload, code=200):
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/url-download/status":
            job_id = urllib.parse.parse_qs(parsed.query).get("id", [""])[0]
            with JOBS_LOCK:
                job = dict(JOBS.get(job_id, {}))
            if not job:
                self.send_json({"status": "error", "message": "任务不存在", "downloaded": 0, "total": 0}, 404)
                return
            self.send_json(job)
            return

        if parsed.path not in {"/", "/download", "/url-download"}:
            self.send_error(404)
            return
        self.send_html(app_page())

    def do_POST(self):
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/url-download/refresh":
            try:
                message = refresh_index()
                self.send_json({"message": message})
            except Exception as exc:
                self.send_json({"error": str(exc)}, 500)
            return

        if parsed.path not in {"/download", "/url-download"}:
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > MAX_FORM_BYTES:
            self.send_json({"error": "请求内容过大或为空"}, 400)
            return
        raw = self.rfile.read(length).decode("utf-8", "replace")
        form = urllib.parse.parse_qs(raw)
        url = form.get("url", [""])[0].strip()
        filename = form.get("filename", [""])[0].strip()
        directory = form.get("directory", [""])[0].strip()
        try:
            safe_directory(directory)
            safe_filename(url, filename)
            job_id = uuid.uuid4().hex
            set_job(job_id, status="queued", url=url, downloaded=0, total=0, message="等待下载")
            thread = threading.Thread(target=run_download, args=(job_id, url, filename, directory), daemon=True)
            thread.start()
            self.send_json({"id": job_id, "status": "queued", "message": "下载任务已创建"}, 202)
        except Exception as exc:
            self.send_json({"error": str(exc)}, 500)

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


if __name__ == "__main__":
    os.makedirs(DOWNLOAD_ROOT, exist_ok=True)
    server = ThreadingHTTPServer((BIND, PORT), Handler)
    print(f"URL downloader listening on {BIND}:{PORT}, root={DOWNLOAD_ROOT}", flush=True)
    server.serve_forever()
PY

    chmod +x "$app" || log error "无法设置 URL 下载服务脚本执行权限"

    cat > /etc/systemd/system/url-downloader.service <<EOF
[Unit]
Description=URL downloader for nginx downloads root
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
EnvironmentFile=/etc/default/url-downloader
ExecStart=/usr/bin/python3 /usr/local/bin/url_downloader.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload || log error "systemd daemon-reload 失败"
    systemctl enable url-downloader.service || log error "设置 url-downloader.service 开机启动失败"
    systemctl restart url-downloader.service || log error "重启 url-downloader.service 失败"
    log info "URL 下载服务部署完成: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$URL_DOWNLOADER_PORT/"
}

if [ "$DEPLOY_NGINX" = "true" ]; then
    deploy_nginx_download_site
else
    log info "跳过 nginx 安装配置"
fi

if [ "$DEPLOY_FILEBROWSER" = "true" ]; then
    deploy_filebrowser
else
    log info "跳过 File Browser 部署"
fi

if [ "$DEPLOY_URL_DOWNLOADER" = "true" ]; then
    deploy_url_downloader
else
    log info "跳过 URL 下载服务部署"
fi

if [ "$DEPLOY_NGINX" = "true" ]; then
    log info "下载站点部署完成: http://$(hostname -I 2>/dev/null | awk '{print $1}'):$LISTEN_PORT/"
fi
log info "下载根目录: $DOWNLOAD_ROOT"
