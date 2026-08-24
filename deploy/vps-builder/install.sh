#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$(id -u)" == 0 ]] || { echo 'Run as root.' >&2; exit 1; }
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
install -d -m 0750 /opt/scenic-route-builders /etc/scenic-route-builders /srv/dragmp-public-builder
install -m 0750 "$repo_root/deploy/vps-builder/dragmp-public-builder.sh" /opt/scenic-route-builders/dragmp-public-builder.sh
cat >/etc/systemd/system/dragmp-public-builder.service <<'EOF'
[Unit]
Description=DragMP Public VPS release builder
After=network-online.target
[Service]
Type=oneshot
EnvironmentFile=/etc/scenic-route-builders/github.env
ExecStart=/opt/scenic-route-builders/dragmp-public-builder.sh
Nice=5
TimeoutStartSec=30min
EOF
cat >/etc/systemd/system/dragmp-public-builder.timer <<'EOF'
[Unit]
Description=Poll DragMP Public and publish releases
[Timer]
OnBootSec=80s
OnUnitActiveSec=60s
RandomizedDelaySec=10s
Persistent=true
[Install]
WantedBy=timers.target
EOF
systemctl daemon-reload; systemctl enable --now dragmp-public-builder.timer
