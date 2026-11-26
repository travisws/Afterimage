# Afterimage: Immich server, PostgreSQL and Valkey in one image for Home
# Assistant OS on aarch64. See docs/plan.md.
#
# To update Immich: read its release notes, change IMMICH_VERSION here and
# `version` in config.yaml, rebuild, and run the smoke test.

ARG IMMICH_VERSION=v3.4.2
FROM ghcr.io/immich-app/immich-server:${IMMICH_VERSION}

# PostgreSQL major version. Changing it later means a dump and restore.
ARG PG_MAJOR=17
# VectorChord: same release and download location that Immich's own database
# image uses, pinned by checksum. Immich accepts >= 0.3, < 2.0.
ARG VCHORD_VERSION=0.4.3
ARG VCHORD_SHA256=d69167fea8b97fb791e4b6b3d06599fc666680d5c853732e5dc3fafede9fa1a3

ENV DEBIAN_FRONTEND=noninteractive

RUN set -eux; \
    case "$(dpkg --print-architecture)" in arm64) ;; *) echo "this image is built for arm64 only" >&2; exit 1 ;; esac; \
    # The base image removes ca-certificates, which the PostgreSQL package
    # source (already configured in the base image) needs.
    apt-get update || true; \
    apt-get install -y --no-install-recommends ca-certificates; \
    apt-get update; \
    # Do not create or start a default database cluster at install time.
    mkdir -p /etc/postgresql-common; \
    echo "create_main_cluster = false" > /etc/postgresql-common/createcluster.conf; \
    apt-get install -y --no-install-recommends \
        "postgresql-${PG_MAJOR}" \
        "postgresql-${PG_MAJOR}-pgvector" \
        valkey-server; \
    # VectorChord works with pgvector >= 0.7, < 0.9. Fail the build otherwise.
    pgvector_version="$(dpkg-query -W -f='${Version}' "postgresql-${PG_MAJOR}-pgvector")"; \
    case "$pgvector_version" in 0.7.*|0.8.*) ;; *) echo "pgvector $pgvector_version is outside the range VectorChord supports" >&2; exit 1 ;; esac; \
    curl -fsSL -o /tmp/vchord.deb \
        "https://github.com/tensorchord/VectorChord/releases/download/${VCHORD_VERSION}/postgresql-${PG_MAJOR}-vchord_${VCHORD_VERSION}-1_arm64.deb"; \
    echo "${VCHORD_SHA256}  /tmp/vchord.deb" | sha256sum -c -; \
    apt-get install -y --no-install-recommends /tmp/vchord.deb; \
    rm -f /tmp/vchord.deb; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/*; \
    test -x "/usr/lib/postgresql/${PG_MAJOR}/bin/postgres"; \
    test -f "/usr/lib/postgresql/${PG_MAJOR}/lib/vchord.so"; \
    command -v valkey-server

ENV AFTERIMAGE_PG_MAJOR=${PG_MAJOR}

COPY rootfs /

RUN chmod 0755 /usr/local/bin/afterimage-run /usr/local/bin/afterimage-backup-pre

# The base image's entrypoint is `tini -- /bin/bash -c`; keep tini, replace
# the command with the supervisor.
ENTRYPOINT ["tini", "--"]
CMD ["/usr/local/bin/afterimage-run"]
