#!/usr/bin/env bash
# Installs/updates the fighter server on this Linux box: fetches headless Godot into ~/$DEST,
# imports the game this script sits in and (re)starts the fighter-server systemd service.
# deploy.sh runs it after copying the game over; or run it by hand from a git clone:
#   git clone -b fighter https://github.com/ofurtumi/games ~/games
#   bash ~/games/fighter/tools/server/setup_remote.sh        # after `git pull`, run it again
# Also exports the browser build into WEB_ROOT for Caddy to serve (same content as the server).
# Env: BIND (127.0.0.1, "*" without a reverse proxy), PORT (7350), FILL (4), DEST (fighter-server),
#      WEB (1; 0 skips the browser build), WEB_ROOT (/var/www/fighter).
set -euo pipefail
GAME="$(cd "$(dirname "$0")/../.." && pwd)"
DEST="${DEST:-fighter-server}"
BIND="${BIND:-127.0.0.1}"
PORT="${PORT:-7350}"
FILL="${FILL:-4}"
V="${V:-4.7.2}"
WEB="${WEB:-1}"
WEB_ROOT="${WEB_ROOT:-/var/www/fighter}"
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

if [ "$WEB" = 1 ]; then
	# Only the web template is kept from the export templates (one-time ~1.3 GB download).
	TPL=~/.local/share/godot/export_templates/${V}.stable
	if [ ! -f "$TPL/web_nothreads_release.zip" ]; then
		echo "downloading export templates (once)..."
		mkdir -p "$TPL"
		curl -fL -o templates.tpz "https://github.com/godotengine/godot/releases/download/${V}-stable/Godot_v${V}-stable_export_templates.tpz"
		unzip -o -j templates.tpz "*/web_nothreads_release.zip" -d "$TPL"
		rm templates.tpz
	fi
	echo "exporting the browser build to $WEB_ROOT..."
	sudo mkdir -p "$WEB_ROOT" && sudo chown "$(id -un)" "$WEB_ROOT"
	mkdir -p "$GAME/build/web"
	timeout 600 "./$BIN" --headless --path "$GAME" --export-release Web "$GAME/build/web/index.html" >/dev/null 2>&1 || true
	if [ -f "$GAME/build/web/index.wasm" ]; then
		cp -f "$GAME"/build/web/* "$WEB_ROOT"/ && chmod -R a+rX "$WEB_ROOT"
	else
		echo "!! browser export failed (run the export by hand to see why)"
	fi
fi

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
