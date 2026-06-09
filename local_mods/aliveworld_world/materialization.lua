-- materialization.lua
-- Physical marker placement and registry for AliveWorld

local storage = minetest.get_mod_storage()
local MARKERS_KEY = "aliveworld_markers"

local markers = {}

aliveworld.materialization = {}

local function save_all()
  storage:set_string(MARKERS_KEY, minetest.write_json(markers))
end

function aliveworld.materialization.list()
  local res = {}
  for _, m in pairs(markers) do
    table.insert(res, m)
  end
  table.sort(res, function(a, b) return (a.id or "") < (b.id or "") end)
  return res
end

function aliveworld.materialization.get(id)
  return markers[id]
end

function aliveworld.materialization.save(marker)
  markers[marker.id] = marker
  save_all()
end

function aliveworld.materialization.find_by_event(event_id)
  for _, m in pairs(markers) do
    if m.event_id == event_id then
      return m
    end
  end
  return nil
end

function aliveworld.materialization.find_by_site(site_id)
  for _, m in pairs(markers) do
    if m.site_id == site_id then
      return m
    end
  end
  return nil
end

local function make_marker_id()
  local n = 0
  for _ in pairs(markers) do
    n = n + 1
  end
  return "marker_" .. (n + 1)
end

local function find_ground(pos, search_radius)
  search_radius = search_radius or 16
  local start_y = pos.y
  for dy = 0, search_radius do
    local test_y = start_y + dy
    local below = minetest.get_node({x = pos.x, y = test_y - 1, z = pos.z})
    local current = minetest.get_node({x = pos.x, y = test_y, z = pos.z})
    local above = minetest.get_node({x = pos.x, y = test_y + 1, z = pos.z})
    if below and current and above then
      local bn = below.name
      local cn = current.name
      local an = above.name
      local is_solid_below = (bn ~= "air" and bn ~= "ignore" and bn ~= "mcl_core:water_source"
        and bn ~= "mcl_core:water_flowing" and bn ~= "mcl_core:lava_source"
        and bn ~= "mcl_core:lava_flowing")
      local is_air_current = (cn == "air" or cn == "mcl_flowers:tallgrass" or cn == "mcl_flowers:double_grass")
      local is_air_above = (an == "air" or an:find("mcl_flowers:") or an:find("mcl_core:snow"))
      if is_solid_below and is_air_current and is_air_above then
        return {x = pos.x, y = test_y, z = pos.z}
      end
    end
  end
  for dy = 0, search_radius do
    local test_y = start_y - dy
    local below = minetest.get_node({x = pos.x, y = test_y - 1, z = pos.z})
    local current = minetest.get_node({x = pos.x, y = test_y, z = pos.z})
    local above = minetest.get_node({x = pos.x, y = test_y + 1, z = pos.z})
    if below and current and above then
      local bn = below.name
      local cn = current.name
      local an = above.name
      local is_solid_below = (bn ~= "air" and bn ~= "ignore" and bn ~= "mcl_core:water_source"
        and bn ~= "mcl_core:water_flowing" and bn ~= "mcl_core:lava_source"
        and bn ~= "mcl_core:lava_flowing")
      local is_air_current = (cn == "air" or cn == "mcl_flowers:tallgrass")
      local is_air_above = (an == "air" or an:find("mcl_flowers:"))
      if is_solid_below and is_air_current and is_air_above then
        return {x = pos.x, y = test_y, z = pos.z}
      end
    end
  end
  return nil
end

local function get_node_name_for_event(event_type)
  local table = {
    food_shortage = "aliveworld_world:supply_crate",
    dangerous_roads = "aliveworld_world:road_warning_sign",
    winter_hardship = "aliveworld_world:camp_marker",
    unrest = "aliveworld_world:notice_stake",
    trade_opportunity = "aliveworld_world:supply_crate",
    recovery = "aliveworld_world:notice_stake",
  }
  return table[event_type] or "aliveworld_world:notice_stake"
end

function aliveworld.materialization.can_materialize_site(site)
  if not site then
    return false, "No site provided"
  end
  if site.physical_status == "anchored" or site.physical_status == "materialized" then
    return false, "Site already has physical marker"
  end
  if site.status ~= "active" then
    return false, "Site is not active"
  end
  return true
end

function aliveworld.materialization.materialize_site(site)
  local ok, err = aliveworld.materialization.can_materialize_site(site)
  if not ok then
    return false, err or "Cannot materialize"
  end

  local target_pos = site.anchor_pos or site.pos
  local ground_pos = find_ground(target_pos)
  if not ground_pos then
    return false, "Could not find safe ground near site. Area may not be loaded."
  end

  local node_name = "aliveworld_world:settlement_marker"
  if site.type == "event" then
    node_name = get_node_name_for_event(site.subtype)
  end

  local current = minetest.get_node(ground_pos)
  if current.name ~= "air" and not (current.name:find("mcl_flowers:")) then
    return false, "Position is not empty: " .. current.name
  end

  minetest.set_node(ground_pos, {name = node_name})

  local mid = make_marker_id()
  local marker = {
    id = mid,
    site_id = site.id,
    event_id = site.event_id,
    type = site.subtype,
    status = "placed",
    pos = {x = ground_pos.x, y = ground_pos.y, z = ground_pos.z},
    created_day = site.created_day,
    expires_day = site.expires_day,
    nodes = {
      {pos = {x = ground_pos.x, y = ground_pos.y, z = ground_pos.z}, new_node = node_name},
    },
  }
  markers[mid] = marker
  save_all()

  local meta = minetest.get_meta(ground_pos)
  meta:set_string("aliveworld_marker_id", mid)
  meta:set_string("infotext", "AliveWorld: " .. (site.name_en or site.name))

  if aliveworld.sites and aliveworld.sites.anchor_site then
    aliveworld.sites.anchor_site(site.id, ground_pos, mid)
  end

  minetest.log("action", "[aliveworld_world] materialized site " .. site.id .. " at " ..
    ground_pos.x .. "," .. ground_pos.y .. "," .. ground_pos.z)

  return true, marker
end

function aliveworld.materialization.materialize_event(event)
  if not event or not event.id then
    return false, "Invalid event"
  end
  local site = nil
  if aliveworld.sites and aliveworld.sites.find_by_event then
    site = aliveworld.sites.find_by_event(event.id)
  end
  if not site then
    return false, "No site found for event " .. event.id
  end
  return aliveworld.materialization.materialize_site(site)
end

function aliveworld.materialization.materialize_near_player(player_name, radius)
  radius = radius or 256
  local player = minetest.get_player_by_name(player_name)
  if not player then
    return false, "Player not found: " .. player_name, 0
  end
  local pos = player:get_pos()
  if not pos then
    return false, "Cannot get player position", 0
  end
  local from = {x = pos.x, y = pos.y, z = pos.z}
  local sites = {}
  if aliveworld.sites and aliveworld.sites.list then
    sites = aliveworld.sites.list()
  end
  local created = {}
  for _, s in ipairs(sites) do
    if s.status == "active" and (s.physical_status or "abstract") == "abstract" then
      local dist = aliveworld.sites.distance(from, s.pos)
      if dist <= radius then
        local ok, result = aliveworld.materialization.materialize_site(s)
        if ok then
          table.insert(created, s.id)
        end
      end
    end
  end
  return true, "Materialized " .. #created .. " sites near " .. player_name, #created
end

function aliveworld.materialization.cleanup_expired(world_time)
  local total = world_time
  if type(world_time) == "table" then
    total = world_time.total_days
  end
  local expired_count = 0
  for _, m in pairs(markers) do
    if m.status == "placed" and m.expires_day and total >= m.expires_day then
      m.status = "expired"
      expired_count = expired_count + 1
    end
  end
  if expired_count > 0 then
    save_all()
  end
  return expired_count
end

function aliveworld.materialization.reset()
  markers = {}
  save_all()
end

function aliveworld.materialization.count()
  local n = 0
  for _ in pairs(markers) do
    n = n + 1
  end
  return n
end

-- Load

local function load_all()
  local raw = storage:get_string(MARKERS_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      markers = data
      return true
    end
  end
  return false
end

if not load_all() then
  minetest.log("action", "[aliveworld_world] no markers found in storage")
end

minetest.log("action", "[aliveworld_world] materialization module loaded")
