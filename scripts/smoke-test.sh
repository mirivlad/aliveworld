#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

required_files=(
  "Dockerfile"
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
  "scripts/build-image.sh"
  "scripts/console.sh"
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

DOCKER_COMPOSE="$ROOT/docker-compose.yml"
DOCKERFILE="$ROOT/Dockerfile"

# docker-compose.yml checks
if grep -q "lscr.io/linuxserver" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must not use lscr.io/linuxserver"
  exit 1
fi

if grep -q "ghcr.io/luanti-org/luanti" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must not use ghcr.io/luanti-org/luanti as runtime image"
  exit 1
fi

if ! grep -q "build:" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must use build: (local Dockerfile)"
  exit 1
fi

if ! grep -q "stdin_open: true" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must have stdin_open: true"
  exit 1
fi

if ! grep -q "tty: true" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must have tty: true"
  exit 1
fi

if ! grep -q -- "--terminal" "$DOCKER_COMPOSE"; then
  echo "docker-compose.yml must use --terminal"
  exit 1
fi

# Dockerfile checks
if ! grep -q "ENABLE_CURSES=ON" "$DOCKERFILE"; then
  echo "Dockerfile must have ENABLE_CURSES=ON (ncurses support)"
  exit 1
fi

if ! grep -q "BUILD_SERVER=ON" "$DOCKERFILE"; then
  echo "Dockerfile must have BUILD_SERVER=ON"
  exit 1
fi

# Content checks
if ! grep -q "aliveworld.tick" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must have aliveworld.tick function"
  exit 1
fi

if ! grep -q "aliveworld.reset" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must have aliveworld.reset function"
  exit 1
fi

if ! grep -q "aw_tick_reset" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register aw_tick_reset command"
  exit 1
fi

if ! grep -q "get_environment_profile" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must call get_environment_profile on tick"
  exit 1
fi

if ! grep -q "get_environment_profile\|get_season\|get_food_profile\|get_wood_profile\|get_danger_profile" "$ROOT/local_mods/aliveworld_bridge_mcl/init.lua"; then
  echo "aliveworld_bridge_mcl must provide query API functions"
  exit 1
fi

if ! grep -q "label_en" "$ROOT/local_mods/aliveworld_bridge_mcl/init.lua"; then
  echo "aliveworld_bridge_mcl must provide label_en fields"
  exit 1
fi

if grep -q "Сезон:\|Еда:\|Опасность:\|Дерево:" "$ROOT/local_mods/aliveworld_admin/init.lua"; then
  echo "aliveworld_admin must use English/ASCII only, no Cyrillic"
  exit 1
fi

if grep -q "Симуляция\|сброшен\|Хроника\|Конфиг\|Формат\|Неизвестный\|Пауза\|Возобновить\|Показать\|день\|год" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core commands must use English/ASCII only, no Cyrillic"
  exit 1
fi

if ! grep -q "aw_bridge" "$ROOT/local_mods/aliveworld_admin/init.lua"; then
  echo "aliveworld_admin must register aw_bridge command"
  exit 1
fi

if ! grep -q "aw_status" "$ROOT/local_mods/aliveworld_admin/init.lua"; then
  echo "aliveworld_admin must register aw_status command"
  exit 1
fi

# No forbidden hardcoded paths
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
chmod +x "$ROOT/scripts/build-image.sh"
chmod +x "$ROOT/scripts/console.sh"

docker compose -f "$DOCKER_COMPOSE" config >/dev/null

echo "Smoke test OK"
