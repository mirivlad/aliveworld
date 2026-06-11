-- aliveworld_core/tracking.lua
-- Shared tracking API for AliveWorld
-- Manages per-player active tracks, provides structured results for commands and UI.

aliveworld.tracking = {}

local tracks = {}  -- player_name -> {site_id, target_pos, precision, ...}
local arrival_ack = {}  -- player_name -> {[site_id] = true}

function aliveworld.tracking.track_site(player_or_name, site_id, opts)
  opts = opts or {}
  local result = {
    ok = false,
    error = nil,
    player_name = nil,
    requested_site_id = site_id,
    resolved_site_id = nil,
    title = nil,
    target_pos = nil,
    gps_enabled = false,
    precision = nil,
    physical_status = nil,
  }

  -- Resolve player
  local player
  if type(player_or_name) == "string" then
    player = minetest.get_player_by_name(player_or_name)
    result.player_name = player_or_name
  else
    player = player_or_name
    if player and player:is_player() then
      result.player_name = player:get_player_name()
    end
  end
  if not player or not player:is_player() then
    result.error = "player_not_found"
    return result
  end
  local pname = result.player_name

  -- Resolve site
  if not aliveworld.sites then
    result.error = "sites_module_not_loaded"
    return result
  end
  local site = aliveworld.sites.get(site_id)
  if not site then
    result.error = "site_not_found"
    return result
  end
  result.resolved_site_id = site.id
  result.title = site.name or site.name_en or site.id
  result.physical_status = site.physical_status or "abstract"

  -- Compute target position
  local target_pos = nil
  if aliveworld.sites.resolve_arrival_pos then
    target_pos = aliveworld.sites.resolve_arrival_pos(site)
  end
  if not target_pos then
    target_pos = site.anchor_pos or site.pos
  end
  result.target_pos = target_pos

  -- Determine precision
  local phys = site.physical_status or "abstract"
  result.precision = (phys == "anchored" or phys == "materialized") and "exact" or "approximate"

  -- Save active track state
  tracks[pname] = {
    site_id = site.id,
    target_pos = target_pos,
    precision = result.precision,
    physical_status = phys,
    title = result.title,
    site = site,
  }

  -- Persist site_id to player meta for rejoin
  local pmeta = player:get_meta()
  pmeta:set_string("aliveworld_track_site_id", site.id)

  -- Emit core tracking event
  aliveworld.add_event("tracking_started",
    string.format("Player %s started tracking %s (%s)", pname, site.id, result.title),
    {player = pname, site_id = site.id, precision = result.precision, source = opts.source or "command"}
  )

  result.ok = true
  return result
end

function aliveworld.tracking.untrack(player_or_name)
  local result = {
    ok = false,
    error = nil,
    player_name = nil,
    had_track = false,
    site_id = nil,
  }

  local pname
  if type(player_or_name) == "string" then
    pname = player_or_name
  else
    if player_or_name and player_or_name:is_player() then
      pname = player_or_name:get_player_name()
    end
  end
  if not pname then
    result.error = "player_not_found"
    return result
  end
  result.player_name = pname

  local t = tracks[pname]
  if not t then
    result.had_track = false
    result.ok = true
    return result
  end

  result.had_track = true
  result.site_id = t.site_id

  -- Clear state
  tracks[pname] = nil

  -- Clear player meta
  local player = minetest.get_player_by_name(pname)
  if player then
    player:get_meta():set_string("aliveworld_track_site_id", "")
  end

  -- Emit event
  aliveworld.add_event("tracking_stopped",
    string.format("Player %s stopped tracking %s", pname, t.site_id),
    {player = pname, site_id = t.site_id}
  )

  result.ok = true
  return result
end

function aliveworld.tracking.get_active_track(player_or_name)
  local pname
  if type(player_or_name) == "string" then
    pname = player_or_name
  else
    if player_or_name and player_or_name:is_player() then
      pname = player_or_name:get_player_name()
    end
  end
  if not pname then return nil end

  local t = tracks[pname]
  if not t then return nil end

  -- Refresh site data (site may have been updated since track was created)
  local site = aliveworld.sites and aliveworld.sites.get(t.site_id)
  return {
    site_id = t.site_id,
    target_pos = t.target_pos,
    precision = t.precision,
    physical_status = t.physical_status,
    title = t.title,
    has_arrived = arrival_ack[pname] and arrival_ack[pname][t.site_id] or false,
    site = site or t.site,
  }
end

function aliveworld.tracking.describe_track(player_or_name)
  local pname = (type(player_or_name) == "string") and player_or_name or (player_or_name and player_or_name:get_player_name())
  if not pname then
    return {ok = true, has_track = false, line = "Нет активного waypoint."}
  end
  local track = aliveworld.tracking.get_active_track(pname)
  if not track then
    return {ok = true, has_track = false, line = "Нет активного waypoint."}
  end
  local player = minetest.get_player_by_name(pname)
  local dist = nil
  if player then
    local ppos = player:get_pos()
    if ppos and track.target_pos then
      local dx = track.target_pos.x - ppos.x
      local dz = track.target_pos.z - ppos.z
      dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)
    end
  end
  local line = "AW: " .. (track.title or track.site_id)
  if dist then
    line = line .. " — " .. dist .. " блоков"
  end
  local precision_label = (track.precision == "approximate") and " (примерно)" or ""
  line = line .. precision_label
  return {
    ok = true,
    has_track = true,
    line = line,
    site_id = track.site_id,
    title = track.title,
    distance = dist,
    precision = track.precision,
  }
end

-- Restore track from player meta on join
function aliveworld.tracking.restore_player(player)
  if not player or not player:is_player() then return end
  local pname = player:get_player_name()
  local meta = player:get_meta()
  local site_id = meta:get_string("aliveworld_track_site_id")
  if site_id and site_id ~= "" then
    local site = aliveworld.sites and aliveworld.sites.get(site_id)
    if site and site.status == "active" then
      local t = tracks[pname]
      if not t then
        aliveworld.tracking.track_site(pname, site_id, {source = "rejoin"})
      end
    else
      meta:set_string("aliveworld_track_site_id", "")
    end
  end
end

-- Check arrival for a player (returns nil or {arrived, site, dist, msg, kind})
function aliveworld.tracking.check_arrival(player)
  if not player or not player:is_player() then return nil end
  local pname = player:get_player_name()
  local track = aliveworld.tracking.get_active_track(pname)
  if not track then return nil end

  local ppos = player:get_pos()
  if not ppos then return nil end
  local from = {x = ppos.x, y = ppos.y, z = ppos.z}
  local target = track.target_pos
  if not target then return nil end

  local dx = target.x - from.x
  local dz = target.z - from.z
  local dist = math.floor(math.sqrt(dx*dx + dz*dz) + 0.5)

  local arrival_radius = 12
  local kind = "arrived"
  local site_name = track.title or track.site_id

  if track.physical_status == "abstract" then
    arrival_radius = 30
    kind = "abstract"
  end

  if dist > arrival_radius then
    return nil
  end

  -- Check if already acknowledged
  if arrival_ack[pname] and arrival_ack[pname][track.site_id] then
    return nil
  end

  -- Record arrival ack
  if not arrival_ack[pname] then arrival_ack[pname] = {} end
  arrival_ack[pname][track.site_id] = true

  local msg
  if kind == "abstract" then
    msg = "Вы добрались до окрестностей: " .. site_name .. ".\n"
      .. "Это только слух. Явного объекта здесь нет, но следы подтверждают, что место не случайное."
  else
    msg = "Вы добрались до места: " .. site_name .. "."
  end

  -- Emit chronicle event
  aliveworld.add_event("player_arrived",
    string.format("Player %s arrived at %s (%s)", pname, track.site_id, site_name),
    {player = pname, site_id = track.site_id, kind = kind, dist = dist}
  )

  -- Sync rumor status to visited
  if aliveworld.rumors and aliveworld.rumors.sync_status_from_tracking then
    aliveworld.rumors.sync_status_from_tracking(pname)
  end

  -- Physical clue for abstract sites
  if kind == "abstract" and aliveworld.sites and aliveworld.sites.place_clue_marker then
    local clue_pos = track.target_pos
    aliveworld.sites.place_clue_marker(clue_pos, track.site_id, pname)
    local clue_text = ""
    if track.site and track.site.event_type then
      clue_text = " " .. aliveworld.sites.get_clue_texts(track.site.event_type)
    end
    msg = msg .. "\n[подсказка]" .. clue_text
  end

  return {
    arrived = true,
    site = track.site,
    dist = dist,
    msg = msg,
    kind = kind,
    site_id = track.site_id,
  }
end

-- Reset arrival ack for testing
function aliveworld.tracking.reset_arrival_ack(player_or_name, site_id)
  local pname
  if type(player_or_name) == "string" then
    pname = player_or_name
  else
    if player_or_name and player_or_name:is_player() then
      pname = player_or_name:get_player_name()
    end
  end
  if not pname then
    return {ok = false, error = "player_not_found", player_name = nil, site_id = site_id, removed = false}
  end
  local had_ack = false
  if site_id then
    if arrival_ack[pname] and arrival_ack[pname][site_id] then
      arrival_ack[pname][site_id] = nil
      had_ack = true
    end
  else
    if arrival_ack[pname] then
      had_ack = true
    end
    arrival_ack[pname] = nil
  end
  return {
    ok = true,
    removed = had_ack,
    player_name = pname,
    site_id = site_id,
  }
end

-- Get debug info for a player
function aliveworld.tracking.get_debug_info(player_or_name)
  local pname
  if type(player_or_name) == "string" then
    pname = player_or_name
  else
    if player_or_name and player_or_name:is_player() then
      pname = player_or_name:get_player_name()
    end
  end
  if not pname then
    return {player_name = nil, error = "invalid_player", gps_enabled = false, has_track = false, active_track = nil, arrival_ack = {}}
  end
  local track = aliveworld.tracking.get_active_track(pname)
  return {
    player_name = pname,
    gps_enabled = (aliveworld_player and aliveworld_player.radar and aliveworld_player.radar.is_enabled(pname)) or false,
    has_track = (track ~= nil),
    active_track = track,
    arrival_ack = arrival_ack[pname] or {},
  }
end

-- Globalstep: check arrival every 2s
local arrival_tick = 0
minetest.register_globalstep(function(dtime)
  arrival_tick = arrival_tick + dtime
  if arrival_tick < 2.0 then return end
  arrival_tick = 0
  for _, player in ipairs(minetest.get_connected_players()) do
    local ar = aliveworld.tracking.check_arrival(player)
    if ar and ar.msg then
      minetest.chat_send_player(player:get_player_name(), ar.msg)
      minetest.log("action", "[tracking] arrival: " .. player:get_player_name()
        .. " at " .. tostring(ar.site_id)
        .. " dist=" .. tostring(ar.dist)
        .. " kind=" .. tostring(ar.kind))
    end
  end
end)

-- Restore on join
minetest.register_on_joinplayer(function(player)
  minetest.after(1.0, function()
    aliveworld.tracking.restore_player(player)
  end)
end)

minetest.log("action", "[aliveworld_core] tracking module loaded")
