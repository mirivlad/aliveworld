-- aliveworld_player/tracking.lua
-- Player-facing tracking: compact info text + GPS marker.
-- Old 3D waypoint HUD is removed; tracking targets appear on GPS minimap.

aliveworld_player.tracking = {}

local COLOR_DEFAULT = 0xFFFFFF
local info_hud_ids = {}

local function remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if player and info_hud_ids[player_name] then
    player:hud_remove(info_hud_ids[player_name])
  end
  info_hud_ids[player_name] = nil
end

local function add_info_hud(player_name, short_name)
  remove_hud(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false end

  -- Compact info text: positioned below GPS minimap area
  local id = player:hud_add({
    hud_elem_type = "text",
    position = { x = 1, y = 0 },
    alignment = { x = -1, y = 1 },
    offset = { x = -220, y = 80 },
    text = "AW: " .. short_name,
    scale = { x = 100, y = 100 },
    number = COLOR_DEFAULT,
  })
  if id then
    info_hud_ids[player_name] = id
    return true
  end
  return false
end

local function get_short_name(site)
  if not site then return "?" end
  if site.type == "event" then
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
    return (site.settlement_id or "") .. " — " .. label
  end
  return site.name or site.name_en or site.id
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
    local short_name = get_short_name(site)
    add_info_hud(player_name, short_name)
    -- Notify GPS to refresh markers
    if aliveworld_player.radar and aliveworld_player.radar.is_enabled(player_name) then
      aliveworld_player.radar.mark_dirty(player_name)
    end
    local site_name = result.title or site_id
    if result.precision == "approximate" then
      return true, "Отслеживание: " .. site_name .. " (примерная область). Цель на GPS."
    end
    return true, "Отслеживание: " .. site_name .. ". Цель на GPS."
  end
  return true, "Отслеживание установлено."
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
  -- Notify GPS
  if aliveworld_player.radar and aliveworld_player.radar.is_enabled(player_name) then
    aliveworld_player.radar.mark_dirty(player_name)
  end
  if result.had_track then
    return true, "Отслеживание " .. result.site_id .. " остановлено."
  end
  return true, "Нет активного отслеживания."
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
    target_pos = track.target_pos,
    has_arrived = track.has_arrived,
    tracking_hud_id = info_hud_ids[player_name],
    -- Compatibility alias for older screenshot/test metadata. This is the text
    -- tracking HUD id, not a removed 3D waypoint; remove after consumers migrate.
    hud_id = info_hud_ids[player_name],
  }}
end

function aliveworld_player.tracking.refresh_player(player)
  if not player or not player:is_player() then return end
  local pname = player:get_player_name()
  if not aliveworld.tracking then return end
  local track = aliveworld.tracking.get_active_track(pname)
  if not track then
    remove_hud(pname)
    return
  end
  if not info_hud_ids[pname] then
    local site = track.site
    if site then
      add_info_hud(pname, get_short_name(site))
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
      local precision_label = (track.precision == "approximate") and "· примерно" or ""
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

function aliveworld_player.tracking.check_arrival(player_or_name)
  if not aliveworld.tracking then
    return {ok = false, error = "tracking_module_not_loaded"}
  end
  local player
  if type(player_or_name) == "string" then
    player = minetest.get_player_by_name(player_or_name)
  else
    player = player_or_name
  end
  if not player or not player:is_player() then
    return {ok = false, error = "player_not_found"}
  end
  local result = aliveworld.tracking.check_arrival(player)
  if not result then
    return {ok = true, has_track = false, arrived = false}
  end
  return {
    ok = true,
    has_track = true,
    arrived = result.arrived or false,
    site_id = result.site_id,
    distance = result.dist,
    arrival_radius = 12,
    kind = result.kind,
    msg = result.msg,
  }
end

function aliveworld_player.tracking.get_debug_info(player_or_name)
  if not aliveworld.tracking then
    return {player_name = nil, error = "tracking_module_not_loaded"}
  end
  return aliveworld.tracking.get_debug_info(player_or_name)
end

function aliveworld_player.tracking.describe_track(player_or_name)
  if not aliveworld.tracking then
    return {ok = true, has_track = false, line = "Tracking module not loaded"}
  end
  return aliveworld.tracking.describe_track(player_or_name)
end

function aliveworld_player.tracking.reset_arrival_ack(player_or_name, site_id)
  if not aliveworld.tracking then
    return {ok = false, error = "tracking_module_not_loaded"}
  end
  return aliveworld.tracking.reset_arrival_ack(player_or_name, site_id)
end

-- Globalstep to update info HUD
local info_tick = 0
minetest.register_globalstep(function(dtime)
  info_tick = info_tick + dtime
  if info_tick >= 0.5 then
    info_tick = 0
    aliveworld_player.tracking.refresh_all()
  end
end)

minetest.log("action", "[aliveworld_player] tracking module loaded")
