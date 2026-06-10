-- sites.lua
-- Spatial sites layer for AliveWorld
-- Maps settlements, events, and rumors to positions in the world

local storage = minetest.get_mod_storage()
local SITES_KEY = "aliveworld_sites"

local sites = {}

aliveworld.sites = {}

local DIR_NAMES_RU = {"север", "северо-восток", "восток", "юго-восток", "юг", "юго-запад", "запад", "северо-запад"}
local DIR_NAMES_EN = {"north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"}

function aliveworld.sites.distance(a, b)
  local dx = a.x - b.x
  local dz = a.z - b.z
  return math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
end

function aliveworld.sites.direction_index(from_pos, to_pos)
  local dx = to_pos.x - from_pos.x
  local dz = to_pos.z - from_pos.z
  local angle = math.deg(math.atan2(-dz, dx))
  local bearing = 90 - angle
  if bearing < 0 then bearing = bearing + 360 end
  if bearing >= 360 then bearing = bearing - 360 end
  return math.floor((bearing + 22.5) / 45) % 8
end

function aliveworld.sites.direction_name_ru(from_pos, to_pos)
  return DIR_NAMES_RU[aliveworld.sites.direction_index(from_pos, to_pos) + 1]
end

function aliveworld.sites.direction_name_en(from_pos, to_pos)
  return DIR_NAMES_EN[aliveworld.sites.direction_index(from_pos, to_pos) + 1]
end

function aliveworld.sites.format_direction_ru(from_pos, to_pos)
  local dist = aliveworld.sites.distance(from_pos, to_pos)
  local dir = aliveworld.sites.direction_name_ru(from_pos, to_pos)
  return string.format("примерно %d блоков на %s", dist, dir)
end

function aliveworld.sites.format_direction_en(from_pos, to_pos)
  local dist = aliveworld.sites.distance(from_pos, to_pos)
  local dir = aliveworld.sites.direction_name_en(from_pos, to_pos)
  return string.format("distance=%d direction=%s", dist, dir)
end

function aliveworld.sites.list(filter)
  local res = {}
  for _, s in pairs(sites) do
    if not filter or filter(s) then
      table.insert(res, s)
    end
  end
  table.sort(res, function(a, b) return (a.id or "") < (b.id or "") end)
  return res
end

function aliveworld.sites.get(id)
  -- Direct match by id
  local s = sites[id]
  if s then return s end

  -- Try with site_ prefix (e.g. "birch_ford" -> "site_birch_ford")
  s = sites["site_" .. id]
  if s then return s end

  -- Fallback: search by settlement_id, prefer settlement-type
  local fallback = nil
  for _, site in pairs(sites) do
    if site.settlement_id == id then
      if site.type == "settlement" then
        return site
      end
      if not fallback then
        fallback = site
      end
    end
  end
  return fallback
end

function aliveworld.sites.save(site)
  sites[site.id] = site
  storage:set_string(SITES_KEY, minetest.write_json(sites))
end

function aliveworld.sites.delete(id)
  sites[id] = nil
  storage:set_string(SITES_KEY, minetest.write_json(sites))
end

function aliveworld.sites.find_by_settlement(settlement_id)
  for _, s in pairs(sites) do
    if s.settlement_id == settlement_id then
      return s
    end
  end
  return nil
end

function aliveworld.sites.find_by_event(event_id)
  for _, s in pairs(sites) do
    if s.event_id == event_id then
      return s
    end
  end
  return nil
end

function aliveworld.sites.nearest(from_pos, limit)
  limit = limit or 5
  local sorted = {}
  for _, s in pairs(sites) do
    if s.status == "active" then
      local to_pos = s.anchor_pos or s.pos
      if aliveworld.sites.resolve_arrival_pos then
        local arrival = aliveworld.sites.resolve_arrival_pos(s)
        if arrival then to_pos = arrival end
      end
      local dist = aliveworld.sites.distance(from_pos, to_pos)
      table.insert(sorted, {site = s, dist = dist})
    end
  end
  table.sort(sorted, function(a, b) return a.dist < b.dist end)
  local res = {}
  for i = 1, math.min(limit, #sorted) do
    table.insert(res, sorted[i].site)
  end
  return res
end

local INITIAL_SETTLEMENT_SITES = {
  {
    id = "site_birch_ford",
    type = "settlement",
    subtype = "village",
    name = "Берёзовый Брод",
    name_en = "Birch Ford",
    settlement_id = "birch_ford",
    event_id = nil,
    pos = {x = 320, y = 8, z = -180},
    radius = 80,
    status = "active",
    physical_status = "abstract",
    anchor_pos = nil,
    marker_id = nil,
    discovered = false,
    created_day = 1,
    expires_day = nil,
    data = {},
  },
  {
    id = "site_stone_gully",
    type = "settlement",
    subtype = "village",
    name = "Каменная Балка",
    name_en = "Stone Gully",
    settlement_id = "stone_gully",
    event_id = nil,
    pos = {x = -420, y = 12, z = 260},
    radius = 70,
    status = "active",
    physical_status = "abstract",
    anchor_pos = nil,
    marker_id = nil,
    discovered = false,
    created_day = 1,
    expires_day = nil,
    data = {},
  },
  {
    id = "site_old_road",
    type = "settlement",
    subtype = "outpost",
    name = "Старый Тракт",
    name_en = "Old Road",
    settlement_id = "old_road",
    event_id = nil,
    pos = {x = 880, y = 9, z = 100},
    radius = 60,
    status = "active",
    physical_status = "abstract",
    anchor_pos = nil,
    marker_id = nil,
    discovered = false,
    created_day = 1,
    expires_day = nil,
    data = {},
  },
}

local function simple_hash(str)
  local h = 0
  for i = 1, #str do
    h = (h * 31 + string.byte(str, i)) % 2147483647
  end
  return h
end

local EVENT_OFFSETS = {
  food_shortage = {max_dist = 30, min_dist = 10},
  dangerous_roads = {max_dist = 80, min_dist = 50},
  winter_hardship = {max_dist = 20, min_dist = 5},
  unrest = {max_dist = 10, min_dist = 0},
  trade_opportunity = {max_dist = 40, min_dist = 20},
  recovery = {max_dist = 15, min_dist = 5},
}

function aliveworld.sites.ensure_initial_settlement_sites(created_day)
  created_day = created_day or (aliveworld.get_day and aliveworld.get_day()) or 1
  local created_count = 0
  for _, proto in ipairs(INITIAL_SETTLEMENT_SITES) do
    if not sites[proto.id] then
      local site = minetest.parse_json(minetest.write_json(proto))
      site.created_day = created_day
      sites[site.id] = site
      created_count = created_count + 1

      aliveworld.add_event("site_created",
        string.format("Site created: %s (%s) at %d,%d,%d type=%s",
          site.name_en, site.id, site.pos.x, site.pos.y, site.pos.z, site.type),
        {site_id = site.id, site_type = site.type, settlement_id = site.settlement_id}
      )
    end
  end
  if created_count > 0 then
    storage:set_string(SITES_KEY, minetest.write_json(sites))
  end
  return created_count
end

-- Resolve a safe arrival position for a site.
-- Finds surface ground near site.pos (or anchor_pos if available),
-- avoiding liquid, inside-block, and mid-air positions.
-- Returns {x, y, z} where a player can safely stand.
function aliveworld.sites.resolve_arrival_pos(site)
  if not site then return nil end
  local base_pos = site.anchor_pos or site.pos
  if not base_pos then return nil end

  -- Search from above downward for a walkable surface
  local start_y = 120
  local search = {x = base_pos.x, y = start_y, z = base_pos.z}

  -- Trigger chunk loading
  minetest.emerge_area({x = base_pos.x, y = start_y, z = base_pos.z}, {x = base_pos.x, y = 0, z = base_pos.z})

  for _ = 0, 120 do
    local node = minetest.get_node(search)
    if node.name == "ignore" then
      -- Chunk not loaded yet, try emerge
      minetest.emerge_area(search, search)
      search.y = search.y - 1
    else
      local def = minetest.registered_nodes[node.name]
      -- If this is air or non-walkable, check the block below as a surface candidate
      if def and def.walkable == false then
        local below = minetest.get_node({x = search.x, y = search.y - 1, z = search.z})
        if below.name ~= "ignore" then
          local def_below = minetest.registered_nodes[below.name]
          if def_below and def_below.walkable ~= false then
            local liquid = def_below.liquidtype and def_below.liquidtype ~= "none"
            if not liquid then
              return {x = search.x, y = search.y, z = search.z}
            end
          end
        end
      elseif def and def.liquidtype and def.liquidtype ~= "none" then
        -- Liquid: skip, continue down
      end
      search.y = search.y - 1
    end
  end

  -- Fallback: return original position
  return {x = base_pos.x, y = base_pos.y + 1, z = base_pos.z}
end

-- Get the arrival position for a site, with metadata about precision
function aliveworld.sites.get_arrival_info(site)
  if not site then return nil, "no_site" end
  local arrival = aliveworld.sites.resolve_arrival_pos(site)
  if not arrival then return nil, "no_arrival" end
  local phys = site.physical_status or "abstract"
  if phys == "anchored" or phys == "materialized" then
    return arrival, "exact"
  end
  return arrival, "approximate"
end

-- Check if a position is safe for a player to stand
-- Returns {safe = bool, reasons = {string,...}}
function aliveworld.sites.is_safe_standing_pos(pos)
  if not pos then return {safe = false, reasons = {"no_position"}} end
  local reasons = {}
  local check_pos = {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}

  -- Head node (where player's head would be)
  local head = minetest.get_node(check_pos)
  if head.name == "ignore" then
    table.insert(reasons, "chunk_not_loaded")
    return {safe = false, reasons = reasons}
  end
  local head_def = minetest.registered_nodes[head.name]
  if head_def and head_def.walkable ~= false then
    table.insert(reasons, "head_inside_block")
    return {safe = false, reasons = reasons}
  end
  if head_def and head_def.liquidtype and head_def.liquidtype ~= "none" then
    table.insert(reasons, "head_in_liquid")
    -- Can still be safe briefly but we flag it
  end

  -- Feet node (where player's feet would be)
  local feet = minetest.get_node({x = check_pos.x, y = check_pos.y - 1, z = check_pos.z})
  if feet.name == "ignore" then
    table.insert(reasons, "feet_chunk_not_loaded")
    return {safe = false, reasons = reasons}
  end
  local feet_def = minetest.registered_nodes[feet.name]
  if not feet_def then
    table.insert(reasons, "feet_no_definition")
    return {safe = false, reasons = reasons}
  end
  if feet_def.walkable == false then
    table.insert(reasons, "feet_not_solid")
    return {safe = false, reasons = reasons}
  end
  if feet_def.liquidtype and feet_def.liquidtype ~= "none" then
    if head_def and head_def.liquidtype and head_def.liquidtype ~= "none" then
      table.insert(reasons, "fully_submerged")
    else
      table.insert(reasons, "standing_in_liquid")
    end
  end

  -- Below node (support block)
  local below = minetest.get_node({x = check_pos.x, y = check_pos.y - 2, z = check_pos.z})
  if below.name ~= "ignore" then
    local below_def = minetest.registered_nodes[below.name]
    if below_def and (below_def.walkable == false or (below_def.liquidtype and below_def.liquidtype ~= "none")) then
      table.insert(reasons, "below_unsupported")
    end
  end

  return {safe = #reasons == 0, reasons = reasons}
end

-- Resolve a safe observer position near a site (for awbot screenshots)
-- Scans outward from arrival_pos to find a clear vantage point
function aliveworld.sites.resolve_observer_pos(site)
  if not site then return nil end
  local base = aliveworld.sites.resolve_arrival_pos(site) or site.anchor_pos or site.pos
  if not base then return nil end

  -- Try the arrival position first (player standing there sees the site)
  local result = aliveworld.sites.is_safe_standing_pos(base)
  if result.safe then
    -- Check that water is not directly in front (rough check)
    local water_near = false
    for wx = -1, 1 do
      for wz = -1, 1 do
        local wnode = minetest.get_node({x = base.x + wx, y = base.y, z = base.z + wz})
        local wdef = minetest.registered_nodes[wnode.name]
        if wdef and wdef.liquidtype and wdef.liquidtype ~= "none" then
          water_near = true
        end
      end
    end
    if not water_near then
      return base
    end
  end

  -- Scan in a spiral outward from the base position
  for r = 2, 16 do
    for dx = -r, r do
      for dz = -r, r do
        if math.abs(dx) == r or math.abs(dz) == r then
          local candidate = {x = base.x + dx, y = base.y, z = base.z + dz}
          -- Find surface at this XZ
          local surf = aliveworld.sites.resolve_arrival_pos({pos = candidate, anchor_pos = nil})
          if surf then
            local safe = aliveworld.sites.is_safe_standing_pos(surf)
            if safe.safe then
              return surf
            end
          end
        end
      end
    end
  end

  -- Fallback: return the arrival position
  return base
end

-- Resolve a safe marker position near a site (for physical marker nodes)
-- Similar to observer_pos but prefers ground-level placement
function aliveworld.sites.resolve_marker_pos(site)
  if not site then return nil end
  -- Use anchor_pos if available (marker should be at the exact spot)
  if site.anchor_pos then
    local safe = aliveworld.sites.is_safe_standing_pos(site.anchor_pos)
    if safe.safe then
      return site.anchor_pos
    end
    -- Try one block above
    local above = {x = site.anchor_pos.x, y = site.anchor_pos.y + 1, z = site.anchor_pos.z}
    safe = aliveworld.sites.is_safe_standing_pos(above)
    if safe.safe then
      return above
    end
  end

  -- Fall back to arrival_pos
  local arrival = aliveworld.sites.resolve_arrival_pos(site)
  if arrival then
    local safe = aliveworld.sites.is_safe_standing_pos(arrival)
    if safe.safe then
      return arrival
    end
  end

  -- Final fallback
  return site.anchor_pos or site.pos
end

function aliveworld.sites.create_event_site(event)
  if not event or not event.id then
    return false, "Invalid event"
  end

  if aliveworld.sites.find_by_event(event.id) then
    return false
  end

  local settlement_site = nil
  if event.settlement_id then
    settlement_site = aliveworld.sites.find_by_settlement(event.settlement_id)
  end

  local ref_pos = settlement_site and settlement_site.pos or {x = 0, y = 8, z = 0}

  local h = simple_hash(event.id)
  local offset_config = EVENT_OFFSETS[event.type] or {max_dist = 40, min_dist = 10}
  local dist = offset_config.min_dist + (h % (offset_config.max_dist - offset_config.min_dist + 1))
  local angle_rad = (h % 6283) * 0.001

  local ox = math.floor(math.cos(angle_rad) * dist + 0.5)
  local oz = math.floor(math.sin(angle_rad) * dist + 0.5)

  local pos = {
    x = ref_pos.x + ox,
    y = ref_pos.y,
    z = ref_pos.z + oz,
  }

  local event_text = event.text_en or event.type
  local event_text_ru = event.text_ru or event_text

  local site = {
    id = "site_" .. event.id,
    type = "event",
    subtype = event.type,
    name = event_text_ru,
    name_en = event_text,
    settlement_id = event.settlement_id,
    event_id = event.id,
    pos = pos,
    radius = 40,
    status = "active",
    physical_status = "abstract",
    anchor_pos = nil,
    marker_id = nil,
    discovered = false,
    created_day = event.created_day,
    expires_day = (event.expires_day or event.created_day) + 5,
    data = {
      severity = event.severity or "minor",
    },
  }

  sites[site.id] = site
  storage:set_string(SITES_KEY, minetest.write_json(sites))

  aliveworld.add_event("site_created",
    string.format("Event site created: %s (%s) for event %s at %d,%d,%d",
      site.name_en, site.id, event.id, pos.x, pos.y, pos.z),
    {site_id = site.id, site_type = "event", event_id = event.id, settlement_id = event.settlement_id}
  )

  return true, site
end

function aliveworld.sites.anchor_site(site_id, anchor_pos, marker_id)
  local site = sites[site_id]
  if not site then
    return false, "Site not found: " .. site_id
  end
  site.physical_status = "anchored"
  site.anchor_pos = anchor_pos or {x = site.pos.x, y = site.pos.y, z = site.pos.z}
  site.marker_id = marker_id
  site.discovered = true
  storage:set_string(SITES_KEY, minetest.write_json(sites))
  aliveworld.add_event("site_anchored",
    string.format("Site anchored: %s (%s) at %d,%d,%d",
      site.name_en, site.id, site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z),
    {site_id = site.id, site_type = site.type, settlement_id = site.settlement_id, event_id = site.event_id}
  )
  return true, site
end

function aliveworld.sites.get_physical_status(site_id)
  local site = sites[site_id]
  if not site then return nil end
  return site.physical_status or "abstract"
end

function aliveworld.sites.get_anchor_info(site_id)
  local site = sites[site_id]
  if not site then return nil end
  if site.physical_status == "abstract" then
    return nil
  end
  return {
    physical_status = site.physical_status,
    anchor_pos = site.anchor_pos,
    marker_id = site.marker_id,
  }
end

function aliveworld.sites.expire_old(world_time)
  local total = world_time
  if type(world_time) == "table" then
    total = world_time.total_days
  end
  local expired_count = 0
  for _, s in pairs(sites) do
    if s.status == "active" and s.expires_day and total >= s.expires_day then
      s.status = "expired"
      expired_count = expired_count + 1
    end
  end
  if expired_count > 0 then
    storage:set_string(SITES_KEY, minetest.write_json(sites))
  end
  return expired_count
end

-- Get the display position for a site (prefer arrival_pos, then anchor_pos, then pos)
function aliveworld.sites.get_display_pos(site)
  if not site then return nil end
  if aliveworld.sites.resolve_arrival_pos then
    local arrival = aliveworld.sites.resolve_arrival_pos(site)
    if arrival then return arrival end
  end
  return site.anchor_pos or site.pos
end

function aliveworld.sites.get_places_for_player(player_name)
  if not player_name then return {} end
  local player = minetest.get_player_by_name(player_name)
  if not player then return {} end
  local player_pos = player:get_pos()
  if not player_pos then return {} end
  local from_pos = {x = player_pos.x, y = player_pos.y, z = player_pos.z}
  local places = {}
    for _, s in pairs(sites) do
      if s.type == "settlement" and s.status == "active" then
        local to_pos = aliveworld.sites.get_display_pos(s)
        local dist = aliveworld.sites.distance(from_pos, to_pos)
        local dir = aliveworld.sites.direction_name_ru(from_pos, to_pos)
        local type_name = (s.subtype == "village" and "деревня") or (s.subtype == "outpost" and "форпост") or s.subtype
        local physical_label = "не отмечено"
        if s.physical_status == "anchored" or s.physical_status == "materialized" then
          physical_label = "отмечено"
        end
        table.insert(places, {
          id = s.id,
          name = s.name,
          type_name = type_name,
          dist = dist,
          dir = dir,
          physical_status = s.physical_status or "abstract",
          physical_label = physical_label,
        })
      end
    end
  table.sort(places, function(a, b) return a.dist < b.dist end)
  return places
end

function aliveworld.sites.get_place_details(player_name, site_id)
  if not player_name or not site_id then return nil end
  local site = sites[site_id]
  if not site then return nil end
  local player = minetest.get_player_by_name(player_name)
  if not player then return nil end
  local player_pos = player:get_pos()
  if not player_pos then
    return {site = site, dist = nil, dir = nil}
  end
  local from_pos = {x = player_pos.x, y = player_pos.y, z = player_pos.z}
  local to_pos = aliveworld.sites.get_display_pos(site)
  local dist = aliveworld.sites.distance(from_pos, to_pos)
  local dir = aliveworld.sites.direction_name_ru(from_pos, to_pos)
  return {
    site = site,
    dist = dist,
    dir = dir,
  }
end

function aliveworld.sites.get_near_for_player(player_name, limit)
  if not player_name then return {} end
  limit = limit or 5
  local player = minetest.get_player_by_name(player_name)
  if not player then return {} end
  local player_pos = player:get_pos()
  if not player_pos then return {} end
  local from_pos = {x = player_pos.x, y = player_pos.y, z = player_pos.z}
  local near = aliveworld.sites.nearest(from_pos, limit)
  local result = {}
  for _, s in ipairs(near) do
    local to_pos = aliveworld.sites.get_display_pos(s)
    local dist = aliveworld.sites.distance(from_pos, to_pos)
    local dir = aliveworld.sites.direction_name_ru(from_pos, to_pos)
    local type_label = ""
    if s.type == "settlement" then
      type_label = (s.subtype == "village" and "деревня") or (s.subtype == "outpost" and "форпост") or s.subtype
    elseif s.type == "event" then
      type_label = "событие"
    end
    local physical_label = "не отмечено"
    if s.physical_status == "anchored" or s.physical_status == "materialized" then
      physical_label = "отмечено"
    end
    table.insert(result, {
      id = s.id,
      name = s.name,
      type = s.type,
      type_label = type_label,
      dist = dist,
      dir = dir,
      physical_status = s.physical_status or "abstract",
      physical_label = physical_label,
    })
  end
  return result
end

function aliveworld.sites.count_active()
  local n = 0
  for _, s in pairs(sites) do
    if s.status == "active" then
      n = n + 1
    end
  end
  return n
end

function aliveworld.sites.reset()
  sites = {}
  storage:set_string(SITES_KEY, minetest.write_json({}))
  minetest.log("action", "[aliveworld_core] all sites deleted")
end

-- Clue marker storage
-- Maps clue_id -> {pos={x,y,z}, site_id, placed_at=os.time(), placed_for=player_name}
local clue_markers = {}
local CLUE_MAX_AGE = 300 -- 5 minutes

local CLUES_KEY = "aliveworld_clue_markers"

-- Clue text templates keyed by event type
local CLUE_TEXTS = {
  default = {
    "Здесь есть следы недавнего пребывания.",
    "Кто-то был здесь совсем недавно.",
    "Приглядитесь — земля хранит следы.",
    "Это место связано с событиями из слухов.",
  },
  flood = {
    "Следы воды на камнях ещё свежи.",
    "Водоросли и тина указывают на недавний разлив.",
  },
  fire = {
    "Обгоревшие ветки валяются рядом.",
    "Пепел ещё не развеялся по ветру.",
  },
  crash = {
    "Обломки разбросаны по земле.",
    "Металлический запах витает в воздухе.",
  },
  haunt = {
    "Странный холодок пробегает по коже.",
    "Следы на земле образуют непонятный узор.",
  },
}

function aliveworld.sites.get_clue_texts(event_type)
  local texts = CLUE_TEXTS[event_type] or CLUE_TEXTS.default
  return texts[math.random(#texts)]
end

function aliveworld.sites.place_clue_marker(pos, site_id, player_name)
  if not pos then return false end

  -- Only place for abstract/non-anchor sites
  local site = aliveworld.sites.get(site_id)
  if not site then return false end
  local has_anchor = site.anchor_pos and (site.anchor_pos.x ~= 0 or site.anchor_pos.y ~= 0 or site.anchor_pos.z ~= 0)
  if has_anchor then return false end

  -- Check if we already placed a clue for this site
  for _, m in pairs(clue_markers) do
    if m.site_id == site_id and m.placed_for == player_name then
      return false -- already placed
    end
  end

  -- Pick the best available marker node
  local marker_name
  if minetest.registered_nodes["default:torch"] then
    marker_name = "default:torch"
  elseif minetest.registered_nodes["bones:bones"] then
    marker_name = "bones:bones"
  elseif minetest.registered_nodes["default:sign_wall_wood"] then
    marker_name = "default:sign_wall_wood"
  elseif minetest.registered_nodes["flowers:rose"] then
    marker_name = "flowers:rose"
  else
    -- Fallback: just log the clue position, no node placement
    minetest.log("action", "[aliveworld_core] clue marker: no suitable node found for " .. site_id)
    return false
  end

  -- Find safe ground position
  local ground_pos = aliveworld.sites.resolve_marker_pos(site)
  if not ground_pos then
    ground_pos = {x = pos.x, y = pos.y, z = pos.z}
  end

  -- Place marker on top of ground
  local node = minetest.get_node(ground_pos)
  local def = minetest.registered_nodes[node.name]
  local is_walkable = def and def.walkable

  if is_walkable then
    ground_pos = {x = ground_pos.x, y = ground_pos.y + 1, z = ground_pos.z}
  end

  -- Check if position is free
  local above_node = minetest.get_node(ground_pos)
  local above_def = minetest.registered_nodes[above_node.name]
  if above_def and (above_def.walkable or above_def.liquidtype and above_def.liquidtype ~= "none") then
    return false
  end

  minetest.set_node(ground_pos, {name = marker_name})

  local clue_id = site_id .. "_" .. player_name .. "_" .. tostring(os.time())
  clue_markers[clue_id] = {
    pos = {x = ground_pos.x, y = ground_pos.y, z = ground_pos.z},
    site_id = site_id,
    placed_for = player_name,
    placed_at = os.time(),
  }
  storage:set_string(CLUES_KEY, minetest.write_json(clue_markers))
  return true
end

function aliveworld.sites.cleanup_old_clues()
  local now = os.time()
  local removed = 0
  for id, m in pairs(clue_markers) do
    if now - m.placed_at > CLUE_MAX_AGE then
      local node = minetest.get_node(m.pos)
      if node.name ~= "air" then
        minetest.remove_node(m.pos)
      end
      clue_markers[id] = nil
      removed = removed + 1
    end
  end
  if removed > 0 then
    storage:set_string(CLUES_KEY, minetest.write_json(clue_markers))
  end
  return removed
end

-- Periodic cleanup
local function clue_cleanup_step()
  aliveworld.sites.cleanup_old_clues()
  minetest.after(CLUE_MAX_AGE, clue_cleanup_step)
end

-- Load clue marker positions and schedule cleanup
local function load_clue_markers()
  local raw = storage:get_string(CLUES_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      clue_markers = data
    end
  end
  minetest.after(CLUE_MAX_AGE, clue_cleanup_step)
end

load_clue_markers()

local function load_all()
  local raw = storage:get_string(SITES_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      sites = data
      return true
    end
  end
  return false
end

if not load_all() then
  minetest.log("action", "[aliveworld_core] no sites found in storage")
end

minetest.log("action", "[aliveworld_core] sites module loaded")
