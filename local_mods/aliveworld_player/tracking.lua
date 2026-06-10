-- tracking.lua
-- Waypoint tracking system for AliveWorld

local storage = minetest.get_mod_storage()
aliveworld_player.tracking = {}

local tracks = {}

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

function aliveworld_player.tracking.get_target_pos(site)
  if not site then return nil, "no_site" end
  if (site.physical_status == "anchored" or site.physical_status == "materialized") and site.anchor_pos then
    return site.anchor_pos, "exact"
  end
  return site.pos, "approximate"
end

local function remove_hud(player_name)
  local t = tracks[player_name]
  if not t then return end
  local player = minetest.get_player_by_name(player_name)
  if player and t.hud_id then
    player:hud_remove(t.hud_id)
  end
  tracks[player_name] = nil
end

local function add_hud(player_name, site)
  remove_hud(player_name)
  local target_pos, precision = aliveworld_player.tracking.get_target_pos(site)
  if not target_pos then return false, "No target position" end
  local color = get_color(site)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  local hud_id = player:hud_add({
    hud_elem_type = "waypoint",
    name = site.name_en or site.id,
    text = "m",
    precision = 0,
    number = color,
    world_pos = target_pos,
  })
  if not hud_id then return false, "Failed to add HUD element" end
  tracks[player_name] = {
    track_type = "site",
    track_id = site.id,
    site_id = site.id,
    hud_id = hud_id,
    precision = precision,
  }
  local meta = player:get_meta()
  meta:set_string("aliveworld_track_site_id", site.id)
  return true, precision
end

local function get_site_from_event(event_id)
  if not aliveworld.sites then return nil end
  return aliveworld.sites.find_by_event(event_id)
end

function aliveworld_player.tracking.track_site(player_name, site_id)
  if not aliveworld.sites then return false, "Sites module not loaded" end
  local site = aliveworld.sites.get(site_id)
  if not site then return false, "Site not found: " .. site_id end
  if site.status ~= "active" then return false, "Site is not active" end
  local ok, precision = add_hud(player_name, site)
  if not ok then return false, precision end
  local site_name = site.name or site_id
  if precision == "approximate" then
    return true, "Waypoint установлен на " .. site_name .. ". Место известно только по слухам. Waypoint указывает примерную область."
  end
  return true, "Waypoint установлен на " .. site_name .. "."
end

function aliveworld_player.tracking.track_event(player_name, event_id)
  if not aliveworld.sites then return false, "Sites module not loaded" end
  local site = get_site_from_event(event_id)
  if not site then return false, "No site found for event " .. event_id end
  return aliveworld_player.tracking.track_site(player_name, site.id)
end

function aliveworld_player.tracking.track_near(player_name, radius)
  radius = radius or 1000
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  local ppos = player:get_pos()
  if not ppos then return false, "Cannot get player position" end
  local from = {x = ppos.x, y = ppos.y, z = ppos.z}
  if not aliveworld.sites then return false, "Sites module not loaded" end
  local near = aliveworld.sites.nearest(from, 30)
  local candidates = {}
  for _, s in ipairs(near) do
    if s.status ~= "active" then goto continue end
    local dist = aliveworld.sites.distance(from, s.pos)
    if dist > radius then goto continue end
    local phys = (s.physical_status == "anchored" or s.physical_status == "materialized")
    if s.type == "event" then
      if phys then
        table.insert(candidates, {site = s, priority = 1, dist = dist})
      else
        table.insert(candidates, {site = s, priority = 2, dist = dist})
      end
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
  if not track_id or track_id == "" or track_id == "all" then
    remove_hud(player_name)
    local player = minetest.get_player_by_name(player_name)
    if player then player:get_meta():set_string("aliveworld_track_site_id", "") end
    return true, "Waypoint убран."
  end
  local t = tracks[player_name]
  if not t or t.track_id ~= track_id then
    return false, "No active waypoint for " .. track_id
  end
  remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if player then player:get_meta():set_string("aliveworld_track_site_id", "") end
  return true, "Waypoint для " .. track_id .. " убран."
end

function aliveworld_player.tracking.clear(player_name)
  remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if player then player:get_meta():set_string("aliveworld_track_site_id", "") end
end

function aliveworld_player.tracking.list(player_name)
  local t = tracks[player_name]
  if not t then return {} end
  local site = aliveworld.sites and aliveworld.sites.get(t.site_id)
  return {{
    site_id = t.site_id,
    site = site,
    precision = t.precision,
    hud_id = t.hud_id,
  }}
end

function aliveworld_player.tracking.refresh_player(player)
  local player_name = player:get_player_name()
  local meta = player:get_meta()
  local site_id = meta:get_string("aliveworld_track_site_id")
  if site_id and site_id ~= "" and aliveworld.sites then
    local site = aliveworld.sites.get(site_id)
    if site and site.status == "active" then
      add_hud(player_name, site)
    else
      meta:set_string("aliveworld_track_site_id", "")
    end
  end
end

function aliveworld_player.tracking.refresh_all()
  for _, player in ipairs(minetest.get_connected_players()) do
    aliveworld_player.tracking.refresh_player(player)
  end
end

minetest.log("action", "[aliveworld_player] tracking module loaded")
