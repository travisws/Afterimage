# Afterimage Gateway

HTTPS for Afterimage at your own domain, such as `https://photos.dpool.dev`.
It runs Traefik Proxy, which gets a Let's Encrypt certificate through Cloudflare (DNS-01), renews
it by itself, and passes traffic to the Afterimage app over Home
Assistant's internal network. Uploads are not buffered and have no time
limit, so large videos from phones go through.

## Before you install

1. **Cloudflare API token.** In Cloudflare: My Profile > API Tokens >
   Create Token > Custom token. Permissions: **Zone > Zone > Read** and
   **Zone > DNS > Edit**. Zone resources: include your domain only. Copy the
   token; Cloudflare shows it once. Do not use the Global API Key.
2. **Cloudflare record.** The record for your domain must be **DNS only**
   (grey cloud). Cloudflare's proxy limits uploads and gets in the way of
   Immich.
3. **Port 443 on the Pi must be free.** Home Assistant itself uses 8123, so
   it usually is.

## Install

1. Settings > Apps > Install app, top-right menu > **Check for updates**,
   then install **Afterimage Gateway** from the Afterimage section.
2. On the **Configuration** tab fill in the options below and save.
3. Start it and open the **Log** tab. Within about a minute Traefik logs the
   new certificate. Errors about Cloudflare there mean the token or its
   permissions are wrong.

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `domain` | `photos.dpool.dev` | The address Immich is served at |
| `acme_email` | none, required | Your email. Let's Encrypt uses it for expiry warnings |
| `cloudflare_dns_api_token` | none, required | The Cloudflare API token from step 1. Stored in Home Assistant, written only to a private file inside the app, never logged |
| `cloudflare_zone_api_token` | unset | Only if you split read and edit permissions into two tokens |
| `staging` | off | Use Let's Encrypt's test service while trying things out. Its certificates are not trusted by phones; turn it off for real use |
| `immich_backend` | unset | Normally worked out by itself. Set it (for example `http://923cdf4f-afterimage:2283`) only if the log says it cannot find Immich |
| `log_level` | `info` | Traefik's log level |

## Your network

- **At home:** your router's local DNS should answer the domain with the
  Pi's address (for example `10.0.0.100`), so phones on Wi-Fi go straight to
  it.
- **Away from home:** the public Cloudflare record should point at your home
  address, and your router should forward TCP port 443 to the Pi. Without
  this, backups only run at home.

## In Immich

Set Administration > Settings > Server > External domain to
`https://<your domain>`, so share links use it. In the phone apps, set the
server address to `https://<your domain>`.

## Certificate storage

The certificate and the Let's Encrypt account key are kept in this app's
private data (`acme.json`), which Home Assistant backups include. If the
file is lost, Traefik simply requests a new certificate.
