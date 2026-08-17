#!/bin/bash

# --- 1. 参数与配置检查 ---
if [ -z "$1" ]; then
    echo -e "用法: $0 <IP段> [探测方式]"
    echo -e "示例: $0 10.10.90         (默认使用 ping 探测)"
    echo -e "      $0 10.10.90 arp     (使用 ARP 探测，无视禁Ping，限同网段)"
    echo -e "      $0 10.10.90 tcp     (使用 TCP 端口探测，适合跨网段穿透)"
    exit 1
fi

PREFIX=$1
METHOD=${2:-ping} # 如果没传第二个参数，默认使用 ping

# 工具依赖检查
if [ "$METHOD" = "arp" ] && ! command -v arping >/dev/null 2>&1; then
    echo -e "\033[0;31m错误: 未找到 arping 命令。请先安装 (如: yum install iputils / apt install arping)\033[0m"
    exit 1
fi
if [ "$METHOD" = "tcp" ] && ! command -v nc >/dev/null 2>&1; then
    echo -e "\033[0;31m错误: 未找到 nc 命令。请先安装 (如: yum install nc / apt install netcat)\033[0m"
    exit 1
fi

# --- 2. 颜色与打印头 ---
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "================================================="
echo -e " 目标网段 : $PREFIX.0/24"
echo -e " 探测模式 : 寻找空闲IP [${GREEN}绿色=可用${NC} | ${RED}红色=已占用${NC}]"

case "$METHOD" in
    arp) echo -e " 探测引擎 : ${GREEN}ARP (二层探测, 无视禁Ping)${NC}" ;;
    tcp) echo -e " 探测引擎 : ${GREEN}TCP 端口探测 (跨网段穿透)${NC}" ;;
    ping|*) echo -e " 探测引擎 : ${GREEN}ICMP Ping (常规探测)${NC}" ;;
esac
echo -e "================================================="

# --- 3. 并发探测核心 ---
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

if [ "$(uname -s)" = "Darwin" ]; then
    PING_TIMEOUT_FLAG="-W 1000"
else
    PING_TIMEOUT_FLAG="-W 1"
fi

for i in {1..254}; do
    (
        target="$PREFIX.$i"
        alive=0
        
        case "$METHOD" in
            arp)
                # ARP 探测 (超时 1 秒)
                if arping -c 1 -w 1 "$target" >/dev/null 2>&1; then alive=1; fi
                ;;
            tcp)
                # TCP 探测常见端口: 22(SSH), 80/443(Web), 3306(MySQL), 6379(Redis), 8080/8081(业务)
                # 只要有一个端口通，就说明机器存活
                if nc -z -w 1 "$target" 22 80 443 3306 6379 8080 8081 >/dev/null 2>&1; then alive=1; fi
                ;;
            ping|*)
                # 普通 Ping 探测 (超时 1 秒)
                if ping -c 1 $PING_TIMEOUT_FLAG "$target" >/dev/null 2>&1; then alive=1; fi
                ;;
        esac
        
        # 写入临时文件
        echo $alive > "$TMP_DIR/$i"
    ) &
done

wait # 等待所有后台探测任务完成

# --- 4. 收集结果 ---
# 使用标准索引数组兼容 Bash 3.2+
declare -a is_avail
for i in {1..254}; do
    if [ -f "$TMP_DIR/$i" ]; then alive=$(cat "$TMP_DIR/$i"); else alive=0; fi
    # 找空闲IP逻辑: alive=0 才是可用(1)
    if [ "$alive" -eq 0 ]; then is_avail[$i]=1; else is_avail[$i]=0; fi
done

# --- 5. 打印表格内容 ---
echo " 尾号 |  1~99   | 100~199 | 200~254 | 全组可用状态"
echo "-------------------------------------------------"

for c in {0..99}; do
    row_idx=$(printf "%02d" "$c")
    echo -en "  $row_idx  |"
    
    ip1=$c; ip2=$((100+c)); ip3=$((200+c))
    all_avail=1
    
    # 打印 1~99
    if [ "$ip1" -eq 0 ]; then
        echo -en "   -     |"
    else
        if [ "${is_avail[$ip1]}" -eq 1 ]; then echo -en "  ${GREEN}$(printf "%3s" "$ip1")${NC}    |"; else echo -en "  ${RED}$(printf "%3s" "$ip1")${NC}    |"; all_avail=0; fi
    fi

    # 打印 100~199
    if [ "${is_avail[$ip2]}" -eq 1 ]; then echo -en "   ${GREEN}$(printf "%3s" "$ip2")${NC}   |"; else echo -en "   ${RED}$(printf "%3s" "$ip2")${NC}   |"; all_avail=0; fi

    # 打印 200~254
    if [ "$ip3" -gt 254 ]; then
        echo -en "   -     |"
    else
        if [ "${is_avail[$ip3]}" -eq 1 ]; then echo -en "   ${GREEN}$(printf "%3s" "$ip3")${NC}   |"; else echo -en "   ${RED}$(printf "%3s" "$ip3")${NC}   |"; all_avail=0; fi
    fi

    # 打印全组状态
    if [ "$all_avail" -eq 1 ]; then echo -e "   ${GREEN}√ OK${NC}"; else echo -e ""; fi
done
echo "================================================="

# --- 6. 汇总连续可用 IP 段 ---
echo ""
echo "================ 可用 IP 段汇总 ================"
start_ip=""
total_avail=0

for i in {1..255}; do
    if [ "$i" -le 254 ]; then avail="${is_avail[$i]}"; else avail=0; fi
    
    if [ "$avail" -eq 1 ]; then
        if [ -z "$start_ip" ]; then start_ip=$i; fi
        ((total_avail++))
    else
        if [ -n "$start_ip" ]; then
            end_ip=$(( i - 1 ))
            count=$(( end_ip - start_ip + 1 ))
            if [ "$start_ip" -eq "$end_ip" ]; then
                printf "  %-14s %-16s | 共 %3d 个\n" "$PREFIX.$start_ip" "(单个)" "$count"
            else
                printf "  %-14s ~ %-14s | 共 %3d 个\n" "$PREFIX.$start_ip" "$PREFIX.$end_ip" "$count"
            fi
            start_ip=""
        fi
    fi
done

echo "-------------------------------------------------"
echo -e "  总计可用 IP 数量: ${GREEN}${total_avail}${NC} 个"
echo "================================================="
