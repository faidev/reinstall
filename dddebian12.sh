#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   sudo ./all-in-one.sh vm10
#   sudo ./all-in-one.sh vm10 123456qwert
#
# Description:
# - Argument 1: vm<NUMBER>, e.g. vm10 -> IP last octet = 10
#   If not provided, the script will prompt for it interactively.
# - Argument 2: optional root password
#   - If provided, --password will be passed to reinstall.sh
#   - If not provided, --password will NOT be used

# ===== Get vmXX argument (prompt if missing) =====
if [[ -z "${1:-}" ]]; then
  read -rp "Enter VM identifier (format: vm<NUMBER>, e.g. vm10): " RAW
else
  RAW="$1"
fi

PASS="${2:-}"

# Validate vmXX format
if ! [[ "$RAW" =~ ^vm[0-9]+$ ]]; then
  echo "Invalid format. Expected vm<NUMBER>, e.g. vm10"
  exit 1
fi

LAST="${RAW#vm}"
if [[ "$LAST" -lt 1 || "$LAST" -gt 254 ]]; then
  echo "IP last octet must be between 1 and 254"
  exit 1
fi

# Must run as root
if [[ "${EUID}" -ne 0 ]]; then
  echo "Please run as root: sudo $0 [vmXX] [password]"
  exit 1
fi

# ===== Detect default network interface =====
IFACE="$(ip route | awk '/default/ {print $5; exit}')"
if [[ -z "$IFACE" ]]; then
  echo "Failed to detect network interface (no default route)"
  exit 1
fi

echo "Network interface: $IFACE"
echo "IP last octet: $LAST (from $RAW)"

# ===== Write /etc/network/interfaces =====
cp /etc/network/interfaces "/etc/network/interfaces.bak.$(date +%F-%H%M%S)"

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

echo "Network configuration written to /etc/network/interfaces (backup created)"

# ===== Restart networking =====
echo "Restarting networking service..."
systemctl restart networking

# ===== Check IPv4 and IPv6 connectivity (both required) =====
check_ipv4() { ping -4 -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; }
check_ipv6() { ping -6 -c 1 -W 2 2606:4700:4700::1111 >/dev/null 2>&1; }

wait_network() {
  echo "Checking IPv4 and IPv6 connectivity (both required)..."
  for i in {1..15}; do
    check_ipv4 && V4=1 || V4=0
    check_ipv6 && V6=1 || V6=0

    if [[ "$V4" -eq 1 && "$V6" -eq 1 ]]; then
      echo "IPv4 and IPv6 connectivity confirmed"
      return 0
    fi

    echo "Waiting for network ($i/15)... IPv4=$V4 IPv6=$V6"
    sleep 2
  done

  echo "Network check failed: IPv4=$V4 IPv6=$V6 (installation aborted)"
  return 1
}

wait_network

# ===== Run reinstall.sh online (Debian 12) =====
REINSTALL_URL="https://raw.githubusercontent.com/bin456789/reinstall/main/reinstall.sh"
REINSTALL_ARGS=("debian" "12")

if [[ -n "$PASS" ]]; then
  echo "Root password provided, passing --password to reinstall.sh"
  REINSTALL_ARGS+=("--password" "$PASS")
else
  echo "No root password provided, --password will not be used"
fi

echo "Starting system reinstall: reinstall.sh ${REINSTALL_ARGS[*]}"

if command -v curl >/dev/null 2>&1; then
  bash <(curl -fsSL "$REINSTALL_URL") "${REINSTALL_ARGS[@]}"
elif command -v wget >/dev/null 2>&1; then
  bash <(wget -qO- "$REINSTALL_URL") "${REINSTALL_ARGS[@]}"
else
  echo "Neither curl nor wget is available"
  exit 1
fi

# ===== Ask whether to reboot =====
echo
read -rp "Reboot the server now? [y/N]: " ANSWER
case "$ANSWER" in
  y|Y|yes|YES)
    echo "Rebooting now..."
    reboot
    ;;
  *)
    echo "Reboot skipped. You may reboot manually later."
    ;;
esac
