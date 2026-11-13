#!/usr/bin/env bash
# Installs/updates the fighter server on this Linux box: fetches headless Godot into ~/$DEST,
# imports the game this script sits in and (re)starts the fighter-server systemd service.
# deploy.sh runs it after copying the game over; or run it by hand from a git clone:
#   git clone -b fighter https://github.com/ofurtumi/games ~/games
#   bash ~/games/fighter/tools/server/setup_remote.sh        # after `git pull`, run it again
# Env: BIND (127.0.0.1, "*" without a reverse proxy), PORT (7350), FILL (4), DEST (fighter-server).
set -euo pipefail
GAME="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${DEST:-fighter-server}"
BIND="${BIND:-127.0.0.1}"
PORT="${PORT:-7350}"
FILL="${FILL:-4}"
V="${V:-4.7.2}"
mkdir -p ~/"$DEST"
cd ~/"$DEST"
case "$(uname -m)" in
	x86_64) ARCH=x86_64 ;;
	aarch64|arm64) ARCH=arm64 ;;
	*) echo "unsupported CPU $(uname -m)"; exit 1 ;;
esac
BIN="Godot_v${V}-stable_linux.${ARCH}"
if [ ! -x "$BIN" ]; then
	command -v unzip >/dev/null || sudo apt-get install -y unzip
	curl -fL -o godot.zip "https://github.com/godotengine/godot/releases/download/${V}-stable/${BIN}.zip"
	unzip -o godot.zip && rm godot.zip && chmod +x "$BIN"
fi
dpkg -s libfontconfig1 >/dev/null 2>&1 || sudo apt-get install -y libfontconfig1 >/dev/null # silences a startup warning
echo "importing assets..."
timeout 300 "./$BIN" --headless --path "$GAME" --import >/dev/null 2>&1 || true

sudo tee /etc/systemd/system/fighter-server.service >/dev/null <<UNIT
[Unit]
Description=Arena fighter dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=$(id -un)
WorkingDirectory=$GAME
ExecStart=$HOME/$DEST/$BIN --headless --path $GAME -- --server --port $PORT --bind $BIND --fill $FILL
Restart=always
RestartSec=3
Nice=5

[Install]
WantedBy=multi-user.target
UNIT
sudo systemctl daemon-reload
sudo systemctl enable fighter-server >/dev/null 2>&1
sudo systemctl restart fighter-server
sleep 3
journalctl -u fighter-server -n 5 --no-pager -o cat || true
