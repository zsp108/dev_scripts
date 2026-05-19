#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # 无颜色

echo -e "${CYAN}===============================================${NC}"
echo -e "${GREEN}    V2Ray 客户端 (Client) 配置文件生成脚本${NC}"
echo -e "${CYAN}===============================================${NC}"
echo

# 1. 本地入站端口设置
read -p "1. 请输入本地 Socks 代理端口 (默认: 10808): " SOCKS_PORT
SOCKS_PORT=${SOCKS_PORT:-10808}

read -p "2. 请输入本地 HTTP 代理端口 (默认: 10809): " HTTP_PORT
HTTP_PORT=${HTTP_PORT:-10809}

# 2. 远程服务器节点信息设置
echo -e "\n${YELLOW}--- 请输入你的远程 V2Ray 服务器节点信息 ---${NC}"

read -p "3. 请输入服务器 IP 或域名 (必填): " SERVER_ADDR
while [ -z "$SERVER_ADDR" ]; do
    echo -e "${RED}错误: 服务器地址不能为空！${NC}"
    read -p "3. 请输入服务器 IP 或域名: " SERVER_ADDR
done

read -p "4. 请输入服务器端口 (默认: 10086): " SERVER_PORT
SERVER_PORT=${SERVER_PORT:-10086}

echo -e "${YELLOW}   提示: 一些客户端导出的 Vmess 节点会同时有 uuid 和 password 字段。${NC}"
echo -e "${YELLOW}   这里要填 Vmess 用户 ID，通常是 password 字段；不要填记录本身的 uuid。${NC}"
read -p "5. 请输入 Vmess 用户 ID/password (必填): " SERVER_UUID
while [ -z "$SERVER_UUID" ]; do
    echo -e "${RED}错误: Vmess 用户 ID/password 不能为空！${NC}"
    read -p "5. 请输入 Vmess 用户 ID/password: " SERVER_UUID
done

# 3. 传输协议选择
echo -e "\n6. 请选择服务器的传输网络协议 (Network):"
echo "   1) tcp (默认)"
echo "   2) ws (WebSocket)"
read -p "   请输入数字 [1-2]: " NET_CHOICE

case $NET_CHOICE in
    2)
        NETWORK="ws"
        echo -e "${YELLOW}   注意: WebSocket 路径必须和节点完全一致，尾部 / 也会影响匹配。${NC}"
        read -p "   请输入 WebSocket 路径 (例如: /FyWTswgd/，默认: /ray): " WS_PATH
        WS_PATH=${WS_PATH:-/ray}
        read -p "   是否启用 TLS/WSS? CDN 端口 443/2053 通常需要启用 (Y/n): " TLS_CHOICE
        case $TLS_CHOICE in
            n|N|no|NO)
                TLS_ENABLED="false"
                ;;
            *)
                TLS_ENABLED="true"
                read -p "   请输入 TLS SNI/serverName (默认: ${SERVER_ADDR}): " TLS_SERVER_NAME
                TLS_SERVER_NAME=${TLS_SERVER_NAME:-$SERVER_ADDR}
                ;;
        esac
        read -p "   请输入 WebSocket Host 头/伪装域名 (默认: ${SERVER_ADDR}): " WS_HOST
        WS_HOST=${WS_HOST:-$SERVER_ADDR}
        ;;
    *)
        NETWORK="tcp"
        ;;
esac

# 4. 输出路径
echo
read -p "7. 请输入配置文件保存路径 (默认: ./config.json): " OUTPUT_PATH
OUTPUT_PATH=${OUTPUT_PATH:-./config.json}

echo -e "\n${YELLOW}正在构造客户端配置文件...${NC}"

# 5. 动态构建客户端 Outbound StreamSettings JSON
STREAM_SETTINGS=""
if [ "$NETWORK" == "ws" ]; then
    if [ "$TLS_ENABLED" == "true" ]; then
        STREAM_SETTINGS=',
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "serverName": "'"${TLS_SERVER_NAME}"'",
          "allowInsecure": false
        },
        "wsSettings": {
          "path": "'"${WS_PATH}"'",
          "headers": {
            "Host": "'"${WS_HOST}"'"
          }
        }
      }'
    else
        STREAM_SETTINGS=',
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "'"${WS_PATH}"'",
          "headers": {
            "Host": "'"${WS_HOST}"'"
          }
        }
      }'
    fi
else
    STREAM_SETTINGS=',
      "streamSettings": {
        "network": "tcp"
      }'
fi

# 6. 写入完整客户端 JSON
cat <<EOF > "$OUTPUT_PATH"
{
  "log": {
    "loglevel": "warning"
  },
  "inbounds": [
    {
      "tag": "socks-in",
      "port": ${SOCKS_PORT},
      "listen": "127.0.0.1",
      "protocol": "socks",
      "settings": {
        "auth": "noauth",
        "udp": true,
        "userLevel": 0
      }
    },
    {
      "tag": "http-in",
      "port": ${HTTP_PORT},
      "listen": "127.0.0.1",
      "protocol": "http",
      "settings": {
        "userLevel": 0
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER_ADDR}",
            "port": ${SERVER_PORT},
            "users": [
              {
                "id": "${SERVER_UUID}",
                "alterId": 0,
                "security": "auto",
                "level": 0
              }
            ]
          }
        ]
      }${STREAM_SETTINGS}
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "settings": {}
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {}
    }
  ],
  "routing": {
    "domainStrategy": "AsIs",
    "rules": [
      {
        "type": "field",
        "ip": [
          "0.0.0.0/8",
          "10.0.0.0/8",
          "127.0.0.0/8",
          "169.254.0.0/16",
          "172.16.0.0/12",
          "192.168.0.0/16",
          "::1/128",
          "fc00::/7",
          "fe80::/10"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "outboundTag": "proxy",
        "network": "udp,tcp"
      }
    ]
  }
}
EOF

# 7. 生成结果反馈
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN} 客户端配置文件生成成功！${NC}"
echo -e "${CYAN} 保存路径:${NC} $OUTPUT_PATH"
echo -e "${CYAN} 本地 Socks 端口:${NC} $SOCKS_PORT"
echo -e "${CYAN} 本地 HTTP 端口:${NC} $HTTP_PORT"
echo -e "${GREEN} --------------------------------------------- ${NC}"
echo -e "${CYAN} 远程服务器:${NC} $SERVER_ADDR:$SERVER_PORT"
echo -e "${CYAN} Vmess 用户 ID:${NC} $SERVER_UUID"
echo -e "${CYAN} 传输协议:${NC} $NETWORK"
if [ "$NETWORK" == "ws" ]; then
    echo -e "${CYAN} WS 路径:${NC} $WS_PATH"
    echo -e "${CYAN} WS Host:${NC} $WS_HOST"
    echo -e "${CYAN} TLS/WSS:${NC} $TLS_ENABLED"
    if [ "$TLS_ENABLED" == "true" ]; then
        echo -e "${CYAN} TLS SNI:${NC} $TLS_SERVER_NAME"
    fi
fi
echo -e "${GREEN}===============================================${NC}"
echo -e "${YELLOW}使用方法: 将该文件命名为 config.json 并放入你的 V2Ray 客户端目录即可。${NC}"
echo -e "${YELLOW}提示: curl 测试 SOCKS 时建议使用 socks5h://127.0.0.1:${SOCKS_PORT}，让 DNS 也走代理。${NC}"
if command -v v2ray >/dev/null 2>&1; then
    echo -e "${YELLOW}正在执行 v2ray 配置校验...${NC}"
    v2ray -test -config "$OUTPUT_PATH"
fi
