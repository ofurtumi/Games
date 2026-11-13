#!/usr/bin/env bash
# Server half of deploy.sh (runs on the Linux box, from the copied game). Not meant to be run
# by hand; env DEST BIND PORT FILL V come from deploy.sh.
set -euo pipefail
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
timeout 300 "./$BIN" --headless --path game --import >/dev/null 2>&1 || true

sudo tee /etc/systemd/system/fighter-server.service >/dev/null <<UNIT
[Unit]
Description=Arena fighter dedicated server
After=network-online.target
Wants=network-online.target

[Service]
User=$(id -un)
WorkingDirectory=$HOME/$DEST/game
ExecStart=$HOME/$DEST/$BIN --headless --path $HOME/$DEST/game -- --server --port $PORT --bind $BIND --fill $FILL
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
