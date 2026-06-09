local INITIAL_SETTLEMENTS = {
  {
    id = "birch_ford",
    name = "Берёзовый Брод",
    kind = "village",
    population = 32,
    food = 65,
    wood = 80,
    safety = 60,
    mood = 5,
    prosperity = 25,
    faction_id = "neutral_settlers",
    status = "stable",
  },
  {
    id = "stone_gully",
    name = "Каменная Балка",
    kind = "village",
    population = 18,
    food = 45,
    wood = 50,
    safety = 70,
    mood = 0,
    prosperity = 15,
    faction_id = "neutral_settlers",
    status = "stable",
  },
  {
    id = "old_road",
    name = "Старый Тракт",
    kind = "outpost",
    population = 9,
    food = 35,
    wood = 40,
    safety = 45,
    mood = -10,
    prosperity = 10,
    faction_id = "neutral_settlers",
    status = "stable",
  },
}

local function clamp(v, min, max)
  return math.max(min, math.min(max, v))
end

local function make_settlement(proto, total_days)
  return {
    id = proto.id,
    name = proto.name,
    kind = proto.kind,
    population = proto.population,
    food = proto.food,
    wood = proto.wood,
    safety = proto.safety,
    mood = proto.mood,
    prosperity = proto.prosperity,
    faction_id = proto.faction_id,
    status = proto.status,
    created_day = total_days,
    last_tick_day = total_days,
  }
end

local settlements_data = {}
aliveworld.settlements = {}

local storage = minetest.get_mod_storage()

function aliveworld.settlements.save_all()
  storage:set_string("aliveworld_settlements", minetest.write_json(settlements_data))
end

local function load_all()
  local raw = storage:get_string("aliveworld_settlements")
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      settlements_data = data
      return true
    end
  end
  return false
end

function aliveworld.settlements.list()
  local res = {}
  for _, s in pairs(settlements_data) do
    table.insert(res, s)
  end
  table.sort(res, function(a, b) return a.id < b.id end)
  return res
end

function aliveworld.settlements.get(id)
  return settlements_data[id]
end

function aliveworld.settlements.save(s)
  settlements_data[s.id] = s
  aliveworld.settlements.save_all()
end

function aliveworld.settlements.delete(id)
  settlements_data[id] = nil
  aliveworld.settlements.save_all()
end

function aliveworld.settlements.ensure_initial()
  local count = 0
  for _,_ in pairs(settlements_data) do
    count = count + 1
  end
  if count > 0 then
    return false, "Settlements already exist (" .. count .. " found)"
  end
  local d = aliveworld.get_date()
  for _, proto in ipairs(INITIAL_SETTLEMENTS) do
    settlements_data[proto.id] = make_settlement(proto, d.total_days)
  end
  aliveworld.settlements.save_all()
  minetest.log("action", "[aliveworld_core] initialized " .. #INITIAL_SETTLEMENTS .. " settlements")
  return true, "Initialized " .. #INITIAL_SETTLEMENTS .. " settlements"
end

function aliveworld.settlements.reset_all()
  settlements_data = {}
  aliveworld.settlements.save_all()
  aliveworld.add_event("settlement_reset", "All settlements have been reset by administrator.")
  return aliveworld.settlements.ensure_initial()
end

local function tick_one(s, world_time, env)
  local old_status = s.status

  local food_consumption = math.ceil(s.population / 5) + 1
  s.food = s.food - food_consumption

  local food_gain = math.floor(env.food.availability * 10)
  if s.population < 10 then
    food_gain = math.floor(food_gain * 1.5)
  end
  s.food = s.food + food_gain

  if env.season.key == "winter" then
    s.wood = s.wood - 2
  end

  local danger_effect = math.floor(env.danger.level * 3)
  s.safety = s.safety - danger_effect

  local mood_delta = 0
  if s.food < 20 then
    mood_delta = mood_delta - 5
  elseif s.food > 60 then
    mood_delta = mood_delta + 1
  end
  if s.safety < 30 then
    mood_delta = mood_delta - 3
  elseif s.safety > 70 then
    mood_delta = mood_delta + 1
  end
  mood_delta = mood_delta + math.floor(s.prosperity / 20)
  s.mood = s.mood + mood_delta

  if s.population >= 5 and old_status == "stable" then
    s.prosperity = s.prosperity + 1
  end

  s.food = clamp(s.food, 0, 100)
  s.wood = clamp(s.wood, 0, 100)
  s.safety = clamp(s.safety, 0, 100)
  s.mood = clamp(s.mood, -100, 100)
  s.prosperity = clamp(s.prosperity, 0, 100)

  local new_status = "stable"
  if s.population <= 0 then
    new_status = "abandoned"
  elseif s.mood < -50 then
    new_status = "struggling"
  elseif s.safety < 25 then
    new_status = "unsafe"
  elseif s.food < 20 then
    new_status = "hungry"
  end
  s.status = new_status
  s.last_tick_day = world_time.total_days

  if old_status ~= new_status then
    if new_status == "hungry" then
      aliveworld.add_event("settlement_hungry",
        "Settlement '" .. s.name .. "' is running out of food.",
        {settlement_id = s.id, status = new_status})
    elseif new_status == "unsafe" then
      aliveworld.add_event("settlement_unsafe",
        "Settlement '" .. s.name .. "' has become unsafe: guards cannot handle the threats.",
        {settlement_id = s.id, status = new_status})
    elseif new_status == "struggling" then
      aliveworld.add_event("settlement_struggling",
        "Settlement '" .. s.name .. "' is struggling to survive.",
        {settlement_id = s.id, status = new_status})
    elseif new_status == "abandoned" then
      aliveworld.add_event("settlement_abandoned",
        "Settlement '" .. s.name .. "' has been abandoned.",
        {settlement_id = s.id, status = new_status})
    elseif new_status == "stable" then
      aliveworld.add_event("settlement_recovered",
        "Settlement '" .. s.name .. "' has recovered and looks stable again.",
        {settlement_id = s.id, status = new_status})
    end
  end

  if new_status == "struggling" then
    s.population = math.max(0, s.population - 1)
  elseif new_status == "abandoned" then
    s.population = 0
  elseif new_status == "stable" and math.random() < 0.05 then
    s.population = s.population + 1
  end
end

function aliveworld.settlements.tick_all(world_time, env)
  for _, s in pairs(settlements_data) do
    tick_one(s, world_time, env)
  end
  aliveworld.settlements.save_all()
end

if not load_all() then
  local d = aliveworld.get_date()
  for _, proto in ipairs(INITIAL_SETTLEMENTS) do
    settlements_data[proto.id] = make_settlement(proto, d.total_days)
  end
  aliveworld.settlements.save_all()
  minetest.log("action", "[aliveworld_core] auto-initialized " .. #INITIAL_SETTLEMENTS .. " settlements")
end

minetest.log("action", "[aliveworld_core] settlements module loaded")
