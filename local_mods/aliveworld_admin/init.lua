aliveworld = rawget(_G, "aliveworld") or {}
_G.aliveworld = aliveworld

minetest.register_chatcommand("aw_status", {
  description = "AliveWorld status",
  privs = {server = true},
  func = function()
    local d = aliveworld.get_date()
    local paused = aliveworld.is_paused()
    local c = aliveworld.get_config()
    local lines = {
      string.format("AliveWorld: year=%d month=%d day=%d (total days: %d)",
        d.year, d.month, d.day, d.total_days),
      string.format("Tick: %ds | Paused: %s",
        c.tick_interval, (paused and "yes" or "no")),
    }
    if aliveworld.bridge and aliveworld.bridge.get_environment_profile then
      local env = aliveworld.bridge.get_environment_profile(d)
      table.insert(lines, string.format(
        "Season: %s | Food: %s | Wood: %s | Danger: %s",
        env.season.label_en, env.food.label_en,
        env.wood.label_en, env.danger.label_en))
      table.insert(lines, string.format("Bridge: %s", aliveworld.bridge.game or "?"))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_bridge", {
  params = "<summary|foods|woods|dangers|seasons>",
  description = "Bridge module info",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_bridge <summary|foods|woods|dangers|seasons>"
    end

    if not aliveworld.bridge then
      return false, "No bridge module loaded."
    end

    local d = aliveworld.get_date()
    param = param:lower()

    if param == "summary" then
      local env = aliveworld.bridge.get_environment_profile
        and aliveworld.bridge.get_environment_profile(d)
      if not env then
        return false, "Bridge has no get_environment_profile."
      end
      local lines = {}
      table.insert(lines, string.format("Bridge: %s", aliveworld.bridge.game or "?"))
      table.insert(lines, string.format("Date: year=%d month=%d day=%d",
        d.year, d.month, d.day))
      table.insert(lines, string.format("Season: %s", env.season.key))
      table.insert(lines, string.format("Food: %s (availability=%d%%)",
        env.food.key, math.floor(env.food.availability * 100)))
      table.insert(lines, string.format("Wood: %s (availability=%d%%)",
        env.wood.key, math.floor(env.wood.availability * 100)))
      table.insert(lines, string.format("Danger: %s (level=%d%%)",
        env.danger.key, math.floor(env.danger.level * 100)))
      return true, table.concat(lines, "\n")
    end

    if param == "foods" then
      local p = aliveworld.bridge.get_food_profile
        and aliveworld.bridge.get_food_profile(d)
      if not p then return false, "Bridge has no get_food_profile." end
      return true, string.format("Food: %s (availability=%d%%), items: %s",
        p.key, math.floor(p.availability * 100),
        table.concat(p.items or {}, ", "))
    end

    if param == "woods" then
      local p = aliveworld.bridge.get_wood_profile
        and aliveworld.bridge.get_wood_profile(d)
      if not p then return false, "Bridge has no get_wood_profile." end
      return true, string.format("Wood: %s (availability=%d%%), groups: %s",
        p.key, math.floor(p.availability * 100),
        table.concat(p.groups or {}, ", "))
    end

    if param == "dangers" then
      local p = aliveworld.bridge.get_danger_profile
        and aliveworld.bridge.get_danger_profile(d)
      if not p then return false, "Bridge has no get_danger_profile." end
      return true, string.format("Danger: %s (level=%d%%), mobs: %s",
        p.key, math.floor(p.level * 100),
        table.concat(p.mobs or {}, ", "))
    end

    if param == "seasons" then
      if not aliveworld.bridge.get_season then
        return false, "Bridge has no get_season."
      end
      local cur = aliveworld.bridge.get_season(d)
      return true, string.format(
        "Current season: %s\nmonth 1-3: spring\nmonth 4-6: summer\nmonth 7-9: autumn\nmonth 10-12: winter",
        cur.key)
    end

    return false,
      "Unknown subcommand. Use: summary, foods, woods, dangers, seasons"
  end,
})

minetest.log("action", "[aliveworld_admin] loaded")
