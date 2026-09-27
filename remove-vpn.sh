#!/usr/bin/env bash
# Remove every VPN client/daemon from this box (2026-09) — none are used.
#
# Covers: Tailscale (+ its apt repo), OpenVPN, strongSwan/IPsec, PPTP, L2TP
# (+ its PPA), the NetworkManager VPN plugins, and the ProtonVPN flatpak.
# Not VPNs, kept: warpinator (LAN file sharing), warp-terminal, ppp.
# Asks before each section; re-running skips what's already gone.
#
# Usage: ./remove-vpn.sh

set -u

if [ "$(id -u)" -eq 0 ]; then
  echo "!!! Run as your normal user, not root/sudo (the script sudo's itself)."
  exit 1
fi

confirm() {  # confirm "question" -> 0 if user typed y
  local a
  if ! read -r -p "$1 [y/N] " a 2>/dev/null < /dev/tty; then
    echo "  (no terminal — SKIPPED, run from a real terminal to be asked)"
    return 1
  fi
  [[ "$a" == [yY]* ]]
}

PKGS="tailscale tailscale-archive-keyring openvpn
  network-manager-openvpn network-manager-openvpn-gnome
  network-manager-pptp network-manager-pptp-gnome pptp-linux
  network-manager-l2tp network-manager-l2tp-gnome xl2tpd
  strongswan strongswan-starter strongswan-charon strongswan-libcharon
  libstrongswan libstrongswan-standard-plugins libcharon-extauth-plugins"

echo "[1] VPN packages:"
INST=$(dpkg-query -W -f='${db:Status-Abbrev} ${Package}\n' $PKGS 2>/dev/null | awk '$1=="ii"{print $2}')
if [ -n "$INST" ]; then
  echo "$INST" | sed 's/^/    /'
  if confirm "  Purge these (configs included)?"; then
    command -v tailscale >/dev/null && sudo tailscale down 2>/dev/null
    sudo apt-get purge -y $INST && sudo apt-get autoremove --purge -y
    sudo rm -rf /var/lib/tailscale  # daemon state, not owned by the package
  fi
else
  echo "  none installed"
fi

echo ""; echo "[2] VPN apt repos (Tailscale, nm-l2tp PPA):"
REPOS=$(ls /etc/apt/sources.list.d/tailscale.* /etc/apt/sources.list.d/nm-l2tp-* \
  /usr/share/keyrings/tailscale-* /etc/apt/trusted.gpg.d/nm-l2tp* 2>/dev/null)
if [ -n "$REPOS" ]; then
  echo "$REPOS" | sed 's/^/    /'
  if confirm "  Remove them?"; then
    sudo rm -f $REPOS && sudo apt-get update -qq
  fi
else
  echo "  none"
fi

echo ""; echo "[3] ProtonVPN flatpak:"
if flatpak info com.protonvpn.www >/dev/null 2>&1; then
  if confirm "  Uninstall it and its data (~/.var/app/com.protonvpn.www)?"; then
    flatpak uninstall -y --delete-data com.protonvpn.www
    flatpak uninstall -y --unused
  fi
else
  echo "  not installed"
fi

echo ""; echo "[4] Leftover NetworkManager VPN/WireGuard connections:"
CONS=$(nmcli -t -f UUID,TYPE con show 2>/dev/null | awk -F: '$2=="vpn"||$2=="wireguard"{print $1}')
if [ -n "$CONS" ]; then
  nmcli -f NAME,TYPE con show | grep -E 'vpn|wireguard'
  if confirm "  Delete them?"; then
    for c in $CONS; do nmcli con delete "$c"; done
  fi
else
  echo "  none"
fi

echo ""; echo ">>> Done. Check: dpkg -l | grep -Ei 'vpn|strongswan|tailscale|l2tp|pptp'"
