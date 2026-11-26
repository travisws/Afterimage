#!/usr/bin/env bash
# Builds the Afterimage Traefik app and checks it in local arm64 containers,
# against a stand-in for Immich that reports the size and SHA-256 of every
# upload it receives. It cannot get a real certificate (no real Cloudflare
# token), so Traefik serves its default certificate and curl uses -k. On the
# Pi, check the real certificate by hand.
#
# Usage: scripts/traefik-smoke-test.sh            (Apple's `container` tool)
#        CONTAINER_CLI=docker scripts/traefik-smoke-test.sh

set -Eeuo pipefail

CLI="${CONTAINER_CLI:-container}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${ROOT}/.smoke-traefik"
IMAGE="afterimage-traefik-smoke:dev"
BACKEND_IMAGE="python:3.14-alpine"
TRAEFIK="c0ffee00-traefik"
BACKEND="afterimage-smoke-backend"
DOMAIN="photos.example.test"
TOKEN="smoke-cloudflare-token-0123456789abcdef"

pass() { printf 'PASS  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; echo "--- traefik log ---" >&2; "$CLI" logs "$TRAEFIK" 2>&1 | tail -30 >&2 || true; exit 1; }
ip_of() { "$CLI" inspect "$1" | python3 -c 'import json,sys; d=json.load(sys.stdin); d=d[0] if isinstance(d,list) else d; n=(d.get("networks") or d.get("status",{}).get("networks") or []); a=(n[0].get("address") or n[0].get("ipv4Address") or "") if n else ""; print(a.split("/")[0])'; }

cleanup() {
  for c in "$TRAEFIK" "$BACKEND" afterimage-smoke-badconfig; do
    "$CLI" stop "$c" >/dev/null 2>&1 || true
    "$CLI" rm "$c" >/dev/null 2>&1 || true
  done
  "$CLI" image rm "$IMAGE" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

write_options() {
  cat > "${WORK}/options/options.json" <<JSON
{
  "domain": "$1",
  "acme_email": "smoke@example.com",
  "cloudflare_dns_api_token": "${TOKEN}",
  "staging": true,
  "log_level": "info"$2
}
JSON
}

echo "== build"
cleanup
mkdir -p "${WORK}/options" "${WORK}/backend"
if [ "$CLI" = "container" ]; then
  container system start --disable-kernel-install --timeout 60 >/dev/null 2>&1 || true
fi
if ! "$CLI" build --tag "$IMAGE" "${ROOT}/traefik" >"${WORK}/build.log" 2>&1; then
  tail -30 "${WORK}/build.log" >&2
  fail "image build failed"
fi
pass "image built ($(grep -m1 -o 'Version: *v[0-9.]*' "${WORK}/build.log" | tr -s ' ' || echo 'traefik'))"

# Stand-in for Immich: answers GET with "immich-standin", and for POST reads
# the body in chunks and answers with its size and SHA-256.
cat > "${WORK}/backend/server.py" <<'PY'
import hashlib, http.server
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        body = f"immich-standin host={self.headers.get('Host')} proto={self.headers.get('X-Forwarded-Proto')}".encode()
        self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        left = int(self.headers.get("Content-Length", "0")); h = hashlib.sha256(); n = 0
        while left:
            chunk = self.rfile.read(min(left, 1 << 16))
            if not chunk: break
            h.update(chunk); n += len(chunk); left -= len(chunk)
        body = f"{n} {h.hexdigest()}".encode()
        self.send_response(201); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a): pass
http.server.ThreadingHTTPServer(("0.0.0.0", 2283), H).serve_forever()
PY
"$CLI" run -d --name "$BACKEND" -v "${WORK}/backend:/srv" "$BACKEND_IMAGE" python3 /srv/server.py >/dev/null
sleep 3
BACKEND_IP="$(ip_of "$BACKEND")"
[ -n "$BACKEND_IP" ] || fail "could not find the stand-in's address"

echo "== 1. configuration errors stop the app"
write_options "not a domain" ""
if "$CLI" run --name afterimage-smoke-badconfig -v "${WORK}/options:/options" -e AFTERIMAGE_OPTIONS=/options/options.json "$IMAGE" >"${WORK}/bad.log" 2>&1; then
  fail "the app started with an invalid domain"
fi
grep -q '"domain" must be a host name' "${WORK}/bad.log" || fail "no clear message for an invalid domain"
"$CLI" rm afterimage-smoke-badconfig >/dev/null 2>&1 || true
pass "an invalid domain is refused with a clear message"

echo "== 2. start in front of the stand-in"
write_options "$DOMAIN" ", \"immich_backend\": \"http://${BACKEND_IP}:2283\""
"$CLI" run -d --name "$TRAEFIK" -v "${WORK}/options:/options" -e AFTERIMAGE_OPTIONS=/options/options.json "$IMAGE" >/dev/null
sleep 6
TRAEFIK_IP="$(ip_of "$TRAEFIK")"
[ -n "$TRAEFIK_IP" ] || fail "could not find Traefik's address"
"$CLI" logs "$TRAEFIK" 2>&1 | grep -q "serving https://${DOMAIN}" || fail "no start-up line in the log"
CURL=(curl -sS -k --max-time 300 --resolve "${DOMAIN}:443:${TRAEFIK_IP}")
OUT="$("${CURL[@]}" "https://${DOMAIN}/")"
[ "$OUT" = "immich-standin host=${DOMAIN} proto=https" ] || fail "unexpected answer through Traefik: ${OUT}"
pass "HTTPS for ${DOMAIN} reaches Immich, with the original Host and X-Forwarded-Proto https"
CODE="$(curl -sS -k -o /dev/null -w '%{http_code}' --resolve "other.example.test:443:${TRAEFIK_IP}" https://other.example.test/)"
[ "$CODE" = "404" ] || fail "another host name was not refused (HTTP ${CODE})"
pass "other host names get 404"

echo "== 3. uploads"
head -c 268435456 /dev/urandom > "${WORK}/big.bin"
WANT="268435456 $(shasum -a 256 "${WORK}/big.bin" | awk '{print $1}')"
GOT="$("${CURL[@]}" --data-binary @"${WORK}/big.bin" -H 'Content-Type: application/octet-stream' "https://${DOMAIN}/upload")"
[ "$GOT" = "$WANT" ] || fail "256 MiB upload arrived changed: ${GOT}"
pass "256 MiB upload arrives byte for byte"
head -c 7500000 /dev/urandom > "${WORK}/slow.bin"
WANT="7500000 $(shasum -a 256 "${WORK}/slow.bin" | awk '{print $1}')"
START=$(date +%s)
GOT="$("${CURL[@]}" --limit-rate 100k --data-binary @"${WORK}/slow.bin" -H 'Content-Type: application/octet-stream' "https://${DOMAIN}/upload")"
TOOK=$(( $(date +%s) - START ))
[ "$GOT" = "$WANT" ] || fail "slow upload failed after ${TOOK}s: ${GOT}"
[ "$TOOK" -gt 65 ] || fail "slow upload took only ${TOOK}s, so it did not test the 60 s limit"
pass "an upload lasting ${TOOK}s is not cut off"

echo "== 4. secrets"
if "$CLI" logs "$TRAEFIK" 2>&1 | grep -q "$TOKEN"; then fail "the Cloudflare token appears in the log"; fi
if "$CLI" exec "$TRAEFIK" sh -c 'cat /proc/*/environ 2>/dev/null' | tr '\0' '\n' | grep -q "$TOKEN"; then fail "the token is in a process environment"; fi
PERMS="$("$CLI" exec "$TRAEFIK" stat -c '%a' /run/traefik/cf_dns_api_token /data/acme-staging.json | tr '\n' ' ')"
[ "$PERMS" = "600 600 " ] || fail "token or certificate store is readable by others (${PERMS})"
pass "token kept out of logs and environment; token and certificate files are 600"

echo "== 5. finds Immich from its own host name"
"$CLI" stop "$TRAEFIK" >/dev/null; "$CLI" rm "$TRAEFIK" >/dev/null
write_options "$DOMAIN" ""
"$CLI" run -d --name "$TRAEFIK" -v "${WORK}/options:/options" -e AFTERIMAGE_OPTIONS=/options/options.json "$IMAGE" >/dev/null
sleep 4
OWN="$("$CLI" exec "$TRAEFIK" hostname)"
if [[ "$OWN" == *-traefik ]]; then
  "$CLI" logs "$TRAEFIK" 2>&1 | grep -q "serving https://${DOMAIN} -> http://${OWN%-traefik}-afterimage:2283" || fail "did not derive the Immich address from ${OWN}"
  pass "derives http://${OWN%-traefik}-afterimage:2283 from its own host name"
else
  printf 'SKIP  this container tool does not set the host name to the container name (%s)\n' "$OWN"
fi

echo
echo "All Traefik smoke tests passed."
