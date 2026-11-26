# Afterimage

Private photo and video backup for one household, built on
[Immich](https://immich.app) and packaged as Home Assistant apps for a
Raspberry Pi 5.

> **Status:** Phase 1 of [docs/plan.md](docs/plan.md) is done: the Immich
> app builds and passes its smoke test in an arm64 container. It has not run
> on the Pi yet (Phase 2), and the Traefik app is not written (Phase 3).

## What is here

```
repository.yaml   Makes this a Home Assistant app repository
immich/           The Afterimage app: Immich server, PostgreSQL and Valkey in one container
traefik/          (planned) Traefik with a DNS-01 certificate in front of Immich
scripts/          Smoke test that builds and exercises the image on a Mac or Linux box
docs/plan.md      The plan: decisions, phases, risks, confirmed facts
```

## How it is laid out on the Pi

- **Database:** PostgreSQL inside the app, stored on the Pi in the app's
  private `/data`.
- **Originals and database dumps:** on the NAS share that Home Assistant
  mounts as network storage with usage Share, under
  `/share/<storage name>/immich/`.
- **Machine learning:** off. The Pi has 4 GB of RAM and Immich's docs say to
  run that way.
- **Safety:** Immich is only started while the share is really mounted, so
  photos cannot land on the Pi's own disk.

## Installing

Until this repository is public, Home Assistant cannot clone it. Copy the
`immich/` folder into Home Assistant's local apps folder instead, then install
it from Settings > Apps. Full steps and every option are in
[immich/DOCS.md](immich/DOCS.md).

## Phones

People use the stock Immich app from the App Store and sign in to the
household's server. There is no custom app.

## Security notes

- No secrets are kept in this repository. The database password is generated
  on the Pi at first start. The DNS provider token will be an app option.
- Files on the NAS are not encrypted by Immich. Use the NAS's own volume
  encryption if that matters.
