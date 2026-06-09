local DAYS_PER_MONTH = 30
local MONTHS_PER_YEAR = 12
local MAX_EVENTS = 1000

local MONTH_NAMES_GEN_RU = {
  "Месяц Пробуждения",
  "Месяц Роста",
  "Месяц Цветения",
  "Месяц Солнца",
  "Месяц Плодов",
  "Месяц Урожая",
  "Месяц Ветра",
  "Месяц Туманов",
  "Месяц Дождей",
  "Месяц Листопада",
  "Месяц Стужи",
  "Месяц Тихого Сна",
}

local MONTH_NAMES_GEN_EN = {
  "Month of Awakening",
  "Month of Growth",
  "Month of Blossom",
  "Month of Sun",
  "Month of Fruits",
  "Month of Harvest",
  "Month of Wind",
  "Month of Fog",
  "Month of Rain",
  "Month of Leaffall",
  "Month of Cold",
  "Month of Quiet Sleep",
}

local state = {
  day = 1,
  month = 1,
  year = 1,
  total_days = 1,
  tick_interval = 120,
  paused = false,
  next_event_id = 1,
  events = {},
}

local storage = minetest.get_mod_storage()

local function save()
  storage:set_string("aliveworld", minetest.write_json({
    day = state.day,
    month = state.month,
    year = state.year,
    total_days = state.total_days,
    tick_interval = state.tick_interval,
    paused = state.paused,
    next_event_id = state.next_event_id,
    events = state.events,
  }))
end

local function load()
  local raw = storage:get_string("aliveworld")
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data then
      state.day = data.day or 1
      state.month = data.month or 1
      state.year = data.year or 1
      state.total_days = data.total_days or 1
      state.tick_interval = data.tick_interval or 120
      state.paused = data.paused or false
      state.next_event_id = data.next_event_id or 1
      state.events = data.events or {}
      return
    end
  end

  local old_day = storage:get_int("world_day")
  if old_day > 0 then
    state.total_days = old_day
    local old_chronicle = storage:get_string("chronicle")
    if old_chronicle ~= "" then
      for line in old_chronicle:gmatch("[^\n]+") do
        local ts, msg = line:match("^(%S+) | (.+)$")
        if ts and msg then
          table.insert(state.events, {
            id = state.next_event_id,
            day = 0, month = 0, year = 0, total_day = 0,
            wall_time = ts,
            type = "migrated",
            message = msg,
          })
          state.next_event_id = state.next_event_id + 1
        end
      end
    end
    storage:set_string("world_day", "")
    storage:set_string("chronicle", "")
  else
    table.insert(state.events, {
      id = state.next_event_id,
      day = 1, month = 1, year = 1, total_day = 1,
      wall_time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
      type = "genesis",
      message = "Day 1: World awoke.",
    })
    state.next_event_id = state.next_event_id + 1
  end
  save()
end

local function add_event(type_, message, extra)
  local ev = {
    id = state.next_event_id,
    day = state.day,
    month = state.month,
    year = state.year,
    total_day = state.total_days,
    wall_time = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    type = type_,
    message = message,
  }
  if extra then
    ev.data = extra
  end
  table.insert(state.events, ev)
  state.next_event_id = state.next_event_id + 1
  if #state.events > MAX_EVENTS then
    local n = #state.events - MAX_EVENTS
    for _ = 1, n do
      table.remove(state.events, 1)
    end
  end
  save()
end

local function advance()
  state.total_days = state.total_days + 1
  state.day = state.day + 1
  if state.day > DAYS_PER_MONTH then
    state.day = 1
    state.month = state.month + 1
    if state.month > MONTHS_PER_YEAR then
      state.month = 1
      state.year = state.year + 1
    end
  end
end

aliveworld = rawget(_G, "aliveworld") or {}
_G.aliveworld = aliveworld

function aliveworld.get_day()
  return state.total_days
end

function aliveworld.get_date()
  return {
    day = state.day,
    month = state.month,
    year = state.year,
    total_days = state.total_days,
    month_name = MONTH_NAMES_GEN_RU[state.month],
    month_name_en = MONTH_NAMES_GEN_EN[state.month],
  }
end

function aliveworld.get_events(n)
  n = math.min(n or 10, #state.events)
  local res = {}
  for i = #state.events - n + 1, #state.events do
    table.insert(res, state.events[i])
  end
  return res
end

function aliveworld.add_event(type_, message, extra)
  add_event(type_, message, extra)
end

function aliveworld.tick()
  if state.paused then
    return false, "Simulation paused"
  end
  advance()
  add_event("tick", string.format("Day %d: world lives and develops.", state.total_days))

  if aliveworld.bridge and aliveworld.bridge.get_environment_profile then
    local env = aliveworld.bridge.get_environment_profile(aliveworld.get_date())
    add_event("environment_tick",
      string.format("Day %d: season=%s food=%s wood=%s danger=%s",
        state.total_days, env.season.key, env.food.key, env.wood.key, env.danger.key),
      env)

    if aliveworld.settlements and aliveworld.settlements.tick_all then
      aliveworld.settlements.tick_all(aliveworld.get_date(), env)
    end
  end

  return true, string.format("day %d, month %d, year %d (total: %d)",
    state.day, state.month, state.year, state.total_days)
end

function aliveworld.is_paused()
  return state.paused
end

function aliveworld.set_paused(val)
  state.paused = val
  save()
end

function aliveworld.get_config()
  return {
    tick_interval = state.tick_interval,
    days_per_month = DAYS_PER_MONTH,
    months_per_year = MONTHS_PER_YEAR,
    paused = state.paused,
    total_days = state.total_days,
  }
end

function aliveworld.set_config(key, value)
  if key == "tick_interval" then
    state.tick_interval = tonumber(value) or state.tick_interval
    save()
    return true
  end
  return false
end

load()

dofile(minetest.get_modpath("aliveworld_core") .. "/settlements.lua")

local function tick_loop()
  if not state.paused then
    local ok, msg = aliveworld.tick()
    if ok then
      minetest.log("action", "[aliveworld_core] auto-tick: " .. msg)
    end
  end
  minetest.after(state.tick_interval, tick_loop)
end

minetest.after(state.tick_interval, tick_loop)

function aliveworld.reset(clear_history)
  state.day = 1
  state.month = 1
  state.year = 1
  state.total_days = 1
  if clear_history then
    state.events = {}
    state.next_event_id = 1
  end
  add_event("dev_time_reset",
    "Day 1, month 1, year 1: AliveWorld time reset by administrator.")
  minetest.set_timeofday(0.23)
  save()
end

minetest.register_chatcommand("aw_tick_reset", {
  params = "[confirm] [--clear-history]",
  description = "Reset AliveWorld calendar (date/ticks only)",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "WARNING: will reset AliveWorld calendar. Use /aw_tick_reset confirm"
    end
    if param == "confirm" then
      aliveworld.reset(false)
      return true, "AliveWorld calendar reset. /aw_status to verify."
    end
    if param == "confirm --clear-history" then
      aliveworld.reset(true)
      return true, "AliveWorld calendar and history reset. /aw_status to verify."
    end
    return false, "Unknown parameter. Use /aw_tick_reset confirm (or confirm --clear-history)"
  end,
})

minetest.register_chatcommand("aw_day", {
  description = "Show current date",
  privs = {interact = true},
  func = function()
    local d = aliveworld.get_date()
    return true, string.format("Day %d, month %d, year %d (total days: %d)",
      d.day, d.month, d.year, d.total_days)
  end,
})

minetest.register_chatcommand("aw_time", {
  description = "Show calendar time",
  privs = {interact = true},
  func = function()
    local d = aliveworld.get_date()
    return true, string.format("Day %d, %s, year %d — day %d since dawn",
      d.day, d.month_name_en, d.year, d.total_days)
  end,
})

minetest.register_chatcommand("aw_chronicle", {
  description = "Show latest events (default 10, e.g. /aw_chronicle 20). /aw_chronicle raw for full JSON",
  privs = {interact = true},
  func = function(_, param)
    if param and param:lower() == "raw" then
      return true, minetest.write_json(aliveworld.get_events(#state.events))
    end
    local n = tonumber(param) or 10
    local events = aliveworld.get_events(n)
    if #events == 0 then
      return true, "Chronicle is empty."
    end
    local lines = {}
    for _, ev in ipairs(events) do
      table.insert(lines, string.format(
        "[%s] day %d (%d.%d.%d) [%s] %s",
        ev.wall_time, ev.total_day, ev.day, ev.month, ev.year, ev.type, ev.message
      ))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_history", {
  description = "Show chronicle (alias for /aw_chronicle)",
  privs = {interact = true},
  func = function(_, param)
    return minetest.registered_chatcommands["aw_chronicle"].func(_, param)
  end,
})

minetest.register_chatcommand("aw_tick", {
  description = "Force simulation tick",
  privs = {server = true},
  func = function()
    local ok, msg = aliveworld.tick()
    if not ok then
      return false, msg
    end
    return true, "Simulation: " .. msg
  end,
})

minetest.register_chatcommand("aw_pause", {
  description = "Pause auto-tick simulation",
  privs = {server = true},
  func = function()
    if aliveworld.is_paused() then
      return false, "Simulation is already paused."
    end
    aliveworld.set_paused(true)
    return true, "Simulation paused. /aw_resume to resume."
  end,
})

minetest.register_chatcommand("aw_resume", {
  description = "Resume auto-tick simulation",
  privs = {server = true},
  func = function()
    if not aliveworld.is_paused() then
      return false, "Simulation is already running."
    end
    aliveworld.set_paused(false)
    return true, "Simulation resumed."
  end,
})

minetest.register_chatcommand("aw_config", {
  description = "Show or set config (/aw_config tick_interval=60)",
  privs = {server = true},
  func = function(_, param)
    if param and param ~= "" then
      local key, value = param:match("(%w+)=(.+)")
      if key and value then
        local ok = aliveworld.set_config(key, value)
        if ok then
          return true, "Config updated: " .. key .. " = " .. value
        end
        return false, "Unknown config key: " .. key
      end
      return false, "Format: /aw_config key=value"
    end
    local c = aliveworld.get_config()
    return true, string.format(
      "Tick interval: %ds | Days per month: %d | Months per year: %d | Total days: %d | Paused: %s",
      c.tick_interval, c.days_per_month, c.months_per_year,
      c.total_days, (c.paused and "yes" or "no")
    )
  end,
})

minetest.register_chatcommand("aw_settlements", {
  params = "",
  description = "List all settlements",
  privs = {server = true},
  func = function()
    local list = aliveworld.settlements.list()
    if #list == 0 then
      return true, "No settlements. Use /aw_settlement_init to create."
    end
    local lines = {}
    table.insert(lines, string.format("%-20s %-10s %-8s %-5s %-5s %-5s %-6s %-12s",
      "Name", "Kind", "Pop", "Food", "Wood", "Safe", "Mood", "Status"))
    table.insert(lines, string.rep("-", 80))
    for _, s in ipairs(list) do
      table.insert(lines, string.format("%-20s %-10s %-8d %-5d %-5d %-5d %-6d %-12s",
        s.name, s.kind, s.population, s.food, s.wood, s.safety, s.mood, s.status))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_settlement", {
  params = "<id>",
  description = "Show detailed information about a settlement",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_settlement <id>"
    end
    local s = aliveworld.settlements.get(param)
    if not s then
      return false, "Settlement not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Settlement: %s (%s)", s.name, s.id))
    table.insert(lines, string.format("Kind: %s", s.kind))
    table.insert(lines, string.format("Population: %d", s.population))
    table.insert(lines, string.format("Food: %d/100", s.food))
    table.insert(lines, string.format("Wood: %d/100", s.wood))
    table.insert(lines, string.format("Safety: %d/100", s.safety))
    table.insert(lines, string.format("Mood: %d", s.mood))
    table.insert(lines, string.format("Prosperity: %d/100", s.prosperity))
    table.insert(lines, string.format("Faction: %s", s.faction_id))
    table.insert(lines, string.format("Status: %s", s.status))
    table.insert(lines, string.format("Created: day %d", s.created_day))
    table.insert(lines, string.format("Last tick: day %d", s.last_tick_day))
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_settlement_init", {
  params = "",
  description = "Create initial settlements",
  privs = {server = true},
  func = function()
    local ok, msg = aliveworld.settlements.ensure_initial()
    return ok, msg
  end,
})

minetest.register_chatcommand("aw_settlement_tick", {
  params = "",
  description = "Force settlement simulation tick",
  privs = {server = true},
  func = function()
    if not aliveworld.bridge or not aliveworld.bridge.get_environment_profile then
      return false, "No bridge module loaded"
    end
    local d = aliveworld.get_date()
    local env = aliveworld.bridge.get_environment_profile(d)
    aliveworld.settlements.tick_all(d, env)
    return true, "Settlement tick complete."
  end,
})

minetest.register_chatcommand("aw_settlement_reset", {
  params = "[confirm]",
  description = "Delete all settlements and recreate initial ones",
  privs = {server = true},
  func = function(_, param)
    if not param or param ~= "confirm" then
      return false, "WARNING: this will delete all settlement data. Use /aw_settlement_reset confirm"
    end
    local ok, msg = aliveworld.settlements.reset_all()
    return ok, msg
  end,
})

minetest.log("action", "[aliveworld_core] loaded")
