-- radar.lua
-- AliveWorld Radar HUD — north-up point radar for known sites/events

local storage = minetest.get_mod_storage()

aliveworld_player.radar = {}

local radar_state = {}  -- player_name -> {enabled, hud_ids = {bg, player, pt[1..8]}, radius}

local DEFAULT_RADIUS = 512
local DISPLAY_RADIUS = 70  -- px from center
local MAX_POINTS = 8

local function get_radar_offset(radar_origin)
  -- returns (x, y) offset for center of radar display
  return radar_origin.x + 80, radar_origin.y + 80
end

local TEXTURES = {
  player = "aliveworld_radar_player.png",
  settlement = "aliveworld_radar_settlement.png",
  event = "aliveworld_radar_event.png",
  danger = "aliveworld_radar_danger.png",
  unknown = "aliveworld_radar_unknown.png",
  target = "aliveworld_radar_target.png",
  arrow = "aliveworld_radar_arrow.png",
}

-- Select up to MAX_POINTS sites to display, with priority
local function select_points(player_name)
  if not aliveworld.sites then return {} end
  local player = minetest.get_player_by_name(player_name)
  if not player then return {} end
  local ppos = player:get_pos()
  if not ppos then return {} end
  local from = {x = ppos.x, y = ppos.y, z = ppos.z}

  local all = aliveworld.sites.list()
  local candidates = {}
  local tracked_site_id = nil
  local track_list = aliveworld_player.tracking and aliveworld_player.tracking.list(player_name)
  if track_list and #track_list > 0 then
    tracked_site_id = track_list[1].site_id
  end

  for _, s in ipairs(all) do
    if s.status ~= "active" then goto continue end
    local dist = aliveworld.sites.distance(from, s.pos)
    local phys = (s.physical_status == "anchored" or s.physical_status == "materialized")

    local priority = 99
    if s.id == tracked_site_id then
      priority = 1
    elseif s.type == "event" and phys then
      priority = 2
    elseif s.type == "settlement" and phys then
      priority = 3
    elseif s.type == "event" then
      priority = 4
    elseif s.type == "settlement" then
      priority = 5
    end

    table.insert(candidates, {site = s, priority = priority, dist = dist})
    ::continue::
  end

  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.dist < b.dist
  end)

  local result = {}
  for i = 1, math.min(MAX_POINTS, #candidates) do
    table.insert(result, candidates[i].site)
  end
  return result
end

local function get_icon(site, is_edge, is_tracked, player_pos)
  if is_tracked then
    if is_edge then return TEXTURES.arrow, true end
    return TEXTURES.target, false
  end
  if is_edge then return TEXTURES.arrow, true end
  if site.type == "settlement" then return TEXTURES.settlement, false end
  if site.type == "event" then
    if site.subtype == "dangerous_roads" or site.subtype == "unrest" then
      return TEXTURES.danger, false
    end
    return TEXTURES.event, false
  end
  return TEXTURES.unknown, false
end

local function get_radar_positions(from, site, radar_radius, state)
  local dx = site.pos.x - from.x
  local dz = site.pos.z - from.z
  local dist = math.sqrt(dx * dx + dz * dz)
  local is_edge = dist > radar_radius

  local rx, ry
  if is_edge then
    local nx = dx / dist
    local nz = dz / dist
    rx = nx * DISPLAY_RADIUS
    ry = nz * DISPLAY_RADIUS
  else
    local ratio = DISPLAY_RADIUS / radar_radius
    rx = dx * ratio
    ry = dz * ratio
  end

  local cx, cy = get_radar_offset(state.origin)
  local ox = math.floor(cx + rx + 0.5)
  local oy = math.floor(cy + ry + 0.5)
  return ox, oy, is_edge
end

local function create_radar_huds(player, state)
  local huds = {}
  local pname = player:get_player_name()

  -- Background
  huds.bg = player:hud_add({
    hud_elem_type = "image",
    position = {x = 1, y = 0},
    offset = state.origin,
    text = "aliveworld_radar_bg.png",
    scale = {x = 1, y = 1},
    alignment = {x = 0, y = 0},
  })

  -- Player dot at center
  local cx, cy = get_radar_offset(state.origin)
  huds.player = player:hud_add({
    hud_elem_type = "image",
    position = {x = 0, y = 0},
    offset = {x = cx, y = cy},
    text = TEXTURES.player,
    scale = {x = 1, y = 1},
    alignment = {x = 0.5, y = 0.5},
  })

  -- Pre-allocate 8 point slots, all hidden (scale = 0)
  huds.pts = {}
  for i = 1, MAX_POINTS do
    huds.pts[i] = player:hud_add({
      hud_elem_type = "image",
      position = {x = 0, y = 0},
      offset = {x = 0, y = 0},
      text = TEXTURES.unknown,
      scale = {x = 0, y = 0},
      alignment = {x = 0.5, y = 0.5},
    })
  end

  state.hud_ids = huds
end

local function remove_radar_huds(player, state)
  if not state or not state.hud_ids then return end
  local huds = state.hud_ids
  if huds.bg then player:hud_remove(huds.bg) end
  if huds.player then player:hud_remove(huds.player) end
  if huds.pts then
    for _, id in ipairs(huds.pts) do
      player:hud_remove(id)
    end
  end
  state.hud_ids = nil
end

function aliveworld_player.radar.enable(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  if not radar_state[player_name] then
    radar_state[player_name] = {
      enabled = false,
      origin = {x = -170, y = 60},
      radius = DEFAULT_RADIUS,
    }
  end
  local state = radar_state[player_name]
  if state.enabled then return true, "Radar уже включён." end
  state.enabled = true
  create_radar_huds(player, state)
  aliveworld_player.radar.refresh_player(player)
  minetest.log("action", "[aliveworld_player] radar enabled for " .. player_name)
  return true, "AliveWorld Radar включён."
end

function aliveworld_player.radar.disable(player_name)
  local player = minetest.get_player_by_name(player_name)
  local state = radar_state[player_name]
  if not state or not state.enabled then return true, "Radar и так выключен." end
  state.enabled = false
  if player then
    remove_radar_huds(player, state)
  end
  minetest.log("action", "[aliveworld_player] radar disabled for " .. player_name)
  return true, "AliveWorld Radar выключен."
end

function aliveworld_player.radar.toggle(player_name)
  local state = radar_state[player_name]
  if state and state.enabled then
    return aliveworld_player.radar.disable(player_name)
  else
    return aliveworld_player.radar.enable(player_name)
  end
end

function aliveworld_player.radar.is_enabled(player_name)
  local state = radar_state[player_name]
  return state and state.enabled or false
end

function aliveworld_player.radar.get_points_for_player(player_name)
  return select_points(player_name)
end

function aliveworld_player.radar.get_radius(player_name)
  local state = radar_state[player_name]
  return (state and state.radius) or DEFAULT_RADIUS
end

function aliveworld_player.radar.set_radius(player_name, blocks)
  blocks = tonumber(blocks)
  if not blocks or blocks < 64 then return false, "Минимальный радиус: 64 блока." end
  if blocks > 2000 then return false, "Максимальный радиус: 2000 блоков." end
  if not radar_state[player_name] then
    radar_state[player_name] = {enabled = false, origin = {x = -170, y = 60}, radius = DEFAULT_RADIUS}
  end
  radar_state[player_name].radius = blocks
  local player = minetest.get_player_by_name(player_name)
  if player then
    aliveworld_player.radar.refresh_player(player)
  end
  return true, "Радиус радара изменён на " .. blocks .. " блоков."
end

function aliveworld_player.radar.clear_hud(player_name)
  local state = radar_state[player_name]
  local player = minetest.get_player_by_name(player_name)
  if state and player then
    remove_radar_huds(player, state)
  end
end

function aliveworld_player.radar.refresh_player(player)
  local pname = player:get_player_name()
  local state = radar_state[pname]
  if not state or not state.enabled or not state.hud_ids then return end

  -- Re-create HUDs if they were lost (e.g. after rejoin)
  if not state.hud_ids.bg then
    create_radar_huds(player, state)
  end

  local ppos = player:get_pos()
  if not ppos then return end
  local from = {x = ppos.x, y = ppos.y, z = ppos.z}
  local radius = state.radius
  local huds = state.hud_ids

  -- Get tracked site id
  local tracked_site_id = nil
  local track_list = aliveworld_player.tracking and aliveworld_player.tracking.list(pname)
  if track_list and #track_list > 0 then
    tracked_site_id = track_list[1].site_id
  end

  local points = select_points(pname)

  -- Update player dot position
  local cx, cy = get_radar_offset(state.origin)
  player:hud_change(huds.player, "offset", {x = cx, y = cy})

  -- Update point slots
  for i = 1, MAX_POINTS do
    if i <= #points then
      local site = points[i]
      local is_tracked = (site.id == tracked_site_id)
      local ox, oy, is_edge = get_radar_positions(from, site, radius, state)
      local tex, _ = get_icon(site, is_edge, is_tracked, from)

      -- Use anchor_pos for tracked sites if available
      if is_tracked and (site.physical_status == "anchored" or site.physical_status == "materialized") and site.anchor_pos then
        local tdx = site.anchor_pos.x - from.x
        local tdz = site.anchor_pos.z - from.z
        local tdist = math.sqrt(tdx*tdx + tdz*tdz)
        local is_edge2 = tdist > radius
        if is_edge2 then
          local nx = tdx / tdist
          local nz = tdz / tdist
          ox = math.floor(cx + nx * DISPLAY_RADIUS + 0.5)
          oy = math.floor(cy + nz * DISPLAY_RADIUS + 0.5)
          tex = TEXTURES.arrow
        else
          local ratio = DISPLAY_RADIUS / radius
          ox = math.floor(cx + tdx * ratio + 0.5)
          oy = math.floor(cy + tdz * ratio + 0.5)
          tex = TEXTURES.target
        end
      end

      player:hud_change(huds.pts[i], "offset", {x = ox, y = oy})
      player:hud_change(huds.pts[i], "text", tex)
      player:hud_change(huds.pts[i], "scale", {x = 1, y = 1})
    else
      -- Hide unused slot
      player:hud_change(huds.pts[i], "scale", {x = 0, y = 0})
    end
  end
end

function aliveworld_player.radar.refresh_all()
  for _, player in ipairs(minetest.get_connected_players()) do
    aliveworld_player.radar.refresh_player(player)
  end
end

-- Globalstep for radar refresh
local radar_tick = 0
minetest.register_globalstep(function(dtime)
  radar_tick = radar_tick + dtime
  if radar_tick >= 1.0 then
    radar_tick = 0
    aliveworld_player.radar.refresh_all()
  end
end)

-- Cleanup on leave
minetest.register_on_leaveplayer(function(player)
  local pname = player:get_player_name()
  local state = radar_state[pname]
  if state then
    state.enabled = false
    state.hud_ids = nil
  end
end)

minetest.log("action", "[aliveworld_player] radar module loaded")
