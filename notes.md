# Linux Mint SSD Cleanup — Audit Notes

**Date:** 2026-05-21
**Host:** Linux Mint on `/dev/sda5` (231 GB ext4 root)
**Initial state:** 187 GB used, 33 GB free (**86% full**) ⚠️

---

## TL;DR

- Estimated safe reclaim: **~37 GB** via `cleanup.sh` (this directory).
- Optional reclaim: another **~20 GB** via `extras.sh` (interactive).
- Biggest single win: **Docker Desktop VM disk** (64 GB) — GUI shrink, not scripted.

---

## Method

Parallel `du`/`find`/`dpkg-query` scans of:
- Filesystem (`df -hT`, `df -i`)
- Top-level dirs of `/`, `~`, `~/.cache`, `~/.local/share`, `~/.config`
- `/var/log`, `/var/cache/apt/archives`, `/var/lib/systemd/coredump`
- Installed kernels, rc-state packages, top 25 apt packages by size
- Docker, Snap, Flatpak disk usage
- Trash, Downloads (files >180 days)

---

## Top space hogs (ranked)

### Discovered in `~` (136 GB total)

| Rank | Path | Size | Status |
|---|---|---:|---|
| 1 | `~/.docker/desktop/vms/0/data/Docker.raw` | **64 GB** | Docker Desktop VM — shrink via GUI (see below) |
| 2 | `~/.gradle/caches`/`daemon`/`build-cache` | **14 GB** | `cleanup.sh` step 1 |
| 3 | `~/.var/app/*` | **11 GB** | Flatpak per-app data — manual triage (see "Not touched") |
| 4 | `~/.android/avd/Android_36.1_API_16.avd*` | **8.7 GB** | `extras.sh` (interactive) |
| 5 | `~/.config/Code` + `Cursor` + `Windsurf` + `Antigravity` + `Kiro` + `Windsurf - Next` | **~6.8 GB** | `extras.sh` (workspaceStorage wipe) |
| 6 | `~/.codeium` (3× embedding DBs, 3× Chromium) | **5.4 GB** | `cleanup.sh` step 3 (embedding DBs) |
| 7 | `~/.npm` | **4.5 GB** | `cleanup.sh` step 2 |
| 8 | `~/.nvm` (multiple Node versions) | **3.7 GB** | `extras.sh` — manual `nvm uninstall` |
| 9 | `~/.Genymobile` | **3.3 GB** | `extras.sh` (interactive) |
| 10 | `~/.local/share/swiftly` | **1.9 GB** | `extras.sh` (interactive) |
| 11 | `~/.lldb` | **1.9 GB** | `extras.sh` (interactive) |
| 12 | `~/.local/share/Google` | **1.5 GB** | leave (Chrome installs) |
| 13 | `~/.pub-cache` | **1.7 GB** | `cleanup.sh` step 4 |
| 14 | `~/.windsurf` + `~/.windsurf-next` | **2.2 GB** | leave (IDE state) |
| 15 | `~/.vscode` | **1.6 GB** | leave (extensions you use) |
| 16 | `~/.expo` | **1.6 GB** | `cleanup.sh` step 4 |
| 17 | `~/.mozilla` | **2.2 GB** | leave (Firefox profile) |

### Discovered system-side

| Item | Size | Status |
|---|---:|---|
| 23 installed kernels + 21 rc-state | **~10 GB** | `cleanup.sh` step 8 (`apt autoremove --purge`) |
| 137 rc-state packages (configs only) | small | `cleanup.sh` step 9 |
| Snap (already in `rc` state) | 819 MB | Optional: `sudo apt purge snapd && sudo rm -rf /var/lib/snapd /snap ~/snap` |
| `/var/log` | 1.4 GB | `cleanup.sh` step 9 (journal vacuum) |
| `/var/cache/apt/archives` | 208 KB at audit time | `cleanup.sh` step 9 |
| `/var/lib/systemd/coredump` | 3 dumps (antigravity crashes) | `cleanup.sh` step 9 |

### Top installed apt packages (largest)

| Size | Package | Note |
|---:|---|---|
| 1.6 GB | `wps-office` | Optional purge (`extras.sh`) |
| 919 MB × 2 | `windsurf` + `windsurf-next` | Two parallel Windsurf installs |
| 767 MB | `kiro` | AI IDE |
| 690 MB | `antigravity` | AI IDE (crashing — see `/var/lib/systemd/coredump`) |
| 645 MB | `code` | VS Code |
| 611 MB | `linux-firmware` | Keep |
| 403 MB | `google-chrome-stable` | Keep |
| 372 MB | `mint-cursor-themes` | Hundreds of cursor themes — purge candidate |
| 322 MB | `qemu-efi-aarch64` | Only needed if running ARM64 VMs |
| 15× ~336 MB | `linux-modules-extra-5.15.0-*` | Cleared by autoremove |

---

## Docker Desktop VM disk — 64 GB (GUI only)

Cannot be scripted — requires Docker Desktop UI.

**Two routes:**

1. **Shrink the cap:** Settings → Resources → Advanced → lower "Disk image size" → Apply & Restart. Docker Desktop creates a smaller image and copies data.
2. **Purge all:** Troubleshoot (bug icon, top right) → "Clean / Purge data" → confirm.

Your `modern-tas` stack runs on **native Docker** (separate context), so purging Docker Desktop's data won't affect it.

After either:
```bash
ls -lh ~/.docker/desktop/vms/0/data/Docker.raw
df -h /
```

---

## What `cleanup.sh` does (in order)

1. Wipes `~/.gradle/caches`, `daemon`, `build-cache` (~14 GB)
2. `npm cache clean --force` (~4.5 GB)
3. Deletes Codeium/Windsurf `embedding_database.sqlite` files (~2.7 GB; rebuilt on next open)
4. Removes `~/.expo`, `~/.pub-cache`, browser caches (`Google`, `mozilla`, `wine`) (~3 GB)
5. Removes Wine + opencode leftover user data + Cinnamon menu entries
6. Purges apache2 + PHP 8.1 + PHP 8.3 (+ removes Sury PHP repo)
7. Purges wine + opencode apt packages (+ removes WineHQ repo)
8. `apt autoremove --purge` — drops old kernels + orphaned deps (~10 GB)
9. Purges 137 rc-state packages, vacuums journal to 14 days, removes coredumps, `apt clean`

---

## What `extras.sh` covers (interactive — asks before each)

- Android AVDs in `~/.android/avd/`
- Genymotion (`~/.Genymobile`)
- Flatpak unused runtimes
- `~/.lldb` (debugger artifacts)
- `~/.local/share/swiftly` (Swift toolchain on Linux)
- IDE `workspaceStorage`/`CachedData`/`CachedExtensions`/`logs` for Code, Cursor, Windsurf, Antigravity, Kiro
- `wps-office` package
- Lists old Node versions (manual `nvm uninstall`)
- Lists `~/Downloads` files >180 days (manual review)

---

## Items deliberately NOT cleaned (and why)

| Path | Why kept |
|---|---|
| `~/.docker` (full) | Docker Desktop data — shrink via GUI instead |
| `~/.vscode` (1.6 GB) | Your installed VS Code extensions |
| `~/.windsurf` / `~/.cursor` / `~/.claude` | IDE state you actively use |
| `~/.mozilla` | Firefox profile (bookmarks, history) |
| `~/.local/share/Google` | Chrome installs |
| `~/.local/share/claude` | Claude Code data |
| `~/.local/share/zed` | Zed editor data |
| `~/.config/google-chrome` | Chrome profile |
| `~/.codeium/**/chromium*` (3× 413 MB) | Codeium's bundled browser — Windsurf needs it |
| `~/.android/avd` (sans the named target) | Other AVDs you may use |
| `~/.npm/_logs` only would be safer than full clean — but `npm cache clean --force` is the official command, treated as safe |

---

## Observations worth flagging

### You have 6 AI IDEs installed in parallel

VS Code, Cursor, Windsurf, Windsurf-Next, Antigravity, Kiro — plus Claude Code (CLI), Codeium (Windsurf's engine), opencode.

Each ships its own Electron/Chromium runtime (~400 MB), per-project caches, and extension store. Picking 2 you actually use frees several GB of apt + matching `~/.config` data.

### `antigravity` is crashing

Three coredumps in `/var/lib/systemd/coredump/` from `antigravity` over the last few days. If you don't use it, this is dead weight + recurring crash noise.

### Two Android emulator stacks

Android Studio AVDs (`~/.android` 8.7 GB) **and** Genymotion (`~/.Genymobile` 3.3 GB). Most devs only use one.

### `mint-cursor-themes` is 372 MB

Linux Mint preinstalls hundreds of cursor themes you'll never use. `sudo apt purge mint-cursor-themes` is safe; Mint replaces it with a stub theme.

### Sury PHP repo + WineHQ repo

Third-party APT repos for software you don't use any more. `cleanup.sh` removes both.

---

## Investigation commands (for digging deeper)

```bash
# Top dirs in ~ (regenerates the audit)
du -hxd1 ~ 2>/dev/null | sort -rh | head -20

# Largest files in ~ over 200 MB
find ~ -xdev -type f -size +200M -printf '%s\t%p\n' 2>/dev/null \
  | sort -rn | head -15 | awk '{printf "%6.1f MB  %s\n", $1/1024/1024, $2}'

# Top 25 installed apt packages by size
dpkg-query -W -f='${Installed-Size}\t${Package}\n' 2>/dev/null \
  | sort -rn | head -25 | awk '{printf "%6.1f MB  %s\n", $1/1024, $2}'

# rc-state packages (uninstalled but configs still around)
dpkg -l | awk '/^rc/{print $2}'

# Inspect Flatpak per-app data
du -hxd2 ~/.var/app 2>/dev/null | sort -rh | head -10
flatpak list --app --columns=application,size

# Per-IDE config size
for d in ~/.config/Code ~/.config/Cursor ~/.config/Windsurf \
         ~/.config/Antigravity ~/.config/Kiro "~/.config/Windsurf - Next"; do
  du -sh "$d" 2>/dev/null
done

# What's pinning a big apt package
apt-cache rdepends --installed <package>
```

---

## Ongoing maintenance

- **Monthly:** `sudo apt autoremove --purge && sudo journalctl --vacuum-time=14d && sudo apt clean`
- **After Docker work:** `docker system prune` (the conservative form is fine)
- **Quarterly:** Re-run the investigation commands above; build-tool caches refill fast (Gradle, npm, codeium)
- **Whenever Mint's Update Manager prompts about old kernels:** accept it. Don't accumulate 23 again.
