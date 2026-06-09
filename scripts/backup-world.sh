#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$ROOT/backups/aliveworld-$TS.tar.gz"

mkdir -p "$ROOT/backups"

docker compose -f "$ROOT/docker-compose.yml" stop luanti || true

tar -czf "$OUT" \
  -C "$ROOT" \
  data/worlds \
  data/minetest.conf \
  locks \
  local_mods \
  config

docker compose -f "$ROOT/docker-compose.yml" up -d luanti

echo "$OUT"
