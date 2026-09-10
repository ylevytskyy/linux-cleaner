#!/usr/bin/env bash
# Disable services flagged as redundant by the 4-subagent service audit.
#
# Stack assumed: Expo RN + C/C++ + Docker/Compose + NestJS + Android dev,
# Linux Mint Cinnamon on HP ProBook 650 G2 laptop.
#
# Interactive — confirms before each section. Verifies preconditions where
# possible (no LVM, no libvirt VMs, no L2TP profiles, no NFS in fstab).
#
# Runs sudo only when needed. One sudo prompt at the first section requiring it.

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
  local name="$1"
  mkdir -p ~/.config/autostart
  printf '[Desktop Entry]\nType=Application\nName=disabled\nHidden=true\n' \
    > "$HOME/.config/autostart/$name"
  echo "  ↳ hid $name (override at ~/.config/autostart/$name)"
}

START_BOOT_SVCS=$(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | wc -l)
echo ">>> Starting service audit cleanup. Enabled units at start: $START_BOOT_SVCS"

# ────────────── TIER 1: HIGH CONFIDENCE (verified preconditions) ──────────────

section "1. ZFS suite — no ZFS pool detected"
if sudo zpool list 2>&1 | grep -q 'no pools available\|^$'; then
  echo "Confirmed: no zpools on this system. ext4 root."
  if confirm "Disable zfs-zed + 5 boot units?"; then
    sudo systemctl disable --now zfs-zed.service 2>&1 | tail -2
    sudo systemctl disable zfs-import-cache.service zfs-load-module.service \
      zfs-mount.service zfs-share.service zfs-volume-wait.service 2>&1 | tail -3
  fi
else
  echo "ZFS pool found — skipping."
fi

section "2. LVM monitoring — checking for any LVM/device-mapper volumes"
LVS_OUT=$(sudo lvs --noheadings 2>/dev/null | wc -l)
DM_OUT=$(sudo dmsetup ls 2>/dev/null | grep -v 'No devices' | wc -l)
echo "LVM logical volumes: $LVS_OUT   |   device-mapper devices: $DM_OUT"
if [ "$LVS_OUT" -eq 0 ] && [ "$DM_OUT" -eq 0 ]; then
  if confirm "Disable lvm2-monitor + dm-event.socket + lvm2-lvmpolld.socket?"; then
    sudo systemctl disable --now lvm2-monitor.service 2>&1 | tail -2
    sudo systemctl disable dm-event.socket lvm2-lvmpolld.socket 2>&1 | tail -2
  fi
else
  echo "Device-mapper / LVM found — keeping LVM services."
fi

section "3. libvirt suite — checking for any defined VMs"
if command -v virsh >/dev/null 2>&1; then
  VMS=$(sudo virsh list --all 2>/dev/null | awk 'NR>2 && NF>0 && !/^-+$/' | wc -l)
  echo "Defined libvirt VMs: $VMS"
  if [ "$VMS" -eq 0 ]; then
    if confirm "Disable libvirtd + sockets + virtlockd + virtlogd + libvirt-guests?"; then
      sudo systemctl disable --now virtlockd.service virtlogd.service 2>&1 | tail -2
      sudo systemctl disable --now libvirtd.socket libvirtd-admin.socket libvirtd-ro.socket 2>&1 | tail -2
      sudo systemctl disable libvirtd.service libvirt-guests.service 2>&1 | tail -2
    fi
  else
    echo "VMs found in libvirt — keeping."
  fi
else
  echo "virsh not available — skipping."
fi

section "4. cups-browsed — UNCONDITIONAL disable (CVE-2024-47176, CVSS 9.9)"
echo "Unauthenticated RCE in cups-browsed listening on UDP 631 (all interfaces)."
echo "Manual printer setup still works after disabling — only auto-discovery is lost."
if confirm "Disable cups-browsed?"; then
  sudo systemctl disable --now cups-browsed.service 2>&1 | tail -2
fi

section "5. ModemManager — no cellular modem; interferes with Arduino + ADB"
if confirm "Disable ModemManager.service?"; then
  sudo systemctl disable --now ModemManager.service 2>&1 | tail -2
fi

section "6. kerneloops — auto-submits kernel crashes upstream (privacy)"
if confirm "Disable kerneloops.service?"; then
  sudo systemctl disable --now kerneloops.service 2>&1 | tail -2
fi

section "7. motd-news — Ubuntu MOTD promotional fetcher"
if confirm "Disable motd-news.timer?"; then
  sudo systemctl disable motd-news.timer 2>&1 | tail -2
fi

section "8. casper — Live-ISO leftover on installed system"
if dpkg -l casper 2>/dev/null | grep -q '^ii'; then
  if confirm "Purge casper package?"; then
    sudo apt purge -y casper 2>&1 | tail -3
  fi
fi

section "9. e2scrub_all.timer — only useful with LVM ext4"
if confirm "Disable e2scrub_all.timer?"; then
  sudo systemctl disable e2scrub_all.timer 2>&1 | tail -2
fi

section "10. winbind — Samba domain auth (no AD here)"
if confirm "Disable winbind.service?"; then
  sudo systemctl disable --now winbind.service 2>&1 | tail -2
fi

section "11. networkd-dispatcher — using NetworkManager, not networkd"
if confirm "Disable networkd-dispatcher.service?"; then
  sudo systemctl disable --now networkd-dispatcher.service 2>&1 | tail -2
fi

section "12. NetworkManager-wait-online — slows boot, no NFS/CIFS mounts"
HAS_NFS=$(grep -cE 'nfs|cifs|smbfs' /etc/fstab 2>/dev/null || echo 0)
echo "NFS/CIFS entries in /etc/fstab: $HAS_NFS"
if [ "$HAS_NFS" -eq 0 ]; then
  if confirm "Disable NetworkManager-wait-online.service?"; then
    sudo systemctl disable NetworkManager-wait-online.service 2>&1 | tail -2
  fi
fi

section "13. RDP servers — gnome-remote-desktop + xrdp + xrdp-sesman"
echo "Only relevant if you connect *to* this laptop FROM another machine via RDP."
if confirm "Disable BOTH RDP servers?"; then
  sudo systemctl disable --now gnome-remote-desktop.service 2>&1 | tail -2
  sudo systemctl disable xrdp.service xrdp-sesman.service 2>&1 | tail -2
  hide_autostart pipewire-xrdp.desktop
fi

section "14. L2TP/IPsec VPN stack — checking for L2TP profiles"
L2TP_PROFILES=$(nmcli connection show 2>/dev/null | grep -ci l2tp || echo 0)
echo "L2TP NetworkManager profiles: $L2TP_PROFILES"
if [ "$L2TP_PROFILES" -eq 0 ]; then
  if confirm "Disable strongswan-starter + xl2tpd + openvpn (you only use Tailscale)?"; then
    sudo systemctl disable --now strongswan-starter.service xl2tpd.service 2>&1 | tail -2
    sudo systemctl disable openvpn.service 2>&1 | tail -2
  fi
else
  echo "L2TP profiles found — keeping VPN services."
fi

# ────────────── TIER 2: USER-LEVEL SERVICES ──────────────

section "15. Evolution user services (no Evolution use)"
if confirm "Mask Evolution background services + alarm autostart?"; then
  systemctl --user mask evolution-addressbook-factory.service \
    evolution-calendar-factory.service evolution-source-registry.service 2>&1 | tail -3
  hide_autostart org.gnome.Evolution-alarm-notify.desktop
fi

section "16. Apple File Conduit + GNOME Online Accounts + IBus"
echo "gvfs-afc = iPhone/iPad USB (you do Android), gvfs-goa = GOA (Cinnamon doesn't use it), IBus = CJK input (Ukrainian uses XKB)"
if confirm "Disable all three user services + im-launch autostart?"; then
  systemctl --user disable --now gvfs-afc-volume-monitor.service \
    gvfs-goa-volume-monitor.service 2>&1 | tail -2
  systemctl --user disable org.freedesktop.IBus.session.GNOME.service 2>&1 | tail -1
  hide_autostart im-launch.desktop
fi

section "17. GNOME Keyring SSH agent (often clashes with OpenSSH/1Password)"
echo "Only the SSH-agent component — secrets/WiFi passwords stay working."
if confirm "Mask gcr-ssh-agent + hide gnome-keyring-ssh autostart?"; then
  systemctl --user mask gcr-ssh-agent.socket gcr-ssh-agent.service 2>&1 | tail -2
  hide_autostart gnome-keyring-ssh.desktop
fi

# ────────────── TIER 3: AUTOSTART NO-OPS / DUPLICATES ──────────────

section "18. nvidia-prime autostart (HP ProBook 650 G2 = Intel-only graphics)"
if confirm "Hide nvidia-prime autostart?"; then
  hide_autostart nvidia-prime.desktop
fi

section "19. polkit-mate-authentication-agent (Cinnamon uses GNOME polkit)"
if confirm "Hide polkit-mate-authentication-agent-1 autostart?"; then
  hide_autostart polkit-mate-authentication-agent-1.desktop
fi

section "20. spice-vdagent autostart (only useful inside a SPICE VM)"
if confirm "Hide spice-vdagent autostart?"; then
  hide_autostart spice-vdagent.desktop
fi

section "21. mintwelcome autostart (first-boot greeter)"
if confirm "Hide mintwelcome autostart?"; then
  hide_autostart mintwelcome.desktop
fi

section "22. geoclue-demo-agent (literally the demo, not production geoclue)"
if confirm "Hide geoclue-demo-agent autostart?"; then
  hide_autostart geoclue-demo-agent.desktop
fi

section "23. onboard + orca (on-screen keyboard + screen reader)"
echo "Only relevant if you use accessibility tools."
if confirm "Hide both autostart entries?"; then
  hide_autostart onboard-autostart.desktop
  hide_autostart orca-autostart.desktop
fi

section "24. warpinator (Mint LAN file transfer)"
if confirm "Hide warpinator-autostart?"; then
  hide_autostart warpinator-autostart.desktop
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
echo "  Service disables are immediate."
echo ""
echo "  To undo any autostart override:    rm ~/.config/autostart/<name>"
echo "  To re-enable a service:            sudo systemctl enable --now <unit>"
echo "  To unmask a user unit:             systemctl --user unmask <unit>"
