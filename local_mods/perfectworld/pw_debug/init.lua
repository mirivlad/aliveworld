perfectworld = rawget(_G, "perfectworld") or {}
_G.perfectworld = perfectworld
perfectworld.debug = perfectworld.debug or {}

local function safe_string(v)
  if type(v) == "string" then return v end
  if type(v) == "number" then return tostring(v) end
  return tostring(v)
end

local function active_modules()
  local modules = {}
  for _, entry in ipairs({
    {"core", perfectworld.core},
    {"planner", perfectworld.planner},
    {"structures", perfectworld.structures},
    {"roads", perfectworld.roads},
    {"settlements", perfectworld.settlements},
    {"population", perfectworld.population},
    {"compat_mcl", perfectworld.compat},
    {"debug", perfectworld.debug},
  }) do
    if entry[2] then
      table.insert(modules, entry[1])
    end
  end
  table.sort(modules)
  return modules
end

minetest.register_chatcommand("pw_status", {
  params = "",
  description = "Show PerfectWorld version and configuration",
  privs = {interact = true},
  func = function(name)
    local structures = perfectworld.structures and perfectworld.structures.list() or {}
    local info = {
      "version=" .. safe_string(perfectworld.VERSION or "?"),
      "api=perfectworld",
      "planner_version=" .. safe_string(perfectworld.PLANNER_VERSION or "?"),
      "region_size=" .. safe_string(perfectworld.REGION_SIZE or "?"),
      "world_seed_masked=" .. (perfectworld.world_seed_string and (perfectworld.world_seed_string:sub(1, 8) .. "...") or "?"),
      "structures=" .. #structures,
      "modules=" .. table.concat(active_modules(), ","),
    }
    return true, table.concat(info, "\n")
  end,
})

minetest.register_chatcommand("pw_region", {
  params = "",
  description = "Show the region the calling player is standing in",
  privs = {interact = true},
  func = function(name)
    local player = minetest.get_player_by_name(name)
    if not player then return false, "Player not found" end
    local pos = player:get_pos()
    if not pos then return false, "No position" end
    local rx, rz = perfectworld.get_region_coords(pos)
    local rid = perfectworld.get_region_id(rx, rz)
    local plan = perfectworld.planner and perfectworld.planner.plan_region(rx, rz)
    local info = {
      "region_id=" .. rid,
      "rx=" .. rx,
      "rz=" .. rz,
      "minp=" .. (plan and minetest.pos_to_string(plan.minp) or "?"),
      "maxp=" .. (plan and minetest.pos_to_string(plan.maxp) or "?"),
      "settlement_candidates=" .. (plan and #(plan.settlement_candidates or {}) or 0),
      "road_anchors=" .. (plan and #(plan.road_anchors or {}) or 0),
    }
    return true, table.concat(info, "\n")
  end,
})

minetest.register_chatcommand("pw_plan", {
  params = "[rx] [rz]",
  description = "Show the plan for current region or specified region",
  privs = {interact = true},
  func = function(name, params)
    local rx, rz
    if params and params ~= "" then
      local rx_str, rz_str = params:match("^(%-?%d+)%s+(%-?%d+)$")
      if not rx_str then return false, "Usage: /pw_plan <rx> <rz>" end
      rx, rz = tonumber(rx_str), tonumber(rz_str)
    else
      local player = minetest.get_player_by_name(name)
      if not player then return false, "Player not found" end
      local pos = player:get_pos()
      if not pos then return false, "No position" end
      rx, rz = perfectworld.get_region_coords(pos)
    end
    local plan = perfectworld.planner and perfectworld.planner.plan_region(rx, rz)
    if not plan then return false, "No plan available" end
    local lines = {"plan_id=" .. plan.id}
    table.insert(lines, "rx=" .. tostring(plan.rx))
    table.insert(lines, "rz=" .. tostring(plan.rz))
    table.insert(lines, "planner_version=" .. tostring(plan.planner_version))
    table.insert(lines, "settlement_candidates=" .. #(plan.settlement_candidates or {}))
    table.insert(lines, "road_anchors=" .. #(plan.road_anchors or {}))
    for _, sc in ipairs(plan.settlement_candidates or {}) do
      table.insert(lines, table.concat({
        "candidate_id=" .. sc.id,
        "type=" .. sc.type,
        "x=" .. sc.x,
        "z=" .. sc.z,
        "priority=" .. sc.priority,
        "connection_required=" .. tostring(sc.connection_required == true),
        "status=" .. sc.status,
      }, " "))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.log("action", "[pw_debug] loaded")
