# Luanti TestKit — Testing Documentation

## Concept

Luanti TestKit — универсальный серверный фреймворк для тестирования модов Luanti.
Он предоставляет API для регистрации и запуска тестов, набор ассертов,
хелперы для работы с игроками и репортёр.

TestKit **не зависит** от AliveWorld или любой другой игры.
AliveWorld-тесты живут отдельно, в моде `aliveworld_test_suite`.

## Структура

```
local_mods/
  luanti_testkit/            # ← Универсальный TestKit (не зависит от AliveWorld)
    init.lua                 # Точка входа, авто-загрузка тестов из tests/
    api.lua                  # run_test, run_suite, run_all, run_spec
    assertions.lua           # assert.true, .false, .equal, .near, .contains, etc.
    player.lua               # helpers: get_player, set_pos, run_chatcommand, grant
    suites.lua               # Регистрация suite/test, list_suites, list_tests
    reporter.lua             # Сбор отчёта, печать в консоль, сохранение в JSON
    mod.conf
    tests/
      smoke.lua              # Базовые smoke-тесты TestKit
      player_basic.lua       # Тесты подключения игрока

  aliveworld_test_suite/     # ← Тесты AliveWorld (зависит от luanti_testkit)
    init.lua
    mod.conf
    tests/
      direction.lua          # Тесты направлений и расстояний
      gps.lua                # Тесты GPS/трекинга
      radar.lua              # Тесты радара
      anchors.lua            # Тесты якорей/материализации
      rumors.lua             # Тесты слухов и событий

scripts/
  run-test-client.sh          # Запуск тестового клиента Luanti
  run-luanti-tests.sh         # Хелпер для запуска тестов
```

## Быстрый старт

### 1. Убедись, что TestKit включён

В `data/worlds/aliveworld/world.mt` должны быть:

```
load_mod_luanti_testkit = true
load_mod_aliveworld_test_suite = true
```

### 2. Синхронизируй моды

```bash
./scripts/sync-local-mods.sh
```

### 3. Создай тестового игрока

В консоли сервера (docker attach):

```
/setpassword awbot
/grant awbot all
```

Создай файл `secrets/awbot.password` с тем же паролем:

```bash
cp secrets/awbot.password.example secrets/awbot.password
# Отредактируй secrets/awbot.password — впиши тот же пароль, что на сервере
```

### 4. Запусти тестовый клиент

```bash
./scripts/run-test-client.sh
```

Флаг `--go` заставляет клиента сразу подключиться к серверу.

### 5. Запусти тесты

Через консоль сервера (docker attach):

```
/ltk_all awbot
```

Или отдельный suite:

```
/ltk_suite smoke
/ltk_suite aliveworld awbot
```

Или отдельный тест:

```
/ltk_run aliveworld.direction awbot
```

## Команды TestKit

| Команда | Описание |
|---------|----------|
| `/ltk_list` | Список всех suites и tests |
| `/ltk_run <spec> [player]` | Запустить тест/сьют |
| `/ltk_all [player]` | Запустить все тесты |
| `/ltk_suite <name> [player]` | Запустить сьют |
| `/ltk_report` | Показать последний отчёт |
| `/ltk_reset_report` | Очистить отчёт |
| `/ltk_json_report` | JSON-отчёт в консоль |

## Добавление нового теста

### 1. Создай файл теста

Например `local_mods/aliveworld_test_suite/tests/my_feature.lua`:

```lua
local T = luanti_testkit

T.register_test("aliveworld", "my_feature", function(ctx)
    -- Проверяем, что нужный модуль загружен
    if not aliveworld or not aliveworld.my_feature then
        ctx.skip("aliveworld.my_feature not loaded")
        return
    end

    -- Используем ассерты
    ctx.assert.true(aliveworld.my_feature.is_ready(), "feature must be ready")
    ctx.assert.equal(aliveworld.my_feature.get_value(), 42, "value must be 42")

    -- Используем хелперы
    local player = ctx.helpers.require_player(ctx.player_name)
    local pos = ctx.helpers.get_pos(player)
    ctx.log("Player at: " .. minetest.pos_to_string(pos))
end)
```

### 2. Подключи тест в init.lua

Добавь в `local_mods/aliveworld_test_suite/init.lua`:

```lua
"my_feature",
```

в список `test_files`.

### 3. Синхронизируй и перезапусти

```bash
./scripts/sync-local-mods.sh
docker compose restart luanti
# или перезапусти сервер
```

### 4. Запусти тест

```
/ltk_run aliveworld.my_feature awbot
```

## Формат результата теста

```json
{
  "suite": "aliveworld",
  "name": "direction",
  "status": "PASS",
  "message": "OK",
  "details": ["Direction from TEST_POS to birch_ford: north-east / северо-восток"],
  "duration_ms": 12
}
```

Статусы:
- `PASS` — тест пройден
- `FAIL` — assertion упал
- `SKIP` — тест пропущен (нет зависимости, не загружен модуль и т.п.)
- `ERROR` — необработанная ошибка Lua

## Context API

В функции теста доступен `ctx`:

| Поле | Описание |
|------|----------|
| `ctx.player_name` | Имя игрока (из /ltk_all awbot) |
| `ctx.player` | Player object (если онлайн) |
| `ctx.args` | Дополнительные аргументы |
| `ctx.assert.*` | Ассерты (см. ниже) |
| `ctx.helpers.*` | Хелперы (см. ниже) |
| `ctx.skip(reason)` | Пропустить тест |
| `ctx.log(message)` | Записать в лог теста |

### Assertions

- `ctx.assert.true(value, message)`
- `ctx.assert.false(value, message)`
- `ctx.assert.equal(actual, expected, message)`
- `ctx.assert.not_nil(value, message)`
- `ctx.assert.near(actual, expected, tolerance, message)`
- `ctx.assert.contains(text, needle, message)`
- `ctx.assert.table_has_key(tbl, key, message)`

### Helpers

- `ctx.helpers.get_player(name)` — получить player object
- `ctx.helpers.require_player(name)` — получить player или FAIL
- `ctx.helpers.get_pos(player)` — позиция игрока
- `ctx.helpers.set_pos(player, pos)` — телепорт
- `ctx.helpers.teleport(player, pos)` — то же
- `ctx.helpers.distance2d(pos1, pos2)` — расстояние XZ
- `ctx.helpers.distance3d(pos1, pos2)` — расстояние XYZ
- `ctx.helpers.run_chatcommand(player_name, command)` — выполнить /команду
- `ctx.helpers.grant(player_name, privs)` — выдать привилегии
- `ctx.helpers.has_priv(player_name, priv)` — проверить привилегию
- `ctx.helpers.wait(seconds, callback)` — пауза (блокирующая, не злоупотреблять)

## Правила для тестов

1. **Детерминированность** — тест должен давать одинаковый результат при одинаковых условиях
2. **Не ломать карту** — не ставить/ломать блоки без необходимости; если ставишь — убери
3. **Unloaded area = SKIP** — если область не загружена, не FAIL, а SKIP
4. **Минимум sleep** — `ctx.helpers.wait()` блокирует сервер
5. **Чистота** — каждый тест должен очищать за собой (снять tracking, выключить radar)
6. **Читаемость** — сообщения ассертов должны объяснять причину падения
7. **SKIP вместо FAIL для отсутствующих зависимостей** — если модуль не загружен, это SKIP, а не ошибка теста

## Production

Для production-сервера test-моды можно выключить в `world.mt`:

```
# load_mod_luanti_testkit = false
# load_mod_aliveworld_test_suite = false
```

Это никак не влияет на работу AliveWorld — TestKit не содержит production-логики.
