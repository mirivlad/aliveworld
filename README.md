# Luanti AliveWorld

Воспроизводимая серверная сборка Luanti (бывший Minetest) с Mineclonia.

Все пути — относительные от корня репозитория. `/opt` не используется.

---

## Первый запуск

```bash
mkdir -p ~/git
cd ~/git
git init luanti-aliveworld
cd luanti-aliveworld

mkdir -p config data/games data/mods data/texturepacks data/worlds/aliveworld local_mods scripts locks backups

cp config/luanti.conf data/minetest.conf

chmod +x scripts/install-content.py
chmod +x scripts/sync-local-mods.sh
chmod +x scripts/backup-world.sh
chmod +x scripts/smoke-test.sh

./scripts/install-content.py
./scripts/sync-local-mods.sh
./scripts/smoke-test.sh

docker compose up -d
docker logs -f luanti-aliveworld
```

---

## Проверка в игре

Подключиться к серверу:
- address: IP или домен сервера
- port: 30000
- protocol: UDP port must be forwarded if server is public

В игре выполнить:
```
/aw_status
/aw_day
/aw_tick
/aw_chronicle
```

---

## Обновление контента

1. Сделать backup:
   ```bash
   ./scripts/backup-world.sh
   ```

2. Остановить сервер:
   ```bash
   docker compose down
   ```

3. Обновить контент в тестовой копии или отдельной ветке:
   ```bash
   ./scripts/install-content.py
   ```

4. Синхронизировать наши моды:
   ```bash
   ./scripts/sync-local-mods.sh
   ```

5. Проверить:
   ```bash
   ./scripts/smoke-test.sh
   ```

6. Запустить:
   ```bash
   docker compose up -d
   ```

7. Проверить логи:
   ```bash
   docker logs -f luanti-aliveworld
   ```

---

## Установка dev-модов

```bash
INCLUDE_DEV_MODS=1 ./scripts/install-content.py
```

Устанавливает worldedit, protector и другие dev/admin моды в `data/mods/`.

---

## Правила архитектуры

- `aliveworld_core` не зависит напрямую от Mineclonia, VoxeLibre или Minetest Game.
- Все обращения к конкретным item/node/mob именам живут в `aliveworld_bridge_mcl` или других bridge-модах.
- `aliveworld_core` хранит только абстрактное состояние мира: календарь, хронику, поселения, фракции, события.
- NPC, квесты, биомы, декорации и внешние моды не являются источником истины для симуляции.
- Источник истины — `aliveworld_core`.
- Чужие моды можно заменить, отключить или обновить без потери состояния живого мира.
- Нельзя редактировать файлы Mineclonia, mcl_decor, worldedit, protector или любых других внешних модов.
- Если нужна совместимость с внешним модом — делать отдельный adapter/bridge-мод.
- Все новые фичи живого мира добавляются в `local_mods/aliveworld_*`.
- Production-сервер нельзя автообновлять без backup и проверки в тестовом мире.
- Не использовать абсолютные пути. Весь проект должен быть переносим как git-репозиторий.

---

## Структура проекта

```
luanti-aliveworld/
  docker-compose.yml
  README.md
  .gitignore

  config/
    luanti.conf          # конфиг сервера (копируется в data/minetest.conf)
    content.json         # манифест скачиваемого контента
    enabled_mods.txt     # список включённых модов (справочно)

  data/
    games/               # установленные игры (mineclonia)
    mods/                # установленные моды (копия local_mods + внешние)
    texturepacks/        # установленные текстурпаки
    worlds/              # миры
      aliveworld/
        world.mt         # мета мира

  local_mods/
    aliveworld_core/     # ядро симуляции
    aliveworld_bridge_mcl/ # мост к Mineclonia
    aliveworld_admin/    # админ-инструменты

  scripts/
    install-content.py   # загрузчик контента с ContentDB
    sync-local-mods.sh   # синхронизация local_mods -> data/mods
    backup-world.sh      # бэкап мира
    smoke-test.sh        # проверка структуры

  locks/
    content.lock.json    # фиксация скачанного контента (под git)

  backups/               # архивы бэкапов (в .gitignore)
```
