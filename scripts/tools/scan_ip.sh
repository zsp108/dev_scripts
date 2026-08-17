#!/bin/bash

if [ -z "$1" ]; then
    echo "Usage: $0 <IP_SEGMENT>"
    echo "Example: $0 192.168.1"
    exit 1
fi

IP_SEGMENT=$1

RED='\033[31m'
GREEN='\033[32m'
NC='\033[0m'

TMP_FREE=$(mktemp)
TMP_USED=$(mktemp)

echo "Scanning IP segment: ${IP_SEGMENT}.0/24"
echo "--------------------------------------"

if [ "$(uname -s)" = "Darwin" ]; then
    PING_TIMEOUT_FLAG="-W 1000"
else
    PING_TIMEOUT_FLAG="-W 1"
fi

scan_ip() {
    local ip="$1"
    local timeout_flag="$2"

    if ping -c 1 $timeout_flag "$ip" >/dev/null 2>&1; then
        echo "$ip" >> "$TMP_USED"
    else
        echo "$ip" >> "$TMP_FREE"
    fi
}

export -f scan_ip 2>/dev/null || true
export TMP_FREE TMP_USED

# 并行扫描
for i in {1..254}; do
    scan_ip "$IP_SEGMENT.$i" "$PING_TIMEOUT_FLAG" &
done

wait

echo
echo "------------- RESULT (SORTED) -------------"

# 已使用IP
echo -e "${RED}USED IP:${NC}"
sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n "$TMP_USED" | while read -r ip
do
    echo -e "${RED}$ip USED${NC}"
done

echo

# 未使用IP
echo -e "${GREEN}FREE IP:${NC}"
sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n "$TMP_FREE" | while read -r ip
do
    echo -e "${GREEN}$ip FREE${NC}"
done

echo
echo "------------- SUMMARY -------------"

USED_COUNT=$(wc -l < "$TMP_USED" | tr -d ' ')
FREE_COUNT=$(wc -l < "$TMP_FREE" | tr -d ' ')

echo -e "Used IPs : ${RED}$USED_COUNT${NC}"
echo -e "Free IPs : ${GREEN}$FREE_COUNT${NC}"

echo
echo -e "${GREEN}Available IP list:${NC}"
sort -t . -k 1,1n -k 2,2n -k 3,3n -k 4,4n "$TMP_FREE"

rm -f "$TMP_FREE" "$TMP_USED"