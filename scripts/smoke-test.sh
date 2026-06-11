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
WORLD_MT="$ROOT/data/worlds/aliveworld/world.mt"

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

# Dev world mapgen checks
if ! grep -q "^gameid = mineclonia$" "$WORLD_MT"; then
  echo "world.mt must use gameid = mineclonia"
  exit 1
fi

if ! grep -q "^mg_name = carpathian$" "$WORLD_MT"; then
  echo "world.mt must use mg_name = carpathian"
  exit 1
fi

if ! grep -q "^water_level = 1$" "$WORLD_MT"; then
  echo "world.mt must use water_level = 1"
  exit 1
fi

if ! grep -q "^chunksize = 5$" "$WORLD_MT"; then
  echo "world.mt must use chunksize = 5"
  exit 1
fi

if grep -q "^mgv7_spflags" "$WORLD_MT"; then
  echo "world.mt must not carry mgv7_spflags for carpathian mapgen"
  exit 1
fi

if grep -q "5663755894446027356" "$WORLD_MT"; then
  echo "world.mt must not use the old v7 seed"
  exit 1
fi

if ! grep -q "^fixed_map_seed = " "$WORLD_MT"; then
  echo "world.mt must set fixed_map_seed for reproducible first world creation"
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

# Sites module checks
if ! [ -f "$ROOT/local_mods/aliveworld_core/sites.lua" ]; then
  echo "aliveworld_core must have sites.lua"
  exit 1
fi

if ! grep -q "aliveworld.sites" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must set up aliveworld.sites"
  exit 1
fi

if ! grep -q "sites.lua" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must dofile sites.lua"
  exit 1
fi

if ! grep -q "ensure_initial_settlement_sites" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must call ensure_initial_settlement_sites"
  exit 1
fi

if ! grep -q "create_event_site" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must call create_event_site in tick"
  exit 1
fi

if ! grep -q "/aw_sites" "$ROOT/README.md"; then
  echo "README.md must mention /aw_sites"
  exit 1
fi

if ! grep -q "/aw_places" "$ROOT/README.md"; then
  echo "README.md must mention /aw_places"
  exit 1
fi

if ! grep -q "/aw_near" "$ROOT/README.md"; then
  echo "README.md must mention /aw_near"
  exit 1
fi

if ! grep -q "aw_sites" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_sites command"
  exit 1
fi

if ! grep -q "aw_sites_reset" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_sites_reset command"
  exit 1
fi

if ! grep -q "aw_places" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_places command"
  exit 1
fi

if ! grep -q "aw_near" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_near command"
  exit 1
fi

# AliveWorld World mod checks
required_files+=(
  "local_mods/aliveworld_world/mod.conf"
  "local_mods/aliveworld_world/init.lua"
)

if ! [ -f "$ROOT/local_mods/aliveworld_world/mod.conf" ]; then
  echo "aliveworld_world must have mod.conf"
  exit 1
fi

if ! [ -f "$ROOT/local_mods/aliveworld_world/init.lua" ]; then
  echo "aliveworld_world must have init.lua"
  exit 1
fi

if ! grep -q "aliveworld.materialization" "$ROOT/local_mods/aliveworld_world/init.lua"; then
  echo "aliveworld_world must set up aliveworld.materialization"
  exit 1
fi

if ! grep -q "load_mod_aliveworld_world" "$ROOT/data/worlds/aliveworld/world.mt"; then
  echo "world.mt must have load_mod_aliveworld_world = true"
  exit 1
fi

# Reality Anchoring checks
if ! grep -q "physical_status" "$ROOT/local_mods/aliveworld_core/sites.lua"; then
  echo "sites.lua must have physical_status field"
  exit 1
fi

if ! grep -q "anchor_site" "$ROOT/local_mods/aliveworld_core/sites.lua"; then
  echo "sites.lua must have anchor_site function"
  exit 1
fi

if ! grep -q "aw_site_debug" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_site_debug command"
  exit 1
fi

if ! grep -q "aw_whereami" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_whereami command"
  exit 1
fi

if ! grep -q "aw_compass" "$ROOT/local_mods/aliveworld_core/init.lua"; then
  echo "aliveworld_core must register /aw_compass command"
  exit 1
fi

# Direction logic test (matching Z-axis convention: -z=north, +z=south)
echo -n "  direction logic: "
python3 -c "
import math, sys
DIR = ['north','north-east','east','south-east','south','south-west','west','north-west']
def dir_idx(fx, fz, tx, tz):
    dx = tx - fx; dz = tz - fz
    angle = math.degrees(math.atan2(-dz, dx))
    bearing = (90 - angle) % 360
    return int((bearing + 22.5) // 45) % 8
tests = [
    ((0,0),(100,0),'east'), ((0,0),(-100,0),'west'),
    ((0,0),(0,-100),'north'), ((0,0),(0,100),'south'),
    ((0,0),(100,-100),'north-east'), ((0,0),(100,100),'south-east'),
    ((0,0),(-100,-100),'north-west'), ((0,0),(-100,100),'south-west'),
    ((245,-145),(320,-180),'north-east'),
]
for (fx,fz),(tx,tz),exp in tests:
    got = DIR[dir_idx(fx,fz,tx,tz)]
    if got != exp:
        print(f'FAIL: ({fx},{fz})->({tx},{tz}) expected {exp}, got {got}')
        sys.exit(1)
print('PASS')
" || exit 1

# Materialization checks
if ! grep -q "materialize_site" "$ROOT/local_mods/aliveworld_world/init.lua"; then
  echo "aliveworld_world must have materialize_site command"
  exit 1
fi

if ! grep -q "materialize_near" "$ROOT/local_mods/aliveworld_world/init.lua"; then
  echo "aliveworld_world must have materialize_near command"
  exit 1
fi

if ! grep -q "aw_markers" "$ROOT/local_mods/aliveworld_world/init.lua"; then
  echo "aliveworld_world must register /aw_markers command"
  exit 1
fi

# Player UI physical_status checks
if ! grep -q "отмечено\|не отмечено" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player UI must mention physical status"
  exit 1
fi

if ! grep -q "aw_investigate" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_investigate command"
  exit 1
fi

# GPS/Tracking checks

if ! [ -f "$ROOT/local_mods/aliveworld_player/tracking.lua" ]; then
  echo "aliveworld_player must have tracking.lua"
  exit 1
fi

if ! [ -f "$ROOT/local_mods/aliveworld_player/radar.lua" ]; then
  echo "aliveworld_player must have radar.lua"
  exit 1
fi

if ! grep -q "aliveworld_player.tracking" "$ROOT/local_mods/aliveworld_player/tracking.lua"; then
  echo "tracking.lua must set up aliveworld_player.tracking"
  exit 1
fi

if ! grep -q "aliveworld_player.radar" "$ROOT/local_mods/aliveworld_player/radar.lua"; then
  echo "radar.lua must set up aliveworld_player.radar"
  exit 1
fi

if ! grep -q 'register_chatcommand("aw_track"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_track command"
  exit 1
fi

if ! grep -q 'register_chatcommand("aw_track_event"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_track_event command"
  exit 1
fi

if ! grep -q 'register_chatcommand("aw_untrack"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_untrack command"
  exit 1
fi

if ! grep -q 'register_chatcommand("aw_tracks"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_tracks command"
  exit 1
fi

if ! grep -q 'register_chatcommand("aw_gps"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register /aw_gps command"
  exit 1
fi

if ! grep -q 'register_craftitem("aliveworld_player:gps"' "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must register aliveworld_player:gps item"
  exit 1
fi

if ! grep -q "aliveworld_gps.png" "$ROOT/local_mods/aliveworld_player/init.lua"; then
  echo "aliveworld_player must reference aliveworld_gps.png"
  exit 1
fi

if ! grep -q "get_points_for_player" "$ROOT/local_mods/aliveworld_player/radar.lua"; then
  echo "radar.lua must expose get_points_for_player"
  exit 1
fi

if ! [ -f "$ROOT/local_mods/aliveworld_player/textures/aliveworld_gps.png" ]; then
  echo "aliveworld_player must have aliveworld_gps.png texture"
  exit 1
fi

python3 - "$ROOT" <<'PY'
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
mods_root = root / "local_mods"
texture_refs = re.compile(r'["\'](aliveworld_[A-Za-z0-9_./-]+\.png)["\']')

def required_deps(mod_dir):
    mod_conf = mod_dir / "mod.conf"
    deps = []
    if not mod_conf.exists():
        return deps
    for line in mod_conf.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line.startswith("depends"):
            _, value = line.split("=", 1)
            deps.extend(d.strip() for d in value.split(",") if d.strip())
    return deps

errors = []
for mod_dir in sorted(mods_root.glob("aliveworld_*")):
    if mod_dir.name == "aliveworld_test_suite" or not mod_dir.is_dir():
        continue
    owners = [mod_dir] + [mods_root / dep for dep in required_deps(mod_dir)]
    for lua_file in mod_dir.rglob("*.lua"):
        text = lua_file.read_text(encoding="utf-8")
        for texture in sorted(set(texture_refs.findall(text))):
            found = any((owner / "textures" / texture).exists() for owner in owners)
            if not found:
                rel = lua_file.relative_to(root)
                errors.append(f"{rel} references {texture} outside its mod or required deps")

if errors:
    for error in errors:
        print(error)
    sys.exit(1)
PY

# README checks
if ! grep -q "/aw_site_debug" "$ROOT/README.md"; then
  echo "README.md must mention /aw_site_debug"
  exit 1
fi

if ! grep -q "/aw_anchor_site" "$ROOT/README.md"; then
  echo "README.md must mention /aw_anchor_site"
  exit 1
fi

if ! grep -q "/aw_investigate" "$ROOT/README.md"; then
  echo "README.md must mention /aw_investigate"
  exit 1
fi

if ! grep -q "AliveWorld GPS" "$ROOT/README.md"; then
  echo "README.md must mention AliveWorld GPS"
  exit 1
fi

if ! grep -q "/aw_track " "$ROOT/README.md"; then
  echo "README.md must mention /aw_track"
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

# ================================================
# Luanti TestKit checks
# ================================================

required_files+=(
  "local_mods/luanti_testkit/mod.conf"
  "local_mods/luanti_testkit/init.lua"
  "local_mods/luanti_testkit/api.lua"
  "local_mods/luanti_testkit/assertions.lua"
  "local_mods/luanti_testkit/player.lua"
  "local_mods/luanti_testkit/suites.lua"
  "local_mods/luanti_testkit/reporter.lua"
  "local_mods/aliveworld_test_suite/mod.conf"
  "local_mods/aliveworld_test_suite/init.lua"
  "scripts/run-test-client.sh"
  "scripts/run-luanti-tests.sh"
  "secrets/awbot.password.example"
  "docs/testing.md"
)

for file in "${required_files[@]}"; do
  if [ ! -f "$ROOT/$file" ]; then
    echo "Missing required file: $file"
    exit 1
  fi
done

# TestKit chat commands
if ! grep -q 'register_chatcommand("ltk_run"' "$ROOT/local_mods/luanti_testkit/api.lua"; then
  echo "luanti_testkit must register /ltk_run command"
  exit 1
fi

if ! grep -q 'register_chatcommand("ltk_all"' "$ROOT/local_mods/luanti_testkit/api.lua"; then
  echo "luanti_testkit must register /ltk_all command"
  exit 1
fi

if ! grep -q 'register_chatcommand("ltk_report"' "$ROOT/local_mods/luanti_testkit/reporter.lua"; then
  echo "luanti_testkit must register /ltk_report command"
  exit 1
fi

if ! grep -q 'register_chatcommand("ltk_list"' "$ROOT/local_mods/luanti_testkit/reporter.lua"; then
  echo "luanti_testkit must register /ltk_list command"
  exit 1
fi

# TestKit suite registration
if ! grep -q 'register_test' "$ROOT/local_mods/luanti_testkit/tests/smoke.lua"; then
  echo "luanti_testkit smoke tests must use register_test"
  exit 1
fi

# AliveWorld test suite checks
if ! grep -q 'register_test.*aliveworld.*direction' "$ROOT/local_mods/aliveworld_test_suite/tests/direction.lua"; then
  echo "aliveworld_test_suite must have direction tests (register_test)"
  exit 1
fi

if ! grep -q 'register_test.*aliveworld.*rumor' "$ROOT/local_mods/aliveworld_test_suite/tests/rumors.lua"; then
  echo "aliveworld_test_suite must have rumors tests"
  exit 1
fi

if ! grep -q 'register_test.*aliveworld.*radar' "$ROOT/local_mods/aliveworld_test_suite/tests/radar.lua"; then
  echo "aliveworld_test_suite must have radar tests"
  exit 1
fi

# TestKit mod.conf must NOT depend on aliveworld
if grep -q "^depends.*aliveworld" "$ROOT/local_mods/luanti_testkit/mod.conf"; then
  echo "luanti_testkit/mod.conf must NOT depend on aliveworld (only optional_depends)"
  exit 1
fi

# Run-test-client script must be executable
chmod +x "$ROOT/scripts/run-test-client.sh"
chmod +x "$ROOT/scripts/run-luanti-tests.sh"

chmod +x "$ROOT/scripts/install-content.py"
chmod +x "$ROOT/scripts/sync-local-mods.sh"
chmod +x "$ROOT/scripts/backup-world.sh"
chmod +x "$ROOT/scripts/smoke-test.sh"
chmod +x "$ROOT/scripts/build-image.sh"
chmod +x "$ROOT/scripts/console.sh"

docker compose -f "$DOCKER_COMPOSE" config >/dev/null

echo "Smoke test OK"
