#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "docker-compose.yml"
  "config/luanti.conf"
  "config/content.json"
  "data/worlds/aliveworld/world.mt"
  "local_mods/aliveworld_core/mod.conf"
  "local_mods/aliveworld_core/init.lua"
  "local_mods/aliveworld_bridge_mcl/mod.conf"
  "local_mods/aliveworld_bridge_mcl/init.lua"
  "local_mods/aliveworld_admin/mod.conf"
  "local_mods/aliveworld_admin/init.lua"
  "scripts/install-content.py"
  "scripts/sync-local-mods.sh"
  "scripts/backup-world.sh"
  "scripts/smoke-test.sh"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$ROOT/$file" ]; then
    echo "Missing required file: $file"
    exit 1
  fi
done

if ! grep -q "./data:/config/.minetest" "$ROOT/docker-compose.yml"; then
  echo "docker-compose.yml must use ./data:/config/.minetest"
  exit 1
fi

if grep -R "/opt/luanti-aliveworld" "$ROOT" \
  --exclude-dir=.git \
  --exclude-dir=data \
  --exclude-dir=backups \
  --exclude='smoke-test.sh'; then
  echo "Found forbidden hardcoded /opt/luanti-aliveworld path"
  exit 1
fi

chmod +x "$ROOT/scripts/install-content.py"
chmod +x "$ROOT/scripts/sync-local-mods.sh"
chmod +x "$ROOT/scripts/backup-world.sh"
chmod +x "$ROOT/scripts/smoke-test.sh"

docker compose -f "$ROOT/docker-compose.yml" config >/dev/null

echo "Smoke test OK"
