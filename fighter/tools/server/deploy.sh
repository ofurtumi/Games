#!/usr/bin/env bash
# Deploys the dedicated server to a Linux box over SSH (run from your own machine, repo root
# or anywhere). Copies the game, fetches the matching headless Godot once, imports assets and
# (re)starts a systemd service. Re-run it after every game update - clients and server must
# have the same items/maps.
#
#   tools/server/deploy.sh myserver                 # behind Caddy: binds 127.0.0.1:7350
#   tools/server/deploy.sh myserver --public        # no proxy: listens on all interfaces
#
# Env: PORT (7350), FILL (4 fighters incl. bots), DEST (~/fighter-server on the server).
# The service runs as your SSH user. sudo is needed once per deploy to install/restart it.
set -euo pipefail

HOST="${1:?usage: deploy.sh <ssh-host> [--public]}"
BIND=127.0.0.1
[ "${2:-}" = "--public" ] && BIND="*"
PORT="${PORT:-7350}"
FILL="${FILL:-4}"
DEST="${DEST:-fighter-server}" # relative to the remote home directory
GODOT_VERSION=4.7.2

cd "$(dirname "$0")/../.."

echo "==> copying game to $HOST:~/$DEST/game"
ssh "$HOST" "mkdir -p ~/$DEST/game"
rsync -az --delete --exclude .godot --exclude '__pycache__' --exclude '*.pyc' --exclude .DS_Store \
	./ "$HOST:$DEST/game/"

echo "==> setting up Godot $GODOT_VERSION and the service"
ssh -t "$HOST" "DEST='$DEST' BIND='$BIND' PORT='$PORT' FILL='$FILL' V='$GODOT_VERSION' bash ~/$DEST/game/tools/server/setup_remote.sh"

echo
echo "==> done. Logs: ssh $HOST journalctl -u fighter-server -f"
if [ "$BIND" = "127.0.0.1" ]; then
	cat <<CADDY
If Caddy isn't set up for it yet, add this to /etc/caddy/Caddyfile on the server
(with a DNS record for the name pointing at your home IP, like your other sites),
then: sudo systemctl reload caddy

fight.example.com {
	reverse_proxy 127.0.0.1:$PORT
}

Players then type fight.example.com in ONLINE -> SERVER.
CADDY
fi
