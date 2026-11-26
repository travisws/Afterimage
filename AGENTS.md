# AGENTS.md

Instructions for AI coding agents working in this repository. Read this
first, then `docs/plan.md`.

## What this project is

Afterimage is a private photo and video backup for one household: Immich,
packaged as Home Assistant apps for a Raspberry Pi 5 (aarch64, 4 GB RAM).
Phones use the stock Immich app. This repository is the Home Assistant app
repository and is the only repository used.

An earlier design (a custom iOS app and Go server) was dropped on 26 Nov
2026. Its documents are on the `afterimage-docs` branch and are not current.

## Current phase

Update this at the end of every phase.

- **Phase:** 1 (the Immich app image), in progress
- **Blocked on:** nothing for Phase 1. Phase 2 needs the owner's values
  listed at the end of `docs/plan.md`
- **Last result from the Pi:** none yet

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
scripts/smoke-test.sh          build the image and run the full smoke test
```

The smoke test must pass before any change to `immich/` is committed.

## Conventions

- Shell: `bash`, `set -Eeuo pipefail`, no dependencies beyond what the Immich
  image and Debian packages provide.
- Keep the app's options few. Every option needs an entry in `immich/DOCS.md`.
- Commits: small, one change each, message says what and why.
