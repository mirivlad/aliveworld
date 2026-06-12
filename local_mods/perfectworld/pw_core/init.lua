perfectworld = rawget(_G, "perfectworld") or {}
_G.perfectworld = perfectworld

local HASH_MOD = 2147483647
local DEFAULT_REGION_SIZE = 1024

local function setting_int(name, default)
  local raw = minetest.settings:get(name)
  local value = tonumber(raw)
  if not value or value < 1 then
    return default
  end
  return math.floor(value)
end

local function deep_copy(value)
  if type(value) ~= "table" then
    return value
  end
  local copy = {}
  for k, v in pairs(value) do
    copy[k] = deep_copy(v)
  end
  return copy
end

local function stable_hash(value)
  local text = tostring(value)
  local hash = 5381
  for i = 1, #text do
    hash = (hash * 131 + text:byte(i) + i * 17) % HASH_MOD
  end
  return hash
end

local function to_base36(num)
  local alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
  num = math.floor(math.abs(tonumber(num) or 0))
  if num == 0 then
    return "0"
  end
  local out = {}
  while num > 0 do
    local index = (num % 36) + 1
    table.insert(out, 1, alphabet:sub(index, index))
    num = math.floor(num / 36)
  end
  return table.concat(out)
end

perfectworld.VERSION = "0.1.0"
perfectworld.PLANNER_VERSION = 1
perfectworld.REGION_SIZE = setting_int("perfectworld.region_size", DEFAULT_REGION_SIZE)
perfectworld.settings = {
  region_size = perfectworld.REGION_SIZE,
}

perfectworld.world_seed_string = tostring(minetest.get_mapgen_setting("seed")
  or minetest.settings:get("fixed_map_seed")
  or "0")
perfectworld.world_seed = tonumber(perfectworld.world_seed_string)

perfectworld.core = perfectworld.core or {}
perfectworld.core.deep_copy = deep_copy
perfectworld.core.stable_hash = stable_hash
perfectworld.core.to_base36 = to_base36

function perfectworld.get_version()
  return perfectworld.VERSION
end

function perfectworld.get_region_coords(pos)
  local rx = math.floor(pos.x / perfectworld.REGION_SIZE)
  local rz = math.floor(pos.z / perfectworld.REGION_SIZE)
  return rx, rz
end

function perfectworld.get_region_id(rx, rz)
  return perfectworld.core.stable_id("region", rx, rz)
end

function perfectworld.core.stable_id(prefix, ...)
  local parts = {
    perfectworld.world_seed_string,
    tostring(perfectworld.PLANNER_VERSION),
    tostring(perfectworld.REGION_SIZE),
  }
  for i = 1, select("#", ...) do
    table.insert(parts, tostring(select(i, ...)))
  end
  return prefix .. "_" .. to_base36(stable_hash(table.concat(parts, "|")))
end

function perfectworld.region_seed(rx, rz, planner_version)
  planner_version = planner_version or perfectworld.PLANNER_VERSION
  return stable_hash(table.concat({
    "seed", perfectworld.world_seed_string,
    "rx", tostring(rx),
    "rz", tostring(rz),
    "planner", tostring(planner_version),
    "region_size", tostring(perfectworld.REGION_SIZE),
  }, "|"))
end

perfectworld.planner = {}
perfectworld.structures = {}
perfectworld.roads = {}
perfectworld.settlements = {}

minetest.log("action", "[pw_core] loaded")
