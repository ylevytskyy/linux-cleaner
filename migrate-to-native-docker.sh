#!/usr/bin/env bash
# Migrate from Docker Desktop to native Docker Engine + Docker Compose v2 plugin
# on Linux Mint (Ubuntu jammy base).
#
# Strategy:
#   1. Inventory current state, warn about data loss inside Docker Desktop's VM.
#   2. Install docker-ce + containerd.io from Docker's official repo.
#   3. Stop & purge Docker Desktop; remove its 64 GB VM disk and integration files.
#   4. Remove obsolete docker-compose v1 standalone (Python).
#   5. Enable native docker.service; remove the desktop-linux context.
#   6. Verify with hello-world.
#
# Run in a real terminal (sudo needs a TTY). It is interactive — confirms before
# anything destructive.

set -u

confirm() {
  local msg="$1"
  local reply=""
  read -r -p "$msg [y/N]: " reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

require_root_sudo() {
  if ! sudo -n true 2>/dev/null; then
    echo "Will prompt for sudo now..."
    sudo -v || { echo "sudo refused — aborting."; exit 1; }
  fi
}

step() {
  echo ""
  echo "============================================="
  echo "  $1"
  echo "============================================="
}

# ───── 1. Pre-flight inventory ─────

step "1. Pre-flight inventory"
echo "Installed Docker apt packages:"
dpkg -l 2>/dev/null | grep -E '^ii\s+(docker|containerd)' | awk '{printf "  %-30s %s\n", $2, $3}'
echo ""
echo "Docker contexts:"
docker context ls 2>/dev/null
echo ""
echo "Active daemon (server version, blank if no daemon reachable):"
docker version --format '{{.Server.Version}}' 2>/dev/null || echo "(unreachable)"
echo ""
echo "Disk under ~/.docker:"
du -sh ~/.docker 2>/dev/null
du -sh ~/.docker/desktop 2>/dev/null
echo ""
echo "Default context's socket:"
docker context inspect default 2>/dev/null | grep -o '"Host": *"[^"]*"' | head -1

# ───── 2. Warn about Docker Desktop VM data ─────

step "2. Data warning"
cat <<'EOF'
Anything that lives ONLY inside Docker Desktop's VM (~/.docker/desktop/vms/0/data/Docker.raw)
will be destroyed. That includes images/containers/volumes you can see ONLY when
running:
    docker --context desktop-linux ...

To save an image first (back out and run separately if needed):
    docker --context desktop-linux save -o ~/Downloads/backup.tar <image:tag>

Your modern-tas stack (containers running on the default context / /var/run/docker.sock)
will also be stopped while the daemon is swapped. You'll relaunch it with:
    cd /media/lion/Data/Projects/modern-tas
    make poc-up-all-docker   # or: docker compose up -d
EOF
echo ""
confirm "Proceed with migration?" || { echo "Aborted."; exit 0; }

require_root_sudo

# ───── 3. Stop Docker Desktop & all running containers ─────

step "3. Stopping Docker Desktop + any running containers"
running=$(docker ps -q 2>/dev/null)
if [ -n "$running" ]; then
  echo "Stopping running containers (default context):"
  docker stop $running 2>&1 | sed 's/^/  /'
fi

# Stop Docker Desktop's user service & GUI
systemctl --user stop docker-desktop.service 2>/dev/null || true
systemctl --user disable docker-desktop.service 2>/dev/null || true
pkill -f 'Docker Desktop' 2>/dev/null || true
pkill -f 'docker-desktop' 2>/dev/null || true
pkill -f 'com.docker' 2>/dev/null || true
sleep 2
echo "Docker Desktop stopped."

# ───── 4. Install docker-ce + containerd.io ─────

step "4. Installing docker-ce + containerd.io from Docker's official repo"
# The Docker apt source already exists at /etc/apt/sources.list.d/docker.list
# (deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu jammy stable)
ls -la /etc/apt/sources.list.d/docker.list
sudo apt update
sudo apt install -y docker-ce containerd.io
# docker-ce-cli, docker-compose-plugin, docker-buildx-plugin already installed.

# ───── 5. Purge Docker Desktop apt package ─────

step "5. Purging docker-desktop apt package"
sudo apt purge -y docker-desktop

# Also drop the obsolete Python v1 docker-compose (use 'docker compose' plugin instead).
if dpkg -l docker-compose 2>/dev/null | grep -q '^ii\s'; then
  echo "Removing obsolete docker-compose v1 (Python) — use 'docker compose' (plugin v2) instead."
  sudo apt purge -y docker-compose
fi

# Sweep orphaned deps left by docker-desktop purge.
sudo apt autoremove --purge -y

# ───── 6. Remove Docker Desktop user data (~50 GB) ─────

step "6. Removing Docker Desktop user data (~50 GB inside ~/.docker/desktop)"
du -sh ~/.docker/desktop 2>/dev/null
rm -rf ~/.docker/desktop
rm -rf ~/.docker/run
rm -rf ~/.docker/cli-plugins/docker-compose 2>/dev/null  # Desktop's compose binary, if present

# Desktop integration in the OS
sudo rm -f /usr/share/applications/docker-desktop.desktop \
           /usr/share/applications/docker-desktop-uri-handler.desktop
rm -f ~/.config/autostart/docker-desktop*.desktop
rm -rf ~/.config/Docker\ Desktop 2>/dev/null

# Stray /usr/local/bin/docker installed by Docker Desktop installer (not from dpkg).
if [ -e /usr/local/bin/docker ] && ! dpkg -S /usr/local/bin/docker >/dev/null 2>&1; then
  echo "Removing /usr/local/bin/docker (not owned by a package — Docker Desktop installer)"
  sudo rm -f /usr/local/bin/docker
fi

# ───── 7. Reconfigure docker contexts ─────

step "7. Reconfiguring docker contexts"
# Switch to default context (native daemon's /var/run/docker.sock).
docker context use default 2>/dev/null || true
# Drop the desktop-linux context entirely.
docker context rm desktop-linux 2>/dev/null || true
docker context ls

# ───── 8. Enable native docker.service ─────

step "8. Enabling native docker.service"
sudo systemctl enable --now docker
sudo systemctl status docker --no-pager 2>&1 | head -10

# Make sure your user is in the docker group (already group 999 here, no-op if so).
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  echo "Adding $USER to docker group..."
  sudo usermod -aG docker "$USER"
  echo "NOTE: you'll need to log out & back in (or 'newgrp docker') for the group to take effect."
fi

# Refresh shell PATH lookup so 'docker' resolves to /usr/bin/docker (from docker-ce-cli)
# instead of the now-deleted /usr/local/bin/docker.
hash -r 2>/dev/null || true

# ───── 9. Verify ─────

step "9. Verification"
echo "Binary used:"
which docker
which docker-compose 2>/dev/null || echo "  (no docker-compose v1 — that's correct, use 'docker compose')"
echo ""
echo "Versions:"
docker version
echo ""
docker compose version
echo ""
echo "docker info (excerpt):"
docker info 2>&1 | grep -E 'Server Version|Storage Driver|Cgroup|Operating System|Kernel|CPUs|Total Memory|Docker Root Dir' | sed 's/^/  /'
echo ""
echo "Hello-world test (pulls 13 KB image, runs, removes):"
docker run --rm hello-world

step "Migration complete"
cat <<EOF

NEXT STEPS:
  - Re-launch your modern-tas stack:
      cd /media/lion/Data/Projects/modern-tas
      docker compose up -d         # or: make poc-up-all-docker
  - Verify your stack's containers come back up: docker ps
  - If 'docker' commands ask for sudo: log out & log back in (group membership).
  - Disk freed: was '$(du -sh ~/.docker 2>/dev/null | awk '{print $1}')' (post-cleanup) under ~/.docker.

If you ever want Docker Desktop back:
  sudo apt install docker-desktop
EOF
