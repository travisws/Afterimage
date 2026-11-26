# Afterimage: Immich on Home Assistant OS

Battle plan, written 26 Nov 2026. This replaces the earlier plan (custom iOS
app and Go server), which is no longer the direction.

## Goal

Private photo and video backup for one household of about five people.
Phones use the stock Immich app. The server is Immich, packaged as a Home
Assistant app that installs from this repository and runs on a Raspberry Pi 5
(aarch64, 4 GB RAM) without hand configuration beyond a few options.

## What gets built

```
iPhone or iPad                       Home Assistant OS on the Pi 5
  Immich app  ── HTTPS ──►  Traefik app          TLS (DNS-01 certificate), port 443
                              │ HTTP on the internal app network
                              ▼
                            Afterimage app (one container)
                              Immich server      pinned release, machine learning off
                              PostgreSQL         data on the Pi, in the app's /data
                              Valkey             job queue, in memory only
                              │
                              ▼
                            NAS share (Home Assistant network storage, usage "Share")
                              /share/<storage>/immich/library, upload, profile   originals
                              /share/<storage>/immich/backups                     database dumps
                              /share/<storage>/immich/thumbs, encoded-video       generated files
```

Two apps live in this repository: `immich/` (the Afterimage app) and
`traefik/`. Nothing else is needed on the Pi.

## Decisions

| Topic | Decision |
| --- | --- |
| Repository | `travisws/Afterimage` only, public, one branch (`main`). Home Assistant installs the app by adding this repository's URL |
| Packaging | One Home Assistant app, one container: Immich server, PostgreSQL and Valkey together, started and watched by one small supervisor script. `arch: aarch64` |
| Immich version | Pinned to an exact release in the Dockerfile (v3.4.2 today). Updated on purpose, never `latest` |
| Machine learning | Off. No machine-learning container. Immich's own docs say 4 GB machines should run this way |
| Database | PostgreSQL inside the app, data in `/data/postgres` on the Pi. Never on the share: Immich's docs forbid network shares for the database |
| Originals | On the NAS share, in Immich's `library`, `upload` and `profile` folders |
| Database dumps | Immich's built-in daily dump, written to `backups/` on the share, last 14 kept. A second dump is taken into `/data` just before every Home Assistant backup |
| Generated files | Thumbnails and transcoded video also on the share for now, so the Pi's disk holds only the database. Revisit if browsing is slow |
| Mount guard | The app refuses to start Immich unless the share path is a real mount point, and stops Immich if the mount disappears. Immich's own `.immich` folder markers are a second check |
| Settings | Generated from the app's options into an Immich config file, so a fresh install comes up already trimmed. This locks those settings in Immich's web UI. An option turns this off |
| Web access | Immich cannot be served under a sub-path, so no Home Assistant ingress. The app page has an Open Web UI button to port 2283, and Traefik serves the real hostname |
| TLS and port 443 | Traefik app in this repository: Let's Encrypt by DNS-01, one router to the Immich app over the internal network, upload timeouts raised |
| Image build | On the Pi from the Dockerfile. Later, GitHub Actions can build the image and Home Assistant pulls it instead (Phase 7) |

## Facts confirmed from current documentation

Read on 26 Nov 2026. Re-check before relying on any of them after an Immich or
Home Assistant update.

| Fact | Source |
| --- | --- |
| Latest Immich release is v3.4.2. Images: `ghcr.io/immich-app/immich-server`, database `ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0`, cache `valkey/valkey:9` | [release](https://github.com/immich-app/immich/releases/latest), [docker-compose.yml](https://github.com/immich-app/immich/blob/main/docker/docker-compose.yml) |
| Minimum 6 GB RAM; "For systems with only 4GB of RAM, Immich can be run with machine learning features disabled". Runs on arm64. Database files are typically 1 to 3 GB and must never be on a network share | [requirements](https://docs.immich.app/install/requirements) |
| Media folders are `upload`, `library`, `thumbs`, `encoded-video`, `profile`, `backups`. At start Immich checks a `.immich` marker in each and fails to start if one is missing | [system integrity](https://docs.immich.app/administration/system-integrity) |
| Only `library`, `upload` and `profile` hold original content | [backup and restore](https://docs.immich.app/administration/backup-and-restore) |
| Automatic database dumps go to `backups/` (default daily 02:00, keep 14) and can be restored from the web UI, including on a fresh install ("Restore from backup" on the welcome screen) | [backup and restore](https://docs.immich.app/administration/backup-and-restore) |
| `IMMICH_MEDIA_LOCATION` (default `/data`) sets the media path inside the container; `IMMICH_CONFIG_FILE` points at a JSON or YAML config and disables editing those settings in the web UI | [environment variables](https://docs.immich.app/install/environment-variables), [config file](https://docs.immich.app/install/config-file) |
| Config keys used here: `machineLearning.enabled`, `ffmpeg.transcode`, `job.<name>.concurrency`, `backup.database.{enabled,cronExpression,keepLastAmount}`, `storageTemplate.{enabled,template}`, `newVersionCheck.enabled`, `nightlyTasks.*`, `server.externalDomain` | [config file](https://docs.immich.app/install/config-file) |
| A standard PostgreSQL (14 to 19) works with pgvector plus VectorChord and `shared_preload_libraries = 'vchord.so'`. Immich calls this "not officially recommended". Automatic dumps need a superuser | [pre-existing Postgres](https://docs.immich.app/administration/postgres-standalone) |
| Behind a proxy Immich must be at the root of a hostname, and the proxy must allow large, unbuffered uploads. Traefik's default 60 s entry-point `readTimeout` cuts video uploads; raise `transport.respondingTimeouts` | [reverse proxy](https://docs.immich.app/administration/reverse-proxy) |
| A Home Assistant app repository needs `repository.yaml` at the root (`name` required); apps are found at any depth. The Supervisor clones with Git. An app's identity includes a hash of the repository URL, so changing the URL makes it a different app | [repository guide](https://contributors.home-assistant.io/apps/guides/repository/) |
| `config.yaml`: `arch` is `aarch64` or `amd64`; `image` makes the Supervisor pull instead of build, with the tag equal to `version`; `map` entries have `type`, `read_only`, `path`; `backup_pre`, `backup_exclude`, `watchdog`, `webui`, `ports`, `timeout` (10 to 300) | [configuration reference](https://contributors.home-assistant.io/apps/reference/configuration/) |
| Any base image is allowed. Without S6 overlay keep `init: true`. Options arrive in `/data/options.json`. Build arguments `BUILD_ARCH` and `BUILD_VERSION` | [Dockerfile guide](https://contributors.home-assistant.io/apps/guides/dockerfile/), [options guide](https://contributors.home-assistant.io/apps/guides/options/) |

## Phases

Each phase ends with something that can be checked.

### Phase 1: the Immich app image

Built and passing `scripts/smoke-test.sh` in an arm64 Linux container on
26 Nov 2026. Not yet run on the Pi.

- [x] `immich/` app folder: `config.yaml`, `Dockerfile`, supervisor and
      helper scripts, generated Immich config, `DOCS.md`
- [x] PostgreSQL 17 with pgvector and VectorChord 0.4.3 (the release Immich's
      own database image uses, pinned by checksum), Valkey, and Immich v3.4.2
      in one image
- [x] First start: database created with a generated password kept in
      `/data`, media folders created on the share
- [x] Mount guard at start (tested). The same check runs every 15 s while
      running and stops Immich if the mount goes away; that path is written
      but cannot be exercised in the container test, so test it on the Pi by
      taking the NAS offline
- [x] Clean shutdown: Immich, then Valkey, then PostgreSQL, inside the stop
      timeout (tested: no forced kill, no crash recovery on the next start)
- [x] Pre-backup dump script (tested by running it). Home Assistant calling
      it, and the `backup_exclude` pattern, can only be checked on the Pi
- [x] Smoke test: server answers; an upload lands on the share byte for byte
      and is filed under `library/<person>/<year>/<month>/`; machine learning
      off and the other managed settings in effect; a restart keeps the data

**Done when:** the container passes the smoke test from a clean start and
after a restart, and refuses to run Immich when the share folder is not a
mount. **Met**, in the container.

### Phase 2: on the Pi, home network only

- [x] Mount the NAS in Settings > System > Storage with usage Share (NFS,
      named `Immich`, 26 Nov 2026)
- [ ] Add this repository in Home Assistant, install the app, check the
      storage name, start
- [ ] Create the admin and one account per person, each with a storage label
      so files land in `library/<person>/<year>/<month>/`
- [ ] Upload from one phone on Wi-Fi with the Immich app
- [ ] Watch memory on the Pi during a large first upload

**Done when:** a photo taken on a phone shows up on the NAS in that person's
folder, and the Pi stays out of swap trouble.

### Phase 3: Traefik, hostname and certificate

- [ ] `traefik/` app: static config from options (hostname, DNS provider,
      API token as a password option, ACME email), DNS-01 certificate stored
      in its `/data`, port 443
- [ ] One router for the Immich hostname to the Immich app on the internal
      network, with `readTimeout` raised for long uploads and no buffering
- [ ] Split DNS: the hostname points at the Pi at home; public record only if
      backups should also run away from home
- [ ] If the DNS provider is Cloudflare, keep the record DNS-only

**Done when:** a video over 1 GB uploads through the real hostname from
home Wi-Fi and, if public, from mobile data.

### Phase 4: backup and restore drill

- [ ] Confirm a dump appears in `backups/` on the share each night
- [ ] Restore drill on another machine: fresh app, same share, "Restore from
      backup", then spot-check 20 files
- [ ] Decide how the NAS itself is backed up; until then this is one copy

**Done when:** a fresh install pointed at the share comes back with every
person's library intact.

### Phase 5: family rollout

- [ ] Immich app on each phone, signed in, background backup on
- [ ] Write down what each person must do once per device
- [ ] Check after a week that every person has recent uploads

### Phase 6: watching it

- [ ] Home Assistant alerts: no upload from a person for N days, share not
      mounted, newest dump older than 48 hours, app restarted by the watchdog
- [ ] Update routine: read the Immich release notes, change the pinned
      version, rebuild, restore drill before big version jumps

### Phase 7: prebuilt image

- [ ] GitHub Actions builds the arm64 image to GHCR; `image:` added to
      `config.yaml`, so the Pi pulls instead of building
- [ ] Keep the repository URL unchanged: Home Assistant ties the app's
      identity to it

## Risks

| Risk | Likelihood | Effect | Answer |
| --- | --- | --- | --- |
| 4 GB RAM is below Immich's stated minimum | Medium | Slow or killed during big uploads | Machine learning off, low job concurrency, transcoding off, watch memory in Phase 2 |
| NAS not mounted at boot or dropped later; Home Assistant then shows an empty local folder | High over a year | Files written to the Pi's own disk, or Immich fails | Mount-point check before start and every 30 s; Immich's `.immich` markers |
| SMB share lacks Unix ownership and permissions, which Immich recommends | Medium | Odd permission errors, slow thumbnails | Prefer NFS if the NAS offers it; test in Phase 2 |
| PostgreSQL built from Debian packages instead of Immich's own database image | Medium | A version mismatch after an Immich update | Pin extension versions; Immich checks the VectorChord version at start and refuses to run if wrong; restore drill before upgrades |
| Home Assistant's hot backup copies a live database folder | Certain if left default | Unusable copy in the backup | Exclude the raw folder; dump before each backup instead |
| Immich update with breaking changes | Medium | Server will not start after an update | Version pinned; `breaking_versions` in `config.yaml`; read release notes first |
| A person deletes a photo in Immich | Certain eventually | Original removed after the trash period | This is a synced library, not an append-only archive. Trash is kept 30 days. NAS-level snapshots are the real protection |
| iOS background upload is limited by the system | Certain | Uploads delayed until the phone is charging or the app is opened | Set expectations; stale-upload alert in Phase 6 |
| Traefik cuts long uploads at 60 s | Certain if left default | Videos fail | `respondingTimeouts` raised in the shipped config |
| Files on the NAS are not encrypted | Certain | Anyone with NAS access can open them | Immich has no encryption at rest. Use the NAS's own volume encryption if wanted |
| Backup exists only on one NAS | Certain | Single point of loss | Phase 4 decision |

## What I need from the owner

- The hostname for Immich, and the DNS provider (the API token goes into the
  Traefik app's options, never into this repository)
- What the Pi boots from (SD card or SSD) and its free space
- Whether a Traefik app is already installed on the Pi, and whether anything
  holds port 443
- Whether backups should run away from home (public DNS record) or only at
  home
- The people who get accounts

## Dropped from the earlier plan

The custom iOS app and upload extension, the Go server, the phone spikes, and
encryption at rest with a master password. Those documents were removed on
26 Nov 2026 at the owner's request.
