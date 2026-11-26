# Afterimage: Photo Backup Project Plan

Nov 26, 2026 · @Travis

## Summary

The project is buildable in roughly 5–8 weekends including encryption and library mirroring. Two unknowns can each sink it, so the plan starts with one to two weekends of throwaway experiments before any real code.

**What gets built:** an iOS/iPadOS app with a PhotoKit background upload extension, and a Go server packaged as a Home Assistant OS app on the Pi 5 that serves HTTPS itself with a DNS-01 certificate, keeps its database on the Pi and stores all files on the network share.

**The two project-killers, in order of danger:**

1. **iCloud Photos may stop the extension from ever running.** A developer reported on iOS 26.4 that the system never schedules the extension while iCloud Photos is on. Apple engineers called it unintended, and the thread shows no fix as of June 2026 ([Apple forum](https://developer.apple.com/forums/thread/822256)). If your household uses iCloud Photos and this still happens on your iOS version, the whole approach needs a fallback.
2. **The upload protocol is a moving draft.** Apple requires the server to speak the IETF resumable-upload draft, including a `104` interim response. Apple's own documentation example uses header names from an early draft, while the current draft has renamed them. The only safe move is to capture what a real iPhone sends and build to that.

**Designed out:** an earlier version of this plan put Traefik in front as an HTTP proxy, which risked it dropping the `104` response and cutting uploads at 60 seconds. The Go server now terminates TLS itself, so no proxy reads the upload traffic.

**Good news from the final review:** plain, non-resumable uploads appear to need no special server protocol. An open-source app sends these jobs to ordinary S3 upload URLs ([Shoebox](https://github.com/jstdlee/shoebox)), and Apple's page says a server without resumable support answers the preflight with `501`. So Phase 1 gets plain upload working first, and resume becomes an upgrade for large videos instead of a gate.

**Recommended order:** Phase 0 spikes, backend (plain upload, then resumable), iOS app, HA OS packaging, port and DNS, hardening and rollout, then encryption (Phase 6) and library structure (Phase 7). Overall difficulty stays about 6/10 if the spikes pass. It rises to 8/10 if the iCloud Photos problem is real for you, because the fallback is the old, harder background approach.

**Assumption used throughout:** the 5 accounts are 5 household members, each with their own Apple Account and devices, signing in with an account key you issue, all uploading to one server and hostname.

**Handing off to a building agent:** give it Agent brief first, then this tab.

**Name, repository and look:** the app and the project are called Afterimage. All code lives in `travisws/Afterimage` (`gh repo clone travisws/Afterimage`). The app is dark-themed only, with about a minute of interface (setup and status), so the icon carries the identity: a near-black tile with a faint, ghosted photo frame fading into the dark.

## Architecture

Each file travels as one HTTPS request from iOS to the NAS. (The original
document has a drawn diagram here; this is the same content as text.)

```
iPhone or iPad
  Your app             Account key, settings, status. Key syncs via iCloud Keychain
    -> Upload extension   Finds new photos, creates one upload job per file
                          (the unproven step, tested in Phase 0)
    -> iOS upload service Apple-run; sends files when power and network allow
         |
         | HTTPS: one request per file, resumable
         v
Home Assistant OS on the Pi 5
  Traefik (optional)   Passes TLS through untouched. Only if it already holds 443
    -> Go backup app      Own TLS, keys, resumable uploads, dedupe by hash
    -> Local database     SQLite in the app's /data. Never on the network share
         |
         | finished files only
         v
NAS share              Photos by person and month. Mounted by HA OS as a share
```

The app only signs people in and shows status; the extension queues jobs; iOS itself performs the transfer, which is why the server must follow Apple's protocol exactly.

Design choices that follow from the research:

- **One request per file, raw body.** The system sends the asset bytes as the raw HTTP body, not multipart, so all metadata travels in headers ([Immich discussion](https://github.com/immich-app/immich/discussions/23245)). Apple confirms one destination URL per resource and no chunking ([Apple forum](https://developer.apple.com/forums/thread/818566)).
- **Server address is compiled in.** `BackgroundUploadURLBase` lives in the extension's Info.plist ([Apple docs](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)). Fine for a personal build with one server; changing hostname means a rebuild.
- **Account keys, not passwords.** You generate one account key per person on the server and hand it over; they paste it (or scan a QR code) once. The app saves it as an iCloud-synced Keychain item, so their other devices find it and set themselves up with no pasting. Each device then trades the key for its own device token, stores it in a Keychain access group shared with the extension, and each job carries it in its `Authorization` header.
- **Database stays local.** SQLite on an SMB share risks lock corruption, so it lives in the app's `/data` (included in HA backups) and only photo files go to the NAS.
- **Write then rename.** Uploads land in a temp folder on the same share and are renamed into place only when complete and hashed, so a half-file never looks like a backup.

* **TLS lives in the backend.** The Go server gets and renews its own Let's Encrypt certificate by DNS-01 (CertMagic or lego) and serves HTTPS directly. If port 443 on the Pi is free, it listens there. If Traefik already holds 443, Traefik forwards this one hostname by TLS passthrough and never decrypts it. The server code is the same either way; only the listen port differs.

- **The network share holds everything needed to recover.** Home Assistant OS mounts the SMB or NFS share (Settings > System > Storage) and the app uses it through its mapped folder; the app does not mount anything itself. Photos, in-progress uploads and (from Phase 6) the key file live on the share. The live database is the one exception: it runs from `/data`, and the server writes a consistent snapshot of it to the share after each upload batch and at least daily. If the Pi dies, a new install pointed at the share restores the snapshot and carries on.

* **Admin lives behind Home Assistant, never on the public port.** Adding people, showing QR codes, disabling, restoring and the status view are a Home Assistant ingress page served from a second, internal listener that accepts connections only from the Supervisor's ingress address `172.30.32.2` ([HA developer docs](https://developers.home-assistant.io/docs/apps/presentation)). The public listener exposes only enrol, upload and a device's own status. A command line on HA OS is awkward to reach, so the page is the main interface.
* **Mount the NAS as a Share, not as Media.** Media storage appears in Home Assistant's media browser ([forum](https://community.home-assistant.io/t/2023-6-network-storage-feature-experiences-and-questions/579663/46)), which would let any HA user browse family photos before Phase 6. Share storage mounts under `/share/<name>`. Home Assistant's automatic backups leave out both the media and share folders ([HA docs](https://www.home-assistant.io/common-tasks/general/backups/)).
* **Resume links are unguessable.** The upload URL returned in `Location` contains a long random value and is enough on its own to continue that one upload, because it is not known whether iOS repeats the `Authorization` header on resume requests.
* **One library, several devices.** An iPhone and iPad on the same iCloud library would each upload everything. The app sends Apple's cloud identifier for each asset, which Apple recommends for backing an asset up only once across devices ([Apple forum](https://developer.apple.com/forums/thread/774303)), and asks the server what it already has before queueing. One report says the identifier can differ between devices ([Apple forum](https://developer.apple.com/forums/thread/843934)), so the content hash stays the final check.
* **Folder dates and name clashes.** The year and month folder comes from the capture date in the device's local time, sent by the app, so a photo taken late on 31 December does not land in the next year. Two different files with the same name in one folder get a short hash suffix. Assets with no capture date go to an `undated` folder.
* **Each device needs one visit.** A synced account key removes the pasting, but the person still has to install the app on each device, open it once and allow full photo access.

### Privacy: one master password (added last, in Phase 6)

Once plain transfer is proven, every stored file is encrypted so that nobody browsing the NAS or the Pi can see names or open anything, and one master password restores everything.

- **One key pair for the whole server.** The server generates it at setup. The public half encrypts files. The private half is itself encrypted with the owner's master password and saved as a small key file; the password is never stored.
- **Stored files** use the `age` format under random names, with original filename and dates inside. The database keeps the pre-encryption SHA-256 so dedupe still works.
- **Restore command:** type the master password, pick a person or everyone, pick an output folder; files come back with original names. The password and unlocked key live in memory only.
- **Changing the password** only re-encrypts the small key file, not the photos.
- **Two things must both survive:** the master password and the key file. Keep a copy of the key file on the NAS beside the photos and in Home Assistant backups (it is useless without the password), and write the password down somewhere safe. Lose either and nothing can be recovered.
- **Password strength matters.** Anyone holding the drive can guess passwords offline against the key file, so use a long passphrase (five or more random words) and a slow key-derivation setting.
- Limits: the server sees each file unencrypted while receiving it, and only the owner can restore. This hides everything from casual browsing and protects a stolen drive.
- Checked: the `age` Go library documents streaming encryption to recipients and passphrase (scrypt) protection, and its command-line tool supports passphrase-protected key files (pkg.go.dev/filippo.io/age). Confirm the exact calls at the start of Phase 6.

## Phase 0: spikes before real code (1–2 weekends)

Ten throwaway experiments decide whether the design above survives. Run them in this order; stop and rethink if 1 or 2 fails.

| # | Spike | How | Pass means | If it fails |
| --- | --- | --- | --- | --- |
| 1 | Does the extension run with iCloud Photos on? | Minimal app + extension on a real device (not Simulator), your normal iCloud Photos setting, uploads pointed at a request-logging server. On iOS 27, turn on Resource Upload Test Mode under Settings > Developer. | `processJobs()` is called and a request arrives | Check Console.app for the `assetsd` "Result: NO" line from the [forum report](https://developer.apple.com/forums/thread/822256). Fallback: background `URLSession` + `BGProcessingTask`, or turn iCloud Photos off. |
| 2 | What does iOS really send? | Log every header of the `OPTIONS` and `POST` from spike 1, especially `Upload-Draft-Interop-Version`, `Upload-Complete` vs `Upload-Incomplete`, and whether your `Authorization` header is on the `OPTIONS`. | You know the exact draft version to implement | Build to the captured headers, not to any document |
| 3 | Does a `104` survive Traefik? | 30-line Go server that sends `104` then `201`; `curl -v` direct, then through Traefik on HTTP/1.1 and HTTP/2. | `104` visible through Traefik on both | TCP router fallback (Phase 4) |
| 4 | Does an interrupted upload resume? | Upload a 1 GB+ video from the device, kill Wi-Fi halfway, restore it. | Server sees an offset query and an append, not a restart from byte 0 | Large videos will restart forever on weak connections; fix protocol handling before going on |
| 5 | Does the account key sync between devices? | Save a Keychain item with `kSecAttrSynchronizable` in a shared access group on one device; read it on a second device on the same Apple Account, from both the app and the extension. | Second device reads the key with no user action | Fall back to pasting or scanning a QR code per device |
| 6 | Can uploads go to a host other than the compiled-in base URL? | Set BackgroundUploadURLBase to one hostname and give a job a destination on a different one. One developer says the base URL is only a connectivity check (Immich discussion #23245); Apple has not confirmed it. | Upload arrives at the second host; the server address can then travel inside the account key | Keep the hostname compiled in; changing it means a rebuild |
| 7 | Does a plain upload work with no resumable support? | Server answers the OPTIONS preflight with 501 and accepts the POST body as an ordinary upload. | File arrives intact; Phase 1 can ship plain upload first | Resumable support is mandatory; do the protocol work before anything else |
| 8 | What do resume requests carry? | During spike 4, log every header on the offset query and the append request. | You know whether Authorization and your custom headers are repeated | No change: the unguessable upload URL already identifies the upload |
| 9 | Does the system upload over mobile data? | Wi-Fi off, mobile data on, add photos. Repeat with allowsCellularAccess set to false on the job's request. | You know the default, and whether the flag is honoured | Tell people uploads may use mobile data, or keep the server home-only |
| 10 | Does a signed build outside Xcode still run the extension? | Install an ad hoc build on a second device with test mode off. If TestFlight is wanted, also upload a build to App Store Connect. | Extension runs within a day; App Store Connect accepts the build | Ad hoc only if App Store Connect rejects it; stop and report if the extension never runs |

**Spike 3 under the built-in TLS design:** run the `104` test against the Go server's own HTTPS port, and through Traefik passthrough if Traefik holds 443. It should pass, since nothing between phone and server reads HTTP; the test is now a confirmation, and the TCP-router fallback is the default.

**Spike 6, conflicting evidence:** one developer says the compiled-in base URL is only a connectivity check; another open-source app's notes say uploads to any other host are refused ([Shoebox](https://github.com/jstdlee/shoebox)). Assume the hostname is compiled in unless the spike proves otherwise.

### What desk research could and could not settle (26 Nov 2026)

| Question | What was found | Status |
| --- | --- | --- |
| Does the extension run with iCloud Photos on? | Apple staff said in May and June 2026 that iCloud Photos should have no bearing and called the report a likely bug; no fix, fixed version or second report appears in the thread ([Apple forum](https://developer.apple.com/forums/thread/822256)). Apps using the extension are in use on iOS 27 ([YAIIU issue on iOS 27.2.1](https://github.com/FawenYo/YAIIU/issues/133)), but none of the reports found says whether iCloud Photos was on. | Still open. Spike 1 on your own devices is the only answer. |
| What headers does iOS send? | Testers on the Immich server project report `Upload-Draft-Interop-Version: 6` with `Upload-Complete` on iOS 18 through 26, version 3 on iOS 17, and that iOS 27 PhotoKit follows draft 12 with the `OPTIONS` check ([Immich pull request](https://github.com/immich-app/immich/pull/22385)). The exact value iOS 27 sends is not published anywhere found. | Mostly answered. Spike 2 confirms the iOS 27 value. |
| Does a build installed outside Xcode run the extension? | Yes, by the evidence: one app using it is on the App Store and sends its builds through TestFlight ([App Store](https://apps.apple.com/ca/app/yaiiu/id6757139615), [its TestFlight workflow](https://github.com/FawenYo/YAIIU/pull/87)), and others ship unsigned builds that people sign themselves ([Shoebox](https://github.com/jstdlee/shoebox)). | Answered: yes. Spike 10 is now a quick confirmation. |
| Mobile data | Decided by the owner: uploads may use mobile data. Nothing found says whether the system does so by default. | Decided. Spike 9 only confirms the behaviour. |

Behaviour other projects measured that the server must respect ([Immich pull request](https://github.com/immich-app/immich/pull/22385)): iOS did not recover after a `413` response, a reviewer noted it does not resume after a `500`, and background uploads over 100 MiB failed when the hostname was proxied through Cloudflare. That project requires authentication on every upload request and its testers report iOS background uploads working, which suggests the `Authorization` header is repeated on resume; spike 8 confirms.

**Why spike 2 matters so much:** Apple's sample exchange shows `Upload-Incomplete: ?0` and a bare-number `Upload-Limit` ([Apple docs](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)). Later drafts use `Upload-Complete` and `Upload-Limit: max-size=…` ([draft -05](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-05)), and the current draft is at interop version 8 ([draft -11](https://www.ietf.org/archive/id/draft-ietf-httpbis-resumable-upload-11.html)). `URLSession` is listed as supporting drafts -04/-05 from iOS 18.1 ([tus implementations list](https://github.com/tus/rufh-implementations)); what iOS 26 and 27 send is not documented anywhere I found. A server that answers with the wrong interop version gets its `104` ignored by the client, per the draft's own rules.

**Shortcut worth testing in spike 2:** `tusd` (Go) has experimental support for drafts -01 through -05 and is listed as interoperating with `URLSession`. Point the phone at a stock `tusd` first. If it works, embed it as a library instead of hand-writing the protocol.

## Phases 1–7

Each phase ends with something you can test on its own. Effort assumes the spikes passed.

### Phase 1: Go backend (1–2 weekends)

- [ ] Account keys: admin command or page that creates a person and prints a high-entropy key once (plus a QR code); store only a SHA-256 hash; allow revoke and reissue
- [ ] Device enrolment: `POST /enroll` trades an account key + device name for a per-device token, so one lost phone can be revoked without rekeying the person
- [ ] Upload endpoint: `OPTIONS` preflight, `POST` with `104`, offset query, append, to the draft version captured in spike 2 (or embedded `tusd`)
- [ ] Metadata from headers: asset ID, resource type, original filename (percent-encoded for non-ASCII), creation date
- [ ] Storage: temp file on the share, SHA-256 while streaming, rename to `/<person>/<yyyy>/<mm>/<name>`; on hash match with an existing file, discard and report success
- [ ] Housekeeping: delete partial uploads older than N days; refuse uploads when free space is under a threshold
- [ ] Status API: last successful upload per person and per device

* [ ] Built-in TLS: DNS-01 certificate via CertMagic or lego, stored in `/data`; DNS API token read from app options and limited to editing the one zone; TLS 1.2 minimum; HTTP/1.1 and HTTP/2; read timeouts sized for multi-gigabyte bodies; listen port configurable; test against Let's Encrypt staging first to avoid rate limits

- [ ] Activity log table: one row per event with UTC time, person, device, event type, result, bytes, duration and client address. Events: enrol, token revoked, upload started, resumed, completed, duplicate, failed (with reason), auth failure
- [ ] System log: start and stop, share mounted or missing, free space, certificate issued or renewed, database snapshot, errors. Structured JSON to standard output so it shows in the Home Assistant app log
- [ ] Never log account keys, tokens, the master password or file contents. Log the asset ID and hash, not the original filename, so logs do not undo Phase 6
- [ ] Retention: keep activity rows for a set period (suggest 180 days), then roll up to daily totals per person
- [ ] Database schema shaped like a Photos library from the start: assets, resources (original, edited, Live Photo video), albums, folders, album membership, with capture date, media type and subtype, favourite, hidden, burst ID, and deleted-on-device time

* [ ] Keys never expire or rotate on their own. An account key and its device tokens stay valid until the owner disables the person, resets their key or removes a device
* [ ] Admin actions (command line first, Home Assistant page later): add person (prints key and QR once), list people and devices, disable or re-enable a person, reset a person's key (old key and all its device tokens stop working), remove one device. Disabling never deletes stored files
* [ ] Status view per person and per device: last successful upload time, last file size and duration, files and bytes in the last 24 hours and 7 days, last error and when
* [ ] Logs identify the person and device by name and a short key ID (first characters of the key's hash), never by the key or token itself
* [ ] Future-proof library schema: store Apple's raw type and subtype numbers alongside readable names, accept and keep values the server does not recognise, and give assets and collections a free-form JSON column for fields added later

- [ ] Key generation built into the server: account keys and device tokens are 256-bit values from the system's secure random source, shown once (text and QR) and stored only as hashes. One first-run setup command creates the database and the first person

* [ ] Build the upload endpoint in two steps. Step A: plain upload, preflight answered with `501`, whole body streamed to disk; get this working end to end with a real phone. Step B: add the resumable protocol to the headers captured in spike 2
* [ ] Sending the `104`: Go's standard server can write 1xx responses with `WriteHeader` since Go 1.19, on HTTP/1.1 and HTTP/2 ([Go issue](https://golang.org/issue/51914)); no custom connection handling is needed
* [ ] If `tusd` is embedded, enforce the size limit yourself: its `-max-size` was reported as not applied on the draft-protocol path ([tusd issue](https://github.com/tus/tusd/issues/1386))
* [ ] Unguessable upload URLs for resume; expire them with the partial file
* [ ] Two listeners: public (enrol, upload, device status) and internal admin (ingress only, source address checked). No admin route on the public listener
* [ ] "Do you have these?" endpoint: the device sends a batch of cloud identifiers and resource types, the server answers which it already holds for that person
* [ ] Folder date from the client's local capture date; hash suffix on name clashes; `undated` folder

- [ ] Accept the interop versions real devices send (6 on iOS 18 to 26; confirm iOS 27's in spike 2) and echo the same version in the `104`
- [ ] Never answer an upload in progress with `413` or `500`: iOS was seen not to recover from either. Announce the size limit up front, and on a server fault close the connection so the system retries
- [ ] If the DNS provider is Cloudflare, keep the backup hostname as a DNS-only record. Proxied uploads over 100 MiB failed for others, and a proxy in the path breaks the design anyway

**Done when:** a `curl` script can enrol, upload, be interrupted, resume, and upload a duplicate without creating a second file.

### Phase 2: iOS/iPadOS app and extension (1–2 weekends)

- [ ] App: paste-or-scan account key screen, full photo-library permission request, enable/disable backup, status view
- [ ] Keychain: account key as a synchronizable item (syncs via iCloud Keychain); device token as a local item with after-first-unlock access so the extension can read it while the phone is locked; both in an access group shared by app and extension
- [ ] Auto-setup: on launch, if a synced account key exists and no device token does, enrol silently
- [ ] Extension on the iOS 27 `PHBackgroundResourceUploadJobExtension` protocol: retry failed, acknowledge finished, create new jobs, in that order ([Apple docs](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background))
- [ ] Change tracking with `PHPersistentChangeToken`, stored in an App Group container; handle the token-expired error by rescanning
- [ ] Decide what counts as "a photo": originals only, or originals plus edited renders; Live Photo video halves; bursts
- [ ] Call `setUploadJobExtensionEnabled(false)` on sign-out, as Apple requires
- [ ] File log in the App Group container that the app can display, written synchronously, because the system kills the extension without a crash report

* [ ] Read the queue size from `PHAssetResourceUploadJob.jobLimit` instead of guessing a number
* [ ] First run: walk the whole library in bounded batches with a saved cursor, then switch to change tracking
* [ ] Default set of resources per asset, unless the owner chooses otherwise: original photo or video, Live Photo paired video, RAW alternate, and the edited full-size render when one exists
* [ ] Send the cloud identifier, resource type, local capture date and original filename as request headers on every job
* [ ] Before queueing a batch, ask the server which items it already has
* [ ] Onboarding screen that explains the one-time steps per device: open the app, allow full photo access, leave it
* [ ] No Wi-Fi-only switch: the owner wants uploads on mobile data too. Do not set any cellular restriction on the job's request

- [ ] Bursts: fetch with all burst frames included, and test a burst left intact. Another app's change tracking broke on exactly this and stopped all uploads until the burst was deleted ([YAIIU issue](https://github.com/FawenYo/YAIIU/issues/133))

* [ ] Look: dark theme only, no light mode. Two screens: setup (paste or scan key, allow photo access) and status. App name on the home screen: Afterimage
* [ ] Icon: near-black background, a faint ghosted photo frame fading out, one soft accent glow. Supply dark and tinted variants; show the owner two or three options before settling

**Done when:** a photo taken with the app closed and the phone locked appears on the NAS without opening the app.

### Phase 3: Home Assistant OS app (half a weekend)

- [ ] `config.yaml` with `arch: aarch64`, the `share` folder mapped read-write, the public listening port, and `ingress: true` with an ingress port for the admin page ([HA developer docs](https://developers.home-assistant.io/docs/add-ons/configuration/))
- [ ] In Home Assistant, add the NAS under Settings > System > Storage with usage **Share**, not Media
- [ ] Static Go binary (`CGO_ENABLED=0`, pure-Go SQLite driver) in a small image; it lives in the travisws/Afterimage repository, not in `ha-immich-traefik`
- [ ] Mount guard: return `503` on uploads unless a sentinel file exists on the share
- [ ] Admin page through ingress: people, devices, QR codes, status, backups, restore

* [ ] Database snapshots to the share (SQLite online backup, written to a temp name then renamed; keep the last few), and a start-up path that restores the newest snapshot when `/data` is empty
* [ ] Check the share's free space and write permission at start-up, and that rename within the share works (SMB and NFS both tested if both are possible)

- [ ] Nightly system backup to the share (`/_system/backups/<date>/`): database snapshot checked with SQLite's integrity check, app configuration, schema and app version, and from Phase 6 the password-protected key file. Keep the last 14 nightly backups; no monthly copies
- [ ] Left out on purpose: the DNS API token and TLS private keys (re-enter the token and the certificate re-issues itself), and the master password (never stored anywhere)
- [ ] Migration path: on a new system, install the app, mount the same share, run one restore command (or start with an empty `/data` and it offers the newest backup), re-enter the DNS token. Phones keep working without signing in again as long as the hostname is unchanged
- [ ] Log each backup, and raise a Home Assistant alert if the newest backup is older than 48 hours or fails its check
- [ ] Migration rehearsal before family rollout: restore the latest backup onto a second machine or container and confirm a phone uploads to it

**Done when:** the app survives an HA OS reboot and a NAS power-cycle without writing a byte to the Pi's own disk.

### Phase 4: port 443 and DNS (an hour or two)

- [ ] Check whether anything holds port 443 on the Pi (see Open decisions)
- [ ] 443 free: map the app's port to host 443 in `config.yaml`
- [ ] 443 held by Traefik: add a TCP router matching the backup hostname by SNI with TLS passthrough to the app's port. No HTTP router, middleware or certificate for this hostname in Traefik
- [ ] Split DNS, one hostname everywhere: a local DNS record on the router points the backup hostname at the Pi's LAN address; public DNS points it at the public address (or has no record, for home-only backups). The DNS-01 certificate is valid either way because it is tied to the name. No bare IP addresses and no per-Wi-Fi switching in the app: a job's URL is fixed when queued but sent later, possibly on another network
- [ ] Rate-limit `/enroll` inside the Go server, since no proxy does it now

**Done when:** spike 4 (interrupted 1 GB upload) passes through the real hostname from mobile data and from home Wi-Fi.

### Phase 5: hardening and family rollout (1 weekend, then ongoing)

- [ ] HA sensors from the status API, plus an automation that notifies you when any person has no upload for N days. This is the only defence against the extension silently not running
- [ ] Initial backfill plan: let the extension work through the library over days, or add a foreground "back up now" button
- [ ] Distribution to the other four people: ad hoc installs first (devices registered by ID, builds last one year, no App Store Connect check). TestFlight only after spike 10 shows App Store Connect accepts the extension; it rejected this extension type in November 2025 ([Apple forum](https://developer.apple.com/forums/thread/806418)). Both need the paid developer account; a free Apple ID works for your own device but builds expire after 7 days
- [ ] Restore test: pick 20 random files from the NAS and open them
- [ ] Re-test after every iOS point release before the family updates

### Phase 6: encryption at rest (half a weekend, only after Phases 1–5 work)

- [ ] From Phase 1 onward, keep file storage behind one small interface and give each file row an `encrypted` flag, so this phase changes one module
- [ ] Setup command: generate the server key pair, ask for the master password twice, save the password-protected key file to `/data` and a copy to the NAS
- [ ] Encrypt on completion of each upload; random stored name; delete the plaintext temp file
- [ ] Migration command: encrypt files already stored in plain form, verify each by hash, then remove the plain copy
- [ ] Restore command as described under Architecture; change-password command
- [ ] Automated test: encrypt, restore with the password, compare hashes; wrong password fails cleanly

**Done when:** a folder listing of the NAS shows only random names that will not open, and a full restore with the master password matches the original hashes.

### Phase 7: Photos library structure (1 weekend, after transfer works)

The goal is a server record that mirrors each person's Photos library as closely as PhotoKit allows, so a restore can rebuild the same organisation.

- [ ] Files on the share stay in `/<person>/<year>/<month>/` by capture date, matching the Years and Months views. Albums are not disk folders, because one photo can sit in many albums; they live in the database
- [ ] Library sync endpoint: the app sends albums, folders of albums, album membership, favourites, hidden flags, media subtypes (Live Photo, screenshot, panorama, slo-mo, burst) and deletions as small JSON updates, separate from file uploads
- [ ] History: keep every version uploaded (original and edited render), and record when an asset was edited or deleted on the device. The backup never deletes a file because the phone did
- [ ] Restore options: by year and month, or with album folders recreated
- [ ] Test whether the upload extension may make its own small network requests for this sync; if not, the app syncs structure whenever it is opened

**What cannot be mirrored:** Memories, People and Pets recognition, Recently Deleted, and step-by-step edit history are not available to apps. Shared albums and a shared library are only partly visible. Treat "exact" as: same dates, media types, albums, folders, favourites and edits.

**Done when:** a restore of one person with album folders matches what their Photos app shows for three spot-checked albums and three months.

## Risk register

Thirty-one foreseeable problems, worst first within each area. Likelihood is my judgement from the sources, not a measurement. The two Traefik rows apply only if an HTTP proxy is ever put in front of the upload route; with TLS in the backend they do not arise.

| Area | Problem | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- | --- |
| iOS | Extension never scheduled while iCloud Photos is on ([report, iOS 26.4](https://developer.apple.com/forums/thread/822256)) | Unknown; test first | Project-killer | Spike 1; stale-backup alert; fallback to background `URLSession` |
| iOS | iCloud-optimized originals silently skipped ([report](https://developer.apple.com/forums/thread/819034)), although Apple's docs say the system downloads them first | Medium | Missing photos with no error | Server-side count vs. library count shown in the app; try download-only jobs for stragglers |
| iOS | Behaviour changes between point releases; a developer reported uploads working on 26.1 and not triggering on 26.2 ([report](https://developer.apple.com/forums/thread/815316)) | High | Backups stop until you patch | Stale-backup alert; test each release on one device first |
| iOS | iOS 26 to 27 migration: jobs created under the old protocol clogged the inflight limit in another app ([YAIIU fix](https://github.com/FawenYo/YAIIU/pull/80)) | Low if you start on iOS 27 | Queue stalls | Build only against the iOS 27 protocol; never let bookkeeping block acknowledging jobs |
| iOS | Extension killed for memory or runtime before finishing ([YAIIU fix](https://github.com/FawenYo/YAIIU/pull/81)) | High on big libraries | Slow or stuck backfill | Small bounded batches per invocation; return `.processing`; no full-library fetch in memory |
| iOS | Crash between acknowledging a job and recording it | Medium | Lost or duplicate bookkeeping | Record first, acknowledge second (Apple's stated order); server dedupe makes re-uploads harmless |
| iOS | Inflight job limit (read from PHAssetResourceUploadJob.jobLimit) | Certain | First backup of a large library takes days | Keep queue full each run; optional foreground "back up now" |
| iOS | Token baked into queued jobs is revoked or rotated | Low | Jobs fail with auth errors | Long-lived device tokens; on auth failure retry with a new destination request |
| iOS | Asset identifiers change on a new or restored phone | Certain eventually | Whole library re-uploads | Server hash dedupe (costs bandwidth only) |
| iOS | Person grants limited photo access | Medium | Extension cannot be enabled | App explains and re-prompts; status shows "needs full access" |
| iOS | Slow debug loop; no Simulator support | Certain | Lost evenings | iOS 27 Resource Upload Test Mode; file logging from day one |
| Keys | iCloud Keychain off, or a shared Apple Account across people | Medium | No auto-setup, or two people merged into one account | Paste/QR fallback; show the account name after setup so mix-ups are visible |
| Keys | Leaked account key | Low | Someone can upload into (not read from) an account | Keys are upload-only; revoke and reissue from the server |
| Protocol | Draft version mismatch between iOS and server | High without spike 2 | No resume, or uploads rejected | Capture real headers; pin behaviour per interop version; keep `tusd` as reference |
| Protocol | Preflight `OPTIONS` arrives without your auth header | Unknown | Every upload fails at preflight | Allow unauthenticated `OPTIONS` on the upload path |
| Traefik | `104` dropped | Unknown | No resumable uploads | Spike 3; TCP router fallback |
| Traefik | 60 s read timeout or a buffering middleware | Certain if left default | Videos fail | Raise timeout; no buffering on the route |
| HA OS | NAS not mounted at boot or dropped later; HA does not remount until you click the repair ([forum](https://community.home-assistant.io/t/retry-network-storage-after-failure/655130)), and apps then write to the Pi's own disk ([forum](https://community.home-assistant.io/t/addons-writing-to-media-when-mount-fails-how-to-safely-use-external-usb-disk-with-ha-os/977890)) | High over a year | Pi disk fills; photos in the wrong place; remount then refuses a non-empty folder | Sentinel-file guard; `503` while unmounted so iOS retries later |
| HA OS | SQLite on SMB | Certain if tried | Database corruption | Keep it in `/data` |
| HA OS | Pi 5 with 4 GB also running Immich and Traefik | Low for this app | Memory pressure | Stream to disk, never buffer a file in RAM |
| Network | Endpoint reachable from the internet | Certain if port 443 is forwarded | Attack surface | Upload-only keys, rate-limited `/enroll`, no directory listing, no download API |
| Data | Backup exists only on one NAS | Certain | Single point of loss | This is a copy, not the archive, until the NAS itself is backed up |
| iOS | App Store Connect rejects the extension identifier (reported November 2025; Apple asked for bug reports) | Low now: apps using it are on the App Store | TestFlight unusable | Ad hoc installs; spike 10 |
| iOS | A family device cannot run iOS 27 | Depends on the devices | No backup for that device | Check every device before starting |
| iOS | Uploads run over mobile data | Unknown | Data charges | Spike 9; Wi-Fi-only switch |
| iOS | Two devices on one iCloud library upload everything twice | Certain with an iPhone and iPad | Double the bandwidth | Cloud identifier check before queueing; hash dedupe |
| HA OS | Photos browsable in Home Assistant's media browser | Certain if mounted as Media | Any HA user sees family photos | Mount as Share; Phase 6 encryption |
| Network | Admin functions exposed on the public port | Certain if built on one listener | Anyone could create accounts | Separate ingress-only listener |
| Data | Wrong year or month folder near midnight | Certain without a rule | Photos filed under the wrong date | Folder from the device's local capture date |
| Protocol | Server answers 413 or 500 during an upload; iOS was seen not to recover or resume | Medium | A file stuck until its job is retried by the app | Announce limits up front; close the connection on faults; retry logic in the extension |
| iOS | An intact burst breaks change tracking and blocks all later uploads (seen in another app on iOS 27.2.1) | Medium | Backups silently stop | Include burst frames in fetches; burst test case; stale-backup alert |

## Open decisions

- [ ] **Does anyone in the household use iCloud Photos?** If yes, spike 1 decides the whole approach.
- [ ] **Does each person have their own Apple Account?** Key sync follows the Apple Account, so a shared one would put two people in one backup account.
- [ ] **Can every device run iOS or iPadOS 27?** A device that cannot gets no backup from this app.
- [ ] **Reachable away from home?** Public hostname (backups run anywhere) or home network only (smaller attack surface, backups wait until people are home).
- [ ] **Wi-Fi only, or mobile data too?** Decided: mobile data is allowed. Spike 9 only confirms the system does it.
- [ ] **Which versions of each photo?** Default in this plan: originals, Live Photo videos, RAW files and edited renders. Originals only would save space.
- [ ] **Paid developer account ($99/year)?** Needed in practice for five people's devices.

* **Decided:** iOS and iPadOS 27 or later only. Standalone storage with no viewer and no Immich link. One master password for encryption, added in Phase 6. Nightly system backups, 14 kept.

- [ ] **Is port 443 free on the Pi?** From a computer on the home network run `nc -zv <Pi address> 443`. "Connection refused" means free; "succeeded" means something (most likely Traefik) holds it. Home Assistant itself uses 8123, not 443.
- [ ] **DNS provider and API token.** Create a token limited to editing DNS records in the one zone, and give it to the app through its options, never the repository.

## Sources

Pages opened and read on 26 Nov 2026 unless marked.

- [Apple: Uploading asset resources in the background](https://developer.apple.com/documentation/photokit/uploading-asset-resources-in-the-background)
- [Apple forum: extension never scheduled when iCloud Photos is enabled](https://developer.apple.com/forums/thread/822256)
- [Apple forum: large videos, no chunking, one request per resource](https://developer.apple.com/forums/thread/818566)
- [Apple forum: iCloud-optimized photos not uploaded](https://developer.apple.com/forums/thread/819034) (search excerpt only)
- [Apple forum: upload not triggered on iOS 26.2](https://developer.apple.com/forums/thread/815316) (search excerpt only; page would not load)
- [Immich discussion #23245: limitations of the extension](https://github.com/immich-app/immich/discussions/23245)
- [YAIIU: open-source app using the extension (AGPL-3.0)](https://github.com/FawenYo/YAIIU), with fixes [#80](https://github.com/FawenYo/YAIIU/pull/80) and [#81](https://github.com/FawenYo/YAIIU/pull/81) (search excerpts)
- [tus: implementations of the resumable-upload draft](https://github.com/tus/rufh-implementations)
- [IETF draft -05](https://datatracker.ietf.org/doc/html/draft-ietf-httpbis-resumable-upload-05) and [draft -11](https://www.ietf.org/archive/id/draft-ietf-httpbis-resumable-upload-11.html) (search excerpts)
- [Go: ReverseProxy forwards 1xx responses](https://github.com/golang/go/issues/26088) (search excerpt)
- [Traefik forum, 2022: 103 not passed through](https://community.traefik.io/t/does-traefik-support-103-early-hints/15237) (search excerpt)
- [Traefik advisory quoting the 60 s readTimeout default](https://advisories.gitlab.com/golang/github.com/traefik/traefik/v3/CVE-2026-88012/) (search excerpt)
- [Home Assistant developer docs: app configuration](https://developers.home-assistant.io/docs/add-ons/configuration/) (search excerpt)
- Home Assistant forum: [network storage not retried](https://community.home-assistant.io/t/retry-network-storage-after-failure/655130), [apps writing to local disk when a mount fails](https://community.home-assistant.io/t/addons-writing-to-media-when-mount-fails-how-to-safely-use-external-usb-disk-with-ha-os/977890) (search excerpts)

Added in the final review (search excerpts unless marked):

- [Shoebox: open-source app sending these jobs to S3 upload URLs](https://github.com/jstdlee/shoebox) (opened)
- [Apple forum: App Store Connect rejects the extension identifier](https://developer.apple.com/forums/thread/806418), and [Apple confirming the identifier is correct](https://developer.apple.com/forums/thread/807582)
- [Apple forum: extension not available in Simulator](https://developer.apple.com/forums/thread/807591)
- [Apple: PHCloudIdentifier](https://developer.apple.com/documentation/photos/phcloudidentifier), [forum: use it to back up an asset once](https://developer.apple.com/forums/thread/774303), [forum: identifier differing between devices](https://developer.apple.com/forums/thread/843934)
- [Go: 1xx responses supported from Go 1.19](https://golang.org/issue/51914)
- [tusd: size limit not applied on the draft path](https://github.com/tus/tusd/issues/1386)
- [Go age library](https://pkg.go.dev/filippo.io/age)
- [Home Assistant developer docs: ingress and the 172.30.32.2 rule](https://developers.home-assistant.io/docs/apps/presentation)
- [Home Assistant: backups leave out media and share folders](https://www.home-assistant.io/common-tasks/general/backups/)
- [Nextcloud Photos iOS pull request using the iOS 27 extension](https://github.com/nextcloud/photos-ios/pull/29)

* [Immich pull request 22385: resumable uploads, with testers' iOS findings](https://github.com/immich-app/immich/pull/22385) (opened)
* [YAIIU issue 133: extension on iOS 27.2.1, burst problem](https://github.com/FawenYo/YAIIU/issues/133) (opened), [YAIIU on the App Store](https://apps.apple.com/ca/app/yaiiu/id6757139615), [TestFlight workflow](https://github.com/FawenYo/YAIIU/pull/87)
* [Apple forum: URLSession resumable uploads tied to a frozen draft](https://developer.apple.com/forums/thread/818379) (opened)
* [Nextcloud iOS pull request 4279: iOS 27 extension with plain WebDAV PUT](https://github.com/nextcloud/ios/pull/4279) (opened)

Still not looked up, from general knowledge: iCloud Keychain sync behaviour of synchronizable items (spike 5 verifies it), ad hoc and TestFlight build lifetimes, the developer account price, and SQLite's unreliability on network shares. Still unknown until tested on a real device: whether the extension runs with iCloud Photos on, the exact upload headers iOS 27 sends, whether resume requests repeat the `Authorization` header, and whether uploads use mobile data.
