-- aliveworld_player/tracking.lua
-- Player-facing waypoint tracking UI, delegates to aliveworld.tracking shared API

aliveworld_player.tracking = {}

local hud_ids = {}  -- player_name -> hud_id (waypoint)
local info_hud_ids = {}  -- player_name -> info_text hud_id (compact distance/status line)

local COLORS = {
  settlement = 0x00CC44,
  dangerous_roads = 0xFF3333,
  food_shortage = 0xFF8800,
  winter_hardship = 0x66AAFF,
  unrest = 0xFF44FF,
  trade_opportunity = 0x33FFFF,
  recovery = 0x33FF88,
  default = 0x888888,
  abstract = 0x666666,
}

local function get_color(site)
  if not site then return COLORS.default end
  if site.physical_status ~= "anchored" and site.physical_status ~= "materialized" then
    return COLORS.abstract
  end
  if site.type == "settlement" then return COLORS.settlement end
  if site.type == "event" and site.subtype then
    return COLORS[site.subtype] or COLORS.default
  end
  return COLORS.default
end

local function remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if player then
    if hud_ids[player_name] then
      player:hud_remove(hud_ids[player_name])
    end
    if info_hud_ids[player_name] then
      player:hud_remove(info_hud_ids[player_name])
    end
  end
  hud_ids[player_name] = nil
  info_hud_ids[player_name] = nil
end

local function add_hud(player_name, site, target_pos)
  remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end

  local color = get_color(site)
  local track = aliveworld.tracking and aliveworld.tracking.get_active_track(player_name)
  local precision = track and track.precision or "approximate"
  -- Compose short display name: settlement name + event type label
  local short_name
  if site.type == "event" then
    local settlement_name = site.settlement_id or ""
    local subtype_labels = {
      dangerous_roads = "опасная дорога",
      food_shortage = "нехватка еды",
      winter_hardship = "зимние трудности",
      unrest = "беспорядки",
      trade_opportunity = "торговля",
      recovery = "восстановление",
      default = "событие",
    }
    local label = subtype_labels[site.subtype] or subtype_labels.default
    short_name = settlement_name .. " — " .. label
  else
    short_name = site.name or site.name_en or site.id
  end
  local title
  if precision == "approximate" then
    title = "AW: " .. short_name .. " (примерная область)"
  else
    title = "AW: " .. short_name
  end

  local hud_id = player:hud_add({
    hud_elem_type = "waypoint",
    name = title,
    text = "m",
    precision = 0,
    number = color,
    world_pos = target_pos,
  })
  if not hud_id then return false, "Failed to add HUD element" end

  hud_ids[player_name] = hud_id

  -- Add compact info text HUD (tracking status + distance)
  local info_hud = player:hud_add({
    hud_elem_type = "text",
    position = {x = 0, y = 0},
    offset = {x = 10, y = 10},
    text = "AW track: " .. short_name,
    alignment = {x = 0, y = 0},
    scale = {x = 100, y = 100},
    number = 0xFFFFFF,
  })
  if info_hud then
    info_hud_ids[player_name] = info_hud
  end

  return true, precision
end

function aliveworld_player.tracking.track_site(player_name, site_id, opts)
  opts = opts or {}
  if not aliveworld.tracking then
    return false, "Tracking module not loaded"
  end
  local result = aliveworld.tracking.track_site(player_name, site_id, {source = opts.source or "player_command"})
  if not result.ok then
    local err_map = {
      player_not_found = "Игрок не найден",
      sites_module_not_loaded = "Модуль мест недоступен",
      site_not_found = "Место не найдено: " .. site_id,
    }
    return false, err_map[result.error] or result.error
  end

  local site = aliveworld.sites.get(result.resolved_site_id)
  if site then
    local ok, precision = add_hud(player_name, site, result.target_pos)
    if not ok then
      return false, precision
    end
    local site_name = result.title or site_id
    if precision == "approximate" then
      return true, "Waypoint установлен на " .. site_name .. ". След ведёт к окрестностям. Это примерная область по слухам."
    end
    return true, "Waypoint установлен на " .. site_name .. "."
  end
  return true, "Waypoint установлен."
end

function aliveworld_player.tracking.track_event(player_name, event_id)
  if not aliveworld.sites then return false, "Sites module not loaded" end
  local site = aliveworld.sites.find_by_event(event_id)
  if not site then return false, "No site found for event " .. event_id end
  return aliveworld_player.tracking.track_site(player_name, site.id)
end

function aliveworld_player.tracking.track_near(player_name, radius)
  radius = radius or 1000
  if not aliveworld.tracking then return false, "Tracking module not loaded" end
  if not aliveworld.sites then return false, "Sites module not loaded" end
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  local ppos = player:get_pos()
  if not ppos then return false, "Cannot get player position" end
  local from = {x = ppos.x, y = ppos.y, z = ppos.z}
  local near = aliveworld.sites.nearest(from, 30)
  local candidates = {}
  for _, s in ipairs(near) do
    if s.status ~= "active" then goto continue end
    local to_pos = aliveworld.sites.get_display_pos(s)
    local dist = aliveworld.sites.distance(from, to_pos)
    if dist > radius then goto continue end
    local phys = (s.physical_status == "anchored" or s.physical_status == "materialized")
    if s.type == "event" then
      table.insert(candidates, {site = s, priority = phys and 1 or 2, dist = dist})
    end
    if s.type == "settlement" and phys then
      table.insert(candidates, {site = s, priority = 3, dist = dist})
    end
    ::continue::
  end
  if #candidates == 0 then
    return false, "No meaningful sites or events nearby."
  end
  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.dist < b.dist
  end)
  return aliveworld_player.tracking.track_site(player_name, candidates[1].site.id)
end

function aliveworld_player.tracking.untrack(player_name, track_id)
  if not aliveworld.tracking then
    return false, "Tracking module not loaded"
  end
  remove_hud(player_name)
  local result = aliveworld.tracking.untrack(player_name)
  if result.had_track then
    return true, "Waypoint для " .. result.site_id .. " убран."
  end
  return true, "Нет активного waypoint."
end

function aliveworld_player.tracking.clear(player_name)
  aliveworld_player.tracking.untrack(player_name)
end

function aliveworld_player.tracking.list(player_name)
  local track = aliveworld.tracking and aliveworld.tracking.get_active_track(player_name)
  if not track then return {} end
  return {{
    site_id = track.site_id,
    site = track.site,
    precision = track.precision,
    hud_id = hud_ids[player_name],
    target_pos = track.target_pos,
    has_arrived = track.has_arrived,
  }}
end

function aliveworld_player.tracking.refresh_player(player)
  if not player or not player:is_player() then return end
  local pname = player:get_player_name()
  if not aliveworld.tracking then return end
  local track = aliveworld.tracking.get_active_track(pname)
  if not track then return end
  if not hud_ids[pname] then
    local site = track.site
    if site then
      add_hud(pname, site, track.target_pos)
    end
  end
  -- Update info text with distance
  if info_hud_ids[pname] and track.target_pos then
    local ppos = player:get_pos()
    if ppos then
      local dx = track.target_pos.x - ppos.x
      local dz = track.target_pos.z - ppos.z
      local dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
      local track_name = track.title or ""
      local precision_label = (track.precision == "approximate") and "· примерная область" or ""
      local info_text = string.format("AW: %s · %d м %s", track_name, dist, precision_label)
      player:hud_change(info_hud_ids[pname], "text", info_text)
    end
  end
end

function aliveworld_player.tracking.refresh_all()
  for _, player in ipairs(minetest.get_connected_players()) do
    aliveworld_player.tracking.refresh_player(player)
  end
end

-- Globalstep to update info HUD
local info_tick = 0
minetest.register_globalstep(function(dtime)
  info_tick = info_tick + dtime
  if info_tick >= 1.0 then
    info_tick = 0
    aliveworld_player.tracking.refresh_all()
  end
end)

minetest.log("action", "[aliveworld_player] tracking module loaded")