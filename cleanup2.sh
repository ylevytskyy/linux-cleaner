#!/usr/bin/env bash
# Re-runnable Linux Mint cleanup (v2, 2026-09).
#
# Replaces the one-shot cleanup.sh (apache/php/wine purge — already done).
# Built from measured state: the big reclaimables now are Docker image/build
# cache (~10G), bun/pnpm/npm caches, unused flatpak runtimes and flatpak app
# caches. Safe caches are cleared automatically; anything costly to rebuild
# (Docker images, gradle, npm, old node versions) asks first; things that
# need a human decision (Movies, Data/wine, unused editors) are only reported.
#
# Deliberately NOT touched: ~/.expo (Expo CLI login), docker volumes (data),
# ~/.config/google-chrome (profile), project node_modules.
#
# Usage: ./cleanup2.sh

set -u

if [ "$(id -u)" -eq 0 ]; then  # under sudo, ~ would point at /root
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

if ! sudo -v 2>/dev/null; then
  echo "!!! No terminal for sudo password — sudo steps will fail."
  echo "!!! Run this script from a regular terminal window."
fi

free_on() { df -h "$1" | awk 'NR==2{print $4}'; }

echo ">>> Free: /: $(free_on /)   Data: $(free_on /media/lion/Data)"

# ───── Safe, automatic (regenerate cheaply) ─────

echo ""; echo "[1] bun install cache..."
du -sh ~/.bun/install/cache 2>/dev/null
rm -rf ~/.bun/install/cache

echo ""; echo "[2] pnpm store prune..."
pnpm store prune 2>&1 | tail -2 || true

echo ""; echo "[3] flatpak app caches (~/.var/app/*/cache)..."
du -shc ~/.var/app/*/cache 2>/dev/null | tail -1
RUNNING=$(flatpak ps --columns=application 2>/dev/null)
for d in ~/.var/app/*/cache; do
  app=$(basename "$(dirname "$d")")
  if grep -qx "$app" <<< "$RUNNING"; then echo "  skip $app (running)"; continue; fi
  rm -rf "${d:?}"/* 2>/dev/null
done

echo ""; echo "[4] unused flatpak runtimes..."
flatpak uninstall --unused --noninteractive -y 2>&1 | tail -3 || true

# ───── System-side (sudo) ─────

echo ""; echo "[5] apt autoremove + clean, rc-configs, journal 14d, crash dumps..."
AUTO=$(apt-get -s autoremove 2>/dev/null | awk '/^Remv/{print $2}')
if [ -n "$AUTO" ]; then
  echo "  autoremove would purge:"; echo "$AUTO" | sed 's/^/    /'
  if confirm "  Purge these packages?"; then sudo apt-get autoremove --purge -y; fi
fi
sudo apt-get clean
RC=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
if [ -n "$RC" ]; then
  echo "  leftover configs of removed packages:"; echo "$RC" | sed 's/^/    /'
  if confirm "  Purge these configs?"; then echo "$RC" | xargs sudo apt-get purge -y 2>&1 | tail -2; fi
fi
sudo journalctl --vacuum-time=14d 2>&1 | tail -1
sudo find /var/lib/systemd/coredump /var/crash -mindepth 1 -delete 2>/dev/null

# ───── Ask first (costly to rebuild) ─────

echo ""; echo "[6] Docker (native engine, /var/lib/docker):"
docker system df 2>/dev/null || echo "  docker not running"
echo "  Removes stopped containers, ALL unused images (next build re-pulls),"
echo "  and build cache. Volumes are NOT touched."
if confirm "  Prune docker?"; then
  docker container prune -f
  docker image prune -af
  docker builder prune -af
fi

echo ""; echo "[7] Gradle caches (next Android build re-downloads deps):"
du -sh ~/.gradle 2>/dev/null
if confirm "  Clear ~/.gradle caches?"; then
  pkill -f GradleDaemon 2>/dev/null  # running daemons break if caches vanish
  rm -rf ~/.gradle/caches ~/.gradle/daemon ~/.gradle/build-cache
fi

echo ""; echo "[8] npm cache:"
du -sh ~/.npm 2>/dev/null
if confirm "  Clear npm cache?"; then
  npm cache clean --force 2>&1 | tail -1
fi

echo ""; echo "[9] Old Node versions in nvm:"
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  KEEP=$(nvm version default)
  echo "  keeping default: $KEEP"
  for v in $(ls "$NVM_DIR/versions/node" 2>/dev/null); do
    [ "$v" = "$KEEP" ] && continue
    if confirm "  Remove node $v?"; then nvm uninstall "$v"; fi
  done
fi

# ───── Report only — your call, nothing deleted ─────

echo ""; echo "[10] Manual-decision items (NOT touched):"
du -sh \
  /media/lion/Data/Movies \
  /media/lion/Data/wine \
  /media/lion/Data/Android \
  /media/lion/Data/OneDrive \
  ~/.devin ~/.config/Devin ~/.config/Devin\ -\ Next \
  ~/.windsurf ~/.config/Windsurf ~/.windsurf-next ~/.config/Windsurf\ -\ Next \
  ~/.antigravity ~/.config/Antigravity \
  ~/.local/share/zed ~/.minikube \
  ~/.config/skypeforlinux \
  2>/dev/null | sort -rh
echo "  (Skype is discontinued — its config dir is dead data.)"
RUNNING_K="linux-image-$(uname -r)"
for k in $(apt-mark showmanual | grep -E '^linux-image-[0-9]'); do
  [ "$k" = "$RUNNING_K" ] && continue
  echo "  Old kernel held as manual (autoremove skips it): $k"
  echo "    to drop: sudo apt-mark auto $k && sudo apt-get autoremove --purge"
done

echo ""; echo ">>> Done. Free: /: $(free_on /)   Data: $(free_on /media/lion/Data)"
