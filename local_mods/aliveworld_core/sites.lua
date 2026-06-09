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
  local angle = math.deg(math.atan2(dz, dx))
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
  return sites[id]
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
      local dist = aliveworld.sites.distance(from_pos, s.pos)
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
        local dist = aliveworld.sites.distance(from_pos, s.pos)
        local dir = aliveworld.sites.direction_name_ru(from_pos, s.pos)
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
  local dist = aliveworld.sites.distance(from_pos, site.pos)
  local dir = aliveworld.sites.direction_name_ru(from_pos, site.pos)
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
    local dist = aliveworld.sites.distance(from_pos, s.pos)
    local dir = aliveworld.sites.direction_name_ru(from_pos, s.pos)
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
