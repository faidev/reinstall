#!/usr/bin/env bash
set -e

# 至少要 IP 尾号
if [ -z "$1" ]; then
  echo "用法: $0 <IP最后一位> [root密码]"
  exit 1
fi

LAST="$1"
PASS="${2:-}"

# IP 校验
if ! [[ "$LAST" =~ ^[0-9]+$ ]] || [ "$LAST" -lt 1 ] || [ "$LAST" -gt 254 ]; then
  echo "❌ IP 最后一位必须是 1–254"
  exit 1
fi

# 自动检测默认网卡
IFACE=$(ip route | awk '/default/ {print $5; exit}')
[ -z "$IFACE" ] && echo "❌ 无法检测网卡" && exit 1

echo "✅ 网卡: $IFACE"
echo "✅ IP 尾号: $LAST"

# 备份 interfaces
cp /etc/network/interfaces /etc/network/interfaces.bak.$(date +%F-%H%M%S)

# 写入网络配置
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

echo "🔄 重启 networking..."
systemctl restart networking

# ===== 在线执行 reinstall =====
REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"

echo "🚀 开始重装 Debian 12"

# 关键：构造参数
REINSTALL_ARGS=("debian" "12")

if [ -n "$PASS" ]; then
  echo "🔐 使用传入的 root 密码"
  REINSTALL_ARGS+=("--password" "$PASS")
fi

if command -v curl >/dev/null 2>&1; then
  bash <(curl -fsSL "$REINSTALL_URL") "${REINSTALL_ARGS[@]}"
elif command -v wget >/dev/null 2>&1; then
  bash <(wget -qO- "$REINSTALL_URL") "${REINSTALL_ARGS[@]}"
else
  echo "❌ curl / wget 均不存在"
  exit 1
fi
