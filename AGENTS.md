# AGENTS.md

Instructions for AI coding agents working in this repository. Read this
first, then `docs/plan.md`.

## What this project is

Afterimage is a private photo and video backup for one household: Immich,
packaged as Home Assistant apps for a Raspberry Pi 5 (aarch64, 4 GB RAM).
Phones use the stock Immich app. This repository is the Home Assistant app
repository and is the only repository used.

An earlier design (a custom iOS app and Go server) was dropped on 26 Nov
2026. Work only from `docs/plan.md`. The repository is public and has one
branch, `main`.

## Current phase

Update this at the end of every phase.

- **Phase:** 3 (Traefik and the domain). Phase 2 is done: the Immich app
  runs on the Pi with the previous library restored (4 users, about 44,700
  assets). The Traefik app for `photos.dpool.dev` (Cloudflare DNS-01) is
  written and passes its container test; next is installing it on the Pi
- **NAS layout:** `/data/immich` on the NAS, exported over NFS and mounted in
  Home Assistant as `Immich`. `library`, `thumbs`, `encoded-video`, `profile`
  and `backups` are separate ZFS datasets; originals are in
  `library/library` and `library/upload`. Do not move datasets: the app's
  folder options map this layout as it is
- **Last result from the Pi:** restore of the previous Immich worked; photos
  and videos visible (26 Nov 2026)

## Hard rules

- Never put the database on the network share. It lives in the app's `/data`.
- Never start Immich unless the share path is a real mount point, and never
  create folders under `/share/<name>` before that check passes. A missing
  mount must mean "wait", never "write to the Pi's disk".
- Never commit secrets: DNS tokens, passwords, hostnames the owner has not
  made public. Generate what can be generated on the device.
- Pin versions (Immich, PostgreSQL major, VectorChord with its checksum).
  Never `latest`.
- Take Immich and Home Assistant facts from their current documentation, not
  from memory. Both changed a lot in 2026 (Immich is at v3, Home Assistant
  renamed add-ons to apps and moved the docs to
  `contributors.home-assistant.io`). `docs/plan.md` lists what was confirmed
  and where.
- Nothing may proxy Immich with buffering or a short read timeout.
- Do not copy code from other Immich add-on repositories. Read them for
  behaviour only and check licences.

## Build, test and run

From the repository root, on an Apple silicon Mac with Apple's `container`
tool (or set `CONTAINER_CLI=docker` on an arm64 Linux machine):

```
scripts/smoke-test.sh          build the Immich app and run its smoke test
scripts/traefik-smoke-test.sh  build the Traefik app and run its smoke test
```

The matching smoke test must pass before any change to `immich/` or
`traefik/` is committed.

## Conventions

- Shell: `bash`, `set -Eeuo pipefail`, no dependencies beyond what the Immich
  image and Debian packages provide.
- Keep the app's options few. Every option needs an entry in `immich/DOCS.md`.
- Commits: small, one change each, message says what and why.
