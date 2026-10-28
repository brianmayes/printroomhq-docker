# Print Room HQ in Docker: for a NAS, Unraid, a home server or any Linux box with Docker.
# Guide: https://printroomhq.com/guide/docker/
#
#   docker build -t printroomhq https://printroomhq.com/docker/Dockerfile
#   docker run -d --name printroomhq --network host --restart unless-stopped -v printroomhq:/printroomhq printroomhq
#
# The image holds Node.js, ffmpeg and a small starter. The first start downloads the current Print Room HQ from
# printroomhq.com (checked against its published checksum) into the /printroomhq volume, next to your printers,
# settings and history. From then on Print Room HQ updates itself there, like on a Pi, so the image rarely needs
# rebuilding. Host networking lets it find printers on your network by itself.
ARG BASE=node:22-bookworm-slim
FROM ${BASE}

RUN apt-get update \
 && apt-get install -y --no-install-recommends ffmpeg tini unzip curl ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && (id -u node >/dev/null 2>&1 || useradd --create-home --uid 1000 node)

ENV PRHQ_HOME=/printroomhq \
    PRHQ_FEED=https://printroomhq.com/beta/dl \
    PORT=8080 \
    PRHQ_DOCKER=1 \
    NODE_ENV=production

COPY <<'EOF' /usr/local/bin/printroomhq
#!/bin/bash
# Starts Print Room HQ: installs it into the volume the first time, then runs it and starts it again after an
# update (Print Room HQ exits with code 3 to finish one) or if it ever stops.
set -uo pipefail
H="${PRHQ_HOME:-/printroomhq}"
APP="$H/app"
log() { echo "[printroomhq] $*"; }

mkdir -p "$APP" "$H/config" "$H/data"
# Run as the unprivileged "node" user, owning its own volume (PUID/PGID pick another user, e.g. on Unraid).
if [ "$(id -u)" = 0 ]; then
  RUN_UID="${PUID:-$(id -u node)}"; RUN_GID="${PGID:-$(id -g node)}"
  chown -R "$RUN_UID:$RUN_GID" "$H" 2>/dev/null || log "Couldn't take ownership of $H; it may be read-only."
  exec setpriv --reuid="$RUN_UID" --regid="$RUN_GID" --clear-groups env HOME="$H" "$0" "$@"
fi

install_app() {
  local tmp app want got
  tmp=$(mktemp -d)
  log "Downloading Print Room HQ from $PRHQ_FEED"
  curl -fsSL "$PRHQ_FEED/latest.json" -o "$tmp/latest.json" || { log "Couldn't reach $PRHQ_FEED. Check this container can reach the internet."; rm -rf "$tmp"; return 1; }
  app=$(sed -n 's/.*"app": *"\([^"]*\)".*/\1/p' "$tmp/latest.json")
  want=$(sed -n 's/.*"appSha256": *"\([0-9a-f]*\)".*/\1/p' "$tmp/latest.json")
  [[ "$app" =~ ^PrintRoomHQ-app-[0-9A-Za-z.-]+\.zip$ ]] || { log "The release file didn't name a Print Room HQ download; stopping."; rm -rf "$tmp"; return 1; }
  [ "${#want}" -eq 64 ] || { log "The release file had no checksum for the download; stopping."; rm -rf "$tmp"; return 1; }
  curl -fsSL "$PRHQ_FEED/$app" -o "$tmp/app.zip" || { log "The download failed."; rm -rf "$tmp"; return 1; }
  got=$(sha256sum "$tmp/app.zip" | awk '{print $1}')
  [ "$want" = "$got" ] || { log "The download didn't match its checksum; stopping."; rm -rf "$tmp"; return 1; }
  unzip -q "$tmp/app.zip" -d "$tmp/app" || { log "Couldn't unpack the download."; rm -rf "$tmp"; return 1; }
  for k in src public pi package.json package-lock.json; do
    rm -rf "${APP:?}/$k"
    [ -e "$tmp/app/$k" ] && cp -a "$tmp/app/$k" "$APP/$k"
  done
  rm -rf "$tmp"
  log "Installing $(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$APP/package.json" | head -1)"
  install_deps
}

# Its packages, from npm. A finished install leaves a copy of the lock file in node_modules, so one that was cut
# short (or a lock file changed by an update) is installed again.
deps_ok() { [ -f "$APP/node_modules/.prhq-lock" ] && cmp -s "$APP/package-lock.json" "$APP/node_modules/.prhq-lock"; }
install_deps() {
  log "Installing its packages (a minute or two)."
  (cd "$APP" && npm ci --omit=dev --no-audit --no-fund --loglevel=error) || { log "Installing its packages failed."; return 1; }
  cp "$APP/package-lock.json" "$APP/node_modules/.prhq-lock"
}

if [ ! -f "$APP/src/server.js" ] || [ ! -f "$APP/package.json" ]; then
  install_app || { log "Trying again in 60 seconds."; sleep 60; exit 1; }
elif ! deps_ok; then
  install_deps || { log "Trying again in 60 seconds."; sleep 60; exit 1; }
fi

cd "$APP"
export DATA_DIR="$H/data" CONFIG="$H/config/printers.json"
child=0; stopping=0
trap 'stopping=1; [ "$child" -gt 0 ] && kill -TERM "$child" 2>/dev/null' TERM INT
while :; do
  node src/server.js & child=$!
  wait "$child"; code=$?
  if [ "$stopping" = 1 ]; then wait "$child" 2>/dev/null; log "Stopped."; exit 0; fi
  child=0
  if [ "$code" = 3 ]; then log "Restarting to finish an update."; continue; fi
  log "Print Room HQ stopped (exit $code). Starting it again in 5 seconds."
  sleep 5
done
EOF

RUN chmod 755 /usr/local/bin/printroomhq && mkdir -p /printroomhq && chown node:node /printroomhq
VOLUME /printroomhq
EXPOSE 8080
HEALTHCHECK --interval=60s --timeout=5s --start-period=180s CMD curl -fsS "http://127.0.0.1:${PORT}/api/access/status" >/dev/null || exit 1
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/printroomhq"]
