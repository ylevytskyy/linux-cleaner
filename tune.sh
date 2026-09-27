#!/usr/bin/env bash
# One-time speed tuning for this Linux Mint box (2026-09).
#
# Each step checks current state first, skips if already applied, asks before
# changing anything, and prints its undo command. Safe to re-run.
# Companion to cleanup2.sh (disk space); this one is about boot/idle speed.
#
# Usage: ./tune.sh

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

echo ">>> Boot time now:"; systemd-analyze 2>/dev/null | head -1

# ───── Changes (ask first) ─────

echo ""; echo "[1] NetworkManager-wait-online (~6s on the boot critical path):"
if systemctl is-enabled -q NetworkManager-wait-online.service 2>/dev/null; then
  echo "  Boot waits until the network is fully up. A laptop without network"
  echo "  mounts (NFS/SMB in fstab) doesn't need that."
  if confirm "  Disable it?"; then
    sudo systemctl disable NetworkManager-wait-online.service
    echo "  undo: sudo systemctl enable NetworkManager-wait-online.service"
  fi
else
  echo "  already disabled"
fi

echo ""; echo "[2] Docker: start on first use instead of at boot (socket activation):"
if systemctl is-enabled -q docker.service 2>/dev/null; then
  AUTO=$(docker ps -a --format '{{.Names}}' 2>/dev/null | while read -r n; do
    p=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$n")
    [ "$p" = always ] || [ "$p" = unless-stopped ] && echo "$n"
  done)
  echo "  docker + containerd then stay off until you run any docker command."
  if [ -n "$AUTO" ]; then
    echo "  NOTE: these containers will no longer auto-start at boot, only once"
    echo "  docker is first used:"; echo "$AUTO" | sed 's/^/    /'
  fi
  if confirm "  Switch docker to socket activation?"; then
    sudo systemctl disable docker.service containerd.service
    sudo systemctl enable docker.socket
    echo "  undo: sudo systemctl enable docker.service containerd.service"
  fi
else
  echo "  already socket-activated (docker.service not enabled)"
fi

echo ""; echo "[3] Login autostart (Mint welcome/report tools, Warpinator):"
AS_ON=""
for n in mintwelcome mintreport warpinator-autostart; do
  [ -f "/etc/xdg/autostart/$n.desktop" ] || continue
  grep -qx 'Hidden=true' "$HOME/.config/autostart/$n.desktop" 2>/dev/null || AS_ON="$AS_ON $n"
done
if [ -n "$AS_ON" ]; then
  echo "  Launched at every login:$AS_ON"
  if confirm "  Stop them autostarting (per-user override, system files untouched)?"; then
    mkdir -p "$HOME/.config/autostart"
    for n in $AS_ON; do
      printf '[Desktop Entry]\nType=Application\nName=%s\nHidden=true\n' "$n" \
        > "$HOME/.config/autostart/$n.desktop"
    done
    echo "  undo: rm$(for n in $AS_ON; do printf ' ~/.config/autostart/%s.desktop' "$n"; done)"
  fi
else
  echo "  already off"
fi

# ───── Checks (report only) ─────

echo ""; echo "[4] CPU microcode:"
if dpkg -s intel-microcode >/dev/null 2>&1; then
  echo "  intel-microcode $(dpkg-query -W -f='${Version}' intel-microcode) installed"
  apt list --upgradable 2>/dev/null | grep -q '^intel-microcode/' \
    && echo "  UPDATE AVAILABLE: sudo apt-get install intel-microcode && reboot"
else
  echo "  NOT installed: sudo apt-get install intel-microcode && reboot"
fi
echo "  GDS: $(cat /sys/devices/system/cpu/vulnerabilities/gather_data_sampling)"
echo "  (\"No microcode\" with the package current = Intel ships no fix for this CPU.)"

echo ""; echo "[5] Projects drive filesystem:"
FS=$(findmnt -no FSTYPE /media/lion/Data 2>/dev/null)
case "$FS" in
  ext4|btrfs|xfs) echo "  $FS — fine" ;;
  "")             echo "  /media/lion/Data not mounted" ;;
  *)              echo "  $FS — slow for node_modules/gradle; move hot projects to ext4" ;;
esac

echo ""; echo ">>> Done. Changes take effect on next boot; compare with: systemd-analyze"
