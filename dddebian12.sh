#!/usr/bin/env bash
set -e

# 参数校验
if [ -z "$1" ]; then
  echo "用法: $0 <IP最后一位>"
  exit 1
fi

LAST="$1"

# 简单校验（1–254）
if ! [[ "$LAST" =~ ^[0-9]+$ ]] || [ "$LAST" -lt 1 ] || [ "$LAST" -gt 254 ]; then
  echo "❌ IP 最后一位必须是 1–254"
  exit 1
fi

# 自动获取默认网卡名
IFACE=$(ip route | awk '/default/ {print $5; exit}')
[ -z "$IFACE" ] && echo "❌ 无法检测网卡" && exit 1

echo "✅ 网卡: $IFACE"
echo "✅ IP 尾号: $LAST"

# 备份原配置
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%F-%H%M%S)

# 写入配置
cat > /etc/network/interfaces <<EOF
source /etc/network/interfaces.d/*

auto lo
iface lo inet loopback

auto $IFACE
iface $IFACE inet static
    address 192.168.89.$LAST/24
    gateway 192.168.89.1
    dns-nameservers 1.1.1.1
    dns-nameservers 8.8.8.8

iface $IFACE inet6 static
    address 2400:f880:b43:612d::$LAST/128
    gateway 2400:f880:b43:612d::1
    dns-nameserver 2606:4700:4700::1111
    dns-nameserver 2001:4860:4860::8888
    accept_ra 0
    autoconf 0
EOF

echo "✅ 配置已写入 /etc/network/interfaces"

# 重启网卡
ifdown "$IFACE" 2>/dev/null || true
ifup "$IFACE"

echo "✅ 网卡已重启"
