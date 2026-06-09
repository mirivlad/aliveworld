-- aliveworld_player/init.lua
-- Player-facing UI for AliveWorld

aliveworld_player = {}

-- Module availability checks

local function has_rumors()
  return aliveworld and aliveworld.rumors and aliveworld.rumors.list
end

local function has_events()
  return aliveworld and aliveworld.events and aliveworld.events.list
end

local function has_settlements()
  return aliveworld and aliveworld.settlements and aliveworld.settlements.list
end

local function has_bridge()
  return aliveworld and aliveworld.bridge and aliveworld.bridge.get_environment_profile
end

-- Text helpers

function aliveworld_player.get_display_text(obj)
  if obj.text_ru and obj.text_ru ~= "" then
    return obj.text_ru
  end
  if obj.label_ru and obj.label_ru ~= "" then
    return obj.label_ru
  end
  return obj.text_en or obj.label_en or ""
end

function aliveworld_player.format_date(d)
  if not d then
    if aliveworld and aliveworld.get_date then
      d = aliveworld.get_date()
    else
      return "Неизвестная дата"
    end
  end
  local season = ""
  if has_bridge() then
    local env = aliveworld.bridge.get_environment_profile(d)
    season = string.format(" — %s", aliveworld_player.get_display_text(env.season))
  end
  return string.format("Год %d, месяц %d, день %d%s", d.year, d.month, d.day, season)
end

-- Chronicle filtering (skip daily noise)

local function is_meaningful_event(ev)
  if ev.type == "tick" or ev.type == "environment_tick" then
    return false
  end
  if ev.type and ev.type:sub(1, 4) == "dev_" then
    return false
  end
  return true
end

-- Formspec display helper

local function show_formspec(player_name, formname, title, text)
  local escaped = minetest.formspec_escape(text)
  local formspec = table.concat({
    "formspec_version[4]",
    "size[8,10]",
    "label[0.2,0.2;", minetest.formspec_escape(title), "]",
    "textarea[0.2,0.8;7.6,8.2;;;", escaped, "]",
    "button_exit[6.5,9;1.5,1;close;Закрыть]",
  })
  minetest.show_formspec(player_name, formname, formspec)
end

-- show_news: active rumors

function aliveworld_player.show_news(player_name)
  local lines = {}

  table.insert(lines, "=== Новости мира ===")
  table.insert(lines, "")

  if aliveworld and aliveworld.get_date then
    table.insert(lines, aliveworld_player.format_date())
    table.insert(lines, "")
  end

  if has_rumors() then
    local list = aliveworld.rumors.list()
    local active = {}
    for _, r in ipairs(list) do
      if r.status == "active" then
        table.insert(active, r)
      end
    end

    if #active == 0 then
      table.insert(lines, "Пока мир молчит. Слухов нет.")
    else
      table.insert(lines, string.format("=== Активные слухи (%d) ===", #active))
      table.insert(lines, "")
      for _, r in ipairs(active) do
        table.insert(lines, string.format("• %s", aliveworld_player.get_display_text(r)))
        table.insert(lines, string.format("  Истекает на день %d", r.expires_day))
        table.insert(lines, "")
      end
    end
  end

  show_formspec(player_name, "aliveworld_player:news", "Новости мира", table.concat(lines, "\n"))
end

-- show_world: world state overview

function aliveworld_player.show_world(player_name)
  local lines = {}

  table.insert(lines, "=== Состояние мира ===")
  table.insert(lines, "")

  if aliveworld and aliveworld.get_date then
    table.insert(lines, aliveworld_player.format_date())
    table.insert(lines, "")
  end

  local settlers_count = 0
  if has_settlements() then
    local list = aliveworld.settlements.list()
    table.insert(lines, string.format("Поселения: %d", #list))
  end

  local events_count = 0
  if has_events() then
    events_count = aliveworld.events.active_count()
  end
  table.insert(lines, string.format("Активные события: %d", events_count))

  local rumors_count = 0
  if has_rumors() then
    for _, r in ipairs(aliveworld.rumors.list()) do
      if r.status == "active" then
        rumors_count = rumors_count + 1
      end
    end
  end
  table.insert(lines, string.format("Активные слухи: %d", rumors_count))
  table.insert(lines, "")

  if has_bridge() then
    local d = aliveworld.get_date()
    local env = aliveworld.bridge.get_environment_profile(d)
    table.insert(lines, "=== Среда ===")
    table.insert(lines, string.format("Сезон: %s", aliveworld_player.get_display_text(env.season)))
    table.insert(lines, string.format("Еда: %s", aliveworld_player.get_display_text(env.food)))
    table.insert(lines, string.format("Дерево: %s", aliveworld_player.get_display_text(env.wood)))
    table.insert(lines, string.format("Опасность: %s", aliveworld_player.get_display_text(env.danger)))
    table.insert(lines, "")
  end

  table.insert(lines, "=== Последние записи летописи ===")
  if aliveworld and aliveworld.get_events then
    local chronicle = aliveworld.get_events(10)
    local shown = 0
    for i = #chronicle, 1, -1 do
      if shown >= 3 then break end
      local ev = chronicle[i]
      if is_meaningful_event(ev) then
        local msg = ev.message or ""
        if ev.text_ru and ev.text_ru ~= "" then
          msg = ev.text_ru
        end
        local day = ev.total_day or ev.day or 0
        table.insert(lines, string.format("[день %d] %s", day, msg))
        shown = shown + 1
      end
    end
  end

  show_formspec(player_name, "aliveworld_player:world", "Состояние мира", table.concat(lines, "\n"))
end

-- show_chronicle: last 10 meaningful entries

function aliveworld_player.show_chronicle(player_name)
  local lines = {}

  table.insert(lines, "=== Летопись ===")
  table.insert(lines, "")

  if aliveworld and aliveworld.get_events then
    local chronicle = aliveworld.get_events(10)
    local shown = 0
    for i = #chronicle, 1, -1 do
      if shown >= 10 then break end
      local ev = chronicle[i]
      if is_meaningful_event(ev) then
        local msg = ev.message or ""
        if ev.text_ru and ev.text_ru ~= "" then
          msg = ev.text_ru
        end
        local day = ev.total_day or ev.day or 0
        table.insert(lines, string.format("[день %d] %s", day, msg))
        shown = shown + 1
      end
    end
    if shown == 0 then
      table.insert(lines, "Записей пока нет.")
    end
  else
    table.insert(lines, "Летопись недоступна.")
  end

  show_formspec(player_name, "aliveworld_player:chronicle", "Летопись", table.concat(lines, "\n"))
end

-- Chat commands

minetest.register_chatcommand("aw_news", {
  params = "",
  description = "Показать активные слухи",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_news в игре."
    end
    aliveworld_player.show_news(player_name)
    return true, "Открываю новости мира..."
  end,
})

minetest.register_chatcommand("aw_world", {
  params = "",
  description = "Показать состояние мира",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_world в игре."
    end
    aliveworld_player.show_world(player_name)
    return true, "Открываю состояние мира..."
  end,
})

minetest.register_chatcommand("aw_chronicle_read", {
  params = "",
  description = "Показать записи летописи",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_chronicle_read в игре."
    end
    aliveworld_player.show_chronicle(player_name)
    return true, "Открываю летопись..."
  end,
})

minetest.register_chatcommand("aw_help", {
  params = "",
  description = "Справка по командам игрока",
  privs = {interact = true},
  func = function()
    local lines = {}
    table.insert(lines, "=== Команды игрока AliveWorld ===")
    table.insert(lines, "/aw_news — показать активные слухи")
    table.insert(lines, "/aw_world — показать состояние мира")
    table.insert(lines, "/aw_chronicle_read — прочитать летопись")
    table.insert(lines, "/aw_help — эта справка")
    table.insert(lines, "")
    table.insert(lines, "Установите Доску слухов в мире для быстрого доступа к новостям.")
    return true, table.concat(lines, "\n")
  end,
})

-- Rumor Board node — wall-mounted notice board

minetest.register_node("aliveworld_player:rumor_board", {
  description = "Rumor Board (AliveWorld)",
  drawtype = "signlike",
  tiles = {"aliveworld_rumor_board_front.png"},
  inventory_image = "aliveworld_rumor_board_front.png",
  wield_image = "aliveworld_rumor_board_front.png",
  paramtype = "light",
  paramtype2 = "wallmounted",
  sunlight_propagates = true,
  walkable = false,
  groups = {dig_immediate = 2, attached_node = 1},
  sounds = (minetest.get_sound_def and minetest.get_sound_def("wood")) or nil,
  selection_box = {
    type = "wallmounted",
    wall_top = {-0.45, 0.4375, -0.45, 0.45, 0.5, 0.45},
    wall_bottom = {-0.45, -0.5, -0.45, 0.45, -0.4375, 0.45},
    wall_side = {-0.5, -0.45, -0.45, -0.4375, 0.45, 0.45},
  },
  collision_box = {
    type = "wallmounted",
    wall_top = {-0.45, 0.4375, -0.45, 0.45, 0.5, 0.45},
    wall_bottom = {-0.45, -0.5, -0.45, 0.45, -0.4375, 0.45},
    wall_side = {-0.5, -0.45, -0.45, -0.4375, 0.45, 0.45},
  },
  on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
    if not clicker or not clicker:is_player() then
      return itemstack
    end
    aliveworld_player.show_news(clicker:get_player_name())
    return itemstack
  end,
})

minetest.log("action", "[aliveworld_player] loaded")
