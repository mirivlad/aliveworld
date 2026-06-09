-- world_events.lua
-- Persistent world events layer for AliveWorld
-- Events are generated from settlement state and environment conditions

local storage = minetest.get_mod_storage()

local EVENTS_KEY = "aliveworld_world_events"
local NEXT_ID_KEY = "aliveworld_world_events_next"
local COOLDOWN_KEY = "aliveworld_world_events_cd"

local events = {}
local next_id = 1
local cooldowns = {}

local MAX_EVENTS_PER_DAY = 3

local COOLDOWNS = {
  food_shortage = 15,
  dangerous_roads = 17,
  winter_hardship = 13,
  unrest = 15,
  trade_opportunity = 20,
  recovery = 10,
}

aliveworld.events = {}

function aliveworld.events.next_id()
  local n = next_id
  next_id = next_id + 1
  storage:set_string(NEXT_ID_KEY, tostring(next_id))
  return string.format("evt_%06d", n)
end

function aliveworld.events.list()
  local res = {}
  for _, ev in pairs(events) do
    table.insert(res, ev)
  end
  table.sort(res, function(a, b) return a.created_day < b.created_day end)
  return res
end

function aliveworld.events.get(id)
  return events[id]
end

function aliveworld.events.save(ev)
  events[ev.id] = ev
  storage:set_string(EVENTS_KEY, minetest.write_json(events))
end

function aliveworld.events.create(event_data)
  local id = aliveworld.events.next_id()
  local e = {
    id = id,
    type = event_data.type,
    severity = event_data.severity,
    settlement_id = event_data.settlement_id,
    faction_id = event_data.faction_id or "neutral_settlers",
    status = "active",
    created_day = event_data.created_day,
    expires_day = event_data.expires_day,
    resolved_day = nil,
    source = event_data.source or "generated",
    data = event_data.data or {},
    text_en = event_data.text_en,
    text_ru = event_data.text_ru,
  }
  events[id] = e
  storage:set_string(EVENTS_KEY, minetest.write_json(events))

  local cd_key = e.settlement_id .. ":" .. e.type
  cooldowns[cd_key] = e.created_day
  storage:set_string(COOLDOWN_KEY, minetest.write_json(cooldowns))

  aliveworld.add_event("world_event_created", string.format(
    "[%s] %s (day %d-%d, %s) %s",
    e.type, e.settlement_id, e.created_day, e.expires_day, e.severity, e.text_en
  ), {
    event_id = id,
    event_type = e.type,
    settlement_id = e.settlement_id,
    severity = e.severity,
  })

  return e
end

function aliveworld.events.resolve(id, reason)
  local e = events[id]
  if not e then
    return false, "Event not found: " .. id
  end
  if e.status ~= "active" then
    return false, "Event " .. id .. " is not active (status: " .. e.status .. ")"
  end
  e.status = "resolved"
  e.resolved_day = aliveworld.get_day()
  storage:set_string(EVENTS_KEY, minetest.write_json(events))

  local chronicle_msg = e.text_en
  if reason and reason ~= "" then
    chronicle_msg = chronicle_msg .. " (resolved: " .. reason .. ")"
  else
    chronicle_msg = chronicle_msg .. " (resolved)"
  end

  aliveworld.add_event("world_event_resolved", chronicle_msg, {
    event_id = id,
    event_type = e.type,
    settlement_id = e.settlement_id,
  })

  return true, "Event " .. id .. " resolved."
end

function aliveworld.events.expire_old(world_time)
  local total = world_time
  if type(world_time) == "table" then
    total = world_time.total_days
  end
  local expired_count = 0
  for _, e in pairs(events) do
    if e.status == "active" and total >= e.expires_day then
      e.status = "expired"
      e.resolved_day = total
      expired_count = expired_count + 1

      aliveworld.add_event("world_event_expired",
        e.text_en .. " (expired)",
        {event_id = e.id, event_type = e.type, settlement_id = e.settlement_id}
      )
    end
  end
  if expired_count > 0 then
    storage:set_string(EVENTS_KEY, minetest.write_json(events))
  end
  return expired_count
end

function aliveworld.events.has_active_event(settlement_id, event_type)
  for _, e in pairs(events) do
    if e.settlement_id == settlement_id and e.type == event_type and e.status == "active" then
      return true
    end
  end
  return false
end

function aliveworld.events.active_count()
  local n = 0
  for _, e in pairs(events) do
    if e.status == "active" then
      n = n + 1
    end
  end
  return n
end

-- Event generation rules

local function generate_for_settlement(s, world_time, env, old_status)
  local created = {}
  local total_days = world_time.total_days

  local function attempt(ev_type, condition_fn, severity_fn, expires_fn, data_fn, texts_en, texts_ru)
    if #created >= MAX_EVENTS_PER_DAY then
      return
    end
    if not condition_fn() then
      return
    end
    if aliveworld.events.has_active_event(s.id, ev_type) then
      return
    end

    local cd_key = s.id .. ":" .. ev_type
    local last_day = cooldowns[cd_key]
    local cd = COOLDOWNS[ev_type] or 10
    if last_day and total_days - last_day < cd then
      return
    end

    if math.random() > 0.5 then
      return
    end

    local severity = severity_fn()
    local text_en = texts_en[severity] or texts_en.minor
    local text_ru = texts_ru[severity] or texts_ru.minor

    local e = aliveworld.events.create({
      type = ev_type,
      severity = severity,
      settlement_id = s.id,
      faction_id = s.faction_id,
      created_day = total_days,
      expires_day = total_days + expires_fn(),
      source = "settlement_tick",
      data = data_fn(),
      text_en = text_en:format(s.id),
      text_ru = text_ru:format(s.name),
    })
    table.insert(created, e.id)

    if aliveworld.rumors and aliveworld.rumors.create_from_event then
      aliveworld.rumors.create_from_event(e)
    end
  end

  attempt("food_shortage",
    function() return s.food < 35 end,
    function()
      if s.food < 15 then return "severe" end
      if s.food < 25 then return "moderate" end
      return "minor"
    end,
    function() return 10 end,
    function() return {food = s.food} end,
    {minor = "%s is running short on food.", moderate = "%s is facing a significant food shortage.", severe = "%s is starving."},
    {minor = "%s начал испытывать нехватку еды.", moderate = "%s столкнулся с серьёзной нехваткой еды.", severe = "%s голодает."}
  )

  attempt("dangerous_roads",
    function() return s.safety < 45 end,
    function()
      if s.safety < 20 then return "severe" end
      if s.safety < 35 then return "moderate" end
      return "minor"
    end,
    function() return 12 end,
    function() return {safety = s.safety, danger = env.danger.level} end,
    {minor = "Travelers report dangers near %s.", moderate = "Roads around %s have become dangerous.", severe = "%s is besieged by hostiles."},
    {minor = "Путники сообщают об опасностях близ %s.", moderate = "Дороги вокруг %s стали опасными.", severe = "%s осаждён враждебными существами."}
  )

  attempt("winter_hardship",
    function() return env.season.key == "winter" and s.wood < 35 end,
    function()
      if s.wood < 15 then return "severe" end
      if s.wood < 25 then return "moderate" end
      return "minor"
    end,
    function() return 8 end,
    function() return {wood = s.wood, season = env.season.key} end,
    {minor = "%s is struggling with the winter cold.", moderate = "%s is running out of firewood in winter.", severe = "%s is freezing."},
    {minor = "%s с трудом переносит зимний холод.", moderate = "В %s заканчиваются дрова зимой.", severe = "%s замерзает."}
  )

  attempt("unrest",
    function() return s.mood < -40 end,
    function()
      if s.mood < -70 then return "severe" end
      if s.mood < -55 then return "moderate" end
      return "minor"
    end,
    function() return 10 end,
    function() return {mood = s.mood} end,
    {minor = "There is growing discontent in %s.", moderate = "Unrest is spreading in %s.", severe = "%s is on the brink of chaos."},
    {minor = "В %s растёт недовольство.", moderate = "В %s распространяются волнения.", severe = "%s находится на грани хаоса."}
  )

  attempt("trade_opportunity",
    function() return s.prosperity > 40 and s.food > 50 and s.safety > 50 end,
    function()
      if s.prosperity > 70 then return "moderate" end
      return "minor"
    end,
    function() return 15 end,
    function() return {prosperity = s.prosperity, food = s.food, safety = s.safety} end,
    {minor = "Merchants report good trade prospects in %s.", moderate = "%s has become a thriving trade hub."},
    {minor = "Купцы сообщают о хороших торговых перспективах в %s.", moderate = "%s стал процветающим торговым центром."}
  )

  if old_status and old_status ~= "stable" and s.status == "stable" then
    attempt("recovery",
      function() return true end,
      function() return "minor" end,
      function() return 5 end,
      function() return {old_status = old_status, new_status = s.status} end,
      {minor = "%s has recovered and is stable again."},
      {minor = "%s оправился и снова стабилен."}
    )
  end

  return created
end

function aliveworld.events.generate_from_settlement(settlement, world_time, env)
  return generate_for_settlement(settlement, world_time, env, nil)
end

function aliveworld.events.tick(world_time, env, old_statuses)
  local all_created = {}
  local list = aliveworld.settlements.list()
  for _, s in ipairs(list) do
    local old_status = old_statuses and old_statuses[s.id]
    local created = generate_for_settlement(s, world_time, env, old_status)
    for _, id in ipairs(created) do
      table.insert(all_created, id)
    end
  end
  return all_created
end

function aliveworld.events.reset()
  events = {}
  next_id = 1
  cooldowns = {}
  storage:set_string(EVENTS_KEY, minetest.write_json({}))
  storage:set_string(NEXT_ID_KEY, "1")
  storage:set_string(COOLDOWN_KEY, minetest.write_json({}))
end

-- Load from storage

local function load_all()
  local raw = storage:get_string(EVENTS_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data and next(data) then
      events = data
    end
  end
  local raw_id = storage:get_string(NEXT_ID_KEY)
  if raw_id and raw_id ~= "" then
    next_id = tonumber(raw_id) or 1
  end
  local raw_cd = storage:get_string(COOLDOWN_KEY)
  if raw_cd and raw_cd ~= "" then
    local ok, data = pcall(minetest.parse_json, raw_cd)
    if ok and data and next(data) then
      cooldowns = data
    end
  end
end

load_all()

minetest.log("action", "[aliveworld_core] world events module loaded")
