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

scan_ip() {
    ip=$1

    if ping -c 1 -W 1 $ip &>/dev/null; then
        echo "$ip" >> $TMP_USED
    else
        echo "$ip" >> $TMP_FREE
    fi
}

export -f scan_ip
export TMP_FREE TMP_USED

# 并行扫描
for i in {1..254}; do
    scan_ip "$IP_SEGMENT.$i" &
done

wait

echo
echo "------------- RESULT (SORTED) -------------"

# 已使用IP
echo -e "${RED}USED IP:${NC}"
sort -V $TMP_USED | while read ip
do
    echo -e "${RED}$ip USED${NC}"
done

echo

# 未使用IP
echo -e "${GREEN}FREE IP:${NC}"
sort -V $TMP_FREE | while read ip
do
    echo -e "${GREEN}$ip FREE${NC}"
done

echo
echo "------------- SUMMARY -------------"

USED_COUNT=$(wc -l < $TMP_USED)
FREE_COUNT=$(wc -l < $TMP_FREE)

echo -e "Used IPs : ${RED}$USED_COUNT${NC}"
echo -e "Free IPs : ${GREEN}$FREE_COUNT${NC}"

echo
echo -e "${GREEN}Available IP list:${NC}"
sort -V $TMP_FREE

rm -f $TMP_FREE $TMP_USED