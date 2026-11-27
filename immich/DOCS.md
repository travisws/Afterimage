# Afterimage

The Immich photo server, PostgreSQL and Valkey in one app. The database stays on this
device. Photos, videos and database dumps go to a network share.

## Before you install

1. **Mount the NAS.** Settings > System > Storage > Add network storage.
   Choose usage **Share**, not Media: Media would show every photo in Home
   Assistant's media browser to every Home Assistant user. The name you give
   it becomes the folder `/share/<name>`.
2. Use NFS if the NAS offers it. Immich recommends storage with Unix
   ownership and permissions, which SMB does not really provide.

## Install

1. Settings > Apps > Install app. In the top-right menu, select
   **Repositories**, add `https://github.com/travisws/Afterimage`, and close
   the dialog.
2. Pick **Afterimage** from the new Afterimage section and select
   **Install**. The first install builds the image on the device, which
   downloads about 1.5 GB and takes a while.
3. On the **Configuration** tab, check that `storage_name` matches the name
   of your network storage, then **Start**.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `storage_name` | `Immich` | The network storage name from step 1, exactly as Home Assistant shows it. The app uses `/share/<storage_name>` |
| `folder_library` | `library/library` | Where Immich's `library` folder (originals, filed by person and date) is, inside the share |
| `folder_upload` | `library/upload` | Where the `upload` folder (new originals before filing) is |
| `folder_thumbs` | `thumbs` | Where the `thumbs` folder (thumbnails and previews) is |
| `folder_encoded_video` | `encoded-video` | Where the `encoded-video` folder (transcoded videos) is |
| `folder_profile` | `profile` | Where the `profile` folder (profile pictures) is |
| `folder_backups` | `backups` | Where the `backups` folder (nightly database dumps) is |
| `require_mount` | on | Start Immich only when `/share/<storage_name>` is a real mount. Leave on. Turning it off lets files be written to this device's own disk |
| `manage_settings` | off | When on, apply the trimmed settings below from a config file; Immich then shows those settings as read-only. Leave off for a restored instance, so its own settings are kept |
| `video_transcoding` | `disabled` | `disabled` keeps videos as uploaded (a Pi has no hardware video encoder). `required` transcodes only what browsers cannot play |
| `storage_template` | `{{y}}/{{MM}}/{{filename}}` | Folder layout under each person's library folder |
| `database_dumps_kept` | 14 | How many nightly database dumps Immich keeps on the share |
| `log_level` | `log` | Immich's log level |
| `external_url` | unset | The public address, such as `https://photos.example.com`, used in links Immich generates |
| `timezone` | unset | A TZ name such as `Europe/London`, used for the nightly schedule and for photos without a time zone |

The folder options are paths inside the share. They let the app use an
existing Immich layout as it is, including folders that are separate datasets
on the NAS. Missing folders are created. Inside the container the app links
the six folders together under `/afterimage/media`, which is the media
location Immich sees.

With `manage_settings` on, the app sets: machine learning off, job
concurrency lowered, database dump daily at 02:00, storage template on,
version check off, face clustering off. With it off, turn machine learning
off yourself in Administration > Settings, because this app does not run it.

## Where things are

| What | Where |
| --- | --- |
| Database | This device, in the app's private data (`postgres/`) |
| Originals | The `folder_library`, `folder_upload` and `folder_profile` folders on the share |
| Database dumps | The `folder_backups` folder on the share, one per night |
| Thumbnails, transcoded video | The `folder_thumbs` and `folder_encoded_video` folders on the share |
| Database password | Generated on first start, kept in the app's private data |

## First start

Open the web interface (port 2283), create the admin account, then create one
account per person. Give each person a **storage label** (Administration >
Users) so their files are stored under `library/<label>/<year>/<month>/`.

## Bringing back an existing Immich

To move an Immich instance here with its users, albums and settings:

1. Stop the old instance and make sure it cannot start again. Two Immich
   servers must never use the same files.
2. Point the six folder options at the old instance's folders on the share,
   and leave `manage_settings` off.
3. Put a recent database dump in the backups folder. Immich's own nightly
   dumps (`immich-db-backup-…sql.gz`) work, from the same Immich version or
   an older one.
4. Start the app. In Immich, use **Restore from backup** on the welcome
   screen, or Administration > Maintenance > Restore database backup if an
   admin account exists, and pick the dump.
5. Immich notices that its media location changed and rewrites the file paths
   in the database by itself on the next start.
6. Turn machine learning off in Administration > Settings.

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
