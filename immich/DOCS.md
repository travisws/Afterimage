# Afterimage (Immich)

Immich server, PostgreSQL and Valkey in one app. The database stays on this
device. Photos, videos and database dumps go to a network share.

## Before you install

1. **Mount the NAS.** Settings > System > Storage > Add network storage.
   Choose usage **Share**, not Media: Media would show every photo in Home
   Assistant's media browser to every Home Assistant user. The name you give
   it becomes the folder `/share/<name>`.
2. Use NFS if the NAS offers it. Immich recommends storage with Unix
   ownership and permissions, which SMB does not really provide.

## Install

While the repository is private, copy the `immich` folder into Home
Assistant's local apps folder (reachable through the Samba or SSH apps), then
Settings > Apps > Install app, refresh, and pick **Afterimage (Immich)** under
local apps. The first install builds the image on the device, which downloads
about 1.5 GB and takes a while.

Once the repository is public, add
`https://github.com/travisws/Afterimage` under Repositories instead.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `storage_name` | none, required | The network storage name from step 1. The app uses `/share/<storage_name>` |
| `storage_subfolder` | `immich` | Folder inside that share for everything Immich stores |
| `require_mount` | on | Start Immich only when `/share/<storage_name>` is a real mount. Leave on. Turning it off lets files be written to this device's own disk |
| `manage_settings` | on | Apply the trimmed settings below from a config file. Immich then shows those settings as read-only in its web UI. Turn off to manage every setting in Immich yourself |
| `video_transcoding` | `disabled` | `disabled` keeps videos as uploaded (a Pi has no hardware video encoder). `required` transcodes only what browsers cannot play |
| `storage_template` | `{{y}}/{{MM}}/{{filename}}` | Folder layout under each person's library folder |
| `database_dumps_kept` | 14 | How many nightly database dumps Immich keeps on the share |
| `log_level` | `log` | Immich's log level |
| `external_url` | unset | The public address, such as `https://photos.example.com`, used in links Immich generates |
| `timezone` | unset | A TZ name such as `Europe/London`, used for the nightly schedule and for photos without a time zone |

With `manage_settings` on, the app sets: machine learning off, job
concurrency lowered, database dump daily at 02:00, storage template on,
version check off, face clustering off.

## Where things are

| What | Where |
| --- | --- |
| Database | This device, in the app's private data (`postgres/`) |
| Originals | `/share/<storage_name>/<subfolder>/library`, `upload`, `profile` |
| Database dumps | `/share/<storage_name>/<subfolder>/backups`, one per night |
| Thumbnails, transcoded video | `/share/<storage_name>/<subfolder>/thumbs`, `encoded-video` |
| Database password | Generated on first start, kept in the app's private data |

## First start

Open the web interface (port 2283), create the admin account, then create one
account per person. Give each person a **storage label** (Administration >
Users) so their files are stored under `library/<label>/<year>/<month>/`.

## If the NAS is offline

The app keeps running but Immich is stopped, and the log repeats that it is
waiting for the share. Nothing is written to this device. Immich starts again
by itself when the share is back.

## Backups

- **Home Assistant backups** of this app contain a fresh database dump
  (`db-dump/`) and the app's settings, not the photos and not the live
  database folder.
- **The share** holds the originals and the nightly dumps. To rebuild on a new
  device: install the app, point it at the same share, and choose **Restore
  from backup** on Immich's welcome screen.
- The NAS itself still needs its own backup. Until it has one, this is a
  single copy.

## Updating Immich

The Immich version is pinned in the `Dockerfile`. Updates are deliberate:
read the Immich release notes, change the pinned version and the app
`version`, rebuild, test.
