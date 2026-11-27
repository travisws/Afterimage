#!/usr/bin/env bash
# Builds the Afterimage image and exercises it in a local arm64 Linux
# container. This is not a substitute for testing on the Pi: it proves the
# image starts, stores an upload on the "share" byte for byte, dumps the
# database, survives a restart, restarts Immich if it dies, and refuses to
# run Immich without a mount. The "share" uses the same split layout as the
# owner's NAS: library/library, library/upload, thumbs, encoded-video,
# profile and backups.
#
# Usage: scripts/smoke-test.sh            (Apple's `container` tool)
#        CONTAINER_CLI=docker scripts/smoke-test.sh
#        KEEP=1 scripts/smoke-test.sh     (leave container, volume and image)

set -Eeuo pipefail

CLI="${CONTAINER_CLI:-container}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.smoke"
IMAGE="afterimage-smoke:dev"
NAME="afterimage-smoke"
VOLUME="afterimage-smoke-data"
BASE="http://127.0.0.1:2283/api"

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; echo "--- last container log lines ---" >&2; "$CLI" logs "$NAME" 2>&1 | tail -40 >&2 || true; exit 1; }
cexec() { "$CLI" exec "$NAME" "$@"; }

cleanup() {
  [ "${KEEP:-0}" = "1" ] && return 0
  "$CLI" stop -t 100 "$NAME" >/dev/null 2>&1 || true
  "$CLI" rm "$NAME" >/dev/null 2>&1 || true
  "$CLI" volume rm "$VOLUME" >/dev/null 2>&1 || true
  "$CLI" image rm "$IMAGE" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

write_options() {
  cat > "${WORK}/options/options.json" <<EOF
{
  "storage_name": "$1",
  "folder_library": "library/library",
  "folder_upload": "library/upload",
  "folder_thumbs": "thumbs",
  "folder_encoded_video": "encoded-video",
  "folder_profile": "profile",
  "folder_backups": "backups",
  "require_mount": true,
  "manage_settings": true,
  "video_transcoding": "disabled",
  "storage_template": "{{y}}/{{MM}}/{{filename}}",
  "database_dumps_kept": 14,
  "log_level": "log"
}
EOF
}

run_container() {
  "$CLI" run -d --name "$NAME" -c 4 -m 4g \
    -v "${VOLUME}:/data" \
    -v "${WORK}/share/teststore:/share/teststore" \
    -v "${WORK}/options:/options" \
    -e AFTERIMAGE_OPTIONS=/options/options.json \
    "$IMAGE" >/dev/null
}

wait_for_immich() {
  local i
  for i in $(seq 1 120); do
    if cexec curl -fsS "${BASE}/server/ping" 2>/dev/null | grep -q pong; then return 0; fi
    sleep 3
  done
  return 1
}

echo "== build"
"$CLI" stop "$NAME" >/dev/null 2>&1 || true
"$CLI" rm "$NAME" >/dev/null 2>&1 || true
"$CLI" volume rm "$VOLUME" >/dev/null 2>&1 || true
rm -rf "$WORK"
mkdir -p "${WORK}/share/teststore" "${WORK}/options"
if [ "$CLI" = "container" ]; then
  container system start --disable-kernel-install --timeout 60 >/dev/null 2>&1 || true
fi
if ! "$CLI" build --tag "$IMAGE" "${ROOT}/immich" >"${WORK}/build.log" 2>&1; then
  tail -30 "${WORK}/build.log" >&2
  fail "image build failed"
fi
"$CLI" volume create "$VOLUME" >/dev/null
pass "image built"

echo "== 1. no mount, no Immich"
write_options plain
run_container
cexec mkdir -p /share/plain
sleep 40
if cexec curl -fsS "${BASE}/server/ping" >/dev/null 2>&1; then fail "Immich is running although /share/plain is not a mount"; fi
"$CLI" logs "$NAME" 2>&1 | grep -q "is not a mounted network share" || fail "no 'waiting for share' message in the log"
[ -z "$(cexec sh -c 'ls -A /share/plain')" ] || fail "something was written into the unmounted folder"
cexec sh -c 'ls /data/postgres/*/PG_VERSION' >/dev/null || fail "PostgreSQL was not initialised"
pass "Immich stays off and writes nothing when the share is not mounted"
cexec /usr/local/bin/afterimage-healthcheck || fail "health check fails while waiting for the share (Home Assistant would restart the app)"
[ "$(cexec cat /run/afterimage/state)" = "waiting" ] || fail "state is not 'waiting' while the share is missing"
pass "health check passes while waiting for the share"
"$CLI" stop -t 100 "$NAME" >/dev/null
"$CLI" rm "$NAME" >/dev/null

echo "== 2. first start with the share mounted"
write_options teststore
run_container
wait_for_immich || fail "Immich did not answer within 6 minutes"
pass "Immich answers on port 2283"
for i in $(seq 1 10); do [ "$(cexec cat /run/afterimage/state)" = "running" ] && break; sleep 3; done
[ "$(cexec cat /run/afterimage/state)" = "running" ] || fail "state did not become 'running' after Immich came up"
cexec /usr/local/bin/afterimage-healthcheck || fail "health check fails while Immich is running"
pass "health check passes once Immich is up (state 'running')"
for folder in library/library library/upload thumbs encoded-video profile backups; do
  [ -f "${WORK}/share/teststore/${folder}/.immich" ] || fail "missing ${folder}/.immich on the share"
done
pass "Immich's six folders and markers are on the share, in the split layout"
if cexec sh -c 'ps aux 2>/dev/null || true' | grep -qi 'machine.learning'; then fail "a machine learning process is running"; fi

echo "== 3. upload through the API"
cexec curl -fsS -X POST "${BASE}/auth/admin-sign-up" -H 'Content-Type: application/json' \
  -d '{"email":"smoke@example.com","password":"smoke-test-password","name":"Smoke Test"}' >/dev/null \
  || fail "admin sign-up failed"
TOKEN="$(cexec sh -c "curl -fsS -X POST ${BASE}/auth/login -H 'Content-Type: application/json' -d '{\"email\":\"smoke@example.com\",\"password\":\"smoke-test-password\"}' | node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>process.stdout.write(JSON.parse(s).accessToken||\"\"))'")"
[ -n "$TOKEN" ] || fail "login returned no access token"
pass "admin created and logged in"

SAMPLE="$(cexec sh -c "find /usr/src/app /usr/share -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' \) -size +2k 2>/dev/null | head -1")"
[ -n "$SAMPLE" ] || fail "no sample image found inside the container"
EXT="${SAMPLE##*.}"
cexec cp "$SAMPLE" "/tmp/smoke-sample.${EXT}"
WANT="$(cexec sha256sum "/tmp/smoke-sample.${EXT}" | awk '{print $1}')"
UPLOAD="$(cexec curl -sS -X POST "${BASE}/assets" -H "Authorization: Bearer ${TOKEN}" \
  -F "assetData=@/tmp/smoke-sample.${EXT}" -F 'deviceAssetId=smoke-1' -F 'deviceId=smoke-test' \
  -F 'fileCreatedAt=2025-12-31T23:30:00.000Z' -F 'fileModifiedAt=2025-12-31T23:30:00.000Z')"
ASSET_ID="$(printf '%s' "$UPLOAD" | sed -n 's/.*"id":"\([^"]*\)".*/\1/p')"
[ -n "$ASSET_ID" ] || fail "upload did not return an asset id: ${UPLOAD}"
pass "upload accepted (asset ${ASSET_ID})"

FOUND=""
for i in $(seq 1 30); do
  while IFS= read -r candidate; do
    if [ "$(shasum -a 256 "$candidate" | awk '{print $1}')" = "$WANT" ]; then FOUND="$candidate"; fi
  done < <(find "${WORK}/share/teststore/library" -type f ! -name '.immich' 2>/dev/null)
  [ -n "$FOUND" ] && break
  sleep 2
done
[ -n "$FOUND" ] || fail "the uploaded file is not on the share with the same SHA-256"
pass "original is on the share, byte for byte: ${FOUND#"${WORK}"/share/teststore/}"

echo "== 3b. trimmed settings and folder layout"
SETTINGS="$(cexec sh -c "curl -fsS ${BASE}/system-config -H 'Authorization: Bearer ${TOKEN}' | node -e 'let s=\"\";process.stdin.on(\"data\",d=>s+=d).on(\"end\",()=>{const c=JSON.parse(s);process.stdout.write([c.machineLearning.enabled,c.storageTemplate.enabled,c.ffmpeg.transcode,c.backup.database.keepLastAmount,c.newVersionCheck.enabled].join(\" \"))})'")"
[ "$SETTINGS" = "false true disabled 14 false" ] || fail "Immich is not running with the managed settings (got: ${SETTINGS})"
pass "machine learning off, storage template on, transcoding off, 14 dumps kept"
MOVED=""
for i in $(seq 1 45); do
  while IFS= read -r candidate; do
    if [ "$(shasum -a 256 "$candidate" | awk '{print $1}')" = "$WANT" ]; then MOVED="$candidate"; fi
  done < <(find "${WORK}/share/teststore/library/library" -type f -path '*/2025/12/*' 2>/dev/null)
  [ -n "$MOVED" ] && break
  sleep 2
done
[ -n "$MOVED" ] || fail "the original was not filed under library/<person>/2025/12/ within 90s"
pass "original filed by person, year and month: ${MOVED#"${WORK}"/share/teststore/}"
THUMBS=""
for i in $(seq 1 30); do
  THUMBS="$(find "${WORK}/share/teststore/thumbs" -type f ! -name '.immich' 2>/dev/null | head -1)"
  [ -n "$THUMBS" ] && break
  sleep 2
done
[ -n "$THUMBS" ] || fail "no thumbnail was written to the thumbs folder"
pass "thumbnails go to their own folder: ${THUMBS#"${WORK}"/share/teststore/}"

echo "== 4. database dump for Home Assistant backups"
cexec /usr/local/bin/afterimage-backup-pre >/dev/null || fail "backup_pre script failed"
cexec sh -c 'gzip -t /data/db-dump/immich-before-ha-backup.sql.gz && [ "$(stat -c %s /data/db-dump/immich-before-ha-backup.sql.gz)" -gt 10000 ]' \
  || fail "the pre-backup dump is missing or too small"
pass "pre-backup database dump written"

echo "== 5. stop and start again"
"$CLI" stop -t 100 "$NAME" >/dev/null
"$CLI" logs "$NAME" 2>&1 | grep -q "afterimage: stopped" || fail "the supervisor did not shut down in order"
if "$CLI" logs "$NAME" 2>&1 | grep -q "did not stop in"; then fail "a service had to be killed on shutdown"; fi
"$CLI" start "$NAME" >/dev/null
wait_for_immich || fail "Immich did not come back after a restart"
CODE="$(cexec curl -s -o /dev/null -w '%{http_code}' "${BASE}/assets/${ASSET_ID}" -H "Authorization: Bearer ${TOKEN}")"
[ "$CODE" = "200" ] || fail "the asset is gone after a restart (HTTP ${CODE})"
if "$CLI" logs "$NAME" 2>&1 | grep -q "was not properly shut down"; then fail "PostgreSQL had to recover from an unclean shutdown"; fi
pass "data survives a clean stop and start"

echo "== 6. Immich dies and comes back"
# Immich renames its main process (the one that starts the workers) to
# "immich"; the API worker is "immich-api".
MAIN_PID="$(cexec pgrep -o -f '^immich$' || true)"
[ -n "$MAIN_PID" ] || fail "could not find the Immich process"
cexec kill -KILL "$MAIN_PID"
sleep 5
"$CLI" logs "$NAME" 2>&1 | grep -q "Immich stopped unexpectedly" || fail "the supervisor did not notice Immich dying"
wait_for_immich || fail "Immich was not restarted"
CODE="$(cexec curl -s -o /dev/null -w '%{http_code}' "${BASE}/assets/${ASSET_ID}" -H "Authorization: Bearer ${TOKEN}")"
[ "$CODE" = "200" ] || fail "the asset is unreachable after the restart (HTTP ${CODE})"
pass "Immich is restarted after it dies"

echo
echo "All smoke tests passed."
