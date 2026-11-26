# Afterimage

Private photo and video backup for one household. iPhones and iPads send new
photos and videos to a server at home, in the background, without anyone
opening an app.

> **Status:** planning complete, nothing built yet. Phase 0 (device
> experiments) is next. See [docs/plan.md](docs/plan.md).

## How it works

```
iPhone or iPad                        Home Assistant OS (Raspberry Pi 5)
┌───────────────────────────┐        ┌──────────────────────────────────┐
│ Afterimage app            │        │ afterimage-server (Go)           │
│   setup and status only   │        │   HTTPS, accounts, uploads       │
│ Upload extension          │ HTTPS  │   SQLite database on the Pi      │
│   queues new photos       │ ─────► │                                  │
│ iOS upload service        │        └───────────────┬──────────────────┘
│   sends when it can       │                        │ finished files
└───────────────────────────┘                        ▼
                                             Network share (NAS)
```

- **The app** signs a person in once and shows backup status.
- **The extension** is a PhotoKit Background Resource Upload extension. iOS
  wakes it when the photo library changes, and it queues upload jobs.
- **iOS itself** performs each upload, so backups run with the app closed and
  the device locked.
- **The server** receives each file, checks it against what it already has,
  and stores it on the network share under `/<person>/<year>/<month>/`.

## What it does

- Backs up every photo and video, including Live Photo videos, RAW files and
  edited versions
- Works for several people, each with their own account and folder
- Sign-in by account key: paste or scan once, and a person's other devices
  set themselves up through iCloud Keychain
- Skips anything the server already holds
- Keeps a per-person activity log and status for troubleshooting
- Makes a nightly backup of everything needed to rebuild the server
- Planned later: files encrypted on disk under one master password, and a
  record of albums, folders and favourites

## What it does not do

- It is not a photo viewer. Files are stored, not browsed.
- It does not sync back to devices or delete anything from them.
- It never deletes a stored file because a device deleted the photo.
- It does not compress or re-encode. Stored files are identical to the
  originals.
- It is not distributed through the App Store.

## Requirements

| Part | Needs |
| --- | --- |
| Devices | iOS or iPadOS 27 or later |
| Server | Home Assistant OS on a 64-bit ARM board (built for Raspberry Pi 5) |
| Storage | An SMB or NFS share, mounted by Home Assistant as Share storage |
| Network | A hostname you control, with DNS that supports DNS-01 certificates |
| Building | A Mac with Xcode, and an Apple developer account for installing on several people's devices |

## Repository layout

```
ios/       App and upload extension
server/    Go server
ha-app/    Home Assistant OS app packaging
spikes/    Phase 0 experiments
docs/      Plan and agent brief
```

## Documentation

- [docs/plan.md](docs/plan.md): phases, tasks, risks and sources
- [docs/agent-brief.md](docs/agent-brief.md): decisions made, open questions
  and rules for whoever is building
- [AGENTS.md](AGENTS.md): instructions for AI coding agents

## Setup

Installation steps will be written as each part is built. In outline:

1. Mount the network share in Home Assistant as Share storage.
2. Install the Afterimage app in Home Assistant and give it the hostname and
   DNS provider token.
3. Create a person in the admin page and hand them their account key.
4. Install the iOS app on their device, paste or scan the key, and allow full
   photo access.

## Security notes

- Account keys can upload only. There is no download or browse API.
- The server stores hashes of keys, never the keys themselves.
- Admin functions are reachable only from inside Home Assistant.
- Secrets (DNS token, keys, signing files, master password) are never
  committed to this repository.

## Known limits

- iOS decides when uploads run. Expect a delay of minutes to hours, with most
  activity overnight on the charger.
- The first backup of a large library takes days.
- Some parts of the Photos library are not available to apps, including
  Memories, People and Pets, and Recently Deleted.
