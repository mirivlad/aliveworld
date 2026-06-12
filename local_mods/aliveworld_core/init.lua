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
    local d = aliveworld.get_date()
    local env = aliveworld.bridge.get_environment_profile(d)
    add_event("environment_tick",
      string.format("Day %d: season=%s food=%s wood=%s danger=%s",
        state.total_days, env.season.key, env.food.key, env.wood.key, env.danger.key),
      env)

    local old_statuses = {}
    if aliveworld.settlements and aliveworld.settlements.list then
      for _, s in ipairs(aliveworld.settlements.list()) do
        old_statuses[s.id] = s.status
      end
    end

    if aliveworld.settlements and aliveworld.settlements.tick_all then
      aliveworld.settlements.tick_all(d, env)
    end

    if aliveworld.events then
      aliveworld.events.expire_old(d)
    end
    if aliveworld.rumors then
      aliveworld.rumors.expire_old(d)
    end
    if aliveworld.sites and aliveworld.sites.expire_old then
      aliveworld.sites.expire_old(d)
    end
    if aliveworld.events and aliveworld.events.tick then
      local created = aliveworld.events.tick(d, env, old_statuses)
      if aliveworld.sites and aliveworld.sites.create_event_site and created then
        for _, ev_id in ipairs(created) do
          local ev = aliveworld.events.get(ev_id)
          if ev then
            aliveworld.sites.create_event_site(ev)
          end
        end
      end
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
dofile(minetest.get_modpath("aliveworld_core") .. "/terrain.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/sites.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/claims.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/job_runner.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/routes.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/route_materialization.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/world_events.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/rumors.lua")
dofile(minetest.get_modpath("aliveworld_core") .. "/tracking.lua")

if aliveworld.sites and aliveworld.sites.ensure_initial_settlement_sites then
  aliveworld.sites.ensure_initial_settlement_sites()
end

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
    table.insert(lines, string.format("%-20s %-10s %-8s %-5s %-5s %-5s %-6s %-12s %s",
      "Name", "Kind", "Pop", "Food", "Wood", "Safe", "Mood", "Status", "Site"))
    table.insert(lines, string.rep("-", 95))
    for _, s in ipairs(list) do
      local has_site = "no"
      if aliveworld.sites and aliveworld.sites.find_by_settlement then
        has_site = aliveworld.sites.find_by_settlement(s.id) and "yes" or "no"
      end
      table.insert(lines, string.format("%-20s %-10s %-8d %-5d %-5d %-5d %-6d %-12s %s",
        s.name, s.kind, s.population, s.food, s.wood, s.safety, s.mood, s.status, has_site))
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
    if aliveworld.sites and aliveworld.sites.find_by_settlement then
      local site = aliveworld.sites.find_by_settlement(s.id)
      if site then
        table.insert(lines, string.format("Site: %s at (%d,%d,%d) radius=%d",
          site.id, site.pos.x, site.pos.y, site.pos.z, site.radius))
      else
        table.insert(lines, "Site: none")
      end
    end
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

minetest.register_chatcommand("aw_settlement_set", {
  params = "<id> <field> <value>",
  description = "Set a settlement field for testing (food, wood, safety, mood, prosperity, population)",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_settlement_set <id> <field> <value>"
    end
    local id, field, value_str = param:match("^(%S+)%s+(%S+)%s+(%S+)$")
    if not id or not field or not value_str then
      return false, "Usage: /aw_settlement_set <id> <field> <value>"
    end
    local s = aliveworld.settlements.get(id)
    if not s then
      return false, "Settlement not found: " .. id
    end
    local allowed = {population = true, food = true, wood = true, safety = true, mood = true, prosperity = true}
    if not allowed[field] then
      return false, "Invalid field. Allowed: population, food, wood, safety, mood, prosperity"
    end
    local value = tonumber(value_str)
    if not value then
      return false, "Value must be a number"
    end
    if field == "population" then
      s.population = math.max(0, math.floor(value))
    elseif field == "food" then
      s.food = math.max(0, math.min(100, value))
    elseif field == "wood" then
      s.wood = math.max(0, math.min(100, value))
    elseif field == "safety" then
      s.safety = math.max(0, math.min(100, value))
    elseif field == "mood" then
      s.mood = math.max(-100, math.min(100, value))
    elseif field == "prosperity" then
      s.prosperity = math.max(0, math.min(100, value))
    end
    aliveworld.settlements.save(s)
    aliveworld.add_event("dev_settlement_modified",
      string.format("Dev: %s=%s for settlement %s", field, value_str, id),
      {settlement_id = id, field = field, value = value}
    )
    return true, string.format("Settlement %s: %s set to %s", id, field, value_str)
  end,
})

minetest.register_chatcommand("aw_events", {
  params = "",
  description = "List all active world events",
  privs = {server = true},
  func = function()
    if not aliveworld.events then
      return false, "Events module not loaded"
    end
    local list = aliveworld.events.list()
    if #list == 0 then
      return true, "No world events."
    end
    local lines = {}
    table.insert(lines, string.format("%-14s %-18s %-10s %-16s %-10s %-8s %s",
      "ID", "Type", "Severity", "Settlement", "Status", "Day", "Text"))
    table.insert(lines, string.rep("-", 100))
    for _, ev in ipairs(list) do
      if ev.status == "active" then
        table.insert(lines, string.format("%-14s %-18s %-10s %-16s %-10s %-8d %s",
          ev.id, ev.type, ev.severity, ev.settlement_id, ev.status, ev.created_day, ev.text_en))
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_event", {
  params = "<id>",
  description = "Show detailed information about a world event",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_event <id>"
    end
    if not aliveworld.events then
      return false, "Events module not loaded"
    end
    local ev = aliveworld.events.get(param)
    if not ev then
      return false, "Event not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Event: %s", ev.id))
    table.insert(lines, string.format("Type: %s (%s)", ev.type, ev.severity))
    table.insert(lines, string.format("Settlement: %s (%s)", ev.settlement_id, ev.faction_id))
    table.insert(lines, string.format("Status: %s", ev.status))
    table.insert(lines, string.format("Created: day %d", ev.created_day))
    table.insert(lines, string.format("Expires: day %d", ev.expires_day))
    if ev.resolved_day then
      table.insert(lines, string.format("Resolved: day %d", ev.resolved_day))
    end
    table.insert(lines, string.format("Source: %s", ev.source))
    table.insert(lines, string.format("Text: %s", ev.text_en))
    if ev.data and next(ev.data) then
      local data_lines = {}
      for k, v in pairs(ev.data) do
        table.insert(data_lines, k .. "=" .. tostring(v))
      end
      table.insert(lines, string.format("Data: %s", table.concat(data_lines, ", ")))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_event_tick", {
  params = "",
  description = "Force world event generation tick",
  privs = {server = true},
  func = function()
    if not aliveworld.events then
      return false, "Events module not loaded"
    end
    if not aliveworld.bridge or not aliveworld.bridge.get_environment_profile then
      return false, "No bridge module loaded"
    end
    local d = aliveworld.get_date()
    local env = aliveworld.bridge.get_environment_profile(d)

    local old_statuses = {}
    if aliveworld.settlements and aliveworld.settlements.list then
      for _, s in ipairs(aliveworld.settlements.list()) do
        old_statuses[s.id] = s.status
      end
    end

    aliveworld.events.expire_old(d)
    if aliveworld.rumors then
      aliveworld.rumors.expire_old(d)
    end
    local created = aliveworld.events.tick(d, env, old_statuses)
    if aliveworld.sites and aliveworld.sites.create_event_site and created then
      for _, ev_id in ipairs(created) do
        local ev = aliveworld.events.get(ev_id)
        if ev then
          aliveworld.sites.create_event_site(ev)
        end
      end
    end

    return true, string.format("Event generation tick complete. %d new events created.", #created)
  end,
})

minetest.register_chatcommand("aw_event_resolve", {
  params = "<id> [reason]",
  description = "Resolve a world event",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_event_resolve <id> [reason]"
    end
    local id, reason = param:match("^(%S+)%s+(.+)$")
    if not id then
      id = param
      reason = nil
    end
    if not aliveworld.events then
      return false, "Events module not loaded"
    end
    local ok, msg = aliveworld.events.resolve(id, reason)
    return ok, msg
  end,
})

minetest.register_chatcommand("aw_event_reset", {
  params = "[confirm]",
  description = "Delete all world events and rumors",
  privs = {server = true},
  func = function(_, param)
    if not param or param ~= "confirm" then
      return false, "WARNING: this will delete all world events and rumors. Use /aw_event_reset confirm"
    end
    if aliveworld.events and aliveworld.events.reset then
      aliveworld.events.reset()
    end
    if aliveworld.rumors and aliveworld.rumors.reset then
      aliveworld.rumors.reset()
    end
    aliveworld.add_event("dev_event_reset", "All world events and rumors have been reset by administrator.")
    return true, "All world events and rumors deleted."
  end,
})

minetest.register_chatcommand("aw_rumors", {
  params = "",
  description = "List all active rumors",
  privs = {server = true},
  func = function()
    if not aliveworld.rumors then
      return false, "Rumors module not loaded"
    end
    local list = aliveworld.rumors.list()
    if #list == 0 then
      return true, "No rumors."
    end
    local lines = {}
    table.insert(lines, string.format("%-14s %-14s %-16s %-10s %-8s %s",
      "ID", "Event", "Settlement", "Status", "Day", "Text"))
    table.insert(lines, string.rep("-", 90))
    for _, r in ipairs(list) do
      if r.status == "active" then
        table.insert(lines, string.format("%-14s %-14s %-16s %-10s %-8d %s",
          r.id, r.event_id, r.settlement_id, r.status, r.created_day, r.text_en))
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_rumor", {
  params = "<id>",
  description = "Show detailed information about a rumor",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_rumor <id>"
    end
    if not aliveworld.rumors then
      return false, "Rumors module not loaded"
    end
    local r = aliveworld.rumors.get(param)
    if not r then
      return false, "Rumor not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Rumor: %s", r.id))
    table.insert(lines, string.format("Event: %s", r.event_id))
    table.insert(lines, string.format("Settlement: %s", r.settlement_id))
    table.insert(lines, string.format("Status: %s", r.status))
    table.insert(lines, string.format("Created: day %d", r.created_day))
    table.insert(lines, string.format("Expires: day %d", r.expires_day))
    table.insert(lines, string.format("Text: %s", r.text_en))
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_sites", {
  params = "",
  description = "List all active sites",
  privs = {server = true},
  func = function()
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local list = aliveworld.sites.list()
    if #list == 0 then
      return true, "No sites."
    end
    local lines = {}
    table.insert(lines, string.format("%-20s %-12s %-12s %-16s %-12s %-10s %s",
      "ID", "Type", "Subtype", "Settlement/Event", "Status", "Pos", "Name"))
    table.insert(lines, string.rep("-", 100))
    for _, s in ipairs(list) do
      if s.status == "active" then
        local ref = s.settlement_id or s.event_id or ""
        table.insert(lines, string.format("%-20s %-12s %-12s %-16s %-12s (%d,%d,%d) %s",
          s.id, s.type, s.subtype, ref, s.status, s.pos.x, s.pos.y, s.pos.z, s.name_en))
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_site", {
  params = "<id>",
  description = "Show detailed site information",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_site <id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Site: %s", site.id))
    table.insert(lines, string.format("Name: %s / %s", site.name, site.name_en))
    table.insert(lines, string.format("Type: %s (%s)", site.type, site.subtype))
    if site.settlement_id then
      table.insert(lines, string.format("Settlement: %s", site.settlement_id))
    end
    if site.event_id then
      table.insert(lines, string.format("Event: %s", site.event_id))
    end
    table.insert(lines, string.format("Pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
    table.insert(lines, string.format("Radius: %d", site.radius))
    table.insert(lines, string.format("Status: %s", site.status))
    table.insert(lines, string.format("Created: day %d", site.created_day))
    if site.expires_day then
      table.insert(lines, string.format("Expires: day %d", site.expires_day))
    end
    if site.data and next(site.data) then
      local data_lines = {}
      for k, v in pairs(site.data) do
        table.insert(data_lines, k .. "=" .. tostring(v))
      end
      table.insert(lines, string.format("Data: %s", table.concat(data_lines, ", ")))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_sites_init", {
  params = "",
  description = "Create initial settlement sites if missing",
  privs = {server = true},
  func = function()
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local count = aliveworld.sites.ensure_initial_settlement_sites()
    if count > 0 then
      return true, "Created " .. count .. " settlement sites."
    end
    return true, "Settlement sites already exist."
  end,
})

minetest.register_chatcommand("aw_sites_reset", {
  params = "[confirm]",
  description = "Delete all sites and recreate initial settlement sites",
  privs = {server = true},
  func = function(_, param)
    if not param or param ~= "confirm" then
      return false, "WARNING: this will delete all AliveWorld sites. Use /aw_sites_reset confirm"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    aliveworld.sites.reset()
    local count = aliveworld.sites.ensure_initial_settlement_sites()
    return true, "Sites reset. Created " .. count .. " settlement sites."
  end,
})

minetest.register_chatcommand("aw_sites_near", {
  params = "<x> <y> <z> [limit]",
  description = "Show nearest active sites from position",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_sites_near <x> <y> <z> [limit]"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local x_str, y_str, z_str, limit_str = param:match("^(%S+)%s+(%S+)%s+(%S+)%s*(%S*)$")
    if not x_str or not y_str or not z_str then
      return false, "Usage: /aw_sites_near <x> <y> <z> [limit]"
    end
    local x = tonumber(x_str)
    local y = tonumber(y_str)
    local z = tonumber(z_str)
    if not x or not y or not z then
      return false, "Coordinates must be numbers"
    end
    local limit = limit_str and tonumber(limit_str) or 5
    if not limit or limit < 1 then
      return false, "Limit must be a positive number"
    end
    local from_pos = {x = x, y = y, z = z}
    local near = aliveworld.sites.nearest(from_pos, limit)
    if #near == 0 then
      return true, "No active sites near (" .. x .. "," .. y .. "," .. z .. ")."
    end
    local lines = {}
    table.insert(lines, string.format("Nearest %d active sites from (%d,%d,%d):", #near, x, y, z))
    table.insert(lines, "")
    for _, s in ipairs(near) do
      local dist = aliveworld.sites.distance(from_pos, s.pos)
      local dir = aliveworld.sites.direction_name_en(from_pos, s.pos)
      table.insert(lines, string.format("  %-20s %-10s dist=%-6d dir=%-12s (%d,%d,%d)",
        s.id, s.type, dist, dir, s.pos.x, s.pos.y, s.pos.z))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_site_debug", {
  params = "<site_id>",
  description = "Show detailed debug info for a site",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_site_debug <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("ID: %s", site.id))
    table.insert(lines, string.format("Name: %s / %s", site.name, site.name_en))
    table.insert(lines, string.format("Type: %s (%s)", site.type, site.subtype))
    table.insert(lines, string.format("Logical pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
    table.insert(lines, string.format("Physical status: %s", site.physical_status or "abstract"))
    if site.anchor_pos then
      table.insert(lines, string.format("Anchor pos: (%d,%d,%d)", site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z))
    else
      table.insert(lines, "Anchor pos: none")
    end
    table.insert(lines, string.format("Marker ID: %s", site.marker_id or "none"))
    table.insert(lines, string.format("Discovered: %s", tostring(site.discovered)))
    table.insert(lines, string.format("Radius: %d", site.radius))
    table.insert(lines, string.format("Status: %s", site.status))
    table.insert(lines, string.format("Settlement: %s", site.settlement_id or "none"))
    table.insert(lines, string.format("Event: %s", site.event_id or "none"))
    table.insert(lines, "")
    local players = minetest.get_connected_players()
    if #players > 0 then
      table.insert(lines, "Distances from players:")
      for _, p in ipairs(players) do
        local pname = p:get_player_name()
        local ppos = p:get_pos()
        if ppos then
          local from = {x = ppos.x, y = ppos.y, z = ppos.z}
          local dx = site.pos.x - from.x
          local dz = site.pos.z - from.z
          local dist = aliveworld.sites.distance(from, site.pos)
          local dir = aliveworld.sites.direction_name_en(from, site.pos)
          table.insert(lines, string.format("  %s: dist=%d dir=%s dx=%d dz=%d", pname, dist, dir, dx, dz))
        end
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

local function format_survey_summary(survey)
  if not survey then return "survey: none" end
  return string.format(
    "pos=(%d,%d,%d) surface=%s score=%.2f height=%d water=%d buildable=%.2f area=%.2f access=%.2f reasons=%s",
    survey.pos and survey.pos.x or 0,
    survey.pos and survey.pos.y or 0,
    survey.pos and survey.pos.z or 0,
    survey.surface_node or "unknown",
    survey.total_score or 0,
    survey.height_range or 0,
    survey.water_distance or -1,
    survey.buildable_ratio or 0,
    survey.area_score or 0,
    survey.accessibility_score or 0,
    table.concat(survey.rejections or {}, ",")
  )
end

minetest.register_chatcommand("aw_site_anchor", {
  params = "<site_id>",
  description = "Start terrain-aware anchor search for a site",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_site_anchor <site_id>"
    end
    if not aliveworld.sites or not aliveworld.sites.start_anchor_site then
      return false, "Site anchoring API not loaded"
    end
    local ok, result = aliveworld.sites.start_anchor_site(param, {
      max_radius = 256,
      max_candidates = 160,
      candidates_per_step = 4,
    })
    if not ok then
      return false, "Anchor failed: " .. (result.error or "unknown")
    end
    return true, string.format("Anchor search %s for %s profile=%s checked=%d/%d steps=%d",
      result.status or "started",
      result.site_id or param,
      result.profile or "unknown",
      result.checked or 0,
      result.candidates and #result.candidates or 0,
      result.steps or 0)
  end,
})

minetest.register_chatcommand("aw_site_anchor_status", {
  params = "<site_id>",
  description = "Show terrain anchor status and summary for a site",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_site_anchor_status <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    local job = aliveworld.sites.get_anchor_job and aliveworld.sites.get_anchor_job(site.id)
    local lines = {}
    table.insert(lines, string.format("Site: %s", site.id))
    table.insert(lines, string.format("Physical status: %s", site.physical_status or "abstract"))
    if site.anchor_pos then
      table.insert(lines, string.format("Anchor pos: (%d,%d,%d)", site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z))
    else
      table.insert(lines, "Anchor pos: none")
    end
    table.insert(lines, string.format("Profile: %s", site.anchor_profile or (job and job.profile) or "none"))
    table.insert(lines, string.format("Version: %s", tostring(site.anchor_version or "none")))
    table.insert(lines, string.format("World seed: %s", tostring(site.anchor_world_seed or "none")))
    if site.anchor_survey then
      table.insert(lines, format_survey_summary(site.anchor_survey))
    end
    if job then
      table.insert(lines, string.format("Job: %s checked=%d/%d steps=%d",
        job.status or "unknown",
        job.checked or 0,
        job.candidates and #job.candidates or 0,
        job.steps or 0))
      if job.result and job.result.error then
        table.insert(lines, "Job error: " .. job.result.error)
      end
    elseif site.anchor_debug then
      table.insert(lines, string.format("Last attempt: %s checked=%s rejected=%s",
        site.anchor_debug.error or site.anchor_debug.status or "unknown",
        tostring(site.anchor_debug.checked or "0"),
        tostring(site.anchor_debug.rejected_count or "0")))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_site_survey", {
  params = "<x> <z>",
  description = "Survey terrain at X/Z and report anchor metrics",
  privs = {server = true},
  func = function(_, param)
    local x, z = (param or ""):match("^%s*(-?%d+)%s+(-?%d+)%s*$")
    if not x or not z then
      return false, "Usage: /aw_site_survey <x> <z>"
    end
    if not aliveworld.terrain or not aliveworld.terrain.survey then
      return false, "Terrain survey API not loaded"
    end
    local survey = aliveworld.terrain.survey({x = tonumber(x), z = tonumber(z)}, {profile = "generic"})
    local lines = {
      "Survey: " .. (survey.ok and "ok" or "rejected"),
      format_survey_summary(survey),
    }
    return true, table.concat(lines, "\n")
  end,
})

local function format_route_summary(route)
  if not route then return "Route: none" end
  local crossings = route.crossings or {}
  local claim = (aliveworld.claims and route.claim_id and aliveworld.claims.get(route.claim_id)) and "yes" or "no"
  return string.format(
    "%s %s %s->%s status=%s points=%d length=%d gain=%d loss=%d max_grade=%.3f water=%d claim=%s planner=%s expanded=%s",
    route.route_id or "?",
    route.kind or "route",
    route.from_site_id or "?",
    route.to_site_id or "?",
    route.status or "?",
    route.points and #route.points or 0,
    route.length or 0,
    route.elevation_gain or 0,
    route.elevation_loss or 0,
    route.max_grade or 0,
    #crossings,
    claim,
    tostring(route.planner_version or "none"),
    tostring(route.planning and route.planning.nodes_expanded or "0")
  )
end

minetest.register_chatcommand("aw_routes", {
  params = "",
  description = "List planned AliveWorld routes",
  privs = {server = true},
  func = function()
    if not aliveworld.routes then
      return false, "Routes module not loaded"
    end
    local list = aliveworld.routes.list()
    if #list == 0 then
      return true, "No routes."
    end
    local lines = {}
    table.insert(lines, string.format("%-16s %-8s %-18s %-18s %-10s %-7s %-8s %-8s %-8s %-6s",
      "ID", "Kind", "From", "To", "Status", "Points", "Length", "MaxGr", "Water", "Claim"))
    table.insert(lines, string.rep("-", 110))
    for _, route in ipairs(list) do
      local claim = (aliveworld.claims and route.claim_id and aliveworld.claims.get(route.claim_id)) and "yes" or "no"
      table.insert(lines, string.format("%-16s %-8s %-18s %-18s %-10s %-7d %-8d %-8.3f %-8d %-6s",
        route.route_id, route.kind or "", route.from_site_id or "", route.to_site_id or "",
        route.status or "", route.points and #route.points or 0, route.length or 0,
        route.max_grade or 0, route.crossings and #route.crossings or 0, claim))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_route", {
  params = "<route_id>",
  description = "Show route summary",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route <route_id>"
    end
    if not aliveworld.routes then
      return false, "Routes module not loaded"
    end
    local route = aliveworld.routes.get(param)
    if not route then
      return false, "Route not found: " .. param
    end
    local lines = {format_route_summary(route)}
    if route.bbox then
      table.insert(lines, string.format("BBox: min=(%d,%d,%d) max=(%d,%d,%d)",
        route.bbox.min.x, route.bbox.min.y, route.bbox.min.z,
        route.bbox.max.x, route.bbox.max.y, route.bbox.max.z))
    end
    if route.planning then
      table.insert(lines, string.format("Planning: candidates=%d expanded=%d elapsed_ms=%d total_cost=%.1f",
        route.planning.candidates_examined or 0,
        route.planning.nodes_expanded or 0,
        route.planning.elapsed_ms or 0,
        route.planning.total_cost or 0))
    end
    table.insert(lines, string.format("Cell size: %d | Planner version: %s | World seed: %s",
      route.cell_size or 0, tostring(route.planner_version or "none"), tostring(route.world_seed or "")))
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_route_plan", {
  params = "<route_id>",
  description = "Start route planning job",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_plan <route_id>"
    end
    if not aliveworld.routes then
      return false, "Routes module not loaded"
    end
    local ok, result = aliveworld.routes.start_plan_route(param, {
      cell_size = 16,
      nodes_per_step = 80,
      max_nodes = 9000,
    })
    if not ok then
      return false, "Route planning failed: " .. tostring(result.error or "unknown")
    end
    return true, string.format("Route planning %s for %s %s->%s",
      result.status or "started", result.route_id or param, result.from_site_id or "?", result.to_site_id or "?")
  end,
})

minetest.register_chatcommand("aw_route_replan", {
  params = "<route_id>",
  description = "Force route replanning",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_replan <route_id>"
    end
    if not aliveworld.routes then
      return false, "Routes module not loaded"
    end
    local ok, result = aliveworld.routes.start_plan_route(param, {
      force_replan = true,
      cell_size = 16,
      nodes_per_step = 80,
      max_nodes = 9000,
    })
    if not ok then
      return false, "Route replanning failed: " .. tostring(result.error or "unknown")
    end
    return true, "Route replanning started: " .. param
  end,
})

minetest.register_chatcommand("aw_route_debug", {
  params = "<route_id>",
  description = "Show route planning debug status",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_debug <route_id>"
    end
    if not aliveworld.routes then
      return false, "Routes module not loaded"
    end
    local route = aliveworld.routes.get(param)
    local job = aliveworld.routes.get_job and aliveworld.routes.get_job(param)
    local lines = {}
    if route then
      table.insert(lines, format_route_summary(route))
    else
      table.insert(lines, "Route: not saved")
    end
    if job then
      table.insert(lines, string.format("Job: %s expanded=%d examined=%d open=%d",
        job.status or "unknown", job.nodes_expanded or 0, job.candidates_examined or 0, job.open and #job.open or 0))
      if job.result and job.result.error then
        table.insert(lines, "Job error: " .. job.result.error)
      end
    else
      table.insert(lines, "Job: none")
    end
    return true, table.concat(lines, "\n")
  end,
})

local function format_materialization_summary(state)
  if not state then return "Materialization: none" end
  local checkpoint = state.checkpoint or {}
  local progress = 0
  if (state.dense_points_count or 0) > 0 then
    progress = math.floor((((checkpoint.dense_index or 1) - 1) / state.dense_points_count) * 100 + 0.5)
    if progress > 100 then progress = 100 end
  end
  local job_info = ""
  if state.job_metrics then
    job_info = string.format(" job_steps=%d cpu_total=%dms max_cpu=%dms over_budget=%d",
      state.job_metrics.steps or 0,
      state.job_metrics.total_cpu_ms or 0,
      state.job_metrics.max_step_cpu_ms or 0,
      state.job_metrics.over_budget_steps or 0)
  end
  return string.format(
    "materialization route=%s status=%s progress=%d%% processed_nodes=%d dense=%d changed=%d veg=%d leaves=%d trunks=%d snow=%d fill=%d cut=%d prot=%d blocked=%d unknown=%d meta=%d other=%d unresolved=%d warnings=%d version=%s checkpoint=%s globalsteps=%d step_ms_max=%d%s",
    state.route_id or "?",
    state.status or "?",
    progress,
    state.processed_nodes or 0,
    state.dense_points_count or 0,
    state.changed_nodes or 0,
    state.vegetation_removed or 0,
    state.leaves_removed or 0,
    state.trunks_removed or 0,
    state.snow_removed or 0,
    state.filled_nodes or 0,
    state.cut_nodes or 0,
    state.skipped_protected or 0,
    state.skipped_blocked or 0,
    state.unknown_blocked or 0,
    state.metadata_protected or 0,
    state.other_replaced or 0,
    state.unresolved and #state.unresolved or 0,
    state.warnings and #state.warnings or 0,
    tostring(state.materializer_version or "none"),
    tostring(checkpoint.dense_index or "none"),
    state.globalsteps or 0,
    state.max_step_ms or 0,
    job_info
  )
end

local function format_materialization_item(prefix, item)
  if not item then return nil end
  local text = prefix .. ": " .. tostring(item.reason or "unknown")
  if item.pos then
    text = text .. " at " .. minetest.pos_to_string(item.pos)
  elseif item.x and item.z then
    text = text .. string.format(" at x=%s z=%s", tostring(item.x), tostring(item.z))
  end
  if item.node then text = text .. " node=" .. tostring(item.node) end
  if item.delta then text = text .. " delta=" .. tostring(item.delta) end
  if item.lane then text = text .. " lane=" .. tostring(item.lane) end
  return text
end

minetest.register_chatcommand("aw_route_materialize", {
  params = "<route_id> [dry-run]",
  description = "Dry-run or start budgeted route materialization",
  privs = {server = true},
  func = function(name, param)
    local route_id, mode = (param or ""):match("^(%S+)%s*(.-)$")
    if not route_id or route_id == "" then
      return false, "Usage: /aw_route_materialize <route_id> [dry-run]"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local ok, result
    if mode == "dry-run" or mode == "dry_run" or mode == "dry" then
      ok, result = aliveworld.routes.materialization.dry_run(route_id, {actor = name})
      if not ok then
        return false, "Route materialization dry-run failed: " .. tostring(result.error or "unknown")
      end
      local lines = {"Dry-run " .. format_materialization_summary(result)}
      if result.unresolved and #result.unresolved > 0 then
        local first = result.unresolved[1]
        table.insert(lines, format_materialization_item("First unresolved", first))
      end
      return true, table.concat(lines, "\n")
    end
    ok, result = aliveworld.routes.materialization.start(route_id, {actor = name})
    if not ok then
      return false, "Route materialization failed: " .. tostring(result.error or "unknown")
    end
    return true, "Started " .. format_materialization_summary(result)
  end,
})

minetest.register_chatcommand("aw_route_materialize_status", {
  params = "<route_id>",
  description = "Show route materialization status",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_materialize_status <route_id>"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local state = aliveworld.routes.materialization.status(param)
    if not state then
      return false, "No materialization state for route: " .. param
    end
    local lines = {format_materialization_summary(state)}
    if state.last_error then
      table.insert(lines, "Last error: " .. tostring(state.last_error))
    end
    if state.unresolved and #state.unresolved > 0 then
      local first = state.unresolved[1]
      table.insert(lines, format_materialization_item("First unresolved", first))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_route_materialize_cancel", {
  params = "<route_id>",
  description = "Cancel a running route materialization job",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_materialize_cancel <route_id>"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local ok, result = aliveworld.routes.materialization.cancel(param, "cancelled_by_command")
    if not ok then
      return false, "Cancel failed: " .. tostring(result.error or "unknown")
    end
    return true, "Cancelled " .. format_materialization_summary(result)
  end,
})

minetest.register_chatcommand("aw_route_materialize_verify", {
  params = "<route_id>",
  description = "Verify a materialized route (async, budgeted). Use aw_route_materialize_verify_status to check progress.",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_materialize_verify <route_id>"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local mat = aliveworld.routes.materialization
    local status = mat.verify_status(param)
    if status and status.status == "running" then
      return false, "Verify already running for route " .. param .. ". Use /aw_route_materialize_verify_status " .. param .. " to check progress."
    end
    local ok, data = mat.verify_async(param)
    if not ok then
      return false, "Verify start failed: " .. tostring(data or "unknown")
    end
    return true, "Verify started for route " .. param .. " (async). Use /aw_route_materialize_verify_status " .. param .. " to check."
  end,
})

minetest.register_chatcommand("aw_route_materialize_verify_status", {
  params = "<route_id>",
  description = "Show verify job progress for a route",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_materialize_verify_status <route_id>"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local status = aliveworld.routes.materialization.verify_status(param)
    if not status then
      return false, "Route not found: " .. param
    end
    local lines = {string.format("Verify route=%s status=%s total_checks=%d palette_mismatch=%d unexpected_water=%d outside_corridor=%d missing_surface=%d",
      param, status.status, status.total_checks or 0,
      status.palette_mismatch or 0, status.unexpected_water or 0,
      status.outside_corridor or 0, status.missing_surface or 0)}
    local md = status.mismatch_details
    if md and md.by_lane then
      table.insert(lines, string.format("  by_lane: road=%d shoulder=%d", md.by_lane.road or 0, md.by_lane.shoulder or 0))
    end
    if md and md.by_expected then
      local parts = {}
      for node_name, cnt in pairs(md.by_expected) do
        table.insert(parts, node_name .. "=" .. cnt)
      end
      if #parts > 0 then
        table.insert(lines, "  by_expected: " .. table.concat(parts, " "))
      end
    end
    if md and md.by_actual then
      local parts = {}
      for node_name, cnt in pairs(md.by_actual) do
        table.insert(parts, node_name .. "=" .. cnt)
      end
      if #parts > 0 then
        table.insert(lines, "  by_actual: " .. table.concat(parts, " "))
      end
    end
    if status.metrics and status.metrics.steps then
      table.insert(lines, string.format("  steps=%d cpu=%dms max_step=%dms over=%d",
        status.metrics.steps, status.metrics.total_cpu_ms,
        status.metrics.max_step_cpu_ms, status.metrics.over_budget_steps))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_route_materialize_debug", {
  params = "<route_id>",
  description = "Show route materialization debug summary",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_route_materialize_debug <route_id>"
    end
    if not aliveworld.routes or not aliveworld.routes.materialization then
      return false, "Route materialization module not loaded"
    end
    local route = aliveworld.routes.get(param)
    local state = aliveworld.routes.materialization.status(param)
    local lines = {}
    if route then
      table.insert(lines, format_route_summary(route))
    else
      table.insert(lines, "Route: not saved")
    end
    table.insert(lines, format_materialization_summary(state))
    if state and state.palette then
      table.insert(lines, string.format("Palette: surface=%s shoulder=%s fill=%s base=%s",
        tostring(state.palette.surface), tostring(state.palette.shoulder), tostring(state.palette.fill), tostring(state.palette.base)))
    end
    if state and state.settings then
      table.insert(lines, string.format("Settings: centerline_step=%s road_width=%s shoulder_width=%s max_cut=%s max_fill=%s pps=%s budget=%dms",
        tostring(state.settings.centerline_step), tostring(state.settings.road_width), tostring(state.settings.shoulder_width),
        tostring(state.settings.max_cut), tostring(state.settings.max_fill), tostring(state.settings.points_per_step or 2),
        state.settings.target_budget_ms or 25))
    end
    if state and state.job_metrics then
      local m = state.job_metrics
      table.insert(lines, string.format("Job metrics: steps=%d total_cpu=%dms max_cpu=%dms over_budget=%d emerge_wait=%dms",
        m.steps or 0, m.total_cpu_ms or 0, m.max_step_cpu_ms or 0, m.over_budget_steps or 0, m.total_emerge_wait_ms or 0))
      if m.phases then
        local max_phase_ms = 0
        local max_phase_name = ""
        for pname, pm in pairs(m.phases) do
          if pm.max_ms and pm.max_ms > max_phase_ms then
            max_phase_ms = pm.max_ms
            max_phase_name = pname
          end
        end
        if max_phase_name ~= "" then
          table.insert(lines, string.format("Phase peaks: %s=%dms", max_phase_name, max_phase_ms))
        end
      end
    end
    if state and state.warnings and #state.warnings > 0 then
      local max_items = math.min(#state.warnings, 5)
      for i = 1, max_items do
        table.insert(lines, format_materialization_item("Warning " .. i, state.warnings[i]))
      end
    end
    if state and state.unresolved and #state.unresolved > 0 then
      table.insert(lines, format_materialization_item("First unresolved", state.unresolved[1]))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_whereami", {
  params = "[player_name]",
  description = "Show current coordinates and nearest sites",
  privs = {server = true},
  func = function(_, param)
    local target = param or ""
    local players = minetest.get_connected_players()
    local p = nil
    if target ~= "" then
      for _, pl in ipairs(players) do
        if pl:get_player_name() == target then
          p = pl
          break
        end
      end
      if not p then
        return false, "Player not found or not online: " .. target
      end
    elseif #players > 0 then
      p = players[1]
    else
      return false, "No players online."
    end
    local ppos = p:get_pos()
    if not ppos then
      return false, "Cannot get player position."
    end
    local from = {x = ppos.x, y = ppos.y, z = ppos.z}
    local pname = p:get_player_name()
    local lines = {}
    table.insert(lines, string.format("Player: %s", pname))
    table.insert(lines, string.format("Pos: (%d,%d,%d)", math.floor(from.x), math.floor(from.y), math.floor(from.z)))
    table.insert(lines, "")
    if aliveworld.sites then
      local near = aliveworld.sites.nearest(from, 5)
      if #near == 0 then
        table.insert(lines, "No active sites nearby.")
      else
        table.insert(lines, "Nearest sites:")
        for _, s in ipairs(near) do
          local dist = aliveworld.sites.distance(from, s.pos)
          local dir = aliveworld.sites.direction_name_en(from, s.pos)
          local phys = s.physical_status or "abstract"
          table.insert(lines, string.format("  %-20s dist=%-6d dir=%-12s phys=%-12s (%d,%d,%d)",
            s.id, dist, dir, phys, s.pos.x, s.pos.y, s.pos.z))
        end
      end
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_site_nav_debug", {
  params = "<site_id>",
  description = "Show navigation positions for a site (arrival, observer, marker)",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_site_nav_debug <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Site: %s (%s)", site.id, site.name_en or site.name))
    table.insert(lines, string.format("Type: %s (%s)", site.type, site.subtype))
    table.insert(lines, string.format("Physical status: %s", site.physical_status or "abstract"))
    table.insert(lines, "")

    -- Anchor pos
    if site.anchor_pos then
      local safe = aliveworld.sites.is_safe_standing_pos(site.anchor_pos)
      table.insert(lines, string.format("Anchor pos: (%d,%d,%d) safe=%s reason=%s",
        site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z,
        tostring(safe.safe), table.concat(safe.reasons, ",")))
    else
      table.insert(lines, "Anchor pos: none")
    end

    -- Arrival pos
    local arrival = aliveworld.sites.resolve_arrival_pos(site)
    if arrival then
      local safe = aliveworld.sites.is_safe_standing_pos(arrival)
      table.insert(lines, string.format("Arrival pos: (%d,%d,%d) safe=%s reason=%s",
        arrival.x, arrival.y, arrival.z,
        tostring(safe.safe), table.concat(safe.reasons, ",")))
    else
      table.insert(lines, "Arrival pos: none (resolution failed)")
    end

    -- Observer pos
    local observer = aliveworld.sites.resolve_observer_pos(site)
    if observer then
      local safe = aliveworld.sites.is_safe_standing_pos(observer)
      table.insert(lines, string.format("Observer pos: (%d,%d,%d) safe=%s reason=%s",
        observer.x, observer.y, observer.z,
        tostring(safe.safe), table.concat(safe.reasons, ",")))
    else
      table.insert(lines, "Observer pos: none (resolution failed)")
    end

    -- Marker pos
    local marker = aliveworld.sites.resolve_marker_pos(site)
    if marker then
      local safe = aliveworld.sites.is_safe_standing_pos(marker)
      table.insert(lines, string.format("Marker pos: (%d,%d,%d) safe=%s reason=%s",
        marker.x, marker.y, marker.z,
        tostring(safe.safe), table.concat(safe.reasons, ",")))
    else
      table.insert(lines, "Marker pos: none (resolution failed)")
    end

    table.insert(lines, "")
    table.insert(lines, string.format("Raw site.pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
    if site.radius then
      table.insert(lines, string.format("Site radius: %d", site.radius))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_compass", {
  params = "<player_name> <site_id>",
  description = "Show direction and distance from player to site",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_compass <player_name> <site_id>"
    end
    local pname, site_id = param:match("^(%S+)%s+(%S+)$")
    if not pname or not site_id then
      return false, "Usage: /aw_compass <player_name> <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(site_id)
    if not site then
      return false, "Site not found: " .. site_id
    end
    local player = minetest.get_player_by_name(pname)
    if not player then
      return false, "Player not found or not online: " .. pname
    end
    local ppos = player:get_pos()
    if not ppos then
      return false, "Cannot get player position."
    end
    local from = {x = ppos.x, y = ppos.y, z = ppos.z}
    local dx = site.pos.x - from.x
    local dz = site.pos.z - from.z
    local dist = aliveworld.sites.distance(from, site.pos)
    local dir_en = aliveworld.sites.direction_name_en(from, site.pos)
    local dir_ru = aliveworld.sites.direction_name_ru(from, site.pos)
    local lines = {}
    table.insert(lines, string.format("Compass: %s -> %s (%s)", pname, site_id, site.name_en))
    table.insert(lines, string.format("Player pos: (%d,%d,%d)", math.floor(from.x), math.floor(from.y), math.floor(from.z)))
    table.insert(lines, string.format("Target pos: (%d,%d,%d)", site.pos.x, site.pos.y, site.pos.z))
    table.insert(lines, string.format("dx=%d dz=%d", dx, dz))
    table.insert(lines, string.format("Distance: %d blocks", dist))
    table.insert(lines, string.format("Direction: %s (%s)", dir_en, dir_ru))
    table.insert(lines, string.format("Physical status: %s", site.physical_status or "abstract"))
    if site.anchor_pos then
      local adist = aliveworld.sites.distance(from, site.anchor_pos)
      table.insert(lines, string.format("Anchor pos: (%d,%d,%d) (dist=%d)", site.anchor_pos.x, site.anchor_pos.y, site.anchor_pos.z, adist))
    end
    return true, table.concat(lines, "\n")
  end,
})

-- Runtime version info
local function get_git_commit()
  local modpath = minetest.get_modpath("aliveworld_core")
  if modpath then
    local f = io.open(modpath .. "/version.txt", "r")
    if f then
      local hash = f:read("*l")
      f:close()
      if hash and hash ~= "" then return hash end
    end
  end
  return "unknown"
end

aliveworld.version = {
  major = 0,
  minor = 2,
  patch = 0,
  label = "dev",
}
aliveworld.version.git_commit = get_git_commit()
aliveworld.version.schema_tracking = 1
aliveworld.version.schema_rumor_ui = 1
aliveworld.version.loaded_at = os.date("!%Y-%m-%dT%H:%M:%SZ")
aliveworld.version.mod_path = minetest.get_modpath("aliveworld_core")

minetest.register_chatcommand("aw_version", {
  params = "",
  description = "Show AliveWorld runtime version info",
  privs = {interact = true},
  func = function()
    local v = aliveworld.version
    local lines = {
      "=== AliveWorld Runtime ===",
      string.format("Version: %d.%d.%d-%s", v.major, v.minor, v.patch, v.label),
      string.format("Commit: %s", v.git_commit),
      string.format("Loaded at: %s", v.loaded_at),
      string.format("Mod path: %s", v.mod_path or "N/A"),
      string.format("Tracking schema: %d", v.schema_tracking),
      string.format("Rumor UI schema: %d", v.schema_rumor_ui),
    }
    return true, table.concat(lines, "\n")
  end,
})

minetest.log("action", string.format("[aliveworld_core] loaded v%d.%d.%d-%s commit=%s",
  aliveworld.version.major, aliveworld.version.minor, aliveworld.version.patch, aliveworld.version.label, aliveworld.version.git_commit))
