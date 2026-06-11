-- aliveworld_test_suite/ui_state.lua
-- UI state management for awbot test client
-- Tracks client UI state, provides cleanup, coordinates with host-side screenshot system

local modpath = minetest.get_modpath("aliveworld_test_suite")
local worldpath = minetest.get_worldpath()

local ui = {}

local state = {
  client_ui_dirty = false,
  known_open_ui = nil,
  screenshot_kind = nil,
  cleanup_count = 0,
  restart_count = 0,
  restored_count = 0,
  observer_pos = {x = 245, y = 23, z = -145},
  player_name = "awbot",
}

local cleanup_handlers = {}

function ui.register_cleanup(ui_type, handler)
  cleanup_handlers[ui_type] = handler
end

function ui.mark_dirty(ui_type)
  state.client_ui_dirty = true
  state.known_open_ui = ui_type
  minetest.log("action", "[ui_state] marked dirty: " .. tostring(ui_type))
end

function ui.mark_clean()
  state.client_ui_dirty = false
  state.known_open_ui = nil
  minetest.log("action", "[ui_state] marked clean")
end

function ui.is_dirty()
  return state.client_ui_dirty
end

function ui.get_known_open_ui()
  return state.known_open_ui
end

function ui.set_screenshot_kind(kind)
  state.screenshot_kind = kind
end

function ui.get_screenshot_kind()
  return state.screenshot_kind
end

function ui.set_observer_pos(pos)
  state.observer_pos = pos
end

local function restore_player_state(pos, site_id)
  local player = minetest.get_player_by_name(state.player_name)
  if not player then
    return false, "player_not_online"
  end

  if pos then
    player:set_pos(pos)
  end
  player:set_hp(20)
  player:set_breath(10)
  player:set_velocity({x = 0, y = 0, z = 0})

  if not aliveworld_player then
    return false, "aliveworld_player_not_loaded"
  end
  if not aliveworld_player.radar or not aliveworld_player.radar.enable then
    return false, "radar_not_loaded"
  end

  if site_id then
    if not aliveworld or not aliveworld.sites or not aliveworld.sites.get then
      return false, "sites_not_loaded"
    end
    if not aliveworld.sites.get(site_id) then
      if aliveworld_player.tracking and aliveworld_player.tracking.untrack then
        aliveworld_player.tracking.untrack(state.player_name)
      end
      return false, "site_not_found: " .. tostring(site_id)
    end
  end

  local gps_ok, gps_msg = aliveworld_player.radar.enable(state.player_name)
  if not gps_ok then
    return false, "gps_enable_failed: " .. tostring(gps_msg)
  end

  if site_id then
    if not aliveworld_player.tracking or not aliveworld_player.tracking.track_site then
      return false, "tracking_not_loaded"
    end
    local track_ok, track_msg = aliveworld_player.tracking.track_site(state.player_name, site_id)
    if not track_ok then
      aliveworld_player.tracking.untrack(state.player_name)
      return false, "track_failed: " .. tostring(track_msg)
    end
  end

  return true, "restored"
end

local function write_restart_signal(reason)
  local signal = {
    action = "restart_awbot_client",
    reason = reason,
    player = state.player_name,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    restore = {
      observer_pos = state.observer_pos,
    },
  }
  local f = io.open(worldpath .. "/awbot_client.signal", "w")
  if f then
    f:write(minetest.write_json(signal))
    f:close()
    minetest.log("action", "[ui_state] restart signal written: " .. tostring(reason))
  end
end

function ui.ensure_clean_world_view()
  if not state.client_ui_dirty then
    return true, "already clean"
  end

  local ui_type = state.known_open_ui
  if ui_type and cleanup_handlers[ui_type] then
    local ok, msg = cleanup_handlers[ui_type]()
    if ok then
      state.client_ui_dirty = false
      state.known_open_ui = nil
      state.cleanup_count = state.cleanup_count + 1
      minetest.log("action", "[ui_state] cleaned via handler for " .. tostring(ui_type) .. ": " .. tostring(msg))
      return true, "cleaned: " .. msg
    end
    minetest.log("action", "[ui_state] handler for " .. tostring(ui_type) .. " failed: " .. tostring(msg))
  end

  minetest.log("action", "[ui_state] cannot clean ui_type=" .. tostring(ui_type) .. ", requesting restart")
  write_restart_signal("cannot_clean_" .. tostring(ui_type or "unknown"))
  state.restart_count = state.restart_count + 1
  state.client_ui_dirty = false
  state.known_open_ui = nil
  return true, "restart_signaled"
end

function ui.restore_state_via_rc()
  minetest.log("action", "[ui_state] restoring state directly on server")
  local ok, msg = restore_player_state(state.observer_pos, "site_birch_ford")
  if ok then
    state.restored_count = state.restored_count + 1
  end
  minetest.log("action", "[ui_state] state restore result: " .. tostring(ok) .. " " .. tostring(msg))
  return ok, msg
end

function ui.get_restart_signal()
  local f = io.open(worldpath .. "/awbot_client.signal", "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if content and content ~= "" then
    local ok, data = pcall(minetest.parse_json, content)
    if ok and data then
      return data
    end
  end
  return nil
end

function ui.clear_restart_signal()
  local f = io.open(worldpath .. "/awbot_client.signal", "w")
  if f then
    f:write("")
    f:close()
  end
end

function ui.get_report()
  return {
    client_ui_dirty = state.client_ui_dirty,
    known_open_ui = state.known_open_ui,
    screenshot_kind = state.screenshot_kind,
    cleanup_count = state.cleanup_count,
    restart_count = state.restart_count,
    restored_count = state.restored_count,
    observer_pos = state.observer_pos,
    player_name = state.player_name,
  }
end

function ui.reset()
  state.client_ui_dirty = false
  state.known_open_ui = nil
  state.screenshot_kind = nil
  state.cleanup_count = 0
  state.restart_count = 0
  state.restored_count = 0
end

-- Known hostile mob entity names (Mineclonia monsters)
local HOSTILE_MOBS = {
  ["mobs_mc:zombie"] = true, ["mobs_mc:baby_zombie"] = true,
  ["mobs_mc:husk"] = true, ["mobs_mc:baby_husk"] = true,
  ["mobs_mc:drowned"] = true, ["mobs_mc:baby_drowned"] = true,
  ["mobs_mc:skeleton"] = true, ["mobs_mc:stray"] = true,
  ["mobs_mc:witherskeleton"] = true,
  ["mobs_mc:creeper"] = true, ["mobs_mc:creeper_charged"] = true,
  ["mobs_mc:spider"] = true, ["mobs_mc:cave_spider"] = true,
  ["mobs_mc:enderman"] = true, ["mobs_mc:endermite"] = true,
  ["mobs_mc:silverfish"] = true,
  ["mobs_mc:witch"] = true,
  ["mobs_mc:ghast"] = true, ["mobs_mc:blaze"] = true,
  ["mobs_mc:guardian"] = true, ["mobs_mc:guardian_elder"] = true,
  ["mobs_mc:slime_big"] = true, ["mobs_mc:slime_small"] = true, ["mobs_mc:slime_tiny"] = true,
  ["mobs_mc:magma_cube_big"] = true, ["mobs_mc:magma_cube_small"] = true, ["mobs_mc:magma_cube_tiny"] = true,
  ["mobs_mc:vex"] = true, ["mobs_mc:shulker"] = true,
  ["mobs_mc:piglin"] = true, ["mobs_mc:piglin_brute"] = true,
  ["mobs_mc:zombified_piglin"] = true,
  ["mobs_mc:hoglin"] = true, ["mobs_mc:zoglin"] = true,
  ["mobs_mc:baby_hoglin"] = true, ["mobs_mc:baby_zoglin"] = true,
  ["mobs_mc:pillager"] = true, ["mobs_mc:vindicator"] = true,
  ["mobs_mc:evoker"] = true, ["mobs_mc:illusioner"] = true,
  ["mobs_mc:ravager"] = true,
  ["mobs_mc:villager_zombie"] = true,
  ["mobs_mc:wither"] = true, ["mobs_mc:enderdragon"] = true,
  ["mobs_mc:killer_bunny"] = true,
}

local TARGET_SITE = {
  site_id = "site_birch_ford",
  site_pos = {x = 320, y = 8, z = -180},
}

local function is_node_liquid(node_name)
  local def = minetest.registered_nodes[node_name]
  if not def then return false end
  return def.liquidtype and def.liquidtype ~= "none"
end

local function is_node_water(node_name)
  return minetest.get_item_group(node_name, "water") > 0
end

local function is_node_lava(node_name)
  return minetest.get_item_group(node_name, "lava") > 0
end

local function is_safe_block(pos)
  local node = minetest.get_node(pos)
  if not node then return false end
  local def = minetest.registered_nodes[node.name]
  if not def then return false end
  if def.walkable == false then return false end
  if def.liquidtype and def.liquidtype ~= "none" then return false end
  if def.groups and (def.groups.dangerous or def.groups.magma) then return false end
  return true
end

local function emerge_pos(pos)
  -- Trigger chunk loading at a position
  local node = minetest.get_node(pos)
  if node.name == "ignore" then
    minetest.emerge_area(pos, pos)
  end
end

-- Find the surface Y level at a given XZ position (top-down scan).
-- Returns a safe standing position (one block above the surface).
local function find_surface_level(x, z, top_y, search_range)
  top_y = top_y or 120
  search_range = search_range or 120
  local check = {x = x, y = top_y, z = z}
  -- Trigger chunk loading first
  emerge_pos({x = x, y = top_y, z = z})
  emerge_pos({x = x, y = 0, z = z})
  for _ = 0, search_range do
    local node = minetest.get_node(check)
    -- If node is ignore, chunk might not be loaded yet; trigger emerge
    if node.name == "ignore" then
      emerge_pos(check)
      check.y = check.y - 1
    else
      local def = minetest.registered_nodes[node.name]
      if def and def.walkable == false then
        local below = minetest.get_node({x = check.x, y = check.y - 1, z = check.z})
        if below.name ~= "ignore" then
          local def_below = minetest.registered_nodes[below.name]
          if def_below and def_below.walkable ~= false and not (def_below.liquidtype and def_below.liquidtype ~= "none") then
            return {x = check.x, y = check.y, z = check.z}
          end
        end
      elseif def and def.liquidtype and def.liquidtype ~= "none" then
        -- Liquid: skip, continue down
      end
      check.y = check.y - 1
    end
  end
  return nil
end

local function find_ground_level(above_pos)
  -- First try: find the surface top at the given XZ
  local surface = find_surface_level(above_pos.x, above_pos.z, 120, 120)
  if surface then return surface end
  -- Second try: scan upward from the given position
  local check = {x = above_pos.x, y = above_pos.y, z = above_pos.z}
  emerge_pos({x = above_pos.x, y = above_pos.y, z = above_pos.z})
  for dy = 0, 40 do
    check.y = above_pos.y + dy
    local node = minetest.get_node(check)
    if node.name ~= "ignore" and node.name == "air" then
      local below = {x = check.x, y = check.y - 1, z = check.z}
      local node_below = minetest.get_node(below)
      if node_below.name ~= "ignore" and is_safe_block(below) then
        return {x = check.x, y = check.y, z = check.z}
      end
    end
  end
  return nil
end

local function find_safe_spot_near(target_pos, radius)
  local scan_radius = radius or 8
  -- First, try the exact target XZ
  local exact = find_surface_level(target_pos.x, target_pos.z)
  if exact then
    local water_near = false
    for wx = -1, 1 do
      for wz = -1, 1 do
        if is_node_water(minetest.get_node({x = exact.x + wx, y = exact.y, z = exact.z + wz}).name) then water_near = true end
        if is_node_water(minetest.get_node({x = exact.x + wx, y = exact.y + 1, z = exact.z + wz}).name) then water_near = true end
      end
    end
    if not water_near then
      return exact
    end
  end

  -- Scan in a spiral outward
  for r = 2, scan_radius, 1 do
    for dx = -r, r do
      for dz = -r, r do
        if math.abs(dx) == r or math.abs(dz) == r then
          local found = find_surface_level(target_pos.x + dx, target_pos.z + dz)
          if found then
            local water_near = false
            for wx = -1, 1 do
              for wz = -1, 1 do
                if is_node_water(minetest.get_node({x = found.x + wx, y = found.y, z = found.z + wz}).name) then water_near = true end
                if is_node_water(minetest.get_node({x = found.x + wx, y = found.y + 1, z = found.z + wz}).name) then water_near = true end
              end
            end
            if not water_near then
              return found
            end
          end
        end
      end
    end
  end
  return nil
end

function ui.prepare_for_screenshot(target_site_id)
  target_site_id = target_site_id or TARGET_SITE.site_id
  local player = minetest.get_player_by_name(state.player_name)
  if not player then
    return {error = "player_offline"}
  end

  -- Close any open formspec first
  minetest.close_formspec(state.player_name, "")
  state.client_ui_dirty = false
  state.known_open_ui = nil

  local pos = vector.round(player:get_pos())
  local head_node = minetest.get_node(pos)
  local feet_node = minetest.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
  local below_node = minetest.get_node({x = pos.x, y = pos.y - 2, z = pos.z})

  local hp = player:get_hp()
  local breath = player:get_breath() or 0

  -- Count hostile mobs nearby
  local hostile_count = 0
  local objs = minetest.get_objects_inside_radius(pos, 16)
  for _, obj in ipairs(objs) do
    local entity = obj:get_luaentity()
    if entity and entity.name and HOSTILE_MOBS[entity.name] then
      hostile_count = hostile_count + 1
    end
  end

  local in_liquid = is_node_liquid(head_node.name)
  local in_water = is_node_water(head_node.name)
  local feet_solid = feet_node.name ~= "air" and (minetest.registered_nodes[feet_node.name] or {}).walkable ~= false
  local below_solid = below_node.name ~= "air" and (minetest.registered_nodes[below_node.name] or {}).walkable ~= false
  local grounded = feet_solid or below_solid

  local needs_teleport = false
  local teleport_reason = ""

  if in_liquid or not grounded then
    needs_teleport = true
    teleport_reason = in_liquid and "in_liquid" or "not_grounded"
  elseif hp < 10 then
    needs_teleport = true
    teleport_reason = "low_hp"
  elseif hostile_count > 0 then
    needs_teleport = true
    teleport_reason = hostile_count .. "_hostile_mobs"
  end

  -- Known safe positions near spawn (always loaded)
  local KNOWN_SAFE = {
    {x = 0, y = 4, z = 0},    -- center spawn platform
    {x = 0, y = 4, z = 1},
    {x = 1, y = 4, z = 0},
    {x = 0, y = 4, z = -1},
    {x = -1, y = 4, z = 0},
    {x = 5, y = 4, z = 0},
    {x = 0, y = 4, z = 5},
  }

  local safe_pos
  local current_safe = grounded and not in_liquid and hp >= 10 and hostile_count == 0
  if current_safe then
    safe_pos = pos
    minetest.log("action", "[ui_state] current position is safe, staying at (" .. pos.x .. "," .. pos.y .. "," .. pos.z .. ")")
  else
    -- Teleport to spawn position (always safe, chunk loads on arrival)
    safe_pos = {x = 0, y = 4, z = 0}
    minetest.log("action", "[ui_state] teleporting to spawn (" .. safe_pos.x .. "," .. safe_pos.y .. "," .. safe_pos.z .. ")")
    minetest.log("action", "[ui_state] safe_pos = (" .. safe_pos.x .. "," .. safe_pos.y .. "," .. safe_pos.z .. ")")
  end

  if needs_teleport then

    minetest.log("action", "[ui_state] teleporting to safe pos (" .. safe_pos.x .. "," .. safe_pos.y .. "," .. safe_pos.z .. ") reason=" .. teleport_reason)
    local restore_ok, restore_msg = restore_player_state(safe_pos, target_site_id)
    if not restore_ok then
      minetest.log("error", "[ui_state] restore failed: " .. tostring(restore_msg))
      return {error = restore_msg}
    end
  else
    local restore_ok, restore_msg = restore_player_state(safe_pos, target_site_id)
    if not restore_ok then
      minetest.log("error", "[ui_state] restore failed: " .. tostring(restore_msg))
      return {error = restore_msg}
    end
  end

  -- Re-capture state after any teleport/heal
  pos = vector.round(player:get_pos())
  head_node = minetest.get_node(pos)
  feet_node = minetest.get_node({x = pos.x, y = pos.y - 1, z = pos.z})
  below_node = minetest.get_node({x = pos.x, y = pos.y - 2, z = pos.z})
  hp = player:get_hp()
  breath = player:get_breath() or 0
  in_liquid = is_node_liquid(head_node.name)
  feet_solid = feet_node.name ~= "air" and (minetest.registered_nodes[feet_node.name] or {}).walkable ~= false
  below_solid = below_node.name ~= "air" and (minetest.registered_nodes[below_node.name] or {}).walkable ~= false
  grounded = feet_solid or below_solid

  -- Re-check hostile mobs at current position
  hostile_count = 0
  objs = minetest.get_objects_inside_radius(pos, 16)
  for _, obj in ipairs(objs) do
    local entity = obj:get_luaentity()
    if entity and entity.name and HOSTILE_MOBS[entity.name] then
      hostile_count = hostile_count + 1
    end
  end

  -- Collect target info
  local target_pos = nil
  local site_data = nil
  if aliveworld and aliveworld.sites then
    site_data = aliveworld.sites.get and aliveworld.sites.get(target_site_id)
    if not site_data then
      local all_sites = aliveworld.sites.list and aliveworld.sites.list()
      if all_sites then
        for _, s in ipairs(all_sites) do
          if s.id == target_site_id then site_data = s end
        end
      end
    end
    if site_data then
      target_pos = site_data.pos
    end
  end
  if not target_pos and TARGET_SITE.site_id == target_site_id then
    target_pos = TARGET_SITE.site_pos
  end

  local distance_to_target = nil
  if target_pos and safe_pos then
    local dx = target_pos.x - safe_pos.x
    local dz = target_pos.z - safe_pos.z
    distance_to_target = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
  end

  -- Collect GPS/track state
  local gps_enabled = false
  local tracks = {}
  local radar_result = nil
  local radar_points = {}
  local radar_points_count = nil
  if aliveworld_player then
    if aliveworld_player.radar then
      gps_enabled = aliveworld_player.radar.is_enabled and aliveworld_player.radar.is_enabled(state.player_name) or false
      if aliveworld_player.radar.get_points_for_player then
        radar_result = aliveworld_player.radar.get_points_for_player(state.player_name)
        if not radar_result or type(radar_result) ~= "table" then
          return {error = "radar_points_api_invalid_result"}
        end
        radar_points = radar_result.points or {}
        radar_points_count = radar_result.count or #radar_points
      else
        return {error = "radar_points_api_missing"}
      end
    else
      return {error = "radar_not_loaded"}
    end
    if aliveworld_player.tracking then
      tracks = aliveworld_player.tracking.list and aliveworld_player.tracking.list(state.player_name) or {}
    end
  else
    return {error = "aliveworld_player_not_loaded"}
  end

  local tracking_hud_id = nil
  local active_tracks_count = #tracks
  if #tracks > 0 then
    tracking_hud_id = tracks[1].tracking_hud_id
  end

  local visual_expectation = {"clean_world", "hud", "radar"}
  if active_tracks_count > 0 then
    table.insert(visual_expectation, "tracked_target")
  end

  local result = {
    player_pos = {x = math.floor(pos.x), y = math.floor(pos.y), z = math.floor(pos.z)},
    target_site = target_site_id,
    target_pos = target_pos and {x = target_pos.x, y = target_pos.y, z = target_pos.z} or nil,
    distance_to_target = distance_to_target,
    in_liquid = in_liquid,
    on_ground = grounded,
    hp = hp,
    breath = breath,
    hostile_mobs_nearby = hostile_count,
    gps_enabled = gps_enabled,
    active_tracks_count = active_tracks_count,
    tracking_hud_id = tracking_hud_id,
    -- Compatibility alias for older screenshot metadata consumers. This value is
    -- the text tracking HUD id, not a removed 3D waypoint HUD id.
    waypoint_hud_id = tracking_hud_id,
    radar_points_count = radar_points_count,
    radar_points = radar_points,
    visual_expectation = visual_expectation,
    needs_teleport = needs_teleport,
    teleport_reason = teleport_reason,
  }

  -- Write state file for host script
  local json_str = minetest.write_json(result)
  if not json_str then
    minetest.log("error", "[ui_state] failed to serialize pre-shot result to JSON")
  else
    local f = io.open(worldpath .. "/awbot_pre_shot.json", "w")
    if f then
      f:write(json_str)
      f:close()
      minetest.log("action", "[ui_state] pre-shot state written to awbot_pre_shot.json (" .. tostring(#json_str) .. " bytes)")
    else
      minetest.log("error", "[ui_state] cannot write awbot_pre_shot.json")
    end
  end

  return result
end

minetest.log("action", "[aliveworld_test_suite] ui_state module loaded")
return ui
