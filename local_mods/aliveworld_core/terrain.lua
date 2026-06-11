-- terrain.lua
-- Terrain survey and deterministic candidate scoring for AliveWorld site anchors.

aliveworld.terrain = aliveworld.terrain or {}

local terrain = aliveworld.terrain

terrain.ANCHOR_VERSION = 1

local DEFAULT_MIN_Y = -64
local DEFAULT_MAX_Y = 160

local PROFILES = {
  birch_ford = {
    name = "birch_ford",
    sample_radius = 16,
    sample_step = 4,
    min_total_score = 0.62,
    max_height_range = 7,
    min_buildable_ratio = 0.58,
    max_water_ratio = 0.18,
    min_area_score = 0.45,
    max_anchor_y = 95,
    water_ideal_min = 8,
    water_ideal_max = 96,
    require_water = true,
    max_water_distance = 128,
  },
  stone_gully = {
    name = "stone_gully",
    sample_radius = 16,
    sample_step = 4,
    min_total_score = 0.52,
    max_height_range = 14,
    min_buildable_ratio = 0.42,
    max_water_ratio = 0.22,
    min_area_score = 0.32,
    max_anchor_y = 125,
    prefer_rough = true,
  },
  route_anchor = {
    name = "route_anchor",
    sample_radius = 14,
    sample_step = 4,
    min_total_score = 0.55,
    max_height_range = 10,
    min_buildable_ratio = 0.46,
    max_water_ratio = 0.20,
    min_area_score = 0.36,
    max_anchor_y = 110,
    require_two_axes = true,
  },
  generic = {
    name = "generic",
    sample_radius = 12,
    sample_step = 4,
    min_total_score = 0.45,
    max_height_range = 12,
    min_buildable_ratio = 0.35,
    max_water_ratio = 0.25,
    min_area_score = 0.25,
    max_anchor_y = 140,
  },
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

function terrain.get_profile(name, overrides)
  local profile = copy_table(PROFILES[name or "generic"] or PROFILES.generic)
  for k, v in pairs(overrides or {}) do
    if k ~= "profile" then
      profile[k] = v
    end
  end
  profile.name = profile.name or name or "generic"
  return profile
end

function terrain.profile_for_site(site)
  if not site then return "generic" end
  if site.settlement_id == "birch_ford" then return "birch_ford" end
  if site.settlement_id == "stone_gully" then return "stone_gully" end
  if site.settlement_id == "old_road" then return "route_anchor" end
  if site.subtype == "outpost" then return "route_anchor" end
  return "generic"
end

function terrain.get_world_seed()
  return minetest.get_mapgen_setting("seed")
    or minetest.get_mapgen_setting("fixed_map_seed")
    or minetest.settings:get("fixed_map_seed")
    or minetest.settings:get("seed")
    or ""
end

local function round2(n)
  return math.floor((n or 0) * 100 + 0.5) / 100
end

local function clamp01(n)
  if n < 0 then return 0 end
  if n > 1 then return 1 end
  return n
end

local function node_def(name)
  return minetest.registered_nodes[name or ""]
end

local function is_liquid(name)
  local def = node_def(name)
  return def and def.liquidtype and def.liquidtype ~= "none"
end

local function is_tree_or_leaf(name)
  return minetest.get_item_group(name, "tree") > 0
    or minetest.get_item_group(name, "leaves") > 0
    or minetest.get_item_group(name, "leafdecay") > 0
end

local function is_plantlike(name)
  local def = node_def(name)
  return minetest.get_item_group(name, "flora") > 0
    or (def and def.drawtype == "plantlike")
    or (name or ""):find("flower", 1, true) ~= nil
    or (name or ""):find("grass", 1, true) ~= nil
end

local function is_buildable_surface(name)
  local def = node_def(name)
  if not def or def.walkable == false then return false end
  if is_liquid(name) or is_tree_or_leaf(name) then return false end
  return true
end

local function is_clear_standing_node(name)
  if name == "ignore" then return false end
  if is_liquid(name) or is_tree_or_leaf(name) then return false end
  if name == "air" or is_plantlike(name) then return true end
  local def = node_def(name)
  return def and def.walkable == false
end

local function surface_at(x, z, min_y, max_y)
  local previous_name = nil
  for y = max_y, min_y, -1 do
    local pos = {x = x, y = y, z = z}
    local node = minetest.get_node(pos)
    if node.name == "ignore" then
      return nil, "area_not_loaded"
    end
    if is_buildable_surface(node.name) and is_clear_standing_node(previous_name or "air") then
      local stand = {x = x, y = y + 1, z = z}
      local head = minetest.get_node({x = x, y = y + 2, z = z})
      local below = minetest.get_node({x = x, y = y - 1, z = z})
      if head.name == "ignore" or below.name == "ignore" then
        return nil, "area_not_loaded"
      end
      return {
        pos = stand,
        surface_node = node.name,
        head_node = head.name,
        below_node = below.name,
        supported = is_buildable_surface(below.name),
        blocked = not is_clear_standing_node(head.name),
      }
    end
    previous_name = node.name
  end
  return nil, "no_surface"
end

local function find_water_distance(center, y, radius, step)
  local best = nil
  for dx = -radius, radius, step do
    for dz = -radius, radius, step do
      local dist = math.sqrt(dx * dx + dz * dz)
      if dist <= radius and (not best or dist < best) then
        for dy = 12, -12, -1 do
          local node = minetest.get_node({x = center.x + dx, y = y + dy, z = center.z + dz})
          if node.name == "ignore" then
            break
          end
          if is_liquid(node.name) then
            best = dist
            break
          end
        end
      end
    end
  end
  if not best then return -1 end
  return math.floor(best + 0.5)
end

local function connected_area_score(cells, buildable_count)
  if buildable_count == 0 then return 0 end
  local by_key = {}
  for _, cell in ipairs(cells) do
    if cell.buildable then
      by_key[cell.x .. ":" .. cell.z] = cell
    end
  end
  local visited = {}
  local best = 0
  for key, cell in pairs(by_key) do
    if not visited[key] then
      local queue = {cell}
      visited[key] = true
      local count = 0
      local qi = 1
      while queue[qi] do
        local cur = queue[qi]
        qi = qi + 1
        count = count + 1
        local neighbors = {
          {x = cur.x + cur.step, z = cur.z},
          {x = cur.x - cur.step, z = cur.z},
          {x = cur.x, z = cur.z + cur.step},
          {x = cur.x, z = cur.z - cur.step},
        }
        for _, n in ipairs(neighbors) do
          local nk = n.x .. ":" .. n.z
          if by_key[nk] and not visited[nk] then
            visited[nk] = true
            table.insert(queue, by_key[nk])
          end
        end
      end
      if count > best then best = count end
    end
  end
  return best / buildable_count
end

local function axis_accessibility(cells, center_y, max_delta)
  local axes = {east = false, west = false, north = false, south = false}
  for _, cell in ipairs(cells) do
    if cell.buildable and math.abs(cell.y - center_y) <= max_delta then
      if cell.dx > 0 and math.abs(cell.dz) <= cell.step then axes.east = true end
      if cell.dx < 0 and math.abs(cell.dz) <= cell.step then axes.west = true end
      if cell.dz > 0 and math.abs(cell.dx) <= cell.step then axes.south = true end
      if cell.dz < 0 and math.abs(cell.dx) <= cell.step then axes.north = true end
    end
  end
  local count = 0
  for _, ok in pairs(axes) do
    if ok then count = count + 1 end
  end
  return count / 4, axes
end

local function empty_survey(pos, profile, reason)
  return {
    ok = false,
    pos = {x = pos.x, y = pos.y or 0, z = pos.z},
    surface_node = nil,
    biome = nil,
    water_distance = -1,
    sample_radius = profile.sample_radius,
    min_y = 0,
    max_y = 0,
    height_range = 0,
    average_y = 0,
    solid_ratio = 0,
    water_ratio = 0,
    air_ratio = 0,
    buildable_ratio = 0,
    slope_score = 0,
    area_score = 0,
    accessibility_score = 0,
    total_score = 0,
    flags = {
      near_water = false,
      steep = false,
      fragmented = false,
      underwater = false,
      unsupported = false,
      blocked = false,
      in_tree = false,
      area_not_loaded = reason == "area_not_loaded",
    },
    rejections = {reason or "no_surface"},
  }
end

--- Survey real terrain around an X/Z candidate.
-- Stable result fields:
-- ok, pos, surface_node, biome, water_distance, sample_radius, min_y, max_y,
-- height_range, average_y, solid_ratio, water_ratio, air_ratio,
-- buildable_ratio, slope_score, area_score, accessibility_score, total_score,
-- flags, rejections.
function terrain.survey(pos, opts)
  opts = opts or {}
  local profile = terrain.get_profile(opts.profile, opts)
  local center = {
    x = math.floor((pos.x or 0) + 0.5),
    y = pos.y and math.floor(pos.y + 0.5) or nil,
    z = math.floor((pos.z or 0) + 0.5),
  }
  local sample_radius = profile.sample_radius or 12
  local sample_step = profile.sample_step or 4
  local min_y = profile.min_y or (center.y and center.y - 64) or DEFAULT_MIN_Y
  local max_y = profile.max_y or (center.y and center.y + 64) or DEFAULT_MAX_Y

  minetest.emerge_area(
    {x = center.x - sample_radius, y = min_y, z = center.z - sample_radius},
    {x = center.x + sample_radius, y = max_y, z = center.z + sample_radius}
  )

  local input_node = center.y and minetest.get_node(center) or {name = "air"}
  if input_node.name == "ignore" then
    return empty_survey(center, profile, "area_not_loaded")
  end
  if is_liquid(input_node.name) then
    local survey = empty_survey(center, profile, "underwater")
    survey.flags.underwater = true
    survey.surface_node = input_node.name
    return survey
  end

  local surface, reason = surface_at(center.x, center.z, min_y, max_y)
  if not surface then
    return empty_survey(center, profile, reason)
  end

  local cells = {}
  local total = 0
  local solid = 0
  local water = 0
  local air = 0
  local buildable = 0
  local min_sample_y = nil
  local max_sample_y = nil
  local sum_y = 0
  local rejections = {}

  for dx = -sample_radius, sample_radius, sample_step do
    for dz = -sample_radius, sample_radius, sample_step do
      if dx * dx + dz * dz <= sample_radius * sample_radius then
        total = total + 1
        local sample, sample_reason = surface_at(center.x + dx, center.z + dz, min_y, max_y)
        if sample_reason == "area_not_loaded" then
          return empty_survey(center, profile, "area_not_loaded")
        end
        if sample then
          local n = minetest.get_node({x = center.x + dx, y = sample.pos.y - 1, z = center.z + dz})
          local current = minetest.get_node(sample.pos)
          if is_liquid(n.name) or is_liquid(current.name) then
            water = water + 1
          elseif is_buildable_surface(n.name) then
            solid = solid + 1
          elseif current.name == "air" then
            air = air + 1
          end
          local sample_buildable = is_buildable_surface(n.name)
            and is_clear_standing_node(current.name)
            and not sample.blocked
            and sample.supported
          if sample_buildable then
            buildable = buildable + 1
          end
          local sy = sample.pos.y
          min_sample_y = min_sample_y and math.min(min_sample_y, sy) or sy
          max_sample_y = max_sample_y and math.max(max_sample_y, sy) or sy
          sum_y = sum_y + sy
          table.insert(cells, {
            x = center.x + dx,
            z = center.z + dz,
            y = sy,
            dx = dx,
            dz = dz,
            step = sample_step,
            buildable = sample_buildable,
          })
        else
          air = air + 1
        end
      end
    end
  end

  if total == 0 or not min_sample_y then
    return empty_survey(center, profile, "no_samples")
  end

  local height_range = max_sample_y - min_sample_y
  local average_y = sum_y / math.max(1, #cells)
  local solid_ratio = solid / total
  local water_ratio = water / total
  local air_ratio = air / total
  local buildable_ratio = buildable / total
  local area_score = connected_area_score(cells, buildable)
  local slope_score = clamp01(1 - (height_range / math.max(1, profile.max_height_range or 12)))
  local accessibility_score, axes = axis_accessibility(cells, surface.pos.y, math.max(2, math.floor((profile.max_height_range or 12) / 2)))
  local water_distance = find_water_distance(surface.pos, surface.pos.y, profile.water_scan_radius or 128, 4)
  local near_water = water_distance >= 0 and water_distance <= (profile.water_ideal_max or 96)
  local water_score = 0.5
  if water_distance >= 0 then
    if water_distance >= (profile.water_ideal_min or 0) and water_distance <= (profile.water_ideal_max or 96) then
      water_score = 1
    else
      water_score = 0.55
    end
  elseif profile.require_water then
    water_score = 0
  end

  local surface_name = surface.surface_node
  local stone_bonus = 0
  if profile.prefer_rough then
    if minetest.get_item_group(surface_name, "stone") > 0 or (surface_name or ""):find("stone", 1, true) then
      stone_bonus = 0.08
    end
    if height_range >= 3 and height_range <= (profile.max_height_range or 14) then
      stone_bonus = stone_bonus + 0.06
    end
  end

  local total_score = clamp01(
    slope_score * 0.22 +
    area_score * 0.24 +
    accessibility_score * 0.18 +
    buildable_ratio * 0.20 +
    solid_ratio * 0.08 +
    water_score * 0.08 +
    stone_bonus
  )

  local flags = {
    near_water = near_water,
    steep = height_range > (profile.max_height_range or 12),
    fragmented = area_score < (profile.min_area_score or 0.25),
    underwater = is_liquid(surface.surface_node),
    unsupported = not surface.supported,
    blocked = surface.blocked or not is_clear_standing_node(surface.head_node),
    in_tree = is_tree_or_leaf(surface.surface_node) or is_tree_or_leaf(surface.head_node),
    area_not_loaded = false,
    high_peak = surface.pos.y > (profile.max_anchor_y or 140),
    route_dead_end = false,
  }
  if profile.require_two_axes then
    local east_west = axes.east and axes.west
    local north_south = axes.north and axes.south
    flags.route_dead_end = not (east_west or north_south)
  end

  if flags.steep then table.insert(rejections, "steep") end
  if flags.fragmented then table.insert(rejections, "fragmented") end
  if flags.underwater then table.insert(rejections, "underwater") end
  if flags.unsupported then table.insert(rejections, "unsupported") end
  if flags.blocked then table.insert(rejections, "blocked") end
  if flags.in_tree then table.insert(rejections, "in_tree") end
  if flags.high_peak then table.insert(rejections, "high_peak") end
  if flags.route_dead_end then table.insert(rejections, "route_dead_end") end
  if buildable_ratio < (profile.min_buildable_ratio or 0.35) then table.insert(rejections, "low_buildable_ratio") end
  if water_ratio > (profile.max_water_ratio or 0.25) then table.insert(rejections, "too_much_water") end
  if profile.require_water and (water_distance < 0 or water_distance > (profile.max_water_distance or 128)) then
    table.insert(rejections, "water_too_far")
  end
  if total_score < (profile.min_total_score or 0.45) then table.insert(rejections, "low_total_score") end

  local biome = nil
  if minetest.get_biome_data then
    local biome_data = minetest.get_biome_data(surface.pos)
    if biome_data and biome_data.biome then
      biome = minetest.get_biome_name(biome_data.biome)
    end
  end

  local ok = #rejections == 0
  return {
    ok = ok,
    pos = {x = surface.pos.x, y = surface.pos.y, z = surface.pos.z},
    surface_node = surface.surface_node,
    biome = biome,
    water_distance = water_distance,
    sample_radius = sample_radius,
    min_y = min_sample_y,
    max_y = max_sample_y,
    height_range = height_range,
    average_y = round2(average_y),
    solid_ratio = round2(solid_ratio),
    water_ratio = round2(water_ratio),
    air_ratio = round2(air_ratio),
    buildable_ratio = round2(buildable_ratio),
    slope_score = round2(slope_score),
    area_score = round2(area_score),
    accessibility_score = round2(accessibility_score),
    total_score = round2(total_score),
    flags = flags,
    rejections = rejections,
  }
end

local function hash_string(str)
  local h = 0
  for i = 1, #str do
    h = (h * 33 + string.byte(str, i)) % 2147483647
  end
  return h
end

function terrain.make_candidates(hint_pos, site_id, opts)
  opts = opts or {}
  local step = opts.candidate_step or 16
  local max_radius = opts.max_radius or 256
  local max_candidates = opts.max_candidates or 160
  local candidates = {}
  local seed_hash = hash_string(tostring(terrain.get_world_seed()) .. ":" .. tostring(site_id or ""))
  local phase = seed_hash % 8
  table.insert(candidates, {x = hint_pos.x, y = hint_pos.y, z = hint_pos.z, ring = 0})
  for radius = step, max_radius, step do
    local ring = {}
    for dx = -radius, radius, step do
      table.insert(ring, {x = hint_pos.x + dx, y = hint_pos.y, z = hint_pos.z - radius, ring = radius})
      table.insert(ring, {x = hint_pos.x + dx, y = hint_pos.y, z = hint_pos.z + radius, ring = radius})
    end
    for dz = -radius + step, radius - step, step do
      table.insert(ring, {x = hint_pos.x - radius, y = hint_pos.y, z = hint_pos.z + dz, ring = radius})
      table.insert(ring, {x = hint_pos.x + radius, y = hint_pos.y, z = hint_pos.z + dz, ring = radius})
    end
    table.sort(ring, function(a, b)
      local ah = hash_string(a.x .. ":" .. a.z .. ":" .. phase)
      local bh = hash_string(b.x .. ":" .. b.z .. ":" .. phase)
      return ah < bh
    end)
    for _, candidate in ipairs(ring) do
      table.insert(candidates, candidate)
      if #candidates >= max_candidates then
        return candidates
      end
    end
  end
  return candidates
end

function terrain.summarize_survey(survey)
  if not survey then return nil end
  return {
    ok = survey.ok,
    pos = survey.pos and {x = survey.pos.x, y = survey.pos.y, z = survey.pos.z} or nil,
    surface_node = survey.surface_node,
    biome = survey.biome,
    water_distance = survey.water_distance,
    sample_radius = survey.sample_radius,
    min_y = survey.min_y,
    max_y = survey.max_y,
    height_range = survey.height_range,
    average_y = survey.average_y,
    solid_ratio = survey.solid_ratio,
    water_ratio = survey.water_ratio,
    air_ratio = survey.air_ratio,
    buildable_ratio = survey.buildable_ratio,
    slope_score = survey.slope_score,
    area_score = survey.area_score,
    accessibility_score = survey.accessibility_score,
    total_score = survey.total_score,
    flags = copy_table(survey.flags),
    rejections = copy_table(survey.rejections),
  }
end

function terrain.find_anchor(site, opts)
  opts = opts or {}
  if not site or not site.pos then
    return false, {error = "invalid_site"}
  end
  local profile_name = opts.profile or terrain.profile_for_site(site)
  local profile = terrain.get_profile(profile_name, opts)
  local candidates = terrain.make_candidates(site.pos, site.id, opts)
  local best = nil
  local checked = 0
  local rejected = {}
  local started_us = minetest.get_us_time()

  for _, candidate in ipairs(candidates) do
    checked = checked + 1
    local survey = terrain.survey(candidate, profile)
    if survey.ok and (not best or survey.total_score > best.survey.total_score) then
      best = {candidate = candidate, survey = survey}
    else
      table.insert(rejected, {
        pos = {x = candidate.x, y = candidate.y, z = candidate.z},
        score = survey.total_score or 0,
        reasons = survey.rejections or {},
      })
    end
  end

  local duration_ms = math.floor((minetest.get_us_time() - started_us) / 1000)
  if not best then
    return false, {
      error = "no_suitable_candidate",
      profile = profile.name,
      checked = checked,
      duration_ms = duration_ms,
      rejected = rejected,
    }
  end
  return true, {
    profile = profile.name,
    anchor_pos = best.survey.pos,
    survey = terrain.summarize_survey(best.survey),
    checked = checked,
    duration_ms = duration_ms,
    rejected = rejected,
  }
end

minetest.log("action", "[aliveworld_core] terrain module loaded")
