#!/usr/bin/env bash
# Linux Mint SSD cleanup.
#
# Reclaims ~37 GB by clearing build/AI caches, purging apache+PHP+wine+opencode,
# running `apt autoremove` (drops old kernels), and clearing rc-state configs,
# journal, crash dumps, apt cache.
#
# Usage:
#   ./cleanup.sh
#
# Before running:
#   - Close VS Code, Cursor, Windsurf, Antigravity, Kiro, Expo dev server,
#     any Android emulator. Their caches are about to be wiped.
#   - You will be prompted for your sudo password once.
#
# To shrink Docker Desktop's 64 GB VM disk separately:
#   Docker Desktop -> Troubleshoot -> "Clean / Purge data"
#   (or Settings -> Resources -> Advanced -> lower the disk image size cap)

set -u

START_FREE=$(df -BG / | tail -1 | awk '{print $4}')
echo ">>> Starting. Free on /: $START_FREE"

# ───── User-space caches (no sudo) ─────

echo ""; echo "[1/9] Gradle build caches..."
du -sh ~/.gradle 2>/dev/null
rm -rf ~/.gradle/caches ~/.gradle/daemon ~/.gradle/build-cache
du -sh ~/.gradle 2>/dev/null

echo ""; echo "[2/9] npm cache..."
du -sh ~/.npm 2>/dev/null
npm cache clean --force 2>&1 | tail -2
du -sh ~/.npm 2>/dev/null

echo ""; echo "[3/9] Codeium / Windsurf embedding DBs (will re-index on next open)..."
find ~/.codeium -name 'embedding_database.sqlite' -print -delete 2>/dev/null

echo ""; echo "[4/9] Expo + pub cache + browser caches..."
rm -rf ~/.expo ~/.pub-cache ~/.cache/Google ~/.cache/mozilla ~/.cache/wine 2>/dev/null

echo ""; echo "[5/9] Wine + opencode user data + menu entries..."
rm -rf ~/.local/share/opencode ~/.config/opencode
rm -rf ~/.local/share/applications/wine
rm -f  ~/.local/share/applications/wine-extension-*.desktop
rm -f  ~/.config/menus/applications-merged/wine-*.menu
update-desktop-database ~/.local/share/applications 2>/dev/null || true

# ───── System-side (asks for password once) ─────

echo ""; echo "[6/9] Stop & purge apache + PHP (8.1 + 8.3)..."
sudo systemctl disable --now apache2 2>/dev/null || true
sudo apt purge -y \
  apache2 apache2-bin apache2-data apache2-utils \
  libapache2-mod-php8.3 libapache2-mod-php8.1 \
  php-common \
  php8.3 php8.3-cli php8.3-common php8.3-bcmath \
  php8.3-curl php8.3-mbstring php8.3-mysql php8.3-opcache \
  php8.3-readline php8.3-xml php8.3-zip \
  php8.3-gd php8.3-intl \
  php8.1-cli php8.1-common php8.1-curl php8.1-intl \
  php8.1-mbstring php8.1-opcache php8.1-readline \
  php8.1-xml php8.1-zip 2>&1 | tail -3
sudo rm -f /etc/apt/sources.list.d/ondrej-php-jammy.list

echo ""; echo "[7/9] Purge wine + opencode apt packages..."
sudo apt purge -y \
  winehq-stable wine-stable wine-stable-amd64 wine-stable-i386:i386 \
  opencode 2>&1 | tail -3
sudo rm -f /etc/apt/sources.list.d/winehq-jammy.sources

echo ""; echo "[8/9] autoremove (drops 22 old kernels + orphan deps)..."
sudo apt autoremove --purge -y 2>&1 | tail -3

echo ""; echo "[9/9] Purge rc-state configs + journal + crashes + apt cache..."
RC=$(dpkg -l 2>/dev/null | awk '/^rc/{print $2}')
[ -n "$RC" ] && echo "$RC" | sudo xargs apt purge -y 2>&1 | tail -3
sudo journalctl --vacuum-time=14d 2>&1 | tail -2
sudo rm -rf /var/lib/systemd/coredump/*
sudo apt clean
sudo apt update 2>&1 | tail -3

END_FREE=$(df -BG / | tail -1 | awk '{print $4}')
echo ""; echo ">>> Done. Free on /: was $START_FREE  →  now $END_FREE"
