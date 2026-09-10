#!/usr/bin/env bash
# Safe Purge List — high-confidence cleanup from the 5-subagent audit.
#
# Linux Mint 22.3 Cinnamon (Ubuntu 24.04 noble base), HP ProBook 650 G2.
# ext4 root confirmed (no ZFS pool). Tailscale is the active VPN; openvpn /
# strongswan / xl2tpd are dead weight in this setup.
#
# Interactive — confirms before each section. Verifies preconditions where
# possible so a wrong assumption skips the section instead of breaking things.
#
# OVERLAP NOTE: items 1, 2 also appear in tame-services.sh. They are safe to
# re-run (idempotent: systemctl disable on an already-disabled unit is a no-op).
# Skip them with the prompt if you've already run tame-services.sh.

set -u

confirm() {
  local reply=""
  read -r -p "$1 [y/N]: " reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

section() {
  echo ""
  echo "═══════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "═══════════════════════════════════════════════════════════════"
}

hide_autostart() {
  local src="/etc/xdg/autostart/$1"
  local dst="$HOME/.config/autostart/$1"
  mkdir -p "$HOME/.config/autostart"
  if [ -f "$src" ]; then
    cp "$src" "$dst"
    grep -q '^Hidden=' "$dst" && sed -i 's/^Hidden=.*/Hidden=true/' "$dst" \
      || echo "Hidden=true" >> "$dst"
    echo "  ↳ hid $1 (override at $dst)"
  else
    printf '[Desktop Entry]\nType=Application\nName=disabled\nHidden=true\n' > "$dst"
    echo "  ↳ wrote stub override at $dst"
  fi
}

START_BOOT_SVCS=$(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l)
echo ">>> Starting safe purge. Enabled units at start: $START_BOOT_SVCS"

# ────────────── TIER 1: SYSTEM-LEVEL (sudo) ──────────────

section "1. ZFS suite — no ZFS pool detected (also in tame-services.sh)"
if sudo zpool list 2>&1 | grep -q 'no pools available\|^$'; then
  echo "Confirmed: no zpools on this system. ext4 root."
  if confirm "Mask zfs-zed + zfs-import/load/mount/share/volume-wait/volumes?"; then
    sudo systemctl disable --now zfs-zed.service 2>&1 | tail -2
    sudo systemctl mask zfs-import-cache.service zfs-import-scan.service \
      zfs-load-module.service zfs-mount.service zfs-share.service \
      zfs-volume-wait.service zfs-volumes.service 2>&1 | tail -3
  fi
else
  echo "ZFS pool found — skipping."
fi

section "2. NetworkManager-wait-online — slows boot, no NFS/CIFS in fstab (also in tame-services.sh)"
HAS_NFS=$(grep -cE 'nfs|cifs|smbfs' /etc/fstab 2>/dev/null || echo 0)
echo "NFS/CIFS entries in /etc/fstab: $HAS_NFS"
if [ "$HAS_NFS" -eq 0 ]; then
  if confirm "Disable + mask NetworkManager-wait-online.service?"; then
    sudo systemctl disable --now NetworkManager-wait-online.service 2>&1 | tail -2
    sudo systemctl mask NetworkManager-wait-online.service 2>&1 | tail -1
  fi
fi

section "3. networking.service — legacy ifupdown, vestigial on NM-managed Mint"
echo "Mint 22 uses NetworkManager; /etc/network/interfaces typically has loopback only."
if confirm "Disable networking.service?"; then
  sudo systemctl disable --now networking.service 2>&1 | tail -2
fi

section "4. qemu-kvm.service — no libvirt VMs detected"
VMS=0
if command -v virsh >/dev/null 2>&1; then
  VMS=$(sudo virsh list --all 2>/dev/null | awk 'NR>2 && NF>0 && !/^-+$/' | wc -l)
fi
echo "Defined libvirt VMs: $VMS"
if [ "$VMS" -eq 0 ]; then
  if confirm "Disable qemu-kvm.service?"; then
    sudo systemctl disable --now qemu-kvm.service 2>&1 | tail -2
  fi
else
  echo "VMs defined — skipping."
fi

section "5. Ubuntu crash reporter (whoopsie + apport)"
if dpkg -l whoopsie 2>/dev/null | grep -q '^ii' || dpkg -l apport 2>/dev/null | grep -q '^ii'; then
  echo "whoopsie/apport package(s) installed."
  if confirm "Purge whoopsie + apport?"; then
    sudo apt purge -y whoopsie apport 2>&1 | tail -3
  fi
else
  echo "Neither installed — nothing to do."
fi

section "6. avahi-daemon — mDNS broadcaster (.local hostnames, Bonjour printers)"
echo "Disable unless you use .local hostname resolution, Chromecast, or LAN printer auto-discovery."
if confirm "Disable + mask avahi-daemon?"; then
  sudo systemctl disable --now avahi-daemon.service avahi-daemon.socket 2>&1 | tail -2
  sudo systemctl mask avahi-daemon.service 2>&1 | tail -1
fi

# ────────────── TIER 2: USER-LEVEL ──────────────

section "7. filter-chain.service — PipeWire LADSPA effects (unused unless configured)"
if systemctl --user list-unit-files filter-chain.service >/dev/null 2>&1; then
  if confirm "Mask filter-chain.service?"; then
    systemctl --user mask filter-chain.service 2>&1 | tail -1
  fi
else
  echo "filter-chain.service not present in user units — skipping."
fi

section "8. Cinnamon csd plugins for hardware you don't have"
echo "csd-wacom = Wacom tablet config (you have none)"
echo "csd-color = ICC color profile sync (only matters with calibrated displays)"
if confirm "Disable csd-wacom and csd-color plugins via dconf?"; then
  gsettings set org.cinnamon.settings-daemon.plugins.wacom active false 2>/dev/null \
    && echo "  ↳ csd-wacom disabled"
  gsettings set org.cinnamon.settings-daemon.plugins.color active false 2>/dev/null \
    && echo "  ↳ csd-color disabled"
fi

section "9. gvfs volume monitors — protocols you don't use (also in tame-services.sh §16 for afc/goa)"
echo "afc = Apple iPhone/iPad, goa = GNOME Online Accounts"
echo "mtp = Android phone via MTP, gphoto2 = digital cameras via PTP"
if confirm "Mask gvfs-afc + gvfs-goa volume monitors?"; then
  systemctl --user mask gvfs-afc-volume-monitor.service \
    gvfs-goa-volume-monitor.service 2>&1 | tail -2
fi
if confirm "Also mask gvfs-mtp + gvfs-gphoto2? (skip if you connect Android phones or cameras)"; then
  systemctl --user mask gvfs-mtp-volume-monitor.service \
    gvfs-gphoto2-volume-monitor.service 2>&1 | tail -2
fi

# ────────────── TIER 3: AUTOSTART OVERRIDES ──────────────

section "10. Heavy Mint tray applets — run on demand instead of at every login"
echo "mintUpdate (~150MB RSS) and mintreport-tray launch on login."
echo "Hiding only prevents AUTOSTART; you can still launch them from the menu."
if confirm "Hide mintupdate + mintreport autostart entries?"; then
  hide_autostart mintupdate.desktop
  hide_autostart mintreport.desktop
fi

# ────────────── DONE ──────────────

END_BOOT_SVCS=$(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l)
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Done."
echo "═══════════════════════════════════════════════════════════════"
echo "  Enabled units: $START_BOOT_SVCS  →  $END_BOOT_SVCS"
echo ""
echo "  Reboot required for autostart changes to take effect."
echo "  Service disables / masks are immediate."
echo ""
echo "  Undo helpers:"
echo "    autostart override:   rm ~/.config/autostart/<name>.desktop"
echo "    re-enable service:    sudo systemctl unmask <unit> && sudo systemctl enable --now <unit>"
echo "    re-enable user unit:  systemctl --user unmask <unit>"
echo "    re-enable csd plugin: gsettings set org.cinnamon.settings-daemon.plugins.<name> active true"
