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

local function has_sites()
  return aliveworld and aliveworld.sites and aliveworld.sites.list
end

local function get_player_pos(player_name)
  if not player_name then return nil end
  local player = minetest.get_player_by_name(player_name)
  if not player then return nil end
  local pos = player:get_pos()
  if not pos then return nil end
  return {x = pos.x, y = pos.y, z = pos.z}
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

function aliveworld_player.show_news(player_name, player_pos)
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
        local text = aliveworld_player.get_display_text(r)
        if has_sites() and player_pos and r.event_id then
          local site = aliveworld.sites.find_by_event(r.event_id)
          if site and site.status == "active" then
            local phys = site.physical_status or "abstract"
            if phys == "anchored" or phys == "materialized" then
              local direction = aliveworld.sites.format_direction_ru(player_pos, site.pos)
              text = text .. " — " .. direction
            else
              local dir = aliveworld.sites.direction_name_ru(player_pos, site.pos)
              text = text .. " — место пока не отмечено, слух указывает примерное направление: " .. dir
            end
          end
        end
        table.insert(lines, string.format("• %s", text))
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

  local places_count = 0
  if has_sites() then
    for _, s in ipairs(aliveworld.sites.list()) do
      if s.type == "settlement" and s.status == "active" then
        places_count = places_count + 1
      end
    end
  end
  table.insert(lines, string.format("Известные места: %d", places_count))
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

-- show_places: list known settlement sites

function aliveworld_player.show_places(player_name)
  local lines = {}
  table.insert(lines, "=== Известные места ===")
  table.insert(lines, "")

  if not has_sites() then
    table.insert(lines, "Модуль мест недоступен.")
    show_formspec(player_name, "aliveworld_player:places", "Известные места", table.concat(lines, "\n"))
    return
  end

  local places = aliveworld.sites.get_places_for_player(player_name)
  if #places == 0 then
    table.insert(lines, "Нет известных мест.")
  else
    for _, p in ipairs(places) do
      table.insert(lines, string.format("• %s (%s)", p.name, p.type_name))
      if p.physical_status == "anchored" or p.physical_status == "materialized" then
        table.insert(lines, string.format("  %s, %d блоков — место отмечено", p.dir, p.dist))
      else
        table.insert(lines, string.format("  Известно только по слухам, место ещё не отмечено"))
      end
      table.insert(lines, "")
    end
  end

  show_formspec(player_name, "aliveworld_player:places", "Известные места", table.concat(lines, "\n"))
end

-- show_place_detail: detailed info about a specific site

function aliveworld_player.show_place_detail(player_name, site_id)
  local lines = {}
  table.insert(lines, "=== Место ===")
  table.insert(lines, "")

  if not has_sites() then
    table.insert(lines, "Модуль мест недоступен.")
    show_formspec(player_name, "aliveworld_player:place", "Место", table.concat(lines, "\n"))
    return
  end

  local details = aliveworld.sites.get_place_details(player_name, site_id)
  if not details then
    table.insert(lines, "Место не найдено.")
    show_formspec(player_name, "aliveworld_player:place", "Место", table.concat(lines, "\n"))
    return
  end

  local site = details.site
  local type_name = ""
  if site.type == "settlement" then
    type_name = (site.subtype == "village" and "деревня") or (site.subtype == "outpost" and "форпост") or site.subtype
  elseif site.type == "event" then
    type_name = "событие"
  end

  table.insert(lines, string.format("Название: %s", site.name))
  table.insert(lines, string.format("Тип: %s", type_name))
  if details.dist and details.dir then
    table.insert(lines, string.format("Направление: %s, %d блоков", details.dir, details.dist))
  end
  table.insert(lines, "")

  if site.type == "settlement" then
    if site.settlement_id and has_settlements() then
      local settlement = aliveworld.settlements.get(site.settlement_id)
      if settlement then
        table.insert(lines, string.format("Население: %d", settlement.population))
        table.insert(lines, string.format("Состояние: %s", settlement.status))
        local status_ru = {stable = "стабильно", hungry = "голодает", unsafe = "небезопасно", struggling = "в упадке", abandoned = "заброшено"}
        table.insert(lines, string.format("Статус: %s", status_ru[settlement.status] or settlement.status))
      end
    end
  elseif site.type == "event" then
    if site.event_id and has_events() then
      local event = aliveworld.events.get(site.event_id)
      if event then
        table.insert(lines, string.format("Событие: %s", event.text_ru or event.text_en))
        table.insert(lines, string.format("Острота: %s", event.severity))
      end
    end
  end

  show_formspec(player_name, "aliveworld_player:place", "Место", table.concat(lines, "\n"))
end

-- show_near: nearest active sites from player

function aliveworld_player.show_near(player_name)
  local lines = {}
  table.insert(lines, "=== Ближайшие места ===")
  table.insert(lines, "")

  if not has_sites() then
    table.insert(lines, "Модуль мест недоступен.")
    show_formspec(player_name, "aliveworld_player:near", "Ближайшие места", table.concat(lines, "\n"))
    return
  end

  local near = aliveworld.sites.get_near_for_player(player_name, 5)
  if #near == 0 then
    table.insert(lines, "Рядом нет известных мест.")
  else
    for _, n in ipairs(near) do
      table.insert(lines, string.format("• %s (%s)", n.name, n.type_label))
      if n.physical_status == "anchored" or n.physical_status == "materialized" then
        table.insert(lines, string.format("  %s, %d блоков — отмечено", n.dir, n.dist))
      else
        table.insert(lines, string.format("  %s, %d блоков — не отмечено", n.dir, n.dist))
      end
      table.insert(lines, "")
    end
  end

  show_formspec(player_name, "aliveworld_player:near", "Ближайшие места", table.concat(lines, "\n"))
end

-- show_investigate: find nearby event sites to investigate

function aliveworld_player.show_investigate(player_name)
  local lines = {}
  table.insert(lines, "=== Исследовать ===")
  table.insert(lines, "")

  if not has_sites() then
    table.insert(lines, "Модуль мест недоступен.")
    show_formspec(player_name, "aliveworld_player:investigate", "Исследовать", table.concat(lines, "\n"))
    return
  end

  local player_pos = get_player_pos(player_name)
  if not player_pos then
    table.insert(lines, "Не могу определить ваше положение.")
    show_formspec(player_name, "aliveworld_player:investigate", "Исследовать", table.concat(lines, "\n"))
    return
  end

  local near = aliveworld.sites.nearest(player_pos, 5)
  local event_sites = {}
  for _, s in ipairs(near) do
    if s.type == "event" and s.status == "active" then
      table.insert(event_sites, s)
    end
  end

  if #event_sites == 0 then
    table.insert(lines, "Рядом нет активных событий.")
  else
    table.insert(lines, string.format("Найдено мест событий рядом: %d", #event_sites))
    table.insert(lines, "")
    for _, s in ipairs(event_sites) do
      local dist = aliveworld.sites.distance(player_pos, s.pos)
      local dir = aliveworld.sites.direction_name_ru(player_pos, s.pos)
      local phys = s.physical_status or "abstract"
      table.insert(lines, string.format("• %s", s.name))
      table.insert(lines, string.format("  %s, %d блоков", dir, dist))
      if phys == "anchored" or phys == "materialized" then
        table.insert(lines, "  Следы события уже замечены в мире.")
      else
        table.insert(lines, "  Ищи следы события поблизости.")
      end

      if s.event_id and has_events() then
        local ev = aliveworld.events.get(s.event_id)
        if ev then
          table.insert(lines, string.format("  Слух: %s", aliveworld_player.get_display_text(ev)))
        end
      end
      table.insert(lines, "")
    end
  end

  show_formspec(player_name, "aliveworld_player:investigate", "Исследовать", table.concat(lines, "\n"))
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
    local player_pos = get_player_pos(player_name)
    aliveworld_player.show_news(player_name, player_pos)
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
    table.insert(lines, "/aw_places — список известных мест")
    table.insert(lines, "/aw_place <id> — подробно о месте")
    table.insert(lines, "/aw_near — ближайшие места")
    table.insert(lines, "/aw_investigate — поиск следов событий рядом")
    table.insert(lines, "/aw_help — эта справка")
    table.insert(lines, "")
    table.insert(lines, "Установите Доску слухов в мире для быстрого доступа к новостям.")
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_places", {
  params = "",
  description = "Список известных мест",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_places в игре."
    end
    aliveworld_player.show_places(player_name)
    return true, "Открываю список мест..."
  end,
})

minetest.register_chatcommand("aw_place", {
  params = "<id>",
  description = "Показать подробную информацию о месте",
  privs = {interact = true},
  func = function(player_name, param)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_place в игре."
    end
    if not param or param == "" then
      return false, "Укажите id места. Используйте /aw_places для списка."
    end
    aliveworld_player.show_place_detail(player_name, param)
    return true, "Открываю информацию о месте..."
  end,
})

minetest.register_chatcommand("aw_near", {
  params = "",
  description = "Показать ближайшие места",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_near в игре."
    end
    aliveworld_player.show_near(player_name)
    return true, "Открываю ближайшие места..."
  end,
})

minetest.register_chatcommand("aw_investigate", {
  params = "",
  description = "Поиск следов событий рядом",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Используйте /aw_investigate в игре."
    end
    aliveworld_player.show_investigate(player_name)
    return true, "Ищу следы событий..."
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
    local player_pos = clicker:get_pos()
    aliveworld_player.show_news(clicker:get_player_name(),
      player_pos and {x = player_pos.x, y = player_pos.y, z = player_pos.z})
    return itemstack
  end,
})

minetest.log("action", "[aliveworld_player] loaded")
