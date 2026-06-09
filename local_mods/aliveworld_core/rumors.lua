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
