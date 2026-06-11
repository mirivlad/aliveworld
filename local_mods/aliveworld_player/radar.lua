-- radar.lua
-- AliveWorld GPS: server-side minimap + marker overlay
--
-- Architecture:
--   Server creates a type="minimap" HUD element at a known screen position
--   and hides the builtin minimap. Markers are image HUD elements overlaid
--   on top. The player yaw rotates markers to match the round minimap.

local storage = minetest.get_mod_storage()

aliveworld_player.radar = {}

-- Layout: single source of truth for minimap geometry.
-- All positions are screen pixels computed from these values.
-- Using fixed pixel size so we always know the node-to-pixel ratio.
local GPS_SIZE_PX = 200
local GPS_POSITION = {x = 1, y = 0}
local GPS_ALIGNMENT = {x = -1, y = 1}
local GPS_OFFSET = {x = -10, y = 10}

local function make_map_rect()
  return {
    size_px = GPS_SIZE_PX,
    position = GPS_POSITION,
    alignment = GPS_ALIGNMENT,
    offset = GPS_OFFSET,
    -- Computed from size: square minimap
    center_off_x = -GPS_OFFSET.x - GPS_SIZE_PX / 2,
    center_off_y = GPS_OFFSET.y + GPS_SIZE_PX / 2,
    visible_radius_px = GPS_SIZE_PX / 2,
  }
end

-- GPS zoom levels: discrete modes that synchronise minimap mode with scale.
-- Each level has:
--   mode_size  — side length in nodes for set_minimap_modes
--   label      — displayed mode label
--   diameter_nodes — total world diameter covered by the minimap
--   radius_nodes   — radius from player
local GPS_ZOOMS = {
  { id = "near",     label = "GPS: Ближний",   mode_size = 80,   diameter_nodes = 80,   radius_nodes = 40   },
  { id = "medium",   label = "GPS: Средний",   mode_size = 200,  diameter_nodes = 200,  radius_nodes = 100  },
  { id = "far",      label = "GPS: Дальний",   mode_size = 512,  diameter_nodes = 512,  radius_nodes = 256  },
  { id = "overview", label = "GPS: Обзор",     mode_size = 512,  diameter_nodes = 512,  radius_nodes = 256  },
}

local function get_pixels_per_node(zoom, map_rect)
  return map_rect.size_px / zoom.diameter_nodes
end

local function get_nodes_per_pixel(zoom, map_rect)
  return zoom.diameter_nodes / map_rect.size_px
end

-- Textures for markers
local TEXTURES = {
  player  = "aliveworld_radar_player.png",
  target  = "aliveworld_radar_target.png",
  settlement = "aliveworld_radar_settlement.png",
  event   = "aliveworld_radar_event.png",
  danger  = "aliveworld_radar_danger.png",
  unknown = "aliveworld_radar_unknown.png",
  arrow   = "aliveworld_radar_arrow.png",
}

local MAX_MARKERS = 8
local MARKER_IMAGE_SIZE = 16

-- Per-player GPS state
local gps_state = {}

local function get_or_create_state(player_name)
  if not gps_state[player_name] then
    gps_state[player_name] = {
      enabled = false,
      zoom_idx = 2,        -- default: medium
      hud_minimap = nil,
      hud_markers = {},
      hud_info = nil,
      last_pos = nil,
      last_yaw = nil,
      last_zoom_id = nil,
      dirty = true,
      rebuild_sources = true,
      -- debug counters
      counters = { geometry_updates = 0, source_rebuilds = 0, hud_changes = 0, idle_skips = 0 },
    }
  end
  return gps_state[player_name]
end

-- Create minimap modes for set_minimap_modes
local function build_minimap_modes()
  local modes = {{ type = "off", label = "Выкл" }}
  for _, z in ipairs(GPS_ZOOMS) do
    table.insert(modes, { type = "radar", label = z.label, size = z.mode_size })
  end
  return modes
end

-- World -> screen projection with yaw rotation (assumes round minimap)
local function world_to_screen(dx_world, dz_world, yaw, pixels_per_node, visible_radius_px)
  -- Rotate world offset by player yaw (negate because minimap rotates opposite)
  -- Round minimap: top of map = player facing direction
  local cos_y = math.cos(-yaw)
  local sin_y = math.sin(-yaw)
  local rx = dx_world * cos_y - dz_world * sin_y
  local rz = dx_world * sin_y + dz_world * cos_y

  local dist = math.sqrt(rx * rx + rz * rz)
  local px = rx * pixels_per_node
  local py = rz * pixels_per_node

  local is_edge = dist > (visible_radius_px / pixels_per_node)
  if is_edge then
    local norm_dist = math.sqrt(rx * rx + rz * rz)
    if norm_dist > 0 then
      px = (rx / norm_dist) * visible_radius_px
      py = (rz / norm_dist) * visible_radius_px
    end
  end

  return px, -py, is_edge
  -- Negate py because screen y increases downward
end

-- Select marker sources for a player
local function select_sources(player_name, player_pos, tracked_site_id)
  if not aliveworld.sites then return {} end
  local from = {x = player_pos.x, y = player_pos.y, z = player_pos.z}
  local all = aliveworld.sites.list()
  local candidates = {}

  for _, s in ipairs(all) do
    if s.status ~= "active" then goto continue end
    local target_pos = (aliveworld.sites.get_display_pos and aliveworld.sites.get_display_pos(s)) or s.pos
    local dx = target_pos.x - from.x
    local dz = target_pos.z - from.z
    local dist = math.sqrt(dx * dx + dz * dz)

    local phys = (s.physical_status == "anchored" or s.physical_status == "materialized")
    local is_tracked = (s.id == tracked_site_id)

    local priority = 99
    if is_tracked then
      priority = 1
    elseif phys and s.type == "event" then
      priority = 2
    elseif phys and s.type == "settlement" then
      priority = 3
    elseif s.type == "event" then
      priority = 4
    elseif s.type == "settlement" then
      priority = 5
    end

    table.insert(candidates, { site = s, target_pos = target_pos, dist = dist, priority = priority, is_tracked = is_tracked })
    ::continue::
  end

  table.sort(candidates, function(a, b)
    if a.priority ~= b.priority then return a.priority < b.priority end
    return a.dist < b.dist
  end)

  local result = {}
  for i = 1, math.min(MAX_MARKERS, #candidates) do
    table.insert(result, candidates[i])
  end
  return result
end

local function get_icon_info(source, is_edge)
  if source.is_tracked then
    if is_edge then return TEXTURES.arrow end
    return TEXTURES.target
  end
  if is_edge then return TEXTURES.arrow end
  if source.site.type == "settlement" then return TEXTURES.settlement end
  if source.site.type == "event" then
    local sub = source.site.subtype
    if sub == "dangerous_roads" or sub == "unrest" then
      return TEXTURES.danger
    end
    return TEXTURES.event
  end
  return TEXTURES.unknown
end

-- Build map_rect for geometry computations
local function get_map_rect()
  return make_map_rect()
end

function aliveworld_player.radar.get_map_rect()
  return get_map_rect()
end

function aliveworld_player.radar.enable(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  local state = get_or_create_state(player_name)
  if state.enabled then return true, "GPS уже включён." end
  state.enabled = true
  state.dirty = true
  state.rebuild_sources = true

  -- Hide builtin minimap
  player:hud_set_flags({ minimap = false, minimap_radar = false })

  -- Set minimap modes
  player:set_minimap_modes(build_minimap_modes(), 1)

  -- Create GPS HUD elements
  local success, err = aliveworld_player.radar.rebuild_hud(player_name, player)
  if not success then
    state.enabled = false
    player:hud_set_flags({ minimap = true })
    return false, err
  end

  minetest.log("action", "[aliveworld_player] GPS enabled for " .. player_name)
  return true, "AliveWorld GPS включён. Нажмите Shift+V для круглой формы."
end

function aliveworld_player.radar.disable(player_name)
  local player = minetest.get_player_by_name(player_name)
  local state = gps_state[player_name]
  if not state or not state.enabled then return true, "GPS и так выключен." end
  state.enabled = false

  if player then
    aliveworld_player.radar.clear_hud(player_name, player)
    player:hud_set_flags({ minimap = true, minimap_radar = true })
  end

  minetest.log("action", "[aliveworld_player] GPS disabled for " .. player_name)
  return true, "AliveWorld GPS выключен."
end

function aliveworld_player.radar.toggle(player_name)
  local state = gps_state[player_name]
  if state and state.enabled then
    return aliveworld_player.radar.disable(player_name)
  else
    return aliveworld_player.radar.enable(player_name)
  end
end

function aliveworld_player.radar.is_enabled(player_name)
  local state = gps_state[player_name]
  return state and state.enabled or false
end

-- GPS zoom control
function aliveworld_player.radar.set_zoom(player_name, zoom_id_or_idx)
  local state = get_or_create_state(player_name)
  local idx
  if type(zoom_id_or_idx) == "number" then
    idx = zoom_id_or_idx
  else
    for i, z in ipairs(GPS_ZOOMS) do
      if z.id == zoom_id_or_idx then idx = i; break end
    end
  end
  if not idx or idx < 1 or idx > #GPS_ZOOMS then
    return false, "Неверный масштаб. Доступны: near, medium, far, overview"
  end

  state.zoom_idx = idx
  state.dirty = true
  state.rebuild_sources = true

  local player = minetest.get_player_by_name(player_name)
  if player and state.enabled then
    player:set_minimap_modes(build_minimap_modes(), idx)
    aliveworld_player.radar.rebuild_hud(player_name, player)
  end
  return true, "GPS масштаб: " .. GPS_ZOOMS[idx].label
end

function aliveworld_player.radar.get_zoom(player_name)
  local state = gps_state[player_name]
  if not state then return GPS_ZOOMS[2] end
  return GPS_ZOOMS[state.zoom_idx] or GPS_ZOOMS[2]
end

function aliveworld_player.radar.get_zoom_index(player_name)
  local state = gps_state[player_name]
  return state and state.zoom_idx or 2
end

function aliveworld_player.radar.zoom_in(player_name)
  local state = get_or_create_state(player_name)
  local new_idx = math.max(1, state.zoom_idx - 1)
  return aliveworld_player.radar.set_zoom(player_name, new_idx)
end

function aliveworld_player.radar.zoom_out(player_name)
  local state = get_or_create_state(player_name)
  local new_idx = math.min(#GPS_ZOOMS, state.zoom_idx + 1)
  return aliveworld_player.radar.set_zoom(player_name, new_idx)
end

-- Mark dirty for source rebuild
function aliveworld_player.radar.mark_dirty(player_name)
  local state = gps_state[player_name]
  if state and state.enabled then
    state.dirty = true
    state.rebuild_sources = true
  end
end

function aliveworld_player.radar.mark_all_dirty()
  for pname, state in pairs(gps_state) do
    if state.enabled then
      state.dirty = true
      state.rebuild_sources = true
    end
  end
end

function aliveworld_player.radar.clear_hud(player_name, player)
  player = player or minetest.get_player_by_name(player_name)
  if not player then return end
  local state = gps_state[player_name]
  if not state then return end

  if state.hud_minimap then
    player:hud_remove(state.hud_minimap)
    state.hud_minimap = nil
  end
  if state.hud_markers then
    for _, id in ipairs(state.hud_markers) do
      player:hud_remove(id)
    end
    state.hud_markers = {}
  end
  if state.hud_info then
    player:hud_remove(state.hud_info)
    state.hud_info = nil
  end
end

function aliveworld_player.radar.rebuild_hud(player_name, player)
  player = player or minetest.get_player_by_name(player_name)
  if not player then return false, "Player not found" end
  local state = get_or_create_state(player_name)

  -- Clear existing HUD
  aliveworld_player.radar.clear_hud(player_name, player)

  local map_rect = make_map_rect()

  -- Create minimap HUD element
  state.hud_minimap = player:hud_add({
    hud_elem_type = "minimap",
    position = map_rect.position,
    alignment = map_rect.alignment,
    offset = map_rect.offset,
    size = { x = map_rect.size_px, y = map_rect.size_px },
    z_index = -2,
  })
  if not state.hud_minimap then
    return false, "Failed to create minimap HUD"
  end

  -- Create marker slots (pre-allocated, hidden by default)
  state.hud_markers = {}
  for i = 1, MAX_MARKERS do
    local id = player:hud_add({
      hud_elem_type = "image",
      position = map_rect.position,
      alignment = { x = 0.5, y = 0.5 },
      offset = { x = 0, y = 0 },
      scale = { x = 1, y = 1 },
      text = TEXTURES.unknown,
      z_index = 0,
    })
    if id then
      state.hud_markers[i] = id
    end
  end

  -- Create info text
  state.hud_info = player:hud_add({
    hud_elem_type = "text",
    position = { x = 1, y = 0 },
    alignment = { x = -1, y = 1 },
    offset = { x = -220, y = 15 },
    text = "AliveWorld GPS",
    scale = { x = 100, y = 100 },
    number = 0xFFFFFF,
    z_index = 1,
  })

  return true
end

-- Core update: compute marker positions and update HUD
function aliveworld_player.radar.update_player(player_name)
  local player = minetest.get_player_by_name(player_name)
  if not player then return end
  local state = gps_state[player_name]
  if not state or not state.enabled then return end

  -- Ensure HUD exists
  if not state.hud_minimap then
    aliveworld_player.radar.rebuild_hud(player_name, player)
  end

  local ppos = player:get_pos()
  if not ppos then return end
  local yaw = player:get_look_horizontal() or 0

  local zoom = GPS_ZOOMS[state.zoom_idx]
  local map_rect = make_map_rect()
  local ppn = get_pixels_per_node(zoom, map_rect)
  local npp = get_nodes_per_pixel(zoom, map_rect)
  local radius_nodes = zoom.radius_nodes

  -- Detect meaningful change
  local moved = false
  if state.last_pos then
    local dx = ppos.x - state.last_pos.x
    local dz = ppos.z - state.last_pos.z
    if dx * dx + dz * dz > 0.001 then
      moved = true
    end
  else
    moved = true
  end

  local yaw_changed = false
  if state.last_yaw then
    local dyaw = yaw - state.last_yaw
    -- Handle wrap-around
    if dyaw > math.pi then dyaw = dyaw - 2 * math.pi end
    if dyaw < -math.pi then dyaw = dyaw + 2 * math.pi end
    if math.abs(dyaw) > 0.0044 then  -- ~0.25 degrees
      yaw_changed = true
    end
  else
    yaw_changed = true
  end

  local zoom_changed = (state.last_zoom_id ~= zoom.id)

  if not moved and not yaw_changed and not zoom_changed and not state.dirty then
    state.counters.idle_skips = state.counters.idle_skips + 1
    return
  end

  state.last_pos = { x = ppos.x, y = ppos.y, z = ppos.z }
  state.last_yaw = yaw
  state.last_zoom_id = zoom.id
  state.counters.geometry_updates = state.counters.geometry_updates + 1

  local sources = {}
  local from = { x = ppos.x, y = ppos.y, z = ppos.z }

  -- Rebuild sources if needed
  if state.rebuild_sources or moved or zoom_changed then
    local tracked_id = nil
    if aliveworld_player.tracking then
      local tracks = aliveworld_player.tracking.list(player_name)
      if tracks and #tracks > 0 then
        tracked_id = tracks[1].site_id
      end
    end
    sources = select_sources(player_name, ppos, tracked_id)
    state.rebuild_sources = false
    state.counters.source_rebuilds = state.counters.source_rebuilds + 1
    state.counters.hud_changes = state.counters.hud_changes + 1
  else
    -- Use cached sources
    sources = state._cached_sources or {}
  end
  state._cached_sources = sources

  -- Update markers
  local map_rect = make_map_rect()
  local center_ox = math.floor(map_rect.center_off_x + 0.5)
  local center_oy = math.floor(map_rect.center_off_y + 0.5)

  for i = 1, MAX_MARKERS do
    if i <= #sources and state.hud_markers[i] then
      local src = sources[i]
      local target_pos = src.target_pos
      local dx = target_pos.x - from.x
      local dz = target_pos.z - from.z

      local px, py, is_edge = world_to_screen(dx, dz, yaw, ppn, map_rect.visible_radius_px)
      local ox = math.floor(center_ox + px + 0.5)
      local oy = math.floor(center_oy + py + 0.5)
      local tex = get_icon_info(src, is_edge)

      player:hud_change(state.hud_markers[i], "offset", { x = ox, y = oy })
      player:hud_change(state.hud_markers[i], "text", tex)
      player:hud_change(state.hud_markers[i], "scale", { x = 1, y = 1 })
    elseif state.hud_markers[i] then
      player:hud_change(state.hud_markers[i], "scale", { x = 0, y = 0 })
    end
  end

  -- Update info text
  if state.hud_info then
    local lines = { "AliveWorld GPS" }
    table.insert(lines, "Масштаб: " .. zoom.label .. " (" .. zoom.diameter_nodes .. " блоков)")

    if aliveworld_player.tracking then
      local tracks = aliveworld_player.tracking.list(player_name)
      if tracks and #tracks > 0 and tracks[1].target_pos then
        local tp = tracks[1].target_pos
        local dx = tp.x - from.x
        local dz = tp.z - from.z
        local dist = math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
        local precision_label = (tracks[1].precision == "approximate") and " · примерно" or ""
        table.insert(lines, string.format("Цель: %d м%s", dist, precision_label))
      end
    end

    local debug_parts = {}
    if state.counters.idle_skips > 0 then
      table.insert(debug_parts, "idle:" .. state.counters.idle_skips)
    end
    -- Only show in debug mode
    if #debug_parts > 0 then
      table.insert(lines, table.concat(debug_parts, " "))
    end

    player:hud_change(state.hud_info, "text", table.concat(lines, "\n"))
  end

  state.dirty = false
end

function aliveworld_player.radar.refresh_player(player)
  aliveworld_player.radar.update_player(player:get_player_name())
end

function aliveworld_player.radar.refresh_all()
  for _, player in ipairs(minetest.get_connected_players()) do
    local pname = player:get_player_name()
    aliveworld_player.radar.update_player(pname)
  end
end

-- Globalstep: cheap detection
local gps_tick = 0
minetest.register_globalstep(function(dtime)
  gps_tick = gps_tick + dtime
  if gps_tick >= 0.2 then
    gps_tick = 0
    aliveworld_player.radar.refresh_all()
  end
end)

-- Cleanup on leave
minetest.register_on_leaveplayer(function(player)
  local pname = player:get_player_name()
  local state = gps_state[pname]
  if state and state.enabled then
    state.enabled = false
    state.hud_minimap = nil
    state.hud_markers = {}
    state.hud_info = nil
  end
  gps_state[pname] = nil
end)

-- Listen for tracking changes
minetest.register_on_chat_message(function(player_name, message)
  -- No-op: tracking changes detected via dirty markers
end)

-- Debug info
function aliveworld_player.radar.get_debug_info(player_name)
  local state = gps_state[player_name]
  if not state then
    return { enabled = false, counters = {} }
  end
  local ids = {}
  ids.minimap = state.hud_minimap
  ids.info = state.hud_info
  ids.markers = {}
  if state.hud_markers then
    for i, id in ipairs(state.hud_markers) do
      ids.markers[i] = id
    end
  end
  return {
    enabled = state.enabled,
    zoom = GPS_ZOOMS[state.zoom_idx],
    counters = state.counters,
    hud_ids = ids,
    dirty = state.dirty,
    rebuild_sources = state.rebuild_sources,
  }
end

minetest.log("action", "[aliveworld_player] GPS radar module loaded")
