# Luanti AliveWorld

Воспроизводимая серверная сборка [Luanti](https://www.luanti.org/) (бывший Minetest) с [Mineclonia](https://content.luanti.org/packages/ryvnf/mineclonia/).

Сервер собирается из исходников в собственный Docker-образ с ncurses и `--terminal` для интерактивной консоли.

**Рекомендуемый текстурпак:** [Hand Painted Pack Expanded](https://content.luanti.org/packages/shaft/hand_painted_expanded/) (shaft, 128×128, CC0). Клиенты увидят предложение скачать его при подключении к серверу.

---

## Требования

- Docker + Docker Compose (плагин)
- Python 3 для `scripts/install-content.py`
- Порты: `30000/udp`

## Сборка образа

```bash
./scripts/build-image.sh
```

Или напрямую:
```bash
docker compose build
```

## Быстрый старт

```bash
# 1. Установить контент (Mineclonia, моды)
./scripts/install-content.py

# 2. Синхронизировать наши моды
./scripts/sync-local-mods.sh

# 3. Собрать образ и запустить
./scripts/build-image.sh
docker compose up -d

# 4. Проверить логи
docker logs -f luanti-aliveworld
```

Если через прокси:
```bash
./scripts/install-content.py --proxy http://127.0.0.1:12334
```

## Серверная консоль

Сервер запускается с флагом `--terminal` — в контейнере работает интерактивная консоль Luanti.

Подключиться:
```bash
./scripts/console.sh
```

Или напрямую:
```bash
docker attach luanti-aliveworld
```

Команды вводятся прямо в консоль:
```
/help
/status
/grant mirivlad all
/aw_day
/aw_time
/aw_tick
/aw_tick_reset          # reset calendar to day 1
/aw_chronicle           # latest events
/aw_chronicle raw       # full JSON dump
/aw_history             # alias for /aw_chronicle
/aw_status              # date + season + food/wood/danger
/aw_bridge summary      # full environment profile
/aw_bridge foods
/aw_bridge woods
/aw_bridge dangers
/aw_bridge seasons
/aw_pause
/aw_resume
/aw_config
/aw_settlements         # list all settlements
/aw_settlement <id>     # detailed info about a settlement
/aw_settlement_init     # create initial settlements
/aw_settlement_tick     # force settlement simulation tick
/aw_settlement_reset    # delete and recreate settlements
/aw_settlement_set     # set a settlement field for testing (server privs)
/aw_events             # list all active world events
/aw_event <id>         # detailed info about a world event
/aw_event_tick         # force world event generation tick
/aw_event_resolve <id> # resolve a world event
/aw_event_reset        # delete all world events and rumors
/aw_rumors             # list all active rumors
/aw_rumor <id>         # detailed info about a rumor
/aw_sites              # list all active sites
/aw_site <id>          # detailed info about a site
/aw_sites_init         # create initial settlement sites
/aw_sites_reset        # delete and recreate sites
/aw_sites_near <x> <y> <z> [limit]  # nearest active sites from position
/aw_site_debug <id>    # full site debug info with player distances
/aw_whereami [player]  # player coords + nearest sites
/aw_compass <player> <site>  # direction/distance from player to site

### Reality Anchoring & Physical Event Markers

Admin commands (`aliveworld_world`):

/aw_anchor_site <site_id>          # place physical marker for a site
/aw_anchor_near <player> [radius]  # anchor sites near player
/aw_markers                        # list all placed markers
/aw_marker <id>                    # detailed marker info
/aw_materialize_site <site_id>     # materialize site as physical POI
/aw_materialize_event <event_id>   # materialize event site
/aw_materialize_near <player> [radius]  # materialize events near player
/aw_markers_reset confirm          # clear marker registry (keeps nodes)

### Player commands (in-game, aliveworld_player, requires `interact`)

/aw_news               # show active rumors (formspec)
/aw_world              # show world state overview (formspec)
/aw_chronicle_read     # read recent chronicle entries (formspec)
/aw_places             # list known settlement sites with direction/distance
/aw_place <id>         # detailed info about a place
/aw_near               # nearest active sites from player position
/aw_investigate        # search for event traces nearby
/aw_help               # command help
```

> **ASCII output**: Server-console commands intentionally use ASCII/English because the ncurses terminal inside Docker may render Cyrillic incorrectly. Russian text (`label_ru`) is preserved in bridge profiles and chronicle event `data` for the future in-game UI layer.

Выход из attach **без остановки сервера**: `Ctrl+P` затем `Ctrl+Q`.

**Не нажимайте Ctrl+C** в attach — это остановит сервер. Если сервер остановился, запустите снова:
```bash
docker compose start
```

Просмотр логов без входа в консоль:
```bash
docker logs luanti-aliveworld
```

## Обновление наших модов

```bash
# Отредактировать файлы в local_mods/aliveworld_*/
# Затем синхронизировать и перезапустить:
./scripts/sync-local-mods.sh
docker compose restart luanti
```

## Полное обновление контента

```bash
./scripts/backup-world.sh
docker compose down
./scripts/install-content.py
./scripts/sync-local-mods.sh
./scripts/smoke-test.sh
./scripts/build-image.sh
docker compose up -d
```

Dev-моды (worldedit, protector):
```bash
INCLUDE_DEV_MODS=1 ./scripts/install-content.py
```

## Правила архитектуры

- `aliveworld_core` не зависит напрямую от Mineclonia или других игр.
- Все обращения к item/node/mob именам живут в `aliveworld_bridge_mcl`.
- `aliveworld_core` — единственный источник истины для состояния живого мира.
- `aliveworld.bridge` — абстрактный слой: `get_environment_profile(world_time)`, `get_season(world_time)`, `get_food_profile(world_time)`, `get_wood_profile(world_time)`, `get_danger_profile(world_time)`.
- Каждый новый день core вызывает bridge и сохраняет environment profile как `environment_tick` в хронике.
- Чужие моды (`mcl_*`) нельзя редактировать — только bridge-моды.
- Новые фичи живого мира — только в `local_mods/aliveworld_*`.

## Структура проекта

```
luanti-aliveworld/
  Dockerfile               # сборка Luanti с ncurses из исходников
  docker-compose.yml       # сервис
  README.md
  .gitignore

  config/
    luanti.conf             # конфиг сервера
    content.json            # манифест скачиваемого контента

  data/                     # runtime-данные (в .gitignore)
    games/                  # установленные игры
    mods/                   # установленные моды
    worlds/aliveworld/      # мир
    mod_data/               # runtime-данные модов
    minetest.conf           # копия config/luanti.conf
    debug.txt               # лог

  local_mods/               # наши моды (под git)
    aliveworld_core/        # ядро симуляции
      init.lua
      settlements.lua       # модель симуляции поселений
      world_events.lua      # генерация мировых событий
      rumors.lua            # слой слухов для игроков
      sites.lua             # пространственная привязка (координаты, расстояния)
    aliveworld_bridge_mcl/  # мост к Mineclonia (сезоны, еда, дерево, опасность)
    aliveworld_admin/       # админ-инструменты (/aw_status, /aw_bridge)
    aliveworld_player/      # player UI (слухи, мир, хроника, Rumor Board node)
    aliveworld_world/       # физические маркеры и материализация объектов в мире

  scripts/
    build-image.sh          # сборка Docker-образа
    console.sh              # подключение к консоли сервера
    install-content.py      # загрузчик контента
    sync-local-mods.sh      # local_mods -> data/mods
    backup-world.sh         # бэкап мира
    smoke-test.sh           # проверка структуры

  locks/
    content.lock.json       # фиксация версий контента

  backups/                  # бэкапы (в .gitignore)
```
