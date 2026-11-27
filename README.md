# Afterimage

Private photo and video backup for one household, built on
[Immich](https://immich.app) and packaged as Home Assistant apps for a
Raspberry Pi 5.

> **Status:** Immich runs on the Pi as the Afterimage app, with the
> household's previous library restored (Phase 2). The Traefik app for
> `https://photos.dpool.dev` is written and tested in a container; it has not
> run on the Pi yet (Phase 3).

## What is here

```
repository.yaml   Makes this a Home Assistant app repository
immich/           "Afterimage": the Immich server, PostgreSQL and Valkey in one container
traefik/          "Afterimage Gateway": Traefik Proxy, HTTPS with a Let's Encrypt certificate by Cloudflare DNS-01
scripts/          Smoke tests that build and exercise each app on a Mac or Linux box
docs/plan.md      The plan: decisions, phases, risks, confirmed facts
```

## How it is laid out on the Pi

- **Database:** PostgreSQL inside the app, stored on the Pi in the app's
  private `/data`.
- **Originals and database dumps:** on the NAS share that Home Assistant
  mounts as network storage with usage Share. One option per Immich folder
  says where it is on the share, so an existing layout is used as it is.
- **Machine learning:** off. The Pi has 4 GB of RAM and Immich's docs say to
  run that way.
- **Safety:** Immich is only started while the share is really mounted, so
  photos cannot land on the Pi's own disk.

## Installing

Add `https://github.com/travisws/Afterimage` as an app repository in Home
Assistant (Settings > Apps > Install app > Repositories), then install
**Afterimage**, and **Afterimage Gateway** for HTTPS at your own domain. Full steps and every option are in
[immich/DOCS.md](immich/DOCS.md).

## Phones

People use the stock Immich app from the App Store and sign in to the
household's server. There is no custom app.

## Security notes

- No secrets are kept in this repository. The database password is generated
  on the Pi at first start. The DNS provider token will be an app option.
- Files on the NAS are not encrypted by Immich. Use the NAS's own volume
  encryption if that matters.
