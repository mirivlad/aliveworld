-- route_materialization.lua
-- Budgeted physical materialization for planned AliveWorld road routes.
-- Uses job_runner for time-sliced execution with phase profiling.

local storage = minetest.get_mod_storage()
local STORAGE_KEY = "aliveworld_route_materialization"

local states = {}
local verify_jobs = {}

local MATERIALIZER_VERSION = 2
local DEFAULTS = {
  centerline_step = 2,
  road_width = 3,
  shoulder_width = 1,
  corridor_radius = 4,
  max_cut = 4,
  max_fill = 7,
  points_per_step = 2,
  max_ops_per_step = 10,
  sample_radius = 2,
  search_y_margin = 16,
  target_budget_ms = 25,
  hard_warn_threshold_ms = 50,
  persist_interval_steps = 5,
}

aliveworld.routes.materialization = aliveworld.routes.materialization or {}
local materialization = aliveworld.routes.materialization

local runner = aliveworld.job_runner

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

local function classify_node(name)
  if name == "air" or name == "ignore" then return "empty" end
  local def = minetest.registered_nodes[name]
  if not def then return "unknown" end
  if def.walkable == false then
    if def.drawtype == "plantlike" or def.drawtype == "plantlike_rooted" then return "vegetation" end
    if minetest.get_item_group(name, "grass") > 0 then return "vegetation" end
    if minetest.get_item_group(name, "flower") > 0 then return "vegetation" end
    if minetest.get_item_group(name, "flora") > 0 then return "vegetation" end
    if minetest.get_item_group(name, "plant") > 0 then return "vegetation" end
    if minetest.get_item_group(name, "snow") > 0 then return "snow" end
    if name:find("azalea", 1, true) or name:find("sapling", 1, true) then return "vegetation" end
    if name:find("bush", 1, true) then return "vegetation" end
    if minetest.get_item_group(name, "leaves") > 0 or minetest.get_item_group(name, "leafdecay") > 0 then return "leaves" end
    return "non_solid_other"
  end
  if minetest.get_item_group(name, "tree") > 0 then return "trunk" end
  if minetest.get_item_group(name, "wood") > 0 then return "trunk" end
  if is_liquid(name) then return "liquid" end
  if minetest.get_item_group(name, "dirt") > 0 then return "natural_ground" end
  if minetest.get_item_group(name, "soil") > 0 then return "natural_ground" end
  if minetest.get_item_group(name, "sand") > 0 then return "natural_ground" end
  if minetest.get_item_group(name, "crumbly") > 0 then return "natural_ground" end
  if minetest.get_item_group(name, "stone") > 0 or minetest.get_item_group(name, "material_stone") > 0 then return "natural_ground" end
  return "solid_other"
end

local function is_safe_clearable(name)
  return classify_node(name) ~= "solid_other" and classify_node(name) ~= "natural_ground" and classify_node(name) ~= "liquid" and name ~= "air" and name ~= "ignore"
end

local function is_natural_ground(name)
  local c = classify_node(name)
  return c == "natural_ground"
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

local function cached_surface(cache, x, z, pos_y, settings)
  local key = tostring(x) .. ":" .. tostring(z)
  if cache[key] then return cache[key] end
  local result, reason = local_surface_at({x = x, y = pos_y or 0, z = z}, settings)
  if result then
    cache[key] = result
  end
  return result, reason
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
    vegetation_removed = 0,
    leaves_removed = 0,
    trunks_removed = 0,
    snow_removed = 0,
    filled_nodes = 0,
    cut_nodes = 0,
    skipped_protected = 0,
    skipped_blocked = 0,
    unknown_blocked = 0,
    metadata_protected = 0,
    other_replaced = 0,
    water_segments = 0,
    warnings = {},
    unresolved = {},
    globalsteps = 0,
    max_step_ms = 0,
    checkpoint = {dense_index = 1, phase = "emerge"},
    settings = copy_table(settings),
    surface_cache = {},
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
    state.metadata_protected = state.metadata_protected + 1
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

local function classify_and_clear(pos, state, dry_run)
  local node = minetest.get_node(pos)
  if node.name == "air" then return end
  state.changed_nodes = state.changed_nodes + 1
  local cat = classify_node(node.name)
  if cat == "vegetation" then state.vegetation_removed = state.vegetation_removed + 1
  elseif cat == "leaves" then state.leaves_removed = state.leaves_removed + 1
  elseif cat == "trunk" then state.trunks_removed = state.trunks_removed + 1
  elseif cat == "snow" then state.snow_removed = state.snow_removed + 1
  elseif cat == "unknown" or cat == "solid_other" then
    state.unknown_blocked = state.unknown_blocked + 1
    add_unresolved(state, {pos = pos_copy(pos), reason = "clear_unknown", node = node.name})
    return
  else
    state.other_replaced = state.other_replaced + 1
  end
  if not dry_run then
    minetest.set_node(pos, {name = "air"})
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

  local sample, reason = cached_surface(state.surface_cache, px, pz, desired_stand_y, state.settings)
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
    state.unknown_blocked = state.unknown_blocked + 1
    add_unresolved(state, {pos = pos_copy(road_pos), reason = "unknown_solid", node = road_node.name})
    return
  end

  if delta < 0 then
    for y = actual_road_y + 1, desired_road_y do
      local fill_pos = {x = px, y = y, z = pz}
      local ok_fill, fill_node = check_can_touch(fill_pos, actor, state)
      if not ok_fill then return end
      if fill_node.name ~= "air" and not is_safe_clearable(fill_node.name) and not is_natural_ground(fill_node.name) then
        state.unknown_blocked = state.unknown_blocked + 1
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
        state.unknown_blocked = state.unknown_blocked + 1
        add_unresolved(state, {pos = pos_copy(cut_pos), reason = "cut_blocked", node = cut_node.name})
        return
      end
      state.cut_nodes = state.cut_nodes + 1
      if cut_node.name ~= "air" then
        local cat = classify_node(cut_node.name)
        if cat == "vegetation" then state.vegetation_removed = state.vegetation_removed + 1
        elseif cat == "leaves" then state.leaves_removed = state.leaves_removed + 1
        elseif cat == "trunk" then state.trunks_removed = state.trunks_removed + 1
        elseif cat == "snow" then state.snow_removed = state.snow_removed + 1
        elseif cat == "empty" then
        else state.other_replaced = state.other_replaced + 1 end
        state.changed_nodes = state.changed_nodes + 1
        if not dry_run then
          minetest.set_node(cut_pos, {name = "air"})
        end
      end
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
        classify_and_clear(clear_pos, state, dry_run)
      elseif is_natural_ground(clear_node.name) then
        state.cut_nodes = state.cut_nodes + 1
        state.changed_nodes = state.changed_nodes + 1
        if not dry_run then
          minetest.set_node(clear_pos, {name = "air"})
        end
      else
        state.unknown_blocked = state.unknown_blocked + 1
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
  report.vegetation_removed = 0
  report.leaves_removed = 0
  report.trunks_removed = 0
  report.snow_removed = 0
  report.filled_nodes = 0
  report.cut_nodes = 0
  report.skipped_protected = 0
  report.skipped_blocked = 0
  report.unknown_blocked = 0
  report.metadata_protected = 0
  report.other_replaced = 0
  report.water_segments = 0
  report.warnings = {}
  report.unresolved = {}
  report.checkpoint = {dense_index = 1, phase = "emerge"}
  report.actor = opts.actor or ""
  report.surface_cache = {}
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

local function process_state_job(job)
  local state = states[job.id]
  if not state or state.status ~= "materializing" then return {status = "done"} end
  local route = aliveworld.routes.get(job.id)
  if not route then
    state.status = "failed"
    state.last_error = "route_not_found"
    state.completed_at = now_string()
    save_all()
    return {status = "failed", error = "route_not_found"}
  end
  local ok_palette, palette = validate_palette()
  if not ok_palette then
    state.status = "failed"
    state.last_error = palette.error
    state.completed_at = now_string()
    save_all()
    return {status = "failed", error = palette.error}
  end

  local step_us = minetest.get_us_time()
  local settings = state.settings or DEFAULTS
  local half_main = math.floor((settings.road_width or 3) / 2)
  local half_total = half_main + (settings.shoulder_width or 1)
  local points = state.dense_points or {}
  local i = state.checkpoint and state.checkpoint.dense_index or 1
  local budget_ms = job.config.target_budget_ms or DEFAULTS.target_budget_ms
  local max_ops = job.config.max_ops_per_step or DEFAULTS.max_ops_per_step
  local ops_done = 0

  while i <= #points and ops_done < max_ops do
    local point = points[i]
    local phase_start = minetest.get_us_time()

    for offset = -half_total, half_total do
      local px = math.floor(point.pos.x + point.perp.x * offset + 0.5)
      local pz = math.floor(point.pos.z + point.perp.z * offset + 0.5)
      local cache_key = tostring(px) .. ":" .. tostring(pz)

      if not state.surface_cache[cache_key] then
        local scan_pos = {x = px, y = point.pos.y, z = pz}
        local margin = settings.search_y_margin or DEFAULTS.search_y_margin
        local min_y = settings.min_y or math.floor((scan_pos.y or 0) - margin)
        local max_y = settings.max_y or math.floor((scan_pos.y or 0) + margin)
        minetest.emerge_area(
          {x = px, y = min_y, z = pz},
          {x = px, y = max_y, z = pz}
        )
        if minetest.load_area then
          pcall(minetest.load_area,
            {x = px, y = min_y, z = pz},
            {x = px, y = max_y, z = pz}
          )
        end
        local surf, _ = local_surface_at(scan_pos, settings)
        if surf then state.surface_cache[cache_key] = surf end
      end

      local lane = math.abs(offset) <= half_main and "road" or "shoulder"
      process_cell(route, state, point, offset, lane, palette, false, state.actor or "")
      state.processed_nodes = state.processed_nodes + 1
      ops_done = ops_done + 1
    end

    state.processed_segments = math.max(state.processed_segments or 0, point.route_segment or 0)
    i = i + 1
    state.checkpoint = {dense_index = i, phase = "mutate"}
    state.globalsteps = (state.globalsteps or 0) + 1

    local elapsed_ms = math.floor((minetest.get_us_time() - step_us) / 1000)
    if elapsed_ms >= budget_ms and i <= #points then
      save_all()
      return {status = "yield", phase = "mutate", ops = ops_done}
    end
  end

  local total_elapsed_ms = math.floor((minetest.get_us_time() - step_us) / 1000)
  state.max_step_ms = math.max(state.max_step_ms or 0, total_elapsed_ms)

  if i > #points then
    finish_state(route, state)
    return {status = "done", phase = "done", elapsed_ms = total_elapsed_ms}
  end

  save_all()
  return {status = "yield", phase = "mutate", ops = ops_done, elapsed_ms = total_elapsed_ms}
end

function materialization.process_jobs(budget)
  for route_id, state in pairs(states) do
    if state.status == "materializing" then
      local existing = runner.get(route_id)
      if existing then
        if budget then
          existing.config.max_ops_per_step = budget
        end
      else
        local pps = state.settings and state.settings.points_per_step or DEFAULTS.points_per_step
        local cfg = {
          target_budget_ms = state.settings and state.settings.target_budget_ms or DEFAULTS.target_budget_ms,
          hard_warn_threshold_ms = state.settings and state.settings.hard_warn_threshold_ms or DEFAULTS.hard_warn_threshold_ms,
          max_ops_per_step = budget or (state.settings and state.settings.max_ops_per_step) or pps,
          persist_interval_steps = state.settings and state.settings.persist_interval_steps or DEFAULTS.persist_interval_steps,
        }
        runner.create(route_id, cfg, {on_step = process_state_job})
      end
    end
  end
  runner.process_jobs()
end

function materialization.status(route_id)
  local state = states[route_id]
  if not state then return nil end
  local result = copy_table(state)
  result.surface_cache = nil
  result.dense_points = nil
  local rj = runner.get(route_id)
  if rj then
    result.job_metrics = runner.job_status(route_id)
  end
  return result
end

function materialization.cancel(route_id, reason)
  local state = states[route_id]
  if not state then
    return false, {error = "materialization_not_found", route_id = route_id}
  end
  if state.status ~= "materializing" then
    return false, {error = "materialization_not_running", route_id = route_id, status = state.status}
  end
  runner.cancel(route_id, reason or "cancelled")
  state.status = "failed"
  state.last_error = reason or "cancelled"
  state.completed_at = now_string()
  save_all()
  return true, copy_table(state)
end

function materialization.reset(route_id)
  runner.remove(route_id)
  states[route_id] = nil
  save_all()
end

function materialization.reset_all()
  for id, _ in pairs(states) do
    runner.remove(id)
  end
  states = {}
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

-- Emerge a bounding box and poll until blocks are actually loaded (non-ignore).
-- Returns true if loaded, false if timed out after ~5 seconds.
local function ensure_area_loaded(minp, maxp)
  minetest.emerge_area(minp, maxp)
  local deadline = minetest.get_us_time() + 5000000
  local samples = {
    {x = minp.x, y = minp.y, z = minp.z},
    {x = maxp.x, y = minp.y, z = minp.z},
    {x = math.floor((minp.x + maxp.x) / 2), y = minp.y, z = minp.z},
  }
  while minetest.get_us_time() < deadline do
    if minetest.load_area then
      pcall(minetest.load_area, minp, maxp)
    end
    local all_loaded = true
    for _, pos in ipairs(samples) do
      if minetest.get_node(pos).name == "ignore" then
        all_loaded = false
        break
      end
    end
    if all_loaded then return true end
  end
  return false
end

materialization.ensure_area_loaded = ensure_area_loaded

-- Verify mode: check a materialized route without changing anything.
-- Returns a report with coverage, palette, gaps, water, corridor checks.
function materialization.verify(route_id, opts)
  opts = opts or {}
  local route = aliveworld.routes.get(route_id)
  if not route then
    return false, {error = "route_not_found", route_id = route_id}
  end
  local state = states[route_id]
  if not state or state.status ~= "materialized" then
    return false, {error = "route_not_materialized", route_id = route_id, status = state and state.status or "no_state"}
  end
  local palette = state.palette or materialization.palette()
  local settings = state.settings or DEFAULTS
  local half_main = math.floor((settings.road_width or 3) / 2)
  local half_total = half_main + (settings.shoulder_width or 1)

  local verify = {
    route_id = route_id,
    status = "completed",
    dense_points_count = state.dense_points_count,
    total_checks = 0,
    gaps = 0,
    palette_mismatch = 0,
    unexpected_water = 0,
    outside_corridor = 0,
    missing_surface = 0,
    mismatch_details = {
      by_lane = {road = 0, shoulder = 0},
      by_expected = {},
      by_actual = {},
      samples = {},
    },
  }

  local dense = state.dense_points
  if not dense then
    local ok, dr = materialization.build_dense_centerline(route, settings)
    if not ok then return false, dr end
    dense = dr.points
  end
  for _, point in ipairs(dense) do
    for offset = -half_total, half_total do
      local px = math.floor(point.pos.x + point.perp.x * offset + 0.5)
      local pz = math.floor(point.pos.z + point.perp.z * offset + 0.5)
      local lane = math.abs(offset) <= half_main and "road" or "shoulder"
      local expected = choose_surface_node(palette, lane)
      local base_y = point.pos.y - 1

      ensure_area_loaded({x = px, y = base_y - 2, z = pz}, {x = px, y = base_y + 4, z = pz})

      verify.total_checks = verify.total_checks + 1
      local found = false
      local is_water = false

      for dy = -2, 3 do
        local check_pos = {x = px, y = base_y + dy, z = pz}
        local node = minetest.get_node(check_pos)
        if node.name == "ignore" then
          break
        end
        if node.name == expected then
          found = true
          break
        end
        if is_liquid(node.name) then
          is_water = true
        end
      end

      if not found then
        if is_water then
          verify.unexpected_water = verify.unexpected_water + 1
        else
          verify.palette_mismatch = verify.palette_mismatch + 1
          verify.mismatch_details.by_lane[lane] = (verify.mismatch_details.by_lane[lane] or 0) + 1
          verify.mismatch_details.by_expected[expected] = (verify.mismatch_details.by_expected[expected] or 0) + 1
          local actual_node = minetest.get_node({x = px, y = base_y, z = pz})
          verify.mismatch_details.by_actual[actual_node.name] = (verify.mismatch_details.by_actual[actual_node.name] or 0) + 1
          if #verify.mismatch_details.samples < 50 then
            table.insert(verify.mismatch_details.samples, {
              pos = {x = px, y = base_y, z = pz},
              lane = lane,
              expected = expected,
              actual = actual_node.name,
            })
          end
        end
      end

      if aliveworld.claims and route.claim_id then
        local road_check = {x = px, y = base_y, z = pz}
        if not aliveworld.claims.contains_pos(route.claim_id, road_check, 0.25) then
          verify.outside_corridor = verify.outside_corridor + 1
        end
      end
    end
  end
  return true, verify
end

-- Verify using job_runner for budgeted execution
local function start_verify_job(route_id, opts)
  local existing = runner.get("verify:" .. route_id)
  if existing then return false, "verify_already_running" end
  local cfg = {
    target_budget_ms = (opts and opts.target_budget_ms) or 25,
    max_ops_per_step = (opts and opts.max_points_per_step) or 2,
    persist_interval_steps = 0,
  }
  local verify_data = {
    route_id = route_id,
    status = "running",
    dense_index = 1,
    gaps = 0,
    palette_mismatch = 0,
    unexpected_water = 0,
    outside_corridor = 0,
    missing_surface = 0,
    total_checks = 0,
    surface_cache = {},
    metrics = {},
    mismatch_details = {
      by_lane = {road = 0, shoulder = 0},
      by_expected = {},
      by_actual = {},
      samples = {},
    },
  }
  verify_jobs[route_id] = verify_data
  local ok, _ = runner.create("verify:" .. route_id, cfg, {
    on_step = function(job)
      local route = aliveworld.routes.get(route_id)
      if not route then return {status = "failed", error = "route_not_found"} end
      local state = states[route_id]
      if not state then return {status = "failed", error = "state_not_found"} end
      local palette = state.palette or materialization.palette()
      local settings = state.settings or DEFAULTS
      local half_main = math.floor((settings.road_width or 3) / 2)
      local half_total = half_main + (settings.shoulder_width or 1)
      local dense = state.dense_points
      if not dense then
        local ok, dr = materialization.build_dense_centerline(route, settings)
        if not ok then return {status = "failed", error = dr.error} end
        dense = dr.points
      end

      local step_us = minetest.get_us_time()
      local i = verify_data.dense_index
      local budget_ms = cfg.target_budget_ms
      local max_ops = cfg.max_ops_per_step
      local ops = 0

      while i <= #dense and ops < max_ops do
        local point = dense[i]
        for offset = -half_total, half_total do
          local px = math.floor(point.pos.x + point.perp.x * offset + 0.5)
          local pz = math.floor(point.pos.z + point.perp.z * offset + 0.5)
          local lane = math.abs(offset) <= half_main and "road" or "shoulder"
          local road_y = point.pos.y - 1
          local road_pos = {x = px, y = road_y, z = pz}
          local expected = choose_surface_node(palette, lane)

          ensure_area_loaded({x = px, y = road_y - 1, z = pz}, {x = px, y = road_y + 3, z = pz})

          verify_data.total_checks = verify_data.total_checks + 1
          local road_node = minetest.get_node(road_pos)

          if road_node.name == "ignore" then
            verify_data.missing_surface = verify_data.missing_surface + 1
          elseif road_node.name ~= expected then
            if is_liquid(road_node.name) then
              verify_data.unexpected_water = verify_data.unexpected_water + 1
            else
              verify_data.palette_mismatch = verify_data.palette_mismatch + 1
              verify_data.mismatch_details.by_lane[lane] = (verify_data.mismatch_details.by_lane[lane] or 0) + 1
              verify_data.mismatch_details.by_expected[expected] = (verify_data.mismatch_details.by_expected[expected] or 0) + 1
              verify_data.mismatch_details.by_actual[road_node.name] = (verify_data.mismatch_details.by_actual[road_node.name] or 0) + 1
              if #verify_data.mismatch_details.samples < 50 then
                table.insert(verify_data.mismatch_details.samples, {
                  pos = {x = px, y = road_y, z = pz},
                  lane = lane,
                  expected = expected,
                  actual = road_node.name,
                })
              end
            end
          end

          if aliveworld.claims and route.claim_id then
            if not aliveworld.claims.contains_pos(route.claim_id, road_pos, 0.25) then
              verify_data.outside_corridor = verify_data.outside_corridor + 1
            end
          end

          ops = ops + 1
        end
        i = i + 1
        verify_data.dense_index = i
        verify_data.metrics = runner.job_status("verify:" .. route_id)

        local elapsed_ms = math.floor((minetest.get_us_time() - step_us) / 1000)
        if elapsed_ms >= budget_ms and i <= #dense then
          return {status = "yield", phase = "verify", ops = ops}
        end
      end

      if i > #dense then
        verify_data.status = "completed"
        runner.remove("verify:" .. route_id)
        return {status = "done", phase = "verify_complete"}
      end
      return {status = "yield", phase = "verify", ops = ops}
    end,
    on_cleanup = function()
      verify_data.status = "completed"
      verify_jobs[route_id] = nil
    end,
  })
  if not ok then
    verify_jobs[route_id] = nil
    return false, "create_failed"
  end
  return true, verify_data
end

function materialization.verify_async(route_id, opts)
  return start_verify_job(route_id, opts)
end

function materialization.verify_status(route_id)
  local vd = runner.get("verify:" .. route_id)
  if not vd then
    local data = verify_jobs[route_id]
    if data then
      return {
        status = "completed",
        total_checks = data.total_checks,
        palette_mismatch = data.palette_mismatch,
        unexpected_water = data.unexpected_water,
        outside_corridor = data.outside_corridor,
        missing_surface = data.missing_surface,
        mismatch_details = data.mismatch_details,
      }
    end
    local state = states[route_id]
    if not state then return nil end
    return {status = "not_running"}
  end
  local metrics = runner.job_status("verify:" .. route_id)
  local data = verify_jobs[route_id]
  return {
    status = "running",
    metrics = metrics,
    total_checks = data and data.total_checks or 0,
    palette_mismatch = data and data.palette_mismatch or 0,
    unexpected_water = data and data.unexpected_water or 0,
    outside_corridor = data and data.outside_corridor or 0,
    missing_surface = data and data.missing_surface or 0,
    mismatch_details = data and data.mismatch_details or {},
  }
end

minetest.register_globalstep(function(dtime)
  materialization.process_jobs()
end)

load_all()
reconcile_materialized_states()

minetest.log("action", "[aliveworld_core] route materialization module loaded (v" .. MATERIALIZER_VERSION .. ")")
