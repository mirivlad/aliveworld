# AGENTS.md — AliveWorld

Руководство для coding agents (Codex, Hermes и др.), начинающих сессию без контекста.

**Язык общения с пользователем:** русский. Названия API, команд, файлов, сущностей и commit messages оставлять в оригинальной технической форме.

---

## 1. Назначение проекта

AliveWorld — серверный набор модов для **Luanti 5.16.1** (бывший Minetest) с игрой **Mineclonia**.

### Цель

Процедурный живой мир, существующий независимо от игрока. Слухи и хроники описывают реальные события симуляции. Игрок со временем может не только наблюдать мир, но и влиять на него.

### Реализовано

- Календарь (дни, месяцы, годы), tick-система
- Environment bridge: сезоны, еда, дерево, опасность через `aliveworld.bridge`
- Поселения (settlements) с симуляцией
- Мировые события (world events), слухи (rumors)
- Сайты (sites): `abstract → anchored → materialized`
- Маршруты (routes): `planned → materialized` с budgeted job'ами
- GPS/радар HUD, трекинг
- Remote controller (JSON-файл в worldpath)
- Luanti TestKit для серверных тестов

### Фундамент (текущая разработка)

- Route materialization (v2): budgeted job с дорожным полотном (coarse_dirt + grass shoulders)
- Terrain survey для anchoring
- Budgeted job runner (`aliveworld.job_runner`)

### Будущие цели (не реализовано)

- Мосты, туннели
- Физические поселения (NPC, здания)
- Квесты
- Полноценная клиентская UI-система

---

## 2. Инварианты архитектуры

Подтверждено кодом (`local_mods/aliveworld_core/`, `local_mods/aliveworld_world/`):

- Логическое состояние site отделено от физического: `physical_status ∈ {"abstract", "anchored", "materialized"}`.
- **Terrain anchoring** (terrain survey для определения поверхности) **не равен** marker materialization (физический signlike marker node) **и не равен** route materialization (полноценная дорога).
- Обычный tick **не перемещает** anchored site самопроизвольно.
- Persistence использует `minetest.get_mod_storage()`, а не параллельные файлы.
- Route planning отделён от route materialization. Planned route — логический коридор с claim, без физических блоков.
- Долгие world jobs (`route_materialization`) используют budgeted runner с `target_budget_ms` и checkpoint'ами.
- Физические изменения мира проверяют claims, protection (`is_protected`), и безопасную классификацию nodes.
- GPS/tracking ссылается на каноническую физическую позицию (`anchor_pos` или `representative_route_pos`).
- Трекинг использует `hud_elem_type = "text"` info HUD (направление + расстояние). GPS/радар — `type = "minimap"` + `hud_elem_type = "image"` маркеры. 3D waypoint (`hud_elem_type = "waypoint"`) не используется — старая реализация удалена, цели отображаются только на GPS-миникарте.
- `aliveworld_core` **по mod.conf не зависит** от Mineclonia (`mod.conf` не указывает `depends = mcl_core`). Однако `route_materialization.lua` напрямую ссылается на `mcl_core:coarse_dirt` и другие Mineclonia node name'ы. Это известное несоответствие, которое необходимо устранить миграцией через bridge.
- Environment-dependent тесты ждут awbot + emerge, а не флапают (см. `auto_run` в `aliveworld_test_suite/init.lua`).
- Отсутствие внешнего предусловия (например, player offline) — не `ERROR`, а `SKIP`.

---

## 3. Карта основных модулей

| Модуль | Путь | Ответственность |
|--------|------|-----------------|
| **core** | `local_mods/aliveworld_core/` | Движок симуляции: календарь, settlements, world events, rumors, sites, routes, claims, job_runner, route materialization |
| **bridge** | `local_mods/aliveworld_bridge_mcl/` | Абстракция Mineclonia: `get_environment_profile()`, сезоны, еда, дерево, опасность |
| **admin** | `local_mods/aliveworld_admin/` | Серверные команды: `/aw_status`, `/aw_bridge`, ASCII-only |
| **player** | `local_mods/aliveworld_player/` | Клиентский UI: `/aw_news`, `/aw_places`, `/aw_near`, `/aw_investigate`, GPS, radar, tracking |
| **world** | `local_mods/aliveworld_world/` | Физические маркеры (signlike nodes), materialization site/event |
| **remote_controller** | `local_mods/aliveworld_remote_controller/` | JSON-управление через `rc_cmd.json` в worldpath |
| **luanti_testkit** | `local_mods/luanti_testkit/` | Универсальный серверный тестовый фреймворк (не зависит от AliveWorld) |
| **aliveworld_test_suite** | `local_mods/aliveworld_test_suite/` | Тесты AliveWorld поверх TestKit, screenshot/ui_state management |

Зависимости по `mod.conf`:

| Мод | Обязательные depends | optional_depends |
|-----|---------------------|------------------|
| `aliveworld_core` | _нет_ | _нет_ |
| `aliveworld_bridge_mcl` | `aliveworld_core` | `mcl_core, mcl_mobs, mcl_villages, mcl_structures` |
| `aliveworld_admin` | `aliveworld_core` | _нет_ |
| `aliveworld_player` | `aliveworld_core` | `aliveworld_bridge_mcl, mcl_core` |
| `aliveworld_world` | `aliveworld_core` | `aliveworld_bridge_mcl, aliveworld_player, mcl_core` |
| `aliveworld_remote_controller` | `aliveworld_core` | _нет_ |
| `luanti_testkit` | _нет_ | `aliveworld_core, aliveworld_player, aliveworld_world` |
| `aliveworld_test_suite` | `luanti_testkit` | `aliveworld_core, aliveworld_player, aliveworld_world, aliveworld_bridge_mcl, aliveworld_admin` |

---

## 4. Обычный запуск для игрока (player mode)

Сервер работает в Docker-контейнере с `--terminal` (ncurses-консоль).

```bash
# Запустить (если не запущен)
cd /home/mirivlad/git/aliveworld
docker compose up -d
```

- **service:** `luanti`
- **container:** `luanti-aliveworld`
- **world:** `/config/.minetest/worlds/aliveworld` (bind-mount: `./data/worlds/aliveworld/`)
- **game:** `mineclonia`
- **port:** `30000/udp`
- **команда:**
  `luantiserver --terminal --config /config/.minetest/minetest.conf --world /config/.minetest/worlds/aliveworld --gameid mineclonia --port 30000`
- **config bind mount:** `./config/luanti.conf` → `/config/.minetest/minetest.conf`
- **bind mounts для модов:** каждый `./local_mods/aliveworld_*` → `/config/.minetest/mods/`

### Подключение к ncurses-консоли

```bash
./scripts/console.sh
# Или напрямую:
docker attach luanti-aliveworld
```

### Выход из attach без остановки сервера

**Ctrl+P, затем Ctrl+Q** (стандартный Docker detach).

**Никогда не нажимайте Ctrl+C** в attach — это остановит сервер.

### Проверка статуса

```bash
docker ps --filter name=luanti-aliveworld
docker inspect luanti-aliveworld --format='{{.State.Status}}'
```

### Остановка

```bash
docker compose stop
# Или:
docker stop luanti-aliveworld
```

### Логи

`docker logs` **зашумлён** ncurses-кодами экрана. Основной источник диагностики — чистый файл `debug.txt`.

---

## 5. Test/agent mode

Test mode запускает сервер **без `--terminal`** и направляет лог в отдельный файл.

Используется `docker-compose.test.yml` (overrides):

```yaml
command: >
  luantiserver
  --config /config/.minetest/minetest.conf
  --world /config/.minetest/worlds/aliveworld
  --gameid mineclonia
  --port 30000
  --logfile /config/.minetest/debug-test.txt
```

Отличия test mode:

- Нет ncurses (нет `--terminal`)
- Лог пишется в `debug-test.txt` вместо ncurses output
- Все остальные настройки (world, game, port) те же

### Запуск test mode

```bash
# Остановить player mode (если запущен)
docker compose down

# Запустить test mode
docker compose -f docker-compose.yml -f docker-compose.test.yml up -d
```

### Остановка test mode

```bash
docker compose -f docker-compose.yml -f docker-compose.test.yml down
```

### Возврат в player mode

```bash
docker compose down
docker compose up -d
```

### Проверка режима

```bash
docker inspect luanti-aliveworld --format='{{json .Config.Cmd}}'
# С --terminal = player mode, без = test mode
```

### Конфликт экземпляров

**Не запускайте** player mode и test mode одновременно — они используют один world и порт. Всегда делайте `down` перед сменой режима.

---

## 6. Политика перезапуска сервера

- Агент может перезапускать dev-сервер для загрузки изменённого Lua-кода.
- Перед перезапуском определить текущий режим (player/test).
- Не запускать второй экземпляр на том же world/port.
- Использовать штатные `docker compose` или скрипты.
- **Не удалять** world, mod storage, auth/player state.
- **Не менять** seed, mapgen, `world.mt`.
- **Не пересоздавать** мир без прямого указания пользователя.
- После restart дождаться готовности (проверить `docker logs` или `debug.txt` на `Server for gameid="mineclonia" listening`).
- Запускать awbot/TestKit только после полной готовности сервера.
- Любые destructive операции (reset sites, clear events, delete world) — только с разрешения пользователя.

---

## 7. Логи

### Пути

| Лог | Внутри контейнера | На хосте |
|-----|-------------------|----------|
| Основной чистый лог | `/config/.minetest/debug.txt` | `data/debug.txt` |
| Test mode лог | `/config/.minetest/debug-test.txt` | `data/debug-test.txt` |
| ncurses output | stdout/stderr | `docker logs luanti-aliveworld` |
| TestKit reports | `/config/.minetest/worlds/aliveworld/ltk_report_*.json` | `data/worlds/aliveworld/ltk_report_*.json` |
| Client log (awbot) | — | `logs/test-client.log` |
| UI test log | — | `logs/test-ui.log` |

### Почему `docker logs` загрязнён

При `--terminal` сервер пишет ncurses-коды в stdout. `docker logs` показывает бинарный мусор экрана. **Читайте `debug.txt` на хосте** — это чистый текстовый лог.

### Команды для работы с логами

```bash
# Чистый лог (основной)
tail -100 data/debug.txt

# Test mode лог (если test mode запускался)
tail -100 data/debug-test.txt

# Поиск ошибок
grep -i "ModError\|LuaError\|SCRIPT ERROR\|traceback\|ERROR" data/debug.txt | tail -30

# Только текущий запуск: найти startup marker и показать всё после него
grep -n "Server for gameid=" data/debug.txt | tail -1
LINE=$(grep -n "Server for gameid=" data/debug.txt | tail -1 | cut -d: -f1)
tail -n +$LINE data/debug.txt

# Байтовый offset (быстрее для больших файлов):
BYTE=$(grep -boa "Server for gameid=" data/debug.txt | tail -1 | cut -d: -f1)
dd if=data/debug.txt bs=1 skip=$BYTE 2>/dev/null | head -100

# TestKit отчёт
grep '\[luanti_testkit\]' data/debug.txt | tail -50
```

### Правила

- Старый лог **нельзя принимать** за результат свежего запуска.
- `debug.txt` не удалять без необходимости.
- `debug-test.txt` **дописывается (append mode)**, не перезаписывается. Для чистого лога перед test mode очистить вручную:
  ```bash
  : > data/debug-test.txt
  ```
- TestKit reports (`ltk_report_*.json`) не коммитить.

---

## 8. awbot и remote controller

### awbot — тестовый клиент

Это экземпляр Luanti-клиента, подключающийся к серверу для выполнения тестов и скриншотов.

```bash
# Запустить awbot (headless server-test client, --go, без xvfb по умолчанию)
./scripts/run-test-client.sh

# Расширенный UI-менеджер (с xvfb, screenshot, PID-файл, daemon)
./scripts/run-test-ui.sh start
./scripts/run-test-ui.sh daemon &   # polling daemon
```

Различия и совместимость:

| Скрипт | xvfb | PID-файл | Screenshot | Для чего |
|--------|------|----------|------------|----------|
| `run-test-client.sh` | нет (HEADLESS=1 использует xvfb-run если доступен) | нет | нет | Быстрый запуск для тестов, без UI |
| `run-test-ui.sh start` | да (всегда xvfb-run) | `run/awbot.pid` | да | Screenshot/визуальная проверка |
| `run-test-ui.sh daemon` | да | `run/awbot.pid` | да | Автоматический poll + restart |

**Эти команды взаимоисключающие** — нельзя запустить два awbot с одним именем на одном сервере. `run-test-ui.sh` проверяет `run/awbot.pid` и отказывается запускаться, если процесс жив.

Особенности `run-test-client.sh`:
- Не создаёт PID-файл и не поддерживает clean stop (kill по PID вручную).
- Не использует xvfb по умолчанию (если `HEADLESS=1`, пытается использовать xvfb-run если доступен).
- Подходит для быстрого запуска без скриншотов и без UI.
- Может создать дубликат awbot — проверяйте `grep "awbot.*joins game" data/debug.txt` перед запуском.

### Проверка подключения

```bash
./scripts/run-test-ui.sh status
grep "awbot.*joins game" data/debug.txt
```

### Остановка

```bash
./scripts/run-test-ui.sh stop
# Или по PID:
kill "$(cat run/awbot.pid)"
```

### Runtime-файлы

- `run/awbot.pid` — PID процесса
- `logs/test-client.log` — вывод клиента
- `logs/test-ui.log` — вывод UI-менеджера

### Remote controller

Мод `aliveworld_remote_controller` (файл `local_mods/aliveworld_remote_controller/init.lua`) опрашивает JSON-файл в мире.

```bash
# Отправить команду
echo '{"command":"teleport","pos":{"x":0,"y":4,"z":0},"player":"awbot"}' \
  > data/worlds/aliveworld/rc_cmd.json
```

Поддерживаемые команды: `teleport`, `runchat`, `whereami`, `kick`, `runall`.

**Важно для `runchat`**: поле `chatcmd` указывается **без** ведущего `/`. Команда регистрируется в `minetest.registered_chatcommands` (например, `"ltk_all"`, `"aw_gps"`, `"aw_clean_ui"`, `"aw_prepare_shot"`). Проверить наличие: `/help <cmd>`.

Ответы и отчёты появляются в `debug.txt` с меткой `[rc_controller]`.

### Запуск двух awbot

Избегать. PID-файл в `run/awbot.pid` защищает от дублирования (`run-test-ui.sh` проверяет). `run-test-client.sh` не проверяет PID — может создать дубликат; проверяйте `grep "awbot.*joins game"` перед запуском.

---

## 9. Секреты

- Файлы: `secrets/awbot.password` (gitignored), `secrets/awbot.password.example` (tracked)
- Используется для: подключения тестового клиента `awbot` к серверу
- Агент может читать `secrets/awbot.password` только для локального запуска
- **Запрещено:** выводить значения в чат, отчёт, лог, diff или commit
- **Запрещено:** копировать в tracked-файлы
- **Запрещено:** создавать новые секреты или менять существующие без разрешения
- Диагностические команды должны маскировать значения

`.gitignore` защищает: `secrets/*` (кроме `*.example`), `data/*` (кроме `world.mt`), `backups/`, `logs/`, `*.log`.

---

## 10. Тестирование

### Пирамида проверок

```bash
# 1. Структурная проверка
./scripts/smoke-test.sh

# 2. Shell syntax
bash -n scripts/*.sh

# 3. Git diff
git diff --check

# 4. Python syntax
python3 -m py_compile scripts/install-content.py
```

### TestKit (серверные тесты)

TestKit — серверный фреймворк. Тесты запускаются через chat-команды на сервере.

Требования:
- Сервер запущен
- Тестовый клиент (awbot) подключён
- Игроку `awbot` выданы права (`/grant awbot all`)

**Targeted TestKit:**

```bash
# Через консоль:
docker attach luanti-aliveworld
/ltk_run aliveworld.direction awbot
# Выход: Ctrl+P Ctrl+Q

# Просмотр результата:
grep '\[luanti_testkit\]' data/debug.txt | tail -30
```

**Full TestKit:**

```bash
# Через консоль:
/ltk_all awbot
```

**Полный автоматический workflow:**

```bash
# 1. Запустить сервер (если не запущен)
docker compose up -d

# 2. Дождаться готовности
grep -q "listening" data/debug.txt && echo "ready"

# 3. Запустить awbot (managed — с PID, xvfb, screenshot)
./scripts/run-test-ui.sh start

# 4. Дождаться подключения
grep -q "awbot.*joins game" data/debug.txt && echo "connected"

# 5. Выполнить тесты — через remote controller (без docker attach)
echo '{"command":"runchat","chatcmd":"ltk_all","params":"awbot","player":"awbot"}' \
  > data/worlds/aliveworld/rc_cmd.json

# 6. Дождаться завершения (учитывать время выполнения ~30-60s)
sleep 30
grep '\[luanti_testkit\] Summary' data/debug.txt | tail -5

# 7. Найти отчёт
ls -t data/worlds/aliveworld/ltk_report_*.json | head -1
```

**TestKit через консоль (альтернатива):**

```bash
# Через docker attach (для интерактивной диагностики)
docker attach luanti-aliveworld
/ltk_all awbot
# Выход: Ctrl+P Ctrl+Q

# Или через консольный ввод (без attach):
docker exec -i luanti-aliveworld sh -c 'echo "/ltk_all awbot" > /proc/1/fd/0'
```

**TestKit reports** сохраняются в `data/worlds/aliveworld/ltk_report_*.json`.
**Не добавлять reports в Git.**

### Трактовка статусов

| Статус | Значение |
|--------|----------|
| PASS | Тест пройден |
| FAIL | Assertion упал — требуется диагностика |
| SKIP | Тест пропущен (нет зависимости, player offline) |
| ERROR | Необработанная ошибка Lua |

Агент обязан перечислять все FAIL/SKIP/ERROR. Не называть тест `unrelated` без диагностики. Один прошедший прогон — не исправление флапа.

---

## 11. Скриншоты и визуальная проверка

Рабочий процесс существует на базе `scripts/run-test-ui.sh` + серверный `aliveworld_test_suite` (ui_state.lua + screenshot.lua).

### Требования

- Сервер запущен
- awbot подключён
- xvfb установлен (для headless)
- `secrets/awbot.password` существует

### Сделать screenshot

```bash
# Запустить awbot с xvfb
./scripts/run-test-ui.sh start

# Дождаться подключения (проверить debug.txt)
# Сделать screenshot
./scripts/run-test-ui.sh screenshot debug_view my_test
# Или:
./scripts/run-test-ui.sh world-screenshot gps_test
```

Серверная сторона: команда `/aw_prepare_shot [site_id]` проверяет безопасность, телепортирует, включает GPS/track, пишет `awbot_pre_shot.json` в worldpath.

### Где появляется файл

- Скриншот: `artifacts/ss_<timestamp>_<name>.png`
- Метаданные: `artifacts/ss_<timestamp>_<name>.png.meta.json`

### Ограничения screenshot workflow

- Полноценный стабильный screenshot workflow существует, но требует xvfb
- Без xvfb HEADLESS=1 выдаёт предупреждение
- Скриншоты требуют запущенного GUI-клиента Luanti (не headless в смысле `--go`)
- `run-test-ui.sh` автоматически определяет номер дисплея Xvfb (функция `find_display`), который может отличаться от `DISPLAY_NUM=99`, если `xvfb-run --auto-servernum` выбрал другой номер
- Runtime artifacts (`artifacts/*.png`, `artifacts/*.json`) не коммитить

### Когда визуальная проверка обязательна

- HUD/GPS (radar, tracking waypoint)
- Дороги (route materialization)
- Structures (маркеры, POI)
- Terrain materialization
- Client-visible UI (formspec)

---

## 12. Runtime-данные и Git

### Tracked (под git)

- `local_mods/*` — весь код
- `config/*` — конфиги
- `scripts/*` — скрипты
- `docs/*` — документация
- `docker-compose.test.yml` — test mode override
- `locks/content.lock.json` — замок версий
- `secrets/awbot.password.example` — пример пароля
- `data/worlds/aliveworld/world.mt` — конфиг мира
- `AGENTS.md` — данное руководство

### Untracked (в .gitignore)

- `data/*` — runtime-данные (игры, моды, мир, логи)
- `data/debug.txt` — основной лог
- `data/debug-test.txt` — test лог
- `data/worlds/aliveworld/*.sqlite` — map, auth, mod storage
- `data/worlds/aliveworld/ltk_report_*.json` — TestKit reports
- `data/worlds/aliveworld/rc_cmd.json` — remote controller
- `backups/*` — бэкапы мира
- `logs/*` — логи awbot
- `run/awbot.pid` — PID файл
- `artifacts/*.png`, `artifacts/*.json` — скриншоты
- `secrets/awbot.password` — пароль
- `__pycache__/`, `*.pyc`

### Перед commit

```bash
git status --short
git diff --stat
git diff --check
```

Если рабочее дерево было грязным до начала работы:
- Сохранить список исходных изменений
- Не делать `git reset`
- Не присваивать чужие изменения себе
- Явно отметить mixed files

---

## 13. Политика commit и push

- Commit создавать только после **всех** требуемых проверок (smoke-test, shell syntax, diff --check).
- Commit должен быть тематическим (одна логическая единица).
- **Не коммитить** runtime state (логи, reports, screenshots, PID, sqlite).
- **Не использовать** `git reset --hard` или `git checkout -- .`.
- **Не force push.**
- **Не push без явного указания пользователя.**
- **Не amend** чужой commit без прямой необходимости и объяснения.
- Если integration tests не запускались — явно указать в итоговом отчёте; не утверждать полную готовность.
- Не утверждать, что задача завершена, если основной критерий не проверен.

---

## 14. Правила поведения агента

1. Сначала читать `AGENTS.md`, затем relevant docs/code.
2. Не гадать — ответ есть в репозитории.
3. Не останавливаться на первой ошибке запуска без диагностики.
4. Показывать точную команду и точный stderr.
5. Отвечать пользователю по-русски. Технические термины и команды — в оригинале.
6. Не скрывать ограничения.
7. Не выдавать будущую архитектуру за реализованную.
8. Не менять scope задачи без причины.
9. Не добавлять новую механику в стабилизационный проход.
10. После изменения Lua-кода перезапускать сервер перед live test.
11. Проверять свежий лог после запуска.
12. Для тяжёлых world operations (`route_materialization`) использовать budgeted jobs.
13. Не выполнять destructive world operations без разрешения пользователя.

---

## 15. Известные ограничения (текущий HEAD)

- **Мосты не реализованы.** Водные преграды отмечаются как unresolved, дорога их обходит.
- **Поселения физически не материализованы.** Существуют только как логические sites с маркерами.
- **NPC и квесты отсутствуют.**
- **Screenshot workflow** требует xvfb и GUI-клиента Luanti на машине разработчика. Без xvfb — предупреждение, без клиента — невозможен.
- **TestKit зависит от awbot** (подключённого игрока). Тесты без player — SKIP.
- **Engine API** может давать неделимые latency peaks (см. `Maximum lag peaked at` в логах). Budgeted jobs учитывают это через `target_budget_ms`.
- **`docker logs` непригоден** для чтения при `--terminal`. Использовать `data/debug.txt`.
- **aliveworld_remote_controller** использует `aliveworld_core` как runtime-зависимость (server tick для JSON poll).
