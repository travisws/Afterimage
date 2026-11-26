# AGENTS.md

Instructions for AI coding agents working in this repository. Read this file
first in every session, then `docs/agent-brief.md`, then `docs/plan.md`.

## What this project is

Afterimage is a private photo and video backup system for one household.

- **iOS/iPadOS app** (iOS 27+), named Afterimage, with a PhotoKit Background
  Resource Upload extension. It backs up each person's photo library with the
  app closed and the device locked.
- **Go server** (`afterimage-server`), packaged as a Home Assistant OS app for
  a Raspberry Pi 5 (aarch64). It serves HTTPS itself, keeps SQLite on the Pi,
  and stores all files on a network share.

It is not an App Store product. It is installed on the household's own
devices only.

## Source of truth

| Document | Holds |
| --- | --- |
| `docs/agent-brief.md` | Decisions already made, open questions, hard rules, API facts |
| `docs/plan.md` | Phases, task lists, "done when" tests, risk register, sources |

If these documents conflict with your prior knowledge, the documents and
Apple's linked documentation win. If they conflict with each other or with
what you observe, stop and ask the owner.

## Repository layout

Proposed layout. Confirm it with the owner before creating files.

```
ios/       App and upload extension (Xcode project)
server/    Go server
ha-app/    Home Assistant OS app packaging (config.yaml, Dockerfile)
spikes/    Phase 0 throwaway experiments
docs/      Plan, agent brief, notes
```

## Current phase

Update this section at the end of every phase.

- **Phase:** 0 (spikes) not yet run on devices. Spike app and log server
  are being built.
- **Owner's instruction, 26 Nov 2026:** build as much of the backend as
  possible now, before the spikes run, and test it as far as it can be tested
  without a phone. This waives the "Phase 0 first" order for server work that
  does not depend on device captures: Phase 1 Step A (plain upload), the
  server parts of Phase 3 (mount guard, snapshots, backups, restore) and a
  draft of the Home Assistant packaging.
- **Still gated on device results:** the resumable upload protocol (Phase 1
  Step B), the real iOS app (Phase 2), and Phases 6 and 7.
- **Blocked on:** values and decisions from the owner (see the brief); none
  answered yet. The DNS-01 certificate step waits for the DNS provider.
- **Last result from the owner's devices:** none yet

## How to work

1. Work one phase at a time, in the order in `docs/plan.md`.
2. At the end of each phase, report what was built, how it was tested, what
   could not be tested, and what the owner needs to run. Then wait.
3. The upload extension does not run in Simulator. The owner runs builds on
   real devices and returns logs. Plan around that loop.
4. If a spike fails, or anything contradicts the documents, stop and report
   before designing around it.
5. Do not ask about anything the brief marks as decided. Do ask about
   anything it marks as open.
6. Keep this file and the "Current phase" section up to date.

## Before writing PhotoKit code

Open and read Apple's page "Uploading asset resources in the background"
(linked in the brief). Take every type and method name from it. This API
shipped in iOS 26.1 and changed in iOS 27; do not write it from memory.

Use `PHBackgroundResourceUploadJobExtension`. Never use the deprecated
`PHBackgroundResourceUploadExtension`. The extension is a Generic Extension
target with extension point `com.apple.photos.background-upload`. It is not a
photo editing extension or a share extension.

## Hard rules

Server and network:

- No HTTP proxy, buffering, compression or middleware in front of the upload
  route. The server terminates TLS itself.
- Admin functions only on the internal Home Assistant ingress listener, which
  accepts connections only from `172.30.32.2`. Never on the public listener.
- Build plain upload first and prove it with a real phone. Then build
  resumable upload to the headers captured from a real device, not to the
  IETF draft or to memory.
- Never answer an upload in progress with `413` or `500`.
- Never trust a person or folder name sent by a client. Identity comes from
  the token.
- If the network share is not mounted, refuse uploads with `503`. Never write
  photos to the Pi's own disk.
- The live SQLite database stays on the Pi, never on the network share.

Data:

- No whole files in memory, on the server or in the extension.
- No compression and no re-encoding. Stored files are byte-identical to the
  originals.
- The backup never deletes a stored file because a device deleted the asset.

Secrets:

- Never commit or log account keys, device tokens, the DNS provider token,
  signing material or the master password.
- Store only hashes of account keys and device tokens.
- Keys never expire or rotate on their own.

App:

- iOS and iPadOS 27 or later only.
- Dark theme only. Two screens: setup and status.
- Uploads may use mobile data. Build no Wi-Fi-only switch.
- Log to a file in the App Group container from the first build. The system
  starts and kills the extension without leaving a crash report.

Process:

- Tests before features on the server. The interrupted-upload,
  duplicate-upload, and backup-and-restore tests must keep passing.
- Encryption (Phase 6) and library structure (Phase 7) are built only after
  the owner confirms transfer works end to end.
- Do not copy code from the open-source projects named in the brief. Read
  them for behaviour only.

## Build, test and run commands

None exist yet. Add the exact commands here as each part is created, and keep
them current:

- Server: build, test, lint, run locally
- iOS: build for device, run unit tests
- Home Assistant app: build the image, install locally
- Spikes: how to run each one and where its logs go

## Conventions

- Go: standard `gofmt` formatting, `log/slog` structured logging, static
  build (`CGO_ENABLED=0`, `GOARCH=arm64`), pure-Go SQLite driver.
- Swift: follow the project's existing style once it exists; shared code
  between app and extension goes in a shared target.
- Commits: small and focused, one logical change each, message says what
  changed and why.
- Do not add dependencies without saying why in the commit or pull request.

## What not to do

- Do not start a later phase early.
- Do not add features, settings or screens the plan does not list.
- Do not introduce another database, a message queue or a web framework
  without asking.
- Do not "fix" a failing spike by changing what it tests.
