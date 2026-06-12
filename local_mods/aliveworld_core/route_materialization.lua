-- route_materialization.lua
-- Budgeted physical materialization for planned AliveWorld road routes.

local storage = minetest.get_mod_storage()
local STORAGE_KEY = "aliveworld_route_materialization"

local states = {}
local timer = 0

local MATERIALIZER_VERSION = 1
local DEFAULTS = {
  centerline_step = 2,
  road_width = 3,
  shoulder_width = 1,
  corridor_radius = 4,
  max_cut = 4,
  max_fill = 7,
  points_per_step = 8,
  sample_radius = 2,
  search_y_margin = 16,
}

aliveworld.routes.materialization = aliveworld.routes.materialization or {}
local materialization = aliveworld.routes.materialization

local function copy_table(src)
  local dst = {}
  for k, v in pairs(src or {}) do
    if type(v) == "table" then
      dst[k] = copy_table(v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function save_all()
  storage:set_string(STORAGE_KEY, minetest.write_json(states))
end

local function load_all()
  local raw = storage:get_string(STORAGE_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and type(data) == "table" then
      states = data
    end
  end
end

local function now_string()
  return os.date("!%Y-%m-%dT%H:%M:%SZ")
end

local function pos_copy(pos)
  return {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
end

local function distance2d(a, b)
  local dx = (a.x or 0) - (b.x or 0)
  local dz = (a.z or 0) - (b.z or 0)
  return math.sqrt(dx * dx + dz * dz)
end

local function merge_settings(opts)
  local settings = copy_table(DEFAULTS)
  for k, v in pairs(opts or {}) do
    if settings[k] ~= nil then
      settings[k] = v
    end
  end
  return settings
end

local function first_registered(candidates)
  for _, name in ipairs(candidates) do
    if minetest.registered_nodes[name] then
      return name
    end
  end
  return nil
end

function materialization.palette()
  return {
    surface = first_registered({"mcl_core:coarse_dirt", "mcl_core:dirt"}),
    shoulder = first_registered({"mcl_core:dirt_with_grass", "mcl_core:dirt"}),
    fill = first_registered({"mcl_core:dirt", "mcl_core:coarse_dirt"}),
    base = first_registered({"mcl_core:dirt", "mcl_core:stone"}),
  }
end

local function validate_palette()
  local palette = materialization.palette()
  for key, node_name in pairs(palette) do
    if not node_name or not minetest.registered_nodes[node_name] then
      return false, {error = "road_palette_node_missing", field = key, node = node_name}
    end
  end
  return true, palette
end

local function has_metadata(pos)
  local meta = minetest.get_meta(pos):to_table()
  for _, _ in pairs(meta.fields or {}) do
    return true
  end
  for _, list in pairs(meta.inventory or {}) do
    if type(list) == "table" then
      for _, stack in ipairs(list) do
        if stack and stack ~= "" then return true end
      end
    end
  end
  return false
end

local function is_liquid(name)
  local def = minetest.registered_nodes[name]
  return def and def.liquidtype and def.liquidtype ~= "none"
end

local function is_safe_clearable(name)
  if name == "air" or name == "ignore" then return true end
  local def = minetest.registered_nodes[name]
  if not def then return false end
  if def.walkable == false then return true end
  if minetest.get_item_group(name, "tree") > 0 then return true end
  if def.drawtype == "plantlike" or def.drawtype == "plantlike_rooted" then return true end
  if minetest.get_item_group(name, "flora") > 0 then return true end
  if minetest.get_item_group(name, "flower") > 0 then return true end
  if minetest.get_item_group(name, "grass") > 0 then return true end
  if minetest.get_item_group(name, "plant") > 0 then return true end
  if minetest.get_item_group(name, "leaves") > 0 then return true end
  if minetest.get_item_group(name, "leafdecay") > 0 then return true end
  if minetest.get_item_group(name, "snow") > 0 then return true end
  if name:find("azalea", 1, true) or name:find("sapling", 1, true) or name:find("bush", 1, true) then return true end
  if name == "mcl_core:snow" then return true end
  return false
end

local function is_natural_ground(name)
  if name == "air" or name == "ignore" then return false end
  if is_liquid(name) then return false end
  if minetest.get_item_group(name, "tree") > 0 then return false end
  if minetest.get_item_group(name, "wood") > 0 then return false end
  if minetest.get_item_group(name, "choppy") > 0 and minetest.get_item_group(name, "tree") == 0 then return false end
  if minetest.get_item_group(name, "container") > 0 then return false end
  if name:find("chest", 1, true) or name:find("door", 1, true) or name:find("fence", 1, true) then return false end
  if name == "mcl_core:diamondblock" or name == "mcl_core:goldblock" or name == "mcl_core:ironblock" then return false end
  if minetest.get_item_group(name, "dirt") > 0 then return true end
  if minetest.get_item_group(name, "soil") > 0 then return true end
  if minetest.get_item_group(name, "sand") > 0 then return true end
  if minetest.get_item_group(name, "crumbly") > 0 then return true end
  if minetest.get_item_group(name, "stone") > 0 or minetest.get_item_group(name, "material_stone") > 0 then return true end
  return name == "mcl_core:dirt_with_grass"
    or name == "mcl_core:dirt"
    or name == "mcl_core:coarse_dirt"
    or name == "mcl_core:gravel"
    or name == "mcl_core:stone"
    or name == "mcl_core:sand"
end

local function local_surface_at(pos, settings)
  local margin = settings.search_y_margin or DEFAULTS.search_y_margin
  local min_y = settings.min_y or math.floor((pos.y or 0) - margin)
  local max_y = settings.max_y or math.floor((pos.y or 0) + margin)
  local saw_ignore = false
  local best_liquid = nil
  for y = max_y, min_y, -1 do
    local node = minetest.get_node({x = pos.x, y = y, z = pos.z})
    if node.name == "ignore" then
      saw_ignore = true
    elseif is_liquid(node.name) then
      best_liquid = best_liquid or {
        ok = true,
        pos = {x = pos.x, y = y + 1, z = pos.z},
        surface_node = node.name,
        flags = {water = true, liquid = true},
      }
    elseif is_natural_ground(node.name) then
      if best_liquid then
        return best_liquid, nil
      end
      local stand = minetest.get_node({x = pos.x, y = y + 1, z = pos.z})
      local head = minetest.get_node({x = pos.x, y = y + 2, z = pos.z})
      local flags = {}
      if stand.name == "ignore" or head.name == "ignore" then
        flags.area_not_loaded = true
      end
      if stand.name ~= "air" or head.name ~= "air" then
        flags.blocked = true
      end
      if minetest.get_item_group(stand.name, "tree") > 0 or minetest.get_item_group(head.name, "tree") > 0
        or minetest.get_item_group(stand.name, "leaves") > 0 or minetest.get_item_group(head.name, "leaves") > 0 then
        flags.tree = true
      end
      return {
        ok = not flags.area_not_loaded,
        pos = {x = pos.x, y = y + 1, z = pos.z},
        surface_node = node.name,
        stand_node = stand.name,
        head_node = head.name,
        flags = flags,
      }, flags.area_not_loaded and "area_not_loaded" or nil
    end
  end
  if best_liquid then return best_liquid, nil end
  return nil, saw_ignore and "area_not_loaded" or "no_surface"
end

local function add_warning(state, warning)
  state.warnings = state.warnings or {}
  if #state.warnings < 40 then
    table.insert(state.warnings, warning)
  end
end

local function add_unresolved(state, item)
  state.unresolved = state.unresolved or {}
  if #state.unresolved < 80 then
    table.insert(state.unresolved, item)
  end
end

local function choose_surface_node(palette, lane)
  if lane == "shoulder" then
    return palette.shoulder
  end
  return palette.surface
end

local function sample_surface(pos, settings)
  if not aliveworld.terrain or not aliveworld.terrain.route_sample then
    return nil, "terrain_api_missing"
  end
  local margin = settings.search_y_margin or DEFAULTS.search_y_margin
  local min_y = settings.min_y or math.floor((pos.y or 0) - margin)
  local max_y = settings.max_y or math.floor((pos.y or 0) + margin)
  local sample = aliveworld.terrain.route_sample(pos, {
    profile = "generic",
    sample_radius = settings.sample_radius,
    sample_step = 2,
    min_y = min_y,
    max_y = max_y,
  })
  if not sample then
    return local_surface_at(pos, settings)
  end
  if not sample.ok and (not sample.surface_node or (sample.flags and sample.flags.area_not_loaded)) then
    local fallback, fallback_reason = local_surface_at(pos, settings)
    if fallback then
      return fallback, fallback_reason
    end
    return sample, sample and sample.rejections and sample.rejections[1] or "no_surface"
  end
  return sample, nil
end

function materialization.build_dense_centerline(route, opts)
  if not route or not route.points or #route.points < 2 then
    return false, {error = "route_points_missing"}
  end
  local settings = merge_settings(opts)
  local dense = {}
  local unresolved = {}
  local last_key = nil
  for i = 1, #route.points - 1 do
    local a = route.points[i].pos
    local b = route.points[i + 1].pos
    local dist = math.max(1, distance2d(a, b))
    local steps = math.max(1, math.ceil(dist / settings.centerline_step))
    for s = 0, steps do
      local t = s / steps
      local x = math.floor(a.x + (b.x - a.x) * t + 0.5)
      local z = math.floor(a.z + (b.z - a.z) * t + 0.5)
      local key = x .. ":" .. z
      if key ~= last_key then
        local sample, reason = sample_surface({x = x, y = a.y + (b.y - a.y) * t, z = z}, settings)
        if not sample or not sample.surface_node then
          table.insert(unresolved, {index = #dense + 1, x = x, z = z, reason = reason or "surface_unavailable"})
        else
          table.insert(dense, {
            pos = pos_copy(sample.pos),
            surface_node = sample.surface_node,
            flags = copy_table(sample.flags or {}),
            route_segment = i,
          })
        end
        last_key = key
      end
    end
  end
  for i, point in ipairs(dense) do
    local prev = dense[math.max(1, i - 1)].pos
    local nxt = dense[math.min(#dense, i + 1)].pos
    local dx = nxt.x - prev.x
    local dz = nxt.z - prev.z
    local len = math.sqrt(dx * dx + dz * dz)
    if len == 0 then
      point.dir = {x = 1, z = 0}
      point.perp = {x = 0, z = 1}
    else
      point.dir = {x = dx / len, z = dz / len}
      point.perp = {x = -dz / len, z = dx / len}
    end
  end
  return true, {points = dense, unresolved = unresolved, settings = settings}
end

local function new_state(route_id, status, settings)
  return {
    route_id = route_id,
    materializer_version = MATERIALIZER_VERSION,
    status = status or "planned",
    started_at = nil,
    completed_at = nil,
    processed_segments = 0,
    processed_nodes = 0,
    road_width = settings.road_width,
    shoulder_width = settings.shoulder_width,
    dense_points_count = 0,
    changed_nodes = 0,
    cleared_nodes = 0,
    filled_nodes = 0,
    cut_nodes = 0,
    skipped_protected = 0,
    skipped_blocked = 0,
    water_segments = 0,
    warnings = {},
    unresolved = {},
    globalsteps = 0,
    max_step_ms = 0,
    checkpoint = {dense_index = 1},
    settings = copy_table(settings),
  }
end

local function would_change(pos, target)
  local current = minetest.get_node(pos)
  return current.name ~= target
end

local function check_can_touch(pos, actor, state)
  local node = minetest.get_node(pos)
  if node.name == "ignore" then
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(pos), reason = "area_not_loaded"})
    return false, node
  end
  if minetest.is_protected(pos, actor or "") then
    state.skipped_protected = state.skipped_protected + 1
    add_unresolved(state, {pos = pos_copy(pos), reason = "protected"})
    return false, node
  end
  if has_metadata(pos) then
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(pos), reason = "metadata"})
    return false, node
  end
  return true, node
end

local function set_node_counted(pos, node_name, state, dry_run)
  if would_change(pos, node_name) then
    state.changed_nodes = state.changed_nodes + 1
    if not dry_run then
      minetest.set_node(pos, {name = node_name})
    end
  end
end

local function clear_node_counted(pos, state, dry_run)
  local node = minetest.get_node(pos)
  if node.name ~= "air" then
    state.changed_nodes = state.changed_nodes + 1
    state.cleared_nodes = state.cleared_nodes + 1
    if not dry_run then
      minetest.set_node(pos, {name = "air"})
    end
  end
end

local function process_cell(route, state, dense_point, offset, lane, palette, dry_run, actor)
  local px = math.floor(dense_point.pos.x + dense_point.perp.x * offset + 0.5)
  local pz = math.floor(dense_point.pos.z + dense_point.perp.z * offset + 0.5)
  local desired_stand_y = dense_point.pos.y
  local desired_road_y = desired_stand_y - 1
  local cell_pos = {x = px, y = desired_stand_y, z = pz}
  local road_pos = {x = px, y = desired_road_y, z = pz}

  if not aliveworld.claims or not aliveworld.claims.contains_pos(route.claim_id or ("route:" .. route.route_id), cell_pos, 0.25) then
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(cell_pos), reason = "outside_route_claim"})
    return
  end

  local sample, reason = sample_surface(cell_pos, state.settings)
  local actual_road_y = desired_road_y
  if sample and sample.surface_node then
    if (sample.flags and (sample.flags.water or sample.flags.liquid)) or is_liquid(sample.surface_node or "") then
      state.water_segments = state.water_segments + 1
      add_unresolved(state, {pos = pos_copy(sample.pos), reason = "unexpected_water"})
      return
    end
    actual_road_y = sample.pos.y - 1
  elseif reason ~= "blocked" then
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(cell_pos), reason = reason or "surface_unavailable"})
    return
  end

  local delta = actual_road_y - desired_road_y
  if delta > state.settings.max_cut then
    if lane == "shoulder" then
      add_warning(state, {pos = pos_copy(sample and sample.pos or cell_pos), reason = "shoulder_cut_skipped", delta = delta})
      return
    end
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(sample.pos), reason = "cut_too_deep", delta = delta, lane = lane})
    return
  end
  if -delta > state.settings.max_fill then
    if lane == "shoulder" then
      add_warning(state, {pos = pos_copy(sample and sample.pos or cell_pos), reason = "shoulder_fill_skipped", delta = delta})
      return
    end
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(sample.pos), reason = "fill_too_high", delta = delta, lane = lane})
    return
  end

  local target_surface = choose_surface_node(palette, lane)
  local ok_touch, road_node = check_can_touch(road_pos, actor, state)
  if not ok_touch then return end
  if is_liquid(road_node.name) then
    state.water_segments = state.water_segments + 1
    add_unresolved(state, {pos = pos_copy(road_pos), reason = "unexpected_water"})
    return
  end
  if road_node.name ~= "air" and not is_natural_ground(road_node.name) and not is_safe_clearable(road_node.name) then
    state.skipped_blocked = state.skipped_blocked + 1
    add_unresolved(state, {pos = pos_copy(road_pos), reason = "unknown_solid", node = road_node.name})
    return
  end

  if delta < 0 then
    for y = actual_road_y + 1, desired_road_y do
      local fill_pos = {x = px, y = y, z = pz}
      local ok_fill, fill_node = check_can_touch(fill_pos, actor, state)
      if not ok_fill then return end
      if fill_node.name ~= "air" and not is_safe_clearable(fill_node.name) and not is_natural_ground(fill_node.name) then
        state.skipped_blocked = state.skipped_blocked + 1
        add_unresolved(state, {pos = pos_copy(fill_pos), reason = "fill_blocked", node = fill_node.name})
        return
      end
      state.filled_nodes = state.filled_nodes + 1
      set_node_counted(fill_pos, palette.fill, state, dry_run)
    end
  elseif delta > 0 then
    for y = desired_road_y + 1, actual_road_y do
      local cut_pos = {x = px, y = y, z = pz}
      local ok_cut, cut_node = check_can_touch(cut_pos, actor, state)
      if not ok_cut then return end
      if not is_natural_ground(cut_node.name) and not is_safe_clearable(cut_node.name) then
        state.skipped_blocked = state.skipped_blocked + 1
        add_unresolved(state, {pos = pos_copy(cut_pos), reason = "cut_blocked", node = cut_node.name})
        return
      end
      state.cut_nodes = state.cut_nodes + 1
      clear_node_counted(cut_pos, state, dry_run)
    end
  end

  set_node_counted(road_pos, target_surface, state, dry_run)

  for y = desired_road_y + 1, desired_road_y + 2 do
    local clear_pos = {x = px, y = y, z = pz}
    local ok_clear, clear_node = check_can_touch(clear_pos, actor, state)
    if not ok_clear then return end
    if clear_node.name ~= "air" then
      if is_liquid(clear_node.name) then
        state.water_segments = state.water_segments + 1
        add_unresolved(state, {pos = pos_copy(clear_pos), reason = "unexpected_water", node = clear_node.name, lane = lane})
        return
      elseif is_safe_clearable(clear_node.name) then
        clear_node_counted(clear_pos, state, dry_run)
      elseif is_natural_ground(clear_node.name) then
        state.cut_nodes = state.cut_nodes + 1
        clear_node_counted(clear_pos, state, dry_run)
      else
        state.skipped_blocked = state.skipped_blocked + 1
        add_unresolved(state, {pos = pos_copy(clear_pos), reason = "headspace_blocked", node = clear_node.name})
        return
      end
    end
  end
end

local function analyze_route(route, opts, dry_run)
  local settings = merge_settings(opts)
  local ok_palette, palette_or_error = validate_palette()
  if not ok_palette then return false, palette_or_error end
  local ok_dense, dense_or_error = materialization.build_dense_centerline(route, settings)
  if not ok_dense then return false, dense_or_error end
  local state = new_state(route.route_id, "planned", settings)
  state.dry_run = dry_run == true
  state.dense_points_count = #(dense_or_error.points or {})
  state.dense_points = copy_table(dense_or_error.points or {})
  for _, item in ipairs(dense_or_error.unresolved or {}) do
    add_unresolved(state, item)
  end
  local half_main = math.floor(settings.road_width / 2)
  local half_total = half_main + settings.shoulder_width
  for _, point in ipairs(state.dense_points) do
    for offset = -half_total, half_total do
      local lane = math.abs(offset) <= half_main and "road" or "shoulder"
      process_cell(route, state, point, offset, lane, palette_or_error, true, opts and opts.actor or "")
    end
  end
  state.palette = palette_or_error
  state.completed_at = now_string()
  return true, state
end

function materialization.dry_run(route_id, opts)
  local route = aliveworld.routes.get(route_id)
  if not route then
    return false, {error = "route_not_found", route_id = route_id}
  end
  if route.status ~= "planned" and route.status ~= "materialized" then
    return false, {error = "route_not_planned", route_id = route_id, status = route.status}
  end
  return analyze_route(route, opts or {}, true)
end

local function mark_old_road_site_materialized(route, state)
  if route.route_id ~= "old_road" or not aliveworld.sites then return end
  local site = aliveworld.sites.get("old_road")
  if not site then return end
  site.data = site.data or {}
  site.data.route_id = route.route_id
  site.data.materialized_route_id = route.route_id
  site.data.route_materializer_version = MATERIALIZER_VERSION
  if route.points and #route.points > 0 and not site.data.representative_route_pos then
    site.data.representative_route_pos = pos_copy(route.points[math.floor(#route.points / 2 + 0.5)].pos)
  end
  site.physical_status = "materialized"
  aliveworld.sites.save(site)
end

function materialization.start(route_id, opts)
  opts = opts or {}
  local existing = states[route_id]
  if existing and existing.status == "materialized" and not opts.force then
    local route = aliveworld.routes.get(route_id)
    if route and route.status ~= "materialized" then
      aliveworld.routes.update(route_id, {
        status = "materialized",
        materialization_status = "materialized",
        materializer_version = existing.materializer_version or MATERIALIZER_VERSION,
        materialized_at = existing.completed_at,
      })
      route.status = "materialized"
      mark_old_road_site_materialized(route, existing)
    end
    return true, copy_table(existing)
  end
  if existing and existing.status == "materializing" and not opts.force then
    return true, copy_table(existing)
  end
  local route = aliveworld.routes.get(route_id)
  if not route then
    return false, {error = "route_not_found", route_id = route_id}
  end
  if route.status ~= "planned" then
    return false, {error = "route_not_planned", route_id = route_id, status = route.status}
  end
  local valid, valid_result = aliveworld.routes.validate_route(route)
  if not valid then
    return false, valid_result
  end
  local ok, report = analyze_route(route, opts, true)
  if not ok then
    return false, report
  end
  if #(report.unresolved or {}) > 0 or (report.water_segments or 0) > 0 then
    report.status = "failed"
    report.started_at = now_string()
    report.completed_at = now_string()
    report.last_error = "dry_run_unresolved"
    states[route_id] = report
    save_all()
    return false, {error = "dry_run_unresolved", route_id = route_id, unresolved = #(report.unresolved or {}), water_segments = report.water_segments or 0}
  end
  report.status = "materializing"
  report.started_at = now_string()
  report.completed_at = nil
  report.changed_nodes = 0
  report.cleared_nodes = 0
  report.filled_nodes = 0
  report.cut_nodes = 0
  report.skipped_protected = 0
  report.skipped_blocked = 0
  report.water_segments = 0
  report.warnings = {}
  report.unresolved = {}
  report.checkpoint = {dense_index = 1}
  report.actor = opts.actor or ""
  states[route_id] = report
  save_all()
  return true, copy_table(report)
end

local function finish_state(route, state)
  if #(state.unresolved or {}) > 0 or (state.water_segments or 0) > 0 then
    state.status = "failed"
    state.last_error = "materialization_unresolved"
    state.completed_at = now_string()
    save_all()
    return
  end
  state.status = "materialized"
  state.completed_at = now_string()
  aliveworld.routes.update(route.route_id, {
    status = "materialized",
    materialization_status = "materialized",
    materializer_version = MATERIALIZER_VERSION,
    materialized_at = state.completed_at,
  })
  mark_old_road_site_materialized(route, state)
  aliveworld.add_event("route_materialized",
    string.format("Route materialized: %s nodes=%d changed=%d", route.route_id, state.processed_nodes or 0, state.changed_nodes or 0),
    {route_id = route.route_id, changed_nodes = state.changed_nodes or 0}
  )
  save_all()
end

local function process_state(route_id, budget)
  local state = states[route_id]
  if not state or state.status ~= "materializing" then return end
  local route = aliveworld.routes.get(route_id)
  if not route then
    state.status = "failed"
    state.last_error = "route_not_found"
    state.completed_at = now_string()
    save_all()
    return
  end
  local ok_palette, palette = validate_palette()
  if not ok_palette then
    state.status = "failed"
    state.last_error = palette.error
    state.completed_at = now_string()
    save_all()
    return
  end
  local started = minetest.get_us_time()
  local settings = state.settings or DEFAULTS
  local half_main = math.floor((settings.road_width or 3) / 2)
  local half_total = half_main + (settings.shoulder_width or 1)
  local points = state.dense_points or {}
  local max_points = budget or settings.points_per_step or DEFAULTS.points_per_step
  local done = 0
  local i = state.checkpoint and state.checkpoint.dense_index or 1
  while i <= #points and done < max_points do
    local point = points[i]
    for offset = -half_total, half_total do
      local lane = math.abs(offset) <= half_main and "road" or "shoulder"
      process_cell(route, state, point, offset, lane, palette, false, state.actor or "")
      state.processed_nodes = state.processed_nodes + 1
    end
    state.processed_segments = math.max(state.processed_segments or 0, point.route_segment or 0)
    i = i + 1
    done = done + 1
  end
  state.checkpoint = {dense_index = i}
  state.globalsteps = (state.globalsteps or 0) + 1
  local elapsed_ms = math.floor((minetest.get_us_time() - started) / 1000)
  state.max_step_ms = math.max(state.max_step_ms or 0, elapsed_ms)
  if i > #points then
    finish_state(route, state)
  else
    save_all()
  end
end

function materialization.process_jobs(budget)
  for route_id, state in pairs(states) do
    if state.status == "materializing" then
      process_state(route_id, budget)
    end
  end
end

function materialization.status(route_id)
  local state = states[route_id]
  return state and copy_table(state) or nil
end

function materialization.cancel(route_id, reason)
  local state = states[route_id]
  if not state then
    return false, {error = "materialization_not_found", route_id = route_id}
  end
  if state.status ~= "materializing" then
    return false, {error = "materialization_not_running", route_id = route_id, status = state.status}
  end
  state.status = "failed"
  state.last_error = reason or "cancelled"
  state.completed_at = now_string()
  save_all()
  return true, copy_table(state)
end

function materialization.reset(route_id)
  states[route_id] = nil
  save_all()
end

local function reconcile_materialized_states()
  for route_id, state in pairs(states) do
    if state.status == "materialized" then
      local route = aliveworld.routes.get(route_id)
      if route and route.status ~= "materialized" then
        aliveworld.routes.update(route_id, {
          status = "materialized",
          materialization_status = "materialized",
          materializer_version = state.materializer_version or MATERIALIZER_VERSION,
          materialized_at = state.completed_at,
        })
        route.status = "materialized"
        mark_old_road_site_materialized(route, state)
      end
    end
  end
end

minetest.register_globalstep(function(dtime)
  timer = timer + dtime
  if timer < 0.2 then return end
  timer = 0
  materialization.process_jobs()
end)

load_all()
reconcile_materialized_states()

minetest.log("action", "[aliveworld_core] route materialization module loaded")
