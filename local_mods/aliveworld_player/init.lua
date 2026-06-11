-- aliveworld_player/init.lua
-- Player-facing UI for AliveWorld

aliveworld_player = {}

dofile(minetest.get_modpath("aliveworld_player") .. "/tracking.lua")
dofile(minetest.get_modpath("aliveworld_player") .. "/radar.lua")

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

local NEWS_FORMSPEC = "aliveworld_player:news"

function aliveworld_player.show_news(player_name, player_pos)
  local formspec = {}
  table.insert(formspec, "formspec_version[4]")
  table.insert(formspec, "size[10,12]")
  table.insert(formspec, "label[0.2,0.2;" .. minetest.formspec_escape("=== Новости мира ===") .. "]")

  local y = 0.8
  if aliveworld and aliveworld.get_date then
    table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape(aliveworld_player.format_date()) .. "]")
    y = y + 0.6
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
      y = y + 0.2
      table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Пока мир молчит. Слухов нет.") .. "]")
    else
      y = y + 0.2
      table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape(string.format("Активные слухи (%d)", #active)) .. "]")
      y = y + 0.6
      for _, r in ipairs(active) do
        local text = aliveworld_player.get_display_text(r)
        local site = nil
        local site_id = nil
        if has_sites() and player_pos and r.event_id then
          site = aliveworld.sites.find_by_event(r.event_id)
          if site and site.status == "active" then
            site_id = site.id
            local phys = site.physical_status or "abstract"
            local target_pos = site.pos
            if aliveworld.sites.resolve_arrival_pos then
              local arrival = aliveworld.sites.resolve_arrival_pos(site)
              if arrival then target_pos = arrival end
            end
            if phys == "anchored" or phys == "materialized" then
              local direction = aliveworld.sites.format_direction_ru(player_pos, target_pos)
              text = text .. " — " .. direction
            else
              local dir = aliveworld.sites.direction_name_ru(player_pos, target_pos)
              text = text .. " — место не отмечено, примерное направление: " .. dir
            end
          end
        end
        -- Truncate long rumor text for formspec display
        local display_text = text
        if #display_text > 60 then
          display_text = display_text:sub(1, 58) .. ".."
        end
        local rumor_status = ""
        if aliveworld.rumors and aliveworld.rumors.get_player_status then
          rumor_status = aliveworld.rumors.get_player_status(player_name, r.id)
        end
        local status_label = (aliveworld.rumors and aliveworld.rumors.get_status_label and aliveworld.rumors.get_status_label(rumor_status)) or ""
        table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("• " .. display_text .. " " .. status_label) .. "]")
        y = y + 0.4
        table.insert(formspec, "label[0.4," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("  Истекает на день " .. r.expires_day) .. "]")
        if site_id then
          table.insert(formspec, "button[7," .. string.format("%.1f", y - 0.1) .. ";1.5,0.5;track_" .. site_id .. ";Отслеживать]")
          table.insert(formspec, "button[8.5," .. string.format("%.1f", y - 0.1) .. ";1.3,0.5;detail_" .. r.id .. ";Подробнее]")
        end
        y = y + 0.6
      end
    end
  end

  table.insert(formspec, "button_exit[8.5," .. string.format("%.1f", y + 0.3) .. ";1.5,0.6;close;Закрыть]")
  minetest.show_formspec(player_name, NEWS_FORMSPEC, table.concat(formspec))
end

-- Show detailed information about a rumor
local DETAIL_FORMSPEC = "aliveworld_player:rumor_detail"

function aliveworld_player.show_rumor_detail(player_name, rumor_id)
  if not aliveworld.rumors then
    minetest.chat_send_player(player_name, "Модуль слухов недоступен.")
    return
  end
  local rumor = aliveworld.rumors.get(rumor_id)
  if not rumor then
    minetest.chat_send_player(player_name, "Слух не найден: " .. rumor_id)
    return
  end

  local player_pos = get_player_pos(player_name)
  local formspec = {}
  table.insert(formspec, "formspec_version[4]")
  table.insert(formspec, "size[10,12]")
  table.insert(formspec, "label[0.2,0.2;" .. minetest.formspec_escape("=== Слух: подробнее ===") .. "]")

  local y = 0.8
  local text = aliveworld_player.get_display_text(rumor)
  table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Слух: " .. text) .. "]")
  y = y + 0.6
  table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("ID: " .. rumor.id) .. "]")
  y = y + 0.4
  table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Истекает: день " .. rumor.expires_day) .. "]")
  y = y + 0.6

  -- Find associated site
  local site_id = nil
  local site = nil
  if has_sites() and rumor.event_id then
    site = aliveworld.sites.find_by_event(rumor.event_id)
    if site and site.status == "active" then
      site_id = site.id
      local phys = site.physical_status or "abstract"
      local target_pos = site.pos
      if aliveworld.sites.resolve_arrival_pos then
        local arrival = aliveworld.sites.resolve_arrival_pos(site)
        if arrival then target_pos = arrival end
      end
      local dist_str = ""
      if player_pos then
        local dx = target_pos.x - player_pos.x
        local dz = target_pos.z - player_pos.z
        local dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
        local dir = aliveworld.sites.direction_name_ru(player_pos, target_pos)
        dist_str = string.format("%d блоков на %s", dist, dir)
      end
      local phys_label = (phys == "anchored" or phys == "materialized") and "отмечено" or "не отмечено"
      table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Место: " .. (site.name or site_id) .. " (" .. phys_label .. ")") .. "]")
      y = y + 0.4
      table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Расстояние: " .. dist_str) .. "]")
      y = y + 0.6
    end
  end

  -- Check player rumor status
  local rumor_player_status = ""
  if aliveworld.rumors and aliveworld.rumors.get_player_status then
    rumor_player_status = aliveworld.rumors.get_player_status(player_name, rumor_id)
  end
  local rumor_status_label = rumor_player_status
  if aliveworld.rumors and aliveworld.rumors.get_status_label then
    rumor_status_label = aliveworld.rumors.get_status_label(rumor_player_status)
  end
  table.insert(formspec, "label[0.2," .. string.format("%.1f", y) .. ";" .. minetest.formspec_escape("Статус: " .. rumor_status_label) .. "]")
  y = y + 0.6

  -- Actions
  if site_id then
    if is_tracking then
      table.insert(formspec, "button[0.2," .. string.format("%.1f", y) .. ";4,0.6;detail_untrack_" .. site_id .. ";Снять трек]")
    else
      table.insert(formspec, "button[0.2," .. string.format("%.1f", y) .. ";4,0.6;detail_track_" .. site_id .. ";Отслеживать]")
    end
  end
  table.insert(formspec, "button[4.5," .. string.format("%.1f", y) .. ";2.5,0.6;detail_back;Назад]")
  y = y + 0.8

  table.insert(formspec, "button_exit[8.5," .. string.format("%.1f", y) .. ";1.5,0.6;detail_close;Закрыть]")
  minetest.show_formspec(player_name, DETAIL_FORMSPEC, table.concat(formspec))
end

-- Handle rumor board and detail button clicks
local function handle_track_click(pname, site_id)
  if not aliveworld_player.tracking then
    minetest.chat_send_player(pname, "Ошибка: модуль отслеживания недоступен.")
    return
  end
  local ok, msg = aliveworld_player.tracking.track_site(pname, site_id, {source = "rumor_board"})
  if ok then
    minetest.chat_send_player(pname, "Waypoint установлен: " .. site_id)
    if aliveworld_player.radar and aliveworld_player.radar.enable then
      aliveworld_player.radar.enable(pname)
      minetest.chat_send_player(pname, "AliveWorld GPS включён.")
    end
  else
    minetest.chat_send_player(pname, "Ошибка: " .. tostring(msg))
  end
end

minetest.register_on_player_receive_fields(function(player, formname, fields)
  local pname = player:get_player_name()

  -- News formspec handler
  if formname == NEWS_FORMSPEC then
    for field, _ in pairs(fields) do
      local track_prefix = "track_"
      if field:sub(1, #track_prefix) == track_prefix then
        local site_id = field:sub(#track_prefix + 1)
        if site_id and site_id ~= "" then
          handle_track_click(pname, site_id)
          minetest.close_formspec(pname, "")
        end
        return true
      end
      local detail_prefix = "detail_"
      if field:sub(1, #detail_prefix) == detail_prefix then
        local rumor_id = field:sub(#detail_prefix + 1)
        if rumor_id and rumor_id ~= "" then
          aliveworld_player.show_rumor_detail(pname, rumor_id)
        end
        return true
      end
    end
  end

  -- Detail formspec handler
  if formname == DETAIL_FORMSPEC then
    for field, _ in pairs(fields) do
      if field == "detail_back" then
        -- Return to news list
        local player_pos = get_player_pos(pname)
        aliveworld_player.show_news(pname, player_pos)
        return true
      end
      local track_prefix = "detail_track_"
      if field:sub(1, #track_prefix) == track_prefix then
        local site_id = field:sub(#track_prefix + 1)
        if site_id and site_id ~= "" then
          handle_track_click(pname, site_id)
          minetest.close_formspec(pname, "")
        end
        return true
      end
      local untrack_prefix = "detail_untrack_"
      if field:sub(1, #untrack_prefix) == untrack_prefix then
        local site_id = field:sub(#untrack_prefix + 1)
        if site_id and site_id ~= "" then
          if aliveworld.tracking then
            aliveworld.tracking.untrack(pname)
          end
          if aliveworld_player.tracking then
            aliveworld_player.tracking.untrack(pname)
          end
          minetest.chat_send_player(pname, "Трек снят.")
          minetest.close_formspec(pname, "")
        end
        return true
      end
    end
  end
end)

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
      table.insert(lines, string.format("  /aw_track %s — отследить", p.id))
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

  table.insert(lines, "")
  table.insert(lines, string.format("Команда: /aw_track %s", site_id))

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
      table.insert(lines, string.format("  Отследить: /aw_track %s", n.id))
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
    table.insert(lines, "")
    table.insert(lines, "--- Информация ---")
    table.insert(lines, "/aw_news — показать активные слухи")
    table.insert(lines, "/aw_world — показать состояние мира")
    table.insert(lines, "/aw_chronicle_read — прочитать летопись")
    table.insert(lines, "/aw_places — список известных мест")
    table.insert(lines, "/aw_place <id> — подробно о месте")
    table.insert(lines, "/aw_near — ближайшие места")
    table.insert(lines, "/aw_investigate — поиск следов событий рядом")
    table.insert(lines, "")
    table.insert(lines, "--- Навигация (GPS) ---")
    table.insert(lines, "/aw_track <site_id> — установить waypoint на место")
    table.insert(lines, "/aw_track_event <event_id> — установить waypoint на событие")
    table.insert(lines, "/aw_track_near [радиус] — отследить ближайшее место")
    table.insert(lines, "/aw_untrack — убрать waypoint")
    table.insert(lines, "/aw_tracks — показать текущий waypoint")
    table.insert(lines, "/aw_gps — вкл/выкл радар (или предмет GPS)")
    table.insert(lines, "/aw_gps_radius <64-2000> — радиус радара в блоках")
    table.insert(lines, "/aw_gps_near — показать ближайшие точки радара")
    table.insert(lines, "")
    table.insert(lines, "--- Прочее ---")
    table.insert(lines, "/aw_help — эта справка")
    table.insert(lines, "")
    table.insert(lines, "Установите Доску слухов в мире для быстрого доступа к новостям.")
    table.insert(lines, "Предмет GPS: /giveme aliveworld_player:gps")
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

-- GPS Item

minetest.register_craftitem("aliveworld_player:gps", {
  description = "AliveWorld GPS",
  inventory_image = "aliveworld_gps.png",
  wield_image = "aliveworld_gps.png",
  stack_max = 1,
  groups = {not_in_creative_inventory = 0},
  on_use = function(itemstack, user, pointed_thing)
    if not user or not user:is_player() then return end
    local pname = user:get_player_name()
    aliveworld_player.radar.toggle(pname)
    return itemstack
  end,
})

-- Tracking commands

minetest.register_chatcommand("aw_track", {
  params = "<site_id>",
  description = "Установить waypoint на место",
  privs = {interact = true},
  func = function(player_name, param)
    if not param or param == "" then
      return false, "Укажите id места. /aw_places — список."
    end
    if not aliveworld_player.tracking then
      return false, "Tracking module not loaded."
    end
    local ok, msg = aliveworld_player.tracking.track_site(player_name, param)
    if ok then
      -- Append distance to arrival_pos
      local player = minetest.get_player_by_name(player_name)
      if player then
        local ppos = player:get_pos()
        local site = aliveworld.sites and aliveworld.sites.get(param)
        if site and ppos then
          local arrival_pos = aliveworld.sites.resolve_arrival_pos and aliveworld.sites.resolve_arrival_pos(site)
          if not arrival_pos then arrival_pos = site.anchor_pos or site.pos end
          local dx = arrival_pos.x - ppos.x
          local dz = arrival_pos.z - ppos.z
          local dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
          msg = msg .. string.format(" Расстояние: %d блоков.", dist)
        end
      end
    end
    return ok, msg
  end,
})

minetest.register_chatcommand("aw_track_event", {
  params = "<event_id>",
  description = "Установить waypoint на событие",
  privs = {interact = true},
  func = function(player_name, param)
    if not param or param == "" then
      return false, "Укажите id события. /aw_events — список."
    end
    if not aliveworld_player.tracking then
      return false, "Tracking module not loaded."
    end
    return aliveworld_player.tracking.track_event(player_name, param)
  end,
})

minetest.register_chatcommand("aw_track_near", {
  params = "[radius]",
  description = "Отследить ближайшее место или событие",
  privs = {interact = true},
  func = function(player_name, param)
    if not aliveworld_player.tracking then
      return false, "Tracking module not loaded."
    end
    local radius = tonumber(param) or 1000
    return aliveworld_player.tracking.track_near(player_name, radius)
  end,
})

minetest.register_chatcommand("aw_untrack", {
  params = "[all|<site_id>]",
  description = "Убрать waypoint",
  privs = {interact = true},
  func = function(player_name, param)
    if not aliveworld_player.tracking then
      return false, "Tracking module not loaded."
    end
    return aliveworld_player.tracking.untrack(player_name, (param or ""):lower())
  end,
})

minetest.register_chatcommand("aw_tracks", {
  params = "",
  description = "Показать текущий waypoint",
  privs = {interact = true},
  func = function(player_name)
    if not aliveworld.tracking then
      return false, "Tracking module not loaded."
    end
    local desc = aliveworld.tracking.describe_track(player_name)
    return true, desc
  end,
})

minetest.register_chatcommand("aw_track_debug", {
  params = "<player_name>",
  description = "Admin debug: show tracking state for player",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_track_debug <player_name>"
    end
    if not aliveworld.tracking then
      return false, "Tracking module not loaded."
    end
    local debug = aliveworld.tracking.get_debug_info(param)
    if not debug then
      return false, "No active track for " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Player: %s", debug.player_name))
    table.insert(lines, string.format("Tracked site: %s", debug.site_id))
    table.insert(lines, string.format("Title: %s", debug.title))
    if debug.target_pos then
      table.insert(lines, string.format("Target pos: (%d,%d,%d)", debug.target_pos.x, debug.target_pos.y, debug.target_pos.z))
    end
    table.insert(lines, string.format("Precision: %s", debug.precision))
    table.insert(lines, string.format("Physical status: %s", debug.physical_status))
    table.insert(lines, string.format("Has arrived: %s", tostring(debug.has_arrived)))
    table.insert(lines, string.format("Arrival ack: %s", tostring(debug.has_arrival_ack)))
    -- Show site details
    local track = aliveworld.tracking.get_active_track(param)
    if track and track.site then
      local site = track.site
      table.insert(lines, string.format("Site name: %s", site.name_en or site.name))
      table.insert(lines, string.format("Site pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
      if site.anchor_pos then
        table.insert(lines, string.format("Anchor pos: (%d,%d,%d)", site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z))
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

-- GPS Radar commands

minetest.register_chatcommand("aw_gps", {
  params = "[on|off|status]",
  description = "AliveWorld GPS — миникарта с маркерами",
  privs = {interact = true},
  func = function(player_name, param)
    if not aliveworld_player.radar then
      return false, "GPS module not loaded."
    end
    param = (param or ""):lower()
    if param == "on" then
      return aliveworld_player.radar.enable(player_name)
    elseif param == "off" then
      return aliveworld_player.radar.disable(player_name)
    elseif param == "status" then
      local enabled = aliveworld_player.radar.is_enabled(player_name)
      local lines = { string.format("GPS: %s", enabled and "вкл" or "выкл") }
      if enabled then
        local zoom = aliveworld_player.radar.get_zoom(player_name)
        table.insert(lines, "Масштаб: " .. zoom.label .. " (" .. zoom.diameter_nodes .. " блоков)")
        if aliveworld.tracking then
          local track = aliveworld.tracking.get_active_track(player_name)
          if track then
            table.insert(lines, "Цель: " .. (track.title or track.site_id))
          end
        end
        local debug = aliveworld_player.radar.get_debug_info(player_name)
        if debug and debug.counters then
          local c = debug.counters
          table.insert(lines, string.format("geo_updates=%d src_rebuilds=%d hud_changes=%d idle_skips=%d",
            c.geometry_updates, c.source_rebuilds, c.hud_changes, c.idle_skips))
        end
      end
      return true, table.concat(lines, "\n")
    elseif param == "zoom_in" or param == "+" then
      return aliveworld_player.radar.zoom_in(player_name)
    elseif param == "zoom_out" or param == "-" then
      return aliveworld_player.radar.zoom_out(player_name)
    elseif param == "near" or param == "medium" or param == "far" or param == "overview" then
      return aliveworld_player.radar.set_zoom(player_name, param)
    else
      return aliveworld_player.radar.toggle(player_name)
    end
  end,
})

minetest.register_chatcommand("aw_gps_zoom", {
  params = "<near|medium|far|overview>",
  description = "Изменить масштаб GPS миникарты",
  privs = {interact = true},
  func = function(player_name, param)
    if not param or param == "" then
      local zoom = aliveworld_player.radar and aliveworld_player.radar.get_zoom(player_name)
      return false, "Укажите масштаб: near, medium, far, overview. Текущий: " .. (zoom and zoom.id or "?")
    end
    if not aliveworld_player.radar then
      return false, "GPS module not loaded."
    end
    return aliveworld_player.radar.set_zoom(player_name, param)
  end,
})

minetest.register_chatcommand("aw_gps_zoom_in", {
  params = "",
  description = "Приблизить GPS",
  privs = {interact = true},
  func = function(player_name)
    if not aliveworld_player.radar then return false, "GPS module not loaded." end
    return aliveworld_player.radar.zoom_in(player_name)
  end,
})

minetest.register_chatcommand("aw_gps_zoom_out", {
  params = "",
  description = "Отдалить GPS",
  privs = {interact = true},
  func = function(player_name)
    if not aliveworld_player.radar then return false, "GPS module not loaded." end
    return aliveworld_player.radar.zoom_out(player_name)
  end,
})

minetest.register_chatcommand("aw_gps_help", {
  params = "",
  description = "AliveWorld GPS: легенда значков",
  privs = {interact = true},
  func = function(player_name)
    local lines = {
      "=== AliveWorld GPS — Легенда ===",
      "",
      "  " .. minetest.colorize("#00FF00", "Жёлтый ромб") .. " — отслеживаемая цель",
      "  " .. minetest.colorize("#00FF00", "Домик") .. " — поселение",
      "  " .. minetest.colorize("#00FF00", "Круг") .. " — событие",
      "  " .. minetest.colorize("#FF0000", "Красный") .. " — опасность (разбой, беспорядки)",
      "  " .. minetest.colorize("#888888", "Серый") .. " — примерная область",
      "  " .. minetest.colorize("#FFFF00", "Стрелка на краю") .. " — цель вне зоны видимости",
      "",
      "Управление:",
      "  /aw_gps on/off — включить/выключить",
      "  /aw_gps zoom_in / zoom_out — приблизить/отдалить",
      "  /aw_gps near/medium/far/overview — выбор масштаба",
      "  /aw_gps status — текущее состояние",
      "  Shift+V — переключить круглый/квадратный режим",
      "",
      "Совет: для лучшей работы используйте круглую форму (Shift+V).",
      "Миникарта всегда в правом верхнем углу.",
    }
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_gps_debug", {
  params = "",
  description = "Debug: show GPS/radar/tracking state",
  privs = {interact = true},
  func = function(player_name)
    local lines = {}
    local player = minetest.get_player_by_name(player_name)
    if not player then
      return false, "Player not found."
    end
    local ppos = player:get_pos()
    table.insert(lines, string.format("Player: %s", player_name))
    table.insert(lines, string.format("Pos: (%d,%d,%d)", math.floor(ppos.x), math.floor(ppos.y), math.floor(ppos.z)))
    table.insert(lines, string.format("Yaw: %.2f", player:get_look_horizontal() or 0))
    table.insert(lines, "")
    local enabled = aliveworld_player.radar and aliveworld_player.radar.is_enabled(player_name)
    table.insert(lines, string.format("GPS enabled: %s", tostring(enabled)))
    if enabled then
      local zoom = aliveworld_player.radar.get_zoom(player_name)
      table.insert(lines, string.format("Zoom: %s (%d blocks diameter)", zoom.id, zoom.diameter_nodes))
      local debug = aliveworld_player.radar.get_debug_info(player_name)
      if debug then
        local c = debug.counters
        table.insert(lines, string.format("Counters: geo=%d src=%d hud=%d idle=%d",
          c.geometry_updates, c.source_rebuilds, c.hud_changes, c.idle_skips))
        table.insert(lines, string.format("Dirty: %s Rebuild: %s", tostring(debug.dirty), tostring(debug.rebuild_sources)))
        if debug.hud_ids then
          table.insert(lines, string.format("Minimap HUD: %s", tostring(debug.hud_ids.minimap)))
          table.insert(lines, string.format("Info HUD: %s", tostring(debug.hud_ids.info)))
          if debug.hud_ids.markers then
            for i, id in ipairs(debug.hud_ids.markers) do
              table.insert(lines, string.format("Marker[%d]: %s", i, tostring(id)))
            end
          end
        end
      end
    end
    table.insert(lines, "")
    local tracks = aliveworld_player.tracking.list(player_name)
    table.insert(lines, string.format("Active tracks: %d", #tracks))
    for _, t in ipairs(tracks) do
      table.insert(lines, string.format("  Site ID: %s", t.site_id))
      table.insert(lines, string.format("  Precision: %s", t.precision))
      if t.site then
        local site = t.site
        local phys = site.physical_status or "abstract"
        table.insert(lines, string.format("  Title: %s", site.name_en or site.name))
        table.insert(lines, string.format("  Physical: %s", phys))
        table.insert(lines, string.format("  Pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
      end
      if t.target_pos then
        local dx = t.target_pos.x - ppos.x
        local dz = t.target_pos.z - ppos.z
        local dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
        table.insert(lines, string.format("  Dist: %d", dist))
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

-- Radar HUD debug: dump all HUD element properties
minetest.register_chatcommand("aw_gps_hud_debug", {
  params = "",
  description = "Debug: show all GPS HUD element properties",
  privs = {interact = true},
  func = function(player_name)
    local player = minetest.get_player_by_name(player_name)
    if not player then return false, "Player not found." end
    local radar_debug = aliveworld_player.radar and aliveworld_player.radar.get_debug_info and aliveworld_player.radar.get_debug_info(player_name)
    if not radar_debug then return false, "GPS debug info not available." end
    local lines = {"=== GPS HUD Debug ==="}
    table.insert(lines, string.format("Enabled: %s", tostring(radar_debug.enabled)))
    table.insert(lines, string.format("Zoom: %s", radar_debug.zoom and radar_debug.zoom.id or "?"))
    table.insert(lines, "")
    if radar_debug.hud_ids then
      local all_ids = {}
      if radar_debug.hud_ids.minimap then table.insert(all_ids, {id=radar_debug.hud_ids.minimap, name="minimap"}) end
      if radar_debug.hud_ids.info then table.insert(all_ids, {id=radar_debug.hud_ids.info, name="info"}) end
      if radar_debug.hud_ids.markers then
        for i, id in ipairs(radar_debug.hud_ids.markers) do
          table.insert(all_ids, {id=id, name="marker["..i.."]"})
        end
      end
      for _, entry in ipairs(all_ids) do
        local prop = player:hud_get(entry.id)
        if prop then
          table.insert(lines, string.format("[%s] id=%s type=%s pos=(%.2f,%.2f) off=(%d,%d) scale=(%.2f,%.2f) align=(%.2f,%.2f) z=%s text=%s",
            entry.name, tostring(entry.id), tostring(prop.type or "?"),
            prop.position and prop.position.x or 0, prop.position and prop.position.y or 0,
            prop.offset and prop.offset.x or 0, prop.offset and prop.offset.y or 0,
            prop.scale and prop.scale.x or 0, prop.scale and prop.scale.y or 0,
            prop.alignment and prop.alignment.x or 0, prop.alignment and prop.alignment.y or 0,
            tostring(prop.z_index or 0), tostring(prop.text or "")))
        else
          table.insert(lines, string.format("[%s] id=%s ERROR: hud_get returned nil", entry.name, tostring(entry.id)))
        end
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

-- Temporary test pattern for radar rendering
local test_pattern_active = {}

minetest.register_chatcommand("aw_gps_testpattern", {
  params = "on|off",
  description = "Show/hide compass test points on GPS minimap",
  privs = {interact = true},
  func = function(player_name, param)
    param = (param or ""):lower()
    local player = minetest.get_player_by_name(player_name)
    if not player then return false, "Player not found." end
    if param == "on" then
      if test_pattern_active[player_name] then
        return true, "Test pattern уже включён."
      end
      test_pattern_active[player_name] = {huds = {}}

      -- Use GPS minimap center for positioning
      local map_rect = aliveworld_player.radar and aliveworld_player.radar.get_map_rect()
      local cx, cy = 90, 90
      if map_rect then
        cx = math.floor(map_rect.center_off_x + 0.5)
        cy = math.floor(map_rect.center_off_y + 0.5)
      end

      -- Test points at 50px radius (simulating GPS coordinates with yaw=0)
      local player_yaw = player:get_look_horizontal() or 0
      local cos_y = math.cos(-player_yaw)
      local sin_y = math.sin(-player_yaw)
      local test_world = {
        {name="FRONT", dx=0, dz=-80, color=0xFF0000},  -- north (forward)
        {name="RIGHT", dx=80, dz=0, color=0x00FF00},    -- east (right)
        {name="BACK",  dx=0, dz=80, color=0x0000FF},     -- south (back)
        {name="LEFT",  dx=-80, dz=0, color=0xFFFF00},    -- west (left)
        {name="CENTER", dx=0, dz=0, color=0xFFFFFF},     -- player position
      }

      -- Scale: assume 200px / 200 blocks (medium zoom)
      local ppn = 200 / 200

      for _, pt in ipairs(test_world) do
        -- Apply yaw rotation to world offsets
        local rx = pt.dx * cos_y - pt.dz * sin_y
        local rz = pt.dx * sin_y + pt.dz * cos_y
        local px = -rx * ppn  -- negate because minimap rotates opposite direction
        local py = rz * ppn

        local id = player:hud_add({
          hud_elem_type = "image",
          position = {x = 1, y = 0},
          alignment = {x = 0.5, y = 0.5},
          offset = {x = cx + px, y = cy - py},
          text = "aliveworld_radar_target.png",
          scale = {x = 1, y = 1},
          z_index = 10,
        })
        table.insert(test_pattern_active[player_name].huds, id)
      end
      return true, "Test pattern: FRONT(красный) RIGHT(зелёный) BACK(синий) LEFT(жёлтый) CENTER(белый)."
    elseif param == "off" then
      local t = test_pattern_active[player_name]
      if t and t.huds then
        for _, id in ipairs(t.huds) do
          player:hud_remove(id)
        end
      end
      test_pattern_active[player_name] = nil
      return true, "Test pattern выключен."
    else
      return false, "Укажите on или off."
    end
  end,
})

-- Debug: close any open formspec via minetest API
minetest.register_chatcommand("aw_clean_ui", {
	params = "",
	description = "Close any open formspec/UI on the client",
	privs = {interact = true},
	func = function(player_name)
		minetest.close_formspec(player_name, "")
		return true, "Formspec closed for " .. player_name
	end,
})

-- Restore waypoint on join

minetest.register_on_joinplayer(function(player)
  if aliveworld_player.tracking and aliveworld_player.tracking.refresh_player then
    aliveworld_player.tracking.refresh_player(player)
  end
end)

minetest.log("action", "[aliveworld_player] loaded")
