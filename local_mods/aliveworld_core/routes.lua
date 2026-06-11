-- routes.lua
-- Persistent terrain-aware route planning for AliveWorld.

local storage = minetest.get_mod_storage()
local ROUTES_KEY = "aliveworld_routes"

local routes = {}
local route_jobs = {}
local route_job_timer = 0

aliveworld.routes = {}

local PLANNER_VERSION = 1
local DEFAULT_SETTINGS = {
  cell_size = 16,
  corridor_radius = 4,
  max_extra_margin = 240,
  max_nodes = 9000,
  nodes_per_step = 80,
  sample_radius = 8,
  min_y = -64,
  max_y = 160,
  waypoint_spacing = 48,
}

local ROUTE_DEFS = {
  old_road = {
    route_id = "old_road",
    kind = "road",
    from_site = "birch_ford",
    to_site = "stone_gully",
  },
}

local NEIGHBORS = {
  {x = 1, z = 0, name = "E"},
  {x = 1, z = 1, name = "SE"},
  {x = 0, z = 1, name = "S"},
  {x = -1, z = 1, name = "SW"},
  {x = -1, z = 0, name = "W"},
  {x = -1, z = -1, name = "NW"},
  {x = 0, z = -1, name = "N"},
  {x = 1, z = -1, name = "NE"},
}

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

local function merge_settings(opts)
  local settings = copy_table(DEFAULT_SETTINGS)
  for k, v in pairs(opts or {}) do
    if settings[k] ~= nil then
      settings[k] = v
    end
  end
  return settings
end

local function save_all()
  storage:set_string(ROUTES_KEY, minetest.write_json(routes))
end

local function load_all()
  local raw = storage:get_string(ROUTES_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data then
      routes = data
    end
  end
end

local function current_day()
  return (aliveworld.get_day and aliveworld.get_day()) or nil
end

local function pos_copy(pos)
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function distance2d(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return math.sqrt(dx * dx + dz * dz)
end

local function distance3d(a, b)
  local dx = a.x - b.x
  local dy = (a.y or 0) - (b.y or 0)
  local dz = a.z - b.z
  return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function resolve_site(site_id)
  if not aliveworld.sites then
    return nil
  end
  return aliveworld.sites.get(site_id)
end

local function endpoint_anchor(site)
  if not site then return nil, "endpoint_not_found" end
  local phys = site.physical_status or "abstract"
  if not site.anchor_pos or not (phys == "anchored" or phys == "materialized") then
    return nil, "endpoint_not_anchored"
  end
  return site.anchor_pos
end

local function route_def(route_id, opts)
  opts = opts or {}
  local def = copy_table(ROUTE_DEFS[route_id])
  if not def and (opts.from_site_id or opts.to_site_id) then
    def = {route_id = opts.route_id or route_id, kind = opts.kind or "road"}
  end
  if not def then
    return nil
  end
  def.route_id = opts.route_id or def.route_id or route_id
  def.kind = opts.kind or def.kind or "road"
  def.from_site = opts.from_site_id or opts.from_site or def.from_site
  def.to_site = opts.to_site_id or opts.to_site or def.to_site
  return def
end

local function validate_endpoints(def)
  if not def or not def.from_site or not def.to_site then
    return false, {error = "route_not_found", route_id = def and def.route_id or nil}
  end
  local from_site = resolve_site(def.from_site)
  if not from_site then
    return false, {error = "endpoint_not_found", route_id = def.route_id, endpoint = "from", site_id = def.from_site}
  end
  local to_site = resolve_site(def.to_site)
  if not to_site then
    return false, {error = "endpoint_not_found", route_id = def.route_id, endpoint = "to", site_id = def.to_site}
  end
  local from_anchor, from_err = endpoint_anchor(from_site)
  if not from_anchor then
    return false, {error = from_err, route_id = def.route_id, endpoint = "from", site_id = from_site.id}
  end
  local to_anchor, to_err = endpoint_anchor(to_site)
  if not to_anchor then
    return false, {error = to_err, route_id = def.route_id, endpoint = "to", site_id = to_site.id}
  end
  return true, {
    from_site = from_site,
    to_site = to_site,
    from_anchor = from_anchor,
    to_anchor = to_anchor,
  }
end

local function route_claim(route)
  local points = {}
  for _, point in ipairs(route.points or {}) do
    table.insert(points, pos_copy(point.pos))
  end
  return {
    claim_id = "route:" .. route.route_id,
    owner_type = "route",
    owner_id = route.route_id,
    kind = "route_corridor",
    priority = 80,
    radius = route.corridor_radius or DEFAULT_SETTINGS.corridor_radius,
    points = points,
    persistent = true,
  }
end

local function route_bbox(points)
  local box = nil
  for _, point in ipairs(points or {}) do
    local p = point.pos or point
    if not box then
      box = {min = pos_copy(p), max = pos_copy(p)}
    else
      box.min.x = math.min(box.min.x, p.x)
      box.min.y = math.min(box.min.y, p.y)
      box.min.z = math.min(box.min.z, p.z)
      box.max.x = math.max(box.max.x, p.x)
      box.max.y = math.max(box.max.y, p.y)
      box.max.z = math.max(box.max.z, p.z)
    end
  end
  return box
end

local function summarize_points(raw_points, settings)
  local points = {}
  local length = 0
  local elevation_gain = 0
  local elevation_loss = 0
  local max_grade = 0
  local grade_sum = 0
  local grade_count = 0
  local crossings = {}
  local active_crossing = nil

  for i, raw in ipairs(raw_points) do
    if i > 1 then
      local prev = raw_points[i - 1]
      local seg_len = distance3d(prev.pos, raw.pos)
      local horiz = math.max(1, distance2d(prev.pos, raw.pos))
      local dy = (raw.pos.y or 0) - (prev.pos.y or 0)
      local grade = math.abs(dy) / horiz
      length = length + seg_len
      if dy > 0 then elevation_gain = elevation_gain + dy end
      if dy < 0 then elevation_loss = elevation_loss + math.abs(dy) end
      max_grade = math.max(max_grade, grade)
      grade_sum = grade_sum + grade
      grade_count = grade_count + 1
    end

    local flags = copy_table(raw.flags or {})
    local is_water = flags.water or flags.liquid or (raw.water_ratio or 0) > 0.35
    if is_water and not active_crossing then
      active_crossing = {kind = "water", from_index = i, to_index = i, width = 0, requires_bridge = false}
    elseif is_water and active_crossing then
      active_crossing.to_index = i
    elseif (not is_water) and active_crossing then
      local from_pos = raw_points[active_crossing.from_index].pos
      local to_pos = raw_points[active_crossing.to_index].pos
      active_crossing.width = math.floor(distance2d(from_pos, to_pos) + settings.cell_size + 0.5)
      active_crossing.requires_bridge = active_crossing.width > settings.cell_size
      table.insert(crossings, active_crossing)
      active_crossing = nil
    end

    table.insert(points, {
      pos = pos_copy(raw.pos),
      surface_node = raw.surface_node,
      cumulative_cost = raw.cumulative_cost or 0,
      flags = flags,
    })
  end
  if active_crossing then
    local from_pos = raw_points[active_crossing.from_index].pos
    local to_pos = raw_points[active_crossing.to_index].pos
    active_crossing.width = math.floor(distance2d(from_pos, to_pos) + settings.cell_size + 0.5)
    active_crossing.requires_bridge = active_crossing.width > settings.cell_size
    table.insert(crossings, active_crossing)
  end

  return {
    points = points,
    length = math.floor(length + 0.5),
    elevation_gain = math.floor(elevation_gain + 0.5),
    elevation_loss = math.floor(elevation_loss + 0.5),
    max_grade = math.floor(max_grade * 1000 + 0.5) / 1000,
    average_grade = grade_count > 0 and math.floor((grade_sum / grade_count) * 1000 + 0.5) / 1000 or 0,
    crossings = crossings,
    bbox = route_bbox(points),
  }
end

local function reduce_points(path, settings)
  if #path <= 2 then return path end
  local reduced = {path[1]}
  local last_dir = nil
  local last_kept = path[1]
  for i = 2, #path - 1 do
    local prev = path[i - 1]
    local cur = path[i]
    local nxt = path[i + 1]
    local dir = tostring((nxt.grid_x or 0) - (cur.grid_x or 0)) .. ":" .. tostring((nxt.grid_z or 0) - (cur.grid_z or 0))
    local water_change = ((cur.flags or {}).water or false) ~= ((nxt.flags or {}).water or false)
    local far = distance2d(last_kept.pos, cur.pos) >= (settings.waypoint_spacing or 48)
    local grade_change = math.abs((nxt.pos.y or 0) - (prev.pos.y or 0)) >= 3
    if dir ~= last_dir or water_change or far or grade_change then
      table.insert(reduced, cur)
      last_kept = cur
      last_dir = dir
    end
  end
  table.insert(reduced, path[#path])
  return reduced
end

local function make_straight_route(def, endpoint, opts, planning)
  local settings = merge_settings(opts)
  local raw_points = {}
  local from = endpoint.from_anchor
  local to = endpoint.to_anchor
  local dist = distance2d(from, to)
  local count = math.max(2, math.floor(dist / settings.cell_size + 0.5) + 1)
  for i = 1, count do
    local t = (i - 1) / math.max(1, count - 1)
    local pos = {
      x = math.floor(from.x + (to.x - from.x) * t + 0.5),
      y = math.floor(from.y + (to.y - from.y) * t + 0.5),
      z = math.floor(from.z + (to.z - from.z) * t + 0.5),
    }
    table.insert(raw_points, {
      pos = pos,
      surface_node = "test:surface",
      cumulative_cost = (i - 1) * settings.cell_size,
      flags = {},
      water_ratio = 0,
    })
  end
  local summary = summarize_points(raw_points, settings)
  local route = {
    route_id = def.route_id,
    kind = def.kind or "road",
    from_site_id = endpoint.from_site.id,
    to_site_id = endpoint.to_site.id,
    from_logical_id = endpoint.from_site.settlement_id,
    to_logical_id = endpoint.to_site.settlement_id,
    status = "planned",
    planner_version = PLANNER_VERSION,
    world_seed = aliveworld.terrain and aliveworld.terrain.get_world_seed and aliveworld.terrain.get_world_seed() or "",
    cell_size = settings.cell_size,
    corridor_radius = settings.corridor_radius,
    points = summary.points,
    result_count = #summary.points,
    length = summary.length,
    elevation_gain = summary.elevation_gain,
    elevation_loss = summary.elevation_loss,
    max_grade = summary.max_grade,
    average_grade = summary.average_grade,
    crossings = summary.crossings,
    bbox = summary.bbox,
    planning = planning or {candidates_examined = #raw_points, nodes_expanded = #raw_points, elapsed_ms = 0, total_cost = summary.length},
    settings = settings,
    planned_day = current_day(),
    claim_id = "route:" .. def.route_id,
  }
  return true, route
end

local function sample_for_grid(job, gx, gz)
  local key = gx .. ":" .. gz
  if job.samples[key] then return job.samples[key] end
  local pos = {
    x = job.origin.x + gx * job.settings.cell_size,
    z = job.origin.z + gz * job.settings.cell_size,
  }
  local sample = aliveworld.terrain.route_sample(pos, {
    profile = "generic",
    sample_radius = job.settings.sample_radius,
    sample_step = 4,
    min_y = job.settings.min_y,
    max_y = job.settings.max_y,
  })
  sample.grid_x = gx
  sample.grid_z = gz
  job.samples[key] = sample
  job.candidates_examined = job.candidates_examined + 1
  return sample
end

local function heuristic(job, gx, gz)
  local dx = job.goal_gx - gx
  local dz = job.goal_gz - gz
  return math.sqrt(dx * dx + dz * dz) * job.settings.cell_size
end

local function pop_open(job)
  local best_i = nil
  local best = nil
  for i, node in ipairs(job.open) do
    if not best
      or node.f < best.f
      or (node.f == best.f and node.h < best.h)
      or (node.f == best.f and node.h == best.h and node.key < best.key) then
      best = node
      best_i = i
    end
  end
  if not best_i then return nil end
  table.remove(job.open, best_i)
  job.open_keys[best.key] = nil
  return best
end

local function push_or_update_open(job, node)
  if job.open_keys[node.key] then
    for _, existing in ipairs(job.open) do
      if existing.key == node.key then
        existing.g = node.g
        existing.h = node.h
        existing.f = node.f
        existing.gx = node.gx
        existing.gz = node.gz
        return
      end
    end
  end
  table.insert(job.open, node)
  job.open_keys[node.key] = true
end

local function reconstruct_path(job, key)
  local reversed = {}
  local cur = key
  while cur do
    local record = job.records[cur]
    table.insert(reversed, 1, record.sample)
    cur = record.parent
  end
  return reversed
end

local function finalize_route(job, found_key)
  local raw_path = reconstruct_path(job, found_key)
  raw_path[1].pos = pos_copy(job.endpoint.from_anchor)
  raw_path[#raw_path].pos = pos_copy(job.endpoint.to_anchor)
  local reduced = reduce_points(raw_path, job.settings)
  local summary = summarize_points(reduced, job.settings)
  local elapsed_ms = math.floor((minetest.get_us_time() - job.started_us) / 1000)
  return {
    route_id = job.def.route_id,
    kind = job.def.kind or "road",
    from_site_id = job.endpoint.from_site.id,
    to_site_id = job.endpoint.to_site.id,
    from_logical_id = job.endpoint.from_site.settlement_id,
    to_logical_id = job.endpoint.to_site.settlement_id,
    status = "planned",
    planner_version = PLANNER_VERSION,
    world_seed = aliveworld.terrain and aliveworld.terrain.get_world_seed and aliveworld.terrain.get_world_seed() or "",
    cell_size = job.settings.cell_size,
    corridor_radius = job.settings.corridor_radius,
    points = summary.points,
    result_count = #summary.points,
    length = summary.length,
    elevation_gain = summary.elevation_gain,
    elevation_loss = summary.elevation_loss,
    max_grade = summary.max_grade,
    average_grade = summary.average_grade,
    crossings = summary.crossings,
    bbox = summary.bbox,
    planning = {
      candidates_examined = job.candidates_examined,
      nodes_expanded = job.nodes_expanded,
      elapsed_ms = elapsed_ms,
      total_cost = job.records[found_key].g,
    },
    settings = job.settings,
    planned_day = current_day(),
    claim_id = "route:" .. job.def.route_id,
  }
end

local function make_job(def, endpoint, opts)
  local settings = merge_settings(opts)
  local dx = endpoint.to_anchor.x - endpoint.from_anchor.x
  local dz = endpoint.to_anchor.z - endpoint.from_anchor.z
  local goal_gx = math.floor(dx / settings.cell_size + (dx >= 0 and 0.5 or -0.5))
  local goal_gz = math.floor(dz / settings.cell_size + (dz >= 0 and 0.5 or -0.5))
  local direct_cells = math.max(math.abs(goal_gx), math.abs(goal_gz))
  local margin_cells = math.max(8, math.floor((settings.max_extra_margin or 240) / settings.cell_size))
  local start_sample = {
    ok = true,
    pos = pos_copy(endpoint.from_anchor),
    surface_node = endpoint.from_site.anchor_survey and endpoint.from_site.anchor_survey.surface_node or "unknown",
    flags = {},
    buildable_ratio = 1,
    solid_ratio = 1,
    water_ratio = 0,
    area_score = 1,
    grid_x = 0,
    grid_z = 0,
  }
  local start_key = "0:0"
  local h = math.sqrt(goal_gx * goal_gx + goal_gz * goal_gz) * settings.cell_size
  local job = {
    route_id = def.route_id,
    status = "running",
    def = def,
    endpoint = endpoint,
    settings = settings,
    origin = {x = endpoint.from_anchor.x, z = endpoint.from_anchor.z},
    goal_gx = goal_gx,
    goal_gz = goal_gz,
    max_abs_gx = math.abs(goal_gx) + margin_cells,
    max_abs_gz = math.abs(goal_gz) + margin_cells,
    max_cells = direct_cells + margin_cells * 2,
    samples = {[start_key] = start_sample},
    records = {[start_key] = {g = 0, h = h, f = h, parent = nil, sample = start_sample, direction = nil, water_run = 0}},
    open = {{key = start_key, gx = 0, gz = 0, g = 0, h = h, f = h}},
    open_keys = {[start_key] = true},
    closed = {},
    candidates_examined = 1,
    nodes_expanded = 0,
    started_us = minetest.get_us_time(),
  }
  return job
end

local function process_job(job, budget)
  budget = budget or job.settings.nodes_per_step or 80
  while budget > 0 do
    budget = budget - 1
    if #job.open == 0 then
      job.status = "failed"
      job.result = {error = "route_not_found", route_id = job.route_id, nodes_expanded = job.nodes_expanded}
      return false, job.result
    end
    if job.nodes_expanded >= (job.settings.max_nodes or 9000) then
      job.status = "failed"
      job.result = {error = "planning_timeout", route_id = job.route_id, nodes_expanded = job.nodes_expanded}
      return false, job.result
    end
    local current = pop_open(job)
    if current and not job.closed[current.key] then
      job.closed[current.key] = true
      job.nodes_expanded = job.nodes_expanded + 1
      if current.gx == job.goal_gx and current.gz == job.goal_gz then
        local route = finalize_route(job, current.key)
        job.status = "done"
        job.result = route
        return true, route
      end
      local current_record = job.records[current.key]
      for _, n in ipairs(NEIGHBORS) do
        local ngx = current.gx + n.x
        local ngz = current.gz + n.z
        if math.abs(ngx) <= job.max_abs_gx and math.abs(ngz) <= job.max_abs_gz then
          local nkey = ngx .. ":" .. ngz
          if not job.closed[nkey] then
            local sample = sample_for_grid(job, ngx, ngz)
            if sample.ok then
              local step_distance = math.sqrt(n.x * n.x + n.z * n.z) * job.settings.cell_size
              local water_run = ((sample.flags or {}).water or (sample.flags or {}).liquid) and ((current_record.water_run or 0) + 1) or 0
              local cost = aliveworld.terrain.route_step_cost(current_record.sample, sample, {
                step_distance = step_distance,
                previous_direction = current_record.direction,
                direction = n.name,
                water_run = water_run,
                max_grade = 1.1,
              })
              if cost.passable then
                local ng = current_record.g + cost.cost
                local old = job.records[nkey]
                if not old or ng < old.g or (ng == old.g and current.key < (old.parent or "")) then
                  local nh = heuristic(job, ngx, ngz)
                  sample.cumulative_cost = ng
                  job.records[nkey] = {
                    g = ng,
                    h = nh,
                    f = ng + nh,
                    parent = current.key,
                    sample = sample,
                    direction = n.name,
                    water_run = water_run,
                  }
                  push_or_update_open(job, {key = nkey, gx = ngx, gz = ngz, g = ng, h = nh, f = ng + nh})
                end
              end
            end
          end
        end
      end
    end
  end
  return nil, job
end

local function validate_and_save_route(route, opts)
  opts = opts or {}
  local claim = route_claim(route)
  local ok_claim, claim_result = aliveworld.claims.register(claim, {
    replace = opts.force_replan == true,
    allowed_owner_ids = {
      [route.from_site_id] = true,
      [route.to_site_id] = true,
    },
  })
  if not ok_claim then
    return false, claim_result
  end
  route.claim_id = claim.claim_id
  routes[route.route_id] = copy_table(route)
  save_all()
  return true, copy_table(route)
end

local function link_old_road_site(route)
  if route.route_id ~= "old_road" or not aliveworld.sites then return end
  local site = aliveworld.sites.get("old_road")
  if not site then return end
  site.data = site.data or {}
  site.data.route_id = route.route_id
  site.data.route_link_version = PLANNER_VERSION
  site.data.route_semantics = "logical_site_link"
  local mid = route.points and route.points[math.max(1, math.floor(#route.points / 2 + 0.5))]
  if mid and mid.pos then
    site.data.representative_route_pos = pos_copy(mid.pos)
  end
  aliveworld.sites.save(site)
end

function aliveworld.routes.get(route_id)
  local route = routes[route_id]
  return route and copy_table(route) or nil
end

function aliveworld.routes.delete(route_id)
  if routes[route_id] then
    routes[route_id] = nil
    save_all()
  end
  if aliveworld.claims then
    aliveworld.claims.delete("route:" .. route_id)
  end
  return true
end

function aliveworld.routes.list()
  local res = {}
  for _, route in pairs(routes) do
    table.insert(res, copy_table(route))
  end
  table.sort(res, function(a, b) return (a.route_id or "") < (b.route_id or "") end)
  return res
end

function aliveworld.routes.validate_route(route)
  if not route then return false, {error = "route_missing"} end
  local from_site = resolve_site(route.from_site_id)
  local to_site = resolve_site(route.to_site_id)
  if not from_site or not to_site then
    return false, {error = "endpoint_not_found", route_id = route.route_id}
  end
  local from_anchor = endpoint_anchor(from_site)
  local to_anchor = endpoint_anchor(to_site)
  if not from_anchor or not to_anchor then
    return false, {error = "endpoint_not_anchored", route_id = route.route_id}
  end
  if not route.claim_id or not (aliveworld.claims and aliveworld.claims.get(route.claim_id)) then
    return false, {error = "route_claim_missing", route_id = route.route_id}
  end
  return true, {status = "valid"}
end

function aliveworld.routes.plan_route(route_id, opts)
  opts = opts or {}
  local existing = routes[route_id]
  if existing and not opts.force_replan then
    local valid = aliveworld.routes.validate_route(existing)
    if valid then
      local copy = copy_table(existing)
      copy.status = copy.status or "planned"
      return true, copy
    end
  end

  local def = route_def(route_id, opts)
  if not def then
    return false, {error = "route_not_found", route_id = route_id}
  end
  local ok_endpoint, endpoint = validate_endpoints(def)
  if not ok_endpoint then
    return false, endpoint
  end
  if not aliveworld.terrain or not aliveworld.terrain.route_sample or not aliveworld.terrain.route_step_cost then
    return false, {error = "terrain_api_missing", route_id = route_id}
  end
  if not aliveworld.claims then
    return false, {error = "claims_api_missing", route_id = route_id}
  end

  local ok_route, route
  if opts.test_mode == "straight_loaded" then
    ok_route, route = make_straight_route(def, endpoint, opts, nil)
  else
    local job = make_job(def, endpoint, opts)
    while job.status == "running" do
      local state_ok, result = process_job(job, job.settings.nodes_per_step)
      if state_ok ~= nil then
        ok_route = state_ok
        route = result
        break
      end
    end
  end
  if not ok_route then
    return false, route
  end
  local saved_ok, saved_or_error = validate_and_save_route(route, opts)
  if not saved_ok then
    return false, saved_or_error
  end
  link_old_road_site(saved_or_error)
  aliveworld.add_event("route_planned",
    string.format("Route planned: %s %s -> %s points=%d length=%d",
      saved_or_error.route_id, saved_or_error.from_site_id, saved_or_error.to_site_id,
      #saved_or_error.points, saved_or_error.length or 0),
    {route_id = saved_or_error.route_id, from_site_id = saved_or_error.from_site_id, to_site_id = saved_or_error.to_site_id}
  )
  return true, saved_or_error
end

function aliveworld.routes.start_plan_route(route_id, opts)
  opts = opts or {}
  if routes[route_id] and not opts.force_replan then
    local valid = aliveworld.routes.validate_route(routes[route_id])
    if valid then
      return true, {status = "already_planned", route_id = route_id, route = copy_table(routes[route_id])}
    end
  end
  local def = route_def(route_id, opts)
  if not def then
    return false, {error = "route_not_found", route_id = route_id}
  end
  local ok_endpoint, endpoint = validate_endpoints(def)
  if not ok_endpoint then
    return false, endpoint
  end
  local job = make_job(def, endpoint, opts)
  job.force_replan = opts.force_replan == true
  route_jobs[route_id] = job
  return true, {
    status = "running",
    route_id = route_id,
    from_site_id = endpoint.from_site.id,
    to_site_id = endpoint.to_site.id,
    goal = {x = job.goal_gx, z = job.goal_gz},
    settings = copy_table(job.settings),
  }
end

function aliveworld.routes.get_job(route_id)
  return route_jobs[route_id]
end

function aliveworld.routes.process_jobs(budget)
  for _, job in pairs(route_jobs) do
    if job.status == "running" then
      local ok, result = process_job(job, budget or job.settings.nodes_per_step)
      if ok == true then
        local saved_ok, saved_or_error = validate_and_save_route(result, {force_replan = job.force_replan})
        if saved_ok then
          link_old_road_site(saved_or_error)
          job.result = saved_or_error
          job.status = "done"
        else
          job.result = saved_or_error
          job.status = "failed"
        end
      elseif ok == false then
        job.result = result
        job.status = "failed"
      end
    end
  end
end

function aliveworld.routes.plan_old_road(opts)
  opts = opts or {}
  opts.route_id = "old_road"
  opts.from_site_id = nil
  opts.to_site_id = nil
  return aliveworld.routes.plan_route("old_road", opts)
end

function aliveworld.routes.get_graph()
  local nodes = {}
  if aliveworld.sites then
    for _, site in ipairs(aliveworld.sites.list()) do
      local phys = site.physical_status or "abstract"
      if site.anchor_pos and (phys == "anchored" or phys == "materialized") then
        nodes[site.id] = {
          site_id = site.id,
          settlement_id = site.settlement_id,
          anchor_pos = pos_copy(site.anchor_pos),
          physical_status = phys,
        }
      end
    end
  end
  local edges = {}
  for _, route in pairs(routes) do
    if route.status == "planned" or route.status == "materialized" then
      local a = route.from_site_id
      local b = route.to_site_id
      local key = a < b and (a .. ":" .. b) or (b .. ":" .. a)
      edges[key] = {
        route_id = route.route_id,
        from_site_id = route.from_site_id,
        to_site_id = route.to_site_id,
        status = route.status,
        length = route.length,
      }
    end
  end
  return {nodes = nodes, edges = edges}
end

minetest.register_globalstep(function(dtime)
  route_job_timer = route_job_timer + dtime
  if route_job_timer < 0.2 then return end
  route_job_timer = 0
  aliveworld.routes.process_jobs()
end)

load_all()

minetest.log("action", "[aliveworld_core] routes module loaded")
