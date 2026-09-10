# linux-cleaner

Disk-cleanup and service-taming scripts for a Linux Mint dev machine
(Expo/RN + Android + Docker + NestJS stack, HP ProBook 650 G2).

Two generations: the May 2026 one-shot audit scripts, and the current
re-runnable `cleanup2.sh`.

## Current

### `cleanup2.sh` — re-runnable cleanup (use this one)

Safe caches are cleared automatically (bun, pnpm store, flatpak app caches,
unused flatpak runtimes, apt autoremove/clean, rc-configs, journal >14d,
crash dumps). Anything costly to rebuild asks first via y/N prompts read from
`/dev/tty`: Docker prune (containers, unused images, build cache — volumes
untouched), gradle caches, npm cache, old nvm Node versions. Items needing a
human decision (Movies, unused editors, SDKs) are only reported, never deleted.

Deliberately not touched: `~/.expo` (Expo CLI login), Chrome profile,
Docker volumes, project `node_modules`.

Run from a real terminal (sudo + prompts need a TTY); without one it warns
and skips instead of failing silently:

```
./cleanup2.sh
```

## Legacy (May 2026 audit, one-shot — already applied on this machine)

- **`cleanup.sh`** — the original one-shot: cleared build/AI caches, purged
  apache2 + PHP 8.1/8.3 + wine + opencode packages, dropped old kernels via
  autoremove, cleaned journal/crash dumps/apt cache. Its package targets are
  long gone, so re-running it mostly no-ops.
- **`extras.sh`** — interactive follow-up for items that might still be in
  use; asks before each section (typical extra reclaim 5–20 GB).
- **`safe-purge.sh`** — high-confidence purge list from a 5-subagent audit
  (e.g. openvpn/strongswan/xl2tpd dead weight next to Tailscale). Verifies
  preconditions per section; overlaps items 1–2 of `tame-services.sh`.
- **`tame-services.sh`** — disables services flagged redundant by the service
  audit (no LVM, no libvirt VMs, no L2TP, no NFS). Interactive, precondition
  checks per section.
- **`migrate-to-native-docker.sh`** — one-time migration from Docker Desktop
  (64 GB VM disk) to native docker-ce + Compose v2. Already done: this
  machine runs the native engine.
- **`notes.md`** — the May 2026 audit report the legacy scripts were built
  from (method, ranked space hogs, estimates).
