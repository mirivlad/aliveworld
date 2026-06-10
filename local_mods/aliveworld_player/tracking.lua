-- aliveworld_player/tracking.lua
-- Player-facing waypoint tracking UI, delegates to aliveworld.tracking shared API

aliveworld_player.tracking = {}

local hud_ids = {}  -- player_name -> hud_id

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
  if player and hud_ids[player_name] then
    player:hud_remove(hud_ids[player_name])
  end
  hud_ids[player_name] = nil
end

local function add_hud(player_name, site, target_pos)
  remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end

  local color = get_color(site)
  local track = aliveworld.tracking and aliveworld.tracking.get_active_track(player_name)
  local precision = track and track.precision or "approximate"
  local title = site.name_en or site.id
  if precision == "approximate" then
    title = "AW: " .. title .. " (примерная область)"
  else
    title = "AW: " .. title
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
  return true, precision
end

function aliveworld_player.tracking.track_site(player_name, site_id)
  if not aliveworld.tracking then
    return false, "Tracking module not loaded"
  end
  local result = aliveworld.tracking.track_site(player_name, site_id, {source = "player_command"})
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
end

function aliveworld_player.tracking.refresh_all()
  for _, player in ipairs(minetest.get_connected_players()) do
    aliveworld_player.tracking.refresh_player(player)
  end
end

minetest.log("action", "[aliveworld_player] tracking module loaded")