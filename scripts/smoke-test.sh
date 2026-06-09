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

# Settlements checks
if ! grep -q "aliveworld.settlements" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must set up aliveworld.settlements"
  exit 1
fi

if ! grep -q "ensure_initial" "$ROOT/local_mods/aliveworld_core/settlements.lua"; then
  echo "settlements.lua must have ensure_initial"
  exit 1
fi

if ! grep -q "tick_all" "$ROOT/local_mods/aliveworld_core/settlements.lua"; then
  echo "settlements.lua must have tick_all"
  exit 1
fi

if ! grep -q "aw_settlements" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_settlements command"
  exit 1
fi

if ! grep -q "aw_settlement_reset" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_settlement_reset command"
  exit 1
fi

if ! grep -q "ASCII output" "$ROOT/README.md"; then
  echo "README.md must contain ASCII output note"
  exit 1
fi

# World events checks
if ! grep -q "world_events.lua" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must dofile world_events.lua"
  exit 1
fi

if ! grep -q "rumors.lua" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must dofile rumors.lua"
  exit 1
fi

if ! grep -q "aliveworld.events" "$ROOT/local_mods/aliveworld_core/world_events.lua"; then
  echo "world_events.lua must set up aliveworld.events"
  exit 1
fi

if ! grep -q "generate_from_settlement" "$ROOT/local_mods/aliveworld_core/world_events.lua"; then
  echo "world_events.lua must have generate_from_settlement"
  exit 1
fi

if ! grep -q "aliveworld.rumors" "$ROOT/local_mods/aliveworld_core/rumors.lua"; then
  echo "rumors.lua must set up aliveworld.rumors"
  exit 1
fi

if ! grep -q "create_from_event" "$ROOT/local_mods/aliveworld_core/rumors.lua"; then
  echo "rumors.lua must have create_from_event"
  exit 1
fi

if ! grep -q "aw_events" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_events command"
  exit 1
fi

if ! grep -q "aw_rumors" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_rumors command"
  exit 1
fi

if ! grep -q "aw_event_reset" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_event_reset command"
  exit 1
fi

# AliveWorld Player checks
if ! [ -f "$ROOT/local_mods/aliveworld_player/mod.conf" ]; then
  echo "aliveworld_player must have mod.conf"
  exit 1
fi

if ! [ -f "$ROOT/local_mods/aliveworld_player/init.lua" ]; then
  echo "aliveworld_player must have init.lua"
  exit 1
fi

if ! grep -q "aw_news" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_news command"
  exit 1
fi

if ! grep -q "rumor_board" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register rumor_board node"
  exit 1
fi

if ! grep -q "signlike" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "rumor_board must use drawtype = signlike"
  exit 1
fi

if ! grep -q "wallmounted" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "rumor_board must use wallmounted paramtype2"
  exit 1
fi

if ! grep -q "on_rightclick" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "rumor_board must preserve right-click handler"
  exit 1
fi

if ! [ -f "$ROOT/local_mods/aliveworld_player/textures/aliveworld_rumor_board_front.png" ]; then
  echo "rumor_board must have front texture"
  exit 1
fi



if ! grep -q "Новости мира\|Состояние мира\|Летопись\|Активные слухи" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player UI must use Russian"
  exit 1
fi

if ! grep -q "load_mod_aliveworld_player" "$ROOT/data/worlds/aliveworld/world.mt"; then
  echo "world.mt must have load_mod_aliveworld_player = true"
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
