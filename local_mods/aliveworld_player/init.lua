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
      return "Unknown date"
    end
  end
  local season = ""
  if has_bridge() then
    local env = aliveworld.bridge.get_environment_profile(d)
    season = string.format(" — %s", aliveworld_player.get_display_text(env.season))
  end
  return string.format("Year %d, Month %d, Day %d (day %d)%s",
    d.year, d.month, d.day, d.total_days, season)
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
    "button_exit[6.5,9;1.5,1;close;Close]",
  })
  minetest.show_formspec(player_name, formname, formspec)
end

-- show_news: active rumors

function aliveworld_player.show_news(player_name)
  local lines = {}

  table.insert(lines, "=== AliveWorld News ===")
  table.insert(lines, "")

  if aliveworld and aliveworld.get_date then
    table.insert(lines, aliveworld_player.format_date())
    table.insert(lines, "")
  end

  if has_rumors() then
    local rumors = aliveworld.rumors.list()
    local active = {}
    for _, r in ipairs(rumors) do
      if r.status == "active" then
        table.insert(active, r)
      end
    end

    if #active == 0 then
      table.insert(lines, "Пока мир молчит. Слухов нет.")
    else
      table.insert(lines, string.format("=== Active Rumors (%d) ===", #active))
      table.insert(lines, "")
      for _, r in ipairs(active) do
        table.insert(lines, string.format("• %s", aliveworld_player.get_display_text(r)))
        table.insert(lines, string.format("  [%s] — expires day %d", r.settlement_id, r.expires_day))
        table.insert(lines, "")
      end
    end
  end

  show_formspec(player_name, "aliveworld_player:news", "AliveWorld News", table.concat(lines, "\n"))
end

-- show_world: world state overview

function aliveworld_player.show_world(player_name)
  local lines = {}

  table.insert(lines, "=== AliveWorld State ===")
  table.insert(lines, "")

  if aliveworld and aliveworld.get_date then
    table.insert(lines, aliveworld_player.format_date())
    table.insert(lines, "")
  end

  local settlers_count = 0
  if has_settlements() then
    local list = aliveworld.settlements.list()
    table.insert(lines, string.format("Settlements: %d", #list))
  end

  local events_count = 0
  if has_events() then
    events_count = aliveworld.events.active_count()
  end
  table.insert(lines, string.format("Active events: %d", events_count))

  local rumors_count = 0
  if has_rumors() then
    for _, r in ipairs(aliveworld.rumors.list()) do
      if r.status == "active" then
        rumors_count = rumors_count + 1
      end
    end
  end
  table.insert(lines, string.format("Active rumors: %d", rumors_count))
  table.insert(lines, "")

  if has_bridge() then
    local d = aliveworld.get_date()
    local env = aliveworld.bridge.get_environment_profile(d)
    table.insert(lines, "=== Environment ===")
    table.insert(lines, string.format("Season: %s", aliveworld_player.get_display_text(env.season)))
    table.insert(lines, string.format("Food: %s", aliveworld_player.get_display_text(env.food)))
    table.insert(lines, string.format("Wood: %s", aliveworld_player.get_display_text(env.wood)))
    table.insert(lines, string.format("Danger: %s", aliveworld_player.get_display_text(env.danger)))
    table.insert(lines, "")
  end

  table.insert(lines, "=== Latest Chronicle ===")
  if aliveworld and aliveworld.get_events then
    local chronicle = aliveworld.get_events(10)
    local shown = 0
    for i = #chronicle, 1, -1 do
      if shown >= 3 then break end
      local ev = chronicle[i]
      if is_meaningful_event(ev) then
        table.insert(lines, string.format("[day %d] %s", ev.total_day or ev.day, ev.message))
        shown = shown + 1
      end
    end
  end

  show_formspec(player_name, "aliveworld_player:world", "AliveWorld State", table.concat(lines, "\n"))
end

-- show_chronicle: last 10 meaningful entries

function aliveworld_player.show_chronicle(player_name)
  local lines = {}

  table.insert(lines, "=== Chronicle ===")
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
        table.insert(lines, string.format("[day %d] %s", day, msg))
        shown = shown + 1
      end
    end
    if shown == 0 then
      table.insert(lines, "Chronicle is empty.")
    end
  else
    table.insert(lines, "Chronicle not available.")
  end

  show_formspec(player_name, "aliveworld_player:chronicle", "AliveWorld Chronicle", table.concat(lines, "\n"))
end

-- Chat commands

minetest.register_chatcommand("aw_news", {
  params = "",
  description = "Show active rumors",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Use /aw_news in-game to open the news UI."
    end
    aliveworld_player.show_news(player_name)
    return true, "Opening AliveWorld News..."
  end,
})

minetest.register_chatcommand("aw_world", {
  params = "",
  description = "Show world state overview",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Use /aw_world in-game to open world state."
    end
    aliveworld_player.show_world(player_name)
    return true, "Opening AliveWorld State..."
  end,
})

minetest.register_chatcommand("aw_chronicle_read", {
  params = "",
  description = "Show recent chronicle entries",
  privs = {interact = true},
  func = function(player_name)
    if not player_name or player_name == "" then
      return false, "Use /aw_chronicle_read in-game to read the chronicle."
    end
    aliveworld_player.show_chronicle(player_name)
    return true, "Opening Chronicle..."
  end,
})

minetest.register_chatcommand("aw_help", {
  params = "",
  description = "AliveWorld player command help",
  privs = {interact = true},
  func = function()
    local lines = {}
    table.insert(lines, "=== AliveWorld Player Commands ===")
    table.insert(lines, "/aw_news — show active rumors")
    table.insert(lines, "/aw_world — show world state")
    table.insert(lines, "/aw_chronicle_read — read chronicle")
    table.insert(lines, "/aw_help — this help")
    table.insert(lines, "")
    table.insert(lines, "Place a Rumor Board in the world for quick news access.")
    return true, table.concat(lines, "\n")
  end,
})

-- Rumor Board node

local board_texture

if minetest.get_modpath("mcl_core") then
  local ok = pcall(function()
    local def = minetest.registered_items["mcl_core:wood"]
    if def and def.tiles then
      board_texture = def.tiles[1]
    else
      board_texture = "mcl_core_wood.png"
    end
  end)
  if not ok then
    board_texture = "mcl_core_wood.png"
  end
elseif minetest.get_modpath("default") then
  board_texture = "default_wood.png"
else
  board_texture = "[colorize:#8B4513"
end

minetest.register_node("aliveworld_player:rumor_board", {
  description = "Rumor Board (AliveWorld)",
  tiles = {board_texture},
  groups = {choppy = 2, oddly_breakable_by_hand = 2, flammable = 3},
  sounds = (minetest.get_sound_def and minetest.get_sound_def("wood")) or nil,
  on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
    if clicker and clicker:is_player() then
      aliveworld_player.show_news(clicker:get_player_name())
    end
    return itemstack
  end,
})

minetest.log("action", "[aliveworld_player] loaded")
