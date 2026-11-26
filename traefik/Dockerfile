# Afterimage Traefik: HTTPS in front of the Afterimage (Immich) app, with a
# Let's Encrypt certificate obtained by DNS-01 through Cloudflare.
#
# To update Traefik: read its release notes, change TRAEFIK_VERSION here and
# `version` in config.yaml, rebuild, and run scripts/traefik-smoke-test.sh.

ARG TRAEFIK_VERSION=v3.8.0
FROM traefik:${TRAEFIK_VERSION} AS traefik

FROM alpine:3.24
RUN apk add --no-cache bash ca-certificates jq tzdata
COPY --from=traefik /usr/local/bin/traefik /usr/local/bin/traefik
COPY rootfs /
RUN chmod 0755 /usr/local/bin/afterimage-traefik \
 && traefik version
CMD ["/usr/local/bin/afterimage-traefik"]
