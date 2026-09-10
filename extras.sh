#!/usr/bin/env bash
# Optional / interactive cleanup for items that might still be in use.
# Asks before each section.
#
# Run AFTER cleanup.sh (or independently).
# Reclaim depends on your answers; typical total: 5-20 GB.

set -u

confirm() {
  local msg="$1"
  local reply=""
  read -r -p "$msg [y/N]: " reply </dev/tty
  [[ "$reply" =~ ^[Yy]$ ]]
}

show_size() {
  [ -e "$1" ] && du -sh "$1" 2>/dev/null
}

section() {
  echo ""
  echo "─────────────────────────────────────────────"
  echo "  $1"
  echo "─────────────────────────────────────────────"
}

START_FREE=$(df -BG / | tail -1 | awk '{print $4}')
echo ">>> Optional cleanups. Free on /: $START_FREE"

# ───── 1. Android AVDs ─────
if [ -d ~/.android/avd ]; then
  section "Android AVDs"
  du -sh ~/.android/avd/* 2>/dev/null
  if [ -d ~/.android/avd/Android_36.1_API_16.avd ]; then
    if confirm "Delete AVD 'Android_36.1_API_16' (~8.7 GB)?"; then
      rm -rf ~/.android/avd/Android_36.1_API_16.avd*
      echo "  -> deleted"
    fi
  fi
  echo "(Other AVDs left alone. Delete via Android Studio Device Manager if needed.)"
fi

# ───── 2. Genymotion ─────
if [ -d ~/.Genymobile ]; then
  section "Genymotion data"
  show_size ~/.Genymobile
  if confirm "Remove ALL Genymotion data (~3.3 GB)? App stays installed."; then
    rm -rf ~/.Genymobile ~/.config/Genymobile
    echo "  -> deleted"
  fi
fi

# ───── 3. Flatpak unused ─────
if command -v flatpak >/dev/null 2>&1; then
  section "Flatpak: unused runtimes + per-app data"
  echo "Installed apps:"
  flatpak list --app --columns=application 2>/dev/null | sed 's/^/  /'
  echo ""
  echo "Per-app data sizes in ~/.var/app:"
  du -hxd1 ~/.var/app 2>/dev/null | sort -rh | head -10
  echo ""
  if confirm "Run 'flatpak uninstall --unused' to clean orphaned runtimes?"; then
    flatpak uninstall --unused
  fi
  echo ""
  echo "To uninstall a specific Flatpak app, run:"
  echo "  flatpak uninstall <application-id>"
  echo "Its data in ~/.var/app/<application-id> is then safe to rm."
fi

# ───── 4. ~/.lldb (debugger artifacts) ─────
if [ -d ~/.lldb ]; then
  section "~/.lldb (debugger cache)"
  show_size ~/.lldb
  echo "Top entries:"
  ls -lh ~/.lldb 2>/dev/null | head -8
  if confirm "Delete ~/.lldb? Rebuilt automatically if you use lldb."; then
    rm -rf ~/.lldb
    echo "  -> deleted"
  fi
fi

# ───── 5. Swiftly (Swift toolchain on Linux) ─────
if [ -d ~/.local/share/swiftly ]; then
  section "Swift toolchain (~/.local/share/swiftly)"
  show_size ~/.local/share/swiftly
  if confirm "Remove Swift toolchain (~1.9 GB)? Only if you don't write Swift on Linux."; then
    rm -rf ~/.local/share/swiftly ~/.config/swiftly ~/.swiftly 2>/dev/null
    echo "  -> deleted. Also remove the swiftly line from your shell rc if present."
  fi
fi

# ───── 6. nvm — list Node versions ─────
if [ -d ~/.nvm/versions/node ]; then
  section "Installed Node versions (via nvm)"
  ls ~/.nvm/versions/node 2>/dev/null | sed 's/^/  /'
  echo ""
  echo "To remove an old version (do this in your interactive shell, not here):"
  echo "  nvm uninstall v18.17.0   # example"
  echo "(Skipping auto-uninstall because sourcing nvm in a sub-shell is brittle.)"
fi

# ───── 7. AI IDE workspaceStorage + cache ─────
section "AI IDE workspaceStorage / CachedData / logs"
ide_dirs=(
  "$HOME/.config/Code"
  "$HOME/.config/Cursor"
  "$HOME/.config/Windsurf"
  "$HOME/.config/Windsurf - Next"
  "$HOME/.config/Antigravity"
  "$HOME/.config/Kiro"
)
total_ide=0
for d in "${ide_dirs[@]}"; do
  if [ -d "$d" ]; then
    for sub in "User/workspaceStorage" "CachedData" "CachedExtensions" "logs"; do
      if [ -d "$d/$sub" ]; then
        size_b=$(du -sb "$d/$sub" 2>/dev/null | awk '{print $1}')
        printf "  %8s  %s/%s\n" "$(du -sh "$d/$sub" 2>/dev/null | awk '{print $1}')" "$d" "$sub"
        total_ide=$((total_ide + ${size_b:-0}))
      fi
    done
  fi
done
echo "  (total: ~$((total_ide / 1024 / 1024)) MB)"
if confirm "Wipe workspaceStorage + CachedData + CachedExtensions + logs in ALL listed IDEs?"; then
  for d in "${ide_dirs[@]}"; do
    if [ -d "$d" ]; then
      rm -rf "$d/User/workspaceStorage" "$d/CachedData" "$d/CachedExtensions" "$d/logs" 2>/dev/null
    fi
  done
  echo "  -> wiped. IDEs rebuild on next open (per-project history is lost)."
fi

# ───── 8. wps-office package (1.6 GB) ─────
if dpkg -l wps-office 2>/dev/null | grep -q '^ii'; then
  section "wps-office (apt package, ~1.6 GB)"
  if confirm "Purge wps-office?"; then
    sudo apt purge -y wps-office
  fi
fi

# ───── 9. mint-cursor-themes (372 MB) ─────
if dpkg -l mint-cursor-themes 2>/dev/null | grep -q '^ii'; then
  section "mint-cursor-themes (~372 MB)"
  echo "Hundreds of cursor themes preinstalled. Mint replaces with a stub if purged."
  if confirm "Purge mint-cursor-themes?"; then
    sudo apt purge -y mint-cursor-themes
  fi
fi

# ───── 10. Snap residue ─────
if [ -d /var/lib/snapd/snaps ] && dpkg -l snapd 2>/dev/null | grep -q '^rc'; then
  section "Snap residue (snapd already in rc state, 819 MB on disk)"
  if confirm "Fully purge snapd + remove /var/lib/snapd, /snap, ~/snap?"; then
    sudo apt purge -y snapd
    sudo rm -rf /var/lib/snapd /snap ~/snap
  fi
fi

# ───── 11. ~/Downloads — list old, don't delete ─────
if [ -d ~/Downloads ]; then
  section "~/Downloads — files older than 180 days"
  count=$(find ~/Downloads -type f -mtime +180 2>/dev/null | wc -l)
  size=$(find ~/Downloads -type f -mtime +180 -printf '%s\n' 2>/dev/null \
         | awk '{s+=$1}END{printf "%.1f MB\n", s/1024/1024}')
  echo "  $count files, total $size"
  echo ""
  echo "To list them:"
  echo "  find ~/Downloads -type f -mtime +180 -ls"
  echo "(Not auto-deleted — review yourself before any rm.)"
fi

# ───── 12. AI IDE app uninstall reminder ─────
section "AI IDE collection (manual decision)"
echo "You have 6 AI IDEs installed in parallel:"
echo "  code (645 MB)        windsurf (919 MB)      cursor      kiro (767 MB)"
echo "  antigravity (690 MB) windsurf-next (919 MB)"
echo ""
echo "Picking 2 you actually use can free 1.5-3 GB of apt + matching ~/.config dirs."
echo "Example removals:"
echo "  sudo apt purge -y windsurf-next antigravity kiro"
echo "  rm -rf ~/.config/'Windsurf - Next' ~/.config/Antigravity ~/.config/Kiro"
echo "  rm -rf ~/.codeium/windsurf-next"

END_FREE=$(df -BG / | tail -1 | awk '{print $4}')
echo ""
echo ">>> Done. Free on /: was $START_FREE  ->  now $END_FREE"
