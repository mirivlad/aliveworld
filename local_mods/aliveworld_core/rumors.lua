-- rumors.lua
-- Rumor layer for AliveWorld
-- Player-facing layer built on top of world events

local storage = minetest.get_mod_storage()

local RUMORS_KEY = "aliveworld_rumors"
local NEXT_ID_KEY = "aliveworld_rumors_next"

local rumors = {}
local next_id = 1

aliveworld.rumors = {}

function aliveworld.rumors.next_id()
  local n = next_id
  next_id = next_id + 1
  storage:set_string(NEXT_ID_KEY, tostring(next_id))
  return string.format("rumor_%06d", n)
end

function aliveworld.rumors.list()
  local res = {}
  for _, r in pairs(rumors) do
    table.insert(res, r)
  end
  table.sort(res, function(a, b) return a.created_day < b.created_day end)
  return res
end

function aliveworld.rumors.get(id)
  return rumors[id]
end

function aliveworld.rumors.save(r)
  rumors[r.id] = r
  storage:set_string(RUMORS_KEY, minetest.write_json(rumors))
end

function aliveworld.rumors.create_from_event(event)
  if not event or not event.id then
    return false, "Invalid event"
  end

  for _, r in pairs(rumors) do
    if r.event_id == event.id then
      return false, "Rumor already exists for event " .. event.id
    end
  end

  local id = aliveworld.rumors.next_id()
  local r = {
    id = id,
    event_id = event.id,
    settlement_id = event.settlement_id or "",
    status = "active",
    created_day = event.created_day,
    expires_day = (event.expires_day or event.created_day) + 3,
    text_en = event.text_en,
    text_ru = event.text_ru,
  }
  rumors[id] = r
  storage:set_string(RUMORS_KEY, minetest.write_json(rumors))
  return true, r
end

function aliveworld.rumors.expire_old(world_time)
  local total = world_time
  if type(world_time) == "table" then
    total = world_time.total_days
  end
  local expired_count = 0
  for _, r in pairs(rumors) do
    if r.status == "active" and total >= r.expires_day then
      r.status = "expired"
      expired_count = expired_count + 1
    end
  end
  if expired_count > 0 then
    storage:set_string(RUMORS_KEY, minetest.write_json(rumors))
  end
  return expired_count
end

-- Per-player rumor visit status
-- Stored in player meta as JSON: {[rumor_id] = "new"|"tracking"|"visited"|"verified"}
function aliveworld.rumors.get_player_status(player_name, rumor_id)
  if not player_name or not rumor_id then return "new" end
  local player = minetest.get_player_by_name(player_name)
  if not player then return "new" end
  local raw = player:get_meta():get_string("aliveworld_rumor_statuses")
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data then
      return data[rumor_id] or "new"
    end
  end
  return "new"
end

function aliveworld.rumors.set_player_status(player_name, rumor_id, status)
  if not player_name or not rumor_id then return end
  local player = minetest.get_player_by_name(player_name)
  if not player then return end
  local raw = player:get_meta():get_string("aliveworld_rumor_statuses")
  local data = {}
  if raw and raw ~= "" then
    local ok, d = pcall(minetest.parse_json, raw)
    if ok and d then data = d end
  end
  data[rumor_id] = status
  player:get_meta():set_string("aliveworld_rumor_statuses", minetest.write_json(data))
end

-- Update rumor status based on tracking state (called periodically)
function aliveworld.rumors.sync_status_from_tracking(player_name)
  if not player_name then return end
  if not aliveworld.tracking then return end

  local track = aliveworld.tracking.get_active_track(player_name)
  if not track then return end

  -- Find which rumors are associated with the tracked site
  local site = track.site
  if not site or not site.event_id then return end

  local rumor_list = aliveworld.rumors.list()
  for _, r in ipairs(rumor_list) do
    if r.event_id == site.event_id then
      local current = aliveworld.rumors.get_player_status(player_name, r.id)
      if current == "new" then
        aliveworld.rumors.set_player_status(player_name, r.id, "tracking")
      end
      if track.has_arrived and current ~= "verified" then
        aliveworld.rumors.set_player_status(player_name, r.id, "visited")
      end
    end
  end
end

-- Get display label for rumor status
function aliveworld.rumors.get_status_label(status)
  local labels = {
    new = "[новый]",
    tracking = "[отслеживается]",
    visited = "[посещено]",
    verified = "[проверено]",
  }
  return labels[status] or ""
end

function aliveworld.rumors.reset()
  rumors = {}
  next_id = 1
  storage:set_string(RUMORS_KEY, minetest.write_json({}))
  storage:set_string(NEXT_ID_KEY, "1")
end

-- Load from storage

local function load_all()
  local raw = storage:get_string(RUMORS_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      rumors = data
    end
  end
  local raw_id = storage:get_string(NEXT_ID_KEY)
  if raw_id and raw_id ~= "" then
    next_id = tonumber(raw_id) or 1
  end
end

load_all()

minetest.log("action", "[aliveworld_core] rumors module loaded")
