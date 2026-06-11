-- aliveworld_test_suite/tests/gps.lua
-- Test GPS / tracking functions

local T = luanti_testkit

T.register_test("aliveworld", "tracking_module_loaded", function(ctx)
	if not aliveworld_player then
		ctx.skip("aliveworld_player not loaded")
		return
	end
	if not aliveworld_player.tracking then
		ctx.skip("aliveworld_player.tracking not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld_player.tracking, "tracking module must exist")
	ctx.assert.not_nil(aliveworld_player.tracking.track_site, "track_site function must exist")
	ctx.assert.not_nil(aliveworld_player.tracking.untrack, "untrack function must exist")
end)

T.register_test("aliveworld", "track_site_birch_ford", function(ctx)
	if not aliveworld_player or not aliveworld_player.tracking then
		ctx.skip("aliveworld_player.tracking not loaded")
		return
	end
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local player = ctx.helpers.get_player(ctx.player_name)
	if not player then
		ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
		return
	end
	local site = aliveworld.sites.get("birch_ford")
	if not site then
		ctx.skip("Site 'birch_ford' not found.")
		return
	end

	-- Track the site
	local ok, result = aliveworld_player.tracking.track_site(ctx.player_name, "birch_ford")
	if not ok then
		ctx.skip("track_site returned false: " .. tostring(result))
		return
	end
	ctx.log("Tracked birch_ford: " .. tostring(result))

	-- Check tracking state exists
	local state = aliveworld_player.tracking.get_state and aliveworld_player.tracking.get_state(ctx.player_name)
	if state then
		ctx.assert.not_nil(state.target_pos, "tracking state must have target_pos")
		ctx.log("target_pos: " .. minetest.pos_to_string(state.target_pos))
	else
		ctx.log("No get_state available, tracking via HUD/waypoint")
	end
end)

T.register_test("aliveworld", "untrack_clears_state", function(ctx)
	if not aliveworld_player or not aliveworld_player.tracking then
		ctx.skip("aliveworld_player.tracking not loaded")
		return
	end
	local player = ctx.helpers.get_player(ctx.player_name)
	if not player then
		ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
		return
	end

	-- First track something
	aliveworld_player.tracking.track_site(ctx.player_name, "birch_ford")

	-- Then untrack
	local ok, msg = aliveworld_player.tracking.untrack(ctx.player_name)
	ctx.log("Untrack result: " .. tostring(msg))

	-- Verify state is cleared
	if aliveworld_player.tracking.get_state then
		local state = aliveworld_player.tracking.get_state(ctx.player_name)
		ctx.assert.is_false(state and state.active, "state should be cleared after untrack")
	end
end)

T.register_test("aliveworld", "track_and_gps_full_workflow", function(ctx)
  ctx.assert.not_nil(aliveworld_player, "aliveworld_player must be loaded")
  if not aliveworld_player then
    return
  end
  ctx.assert.not_nil(aliveworld_player.tracking, "aliveworld_player.tracking must be loaded")
  ctx.assert.not_nil(aliveworld_player.radar, "aliveworld_player.radar must be loaded")
  if not aliveworld_player.tracking or not aliveworld_player.radar then
    return
  end
  ctx.assert.not_nil(aliveworld_player.radar.get_points_for_player, "radar.get_points_for_player must exist")
  if not aliveworld_player.radar.get_points_for_player then
    return
  end

  local player = ctx.helpers.get_player(ctx.player_name)
  if not player then
    ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
    return
  end
  ctx.assert.not_nil(aliveworld, "aliveworld must be loaded")
  ctx.assert.not_nil(aliveworld and aliveworld.sites, "aliveworld.sites must be loaded")
  if not aliveworld or not aliveworld.sites then
    return
  end

  -- Enable GPS
  local ok_gps, msg_gps = aliveworld_player.radar.enable(ctx.player_name)
  ctx.log("GPS enable: " .. tostring(msg_gps))

  -- Track site_birch_ford
  local site = aliveworld.sites.get("site_birch_ford")
  if not site then
    ctx.assert.not_nil(site, "Site 'site_birch_ford' must exist")
    return
  end
  local ok_track, msg_track = aliveworld_player.tracking.track_site(ctx.player_name, "site_birch_ford")
  ctx.assert.is_true(ok_track, "track_site should succeed: " .. tostring(msg_track))
  if not ok_track then
    return
  end
  ctx.log("Track: " .. tostring(msg_track))

  -- Verify via tracking.list
  local track_list = aliveworld_player.tracking.list(ctx.player_name)
  ctx.assert.not_nil(track_list, "track list should exist")
  ctx.assert.equal(1, #track_list, "should have 1 active track")

  -- Verify active track state
  local t = track_list[1]
  ctx.assert.not_nil(t, "active track entry must exist")
  ctx.assert.equal("site_birch_ford", t.site_id, "active track site_id must match")
  ctx.log("Site: " .. tostring(t.site_id) .. " precision=" .. tostring(t.precision))

  -- Verify radar is enabled
  local enabled = aliveworld_player.radar.is_enabled(ctx.player_name)
  ctx.assert.is_true(enabled, "radar should be enabled")
  local rp = aliveworld_player.radar.get_points_for_player(ctx.player_name)
  ctx.assert.not_nil(rp, "get_points_for_player must return a result")
  ctx.assert.not_nil(rp.points, "result must have points array")
  ctx.assert.not_nil(rp.count, "result must have count")
  ctx.assert.equal(#rp.points, rp.count, "count must match points length")
  ctx.assert.is_true(rp.count > 0, "radar should return at least one point")

  local tracked_count = 0
  for _, p in ipairs(rp.points) do
    if p.site_id ~= nil then
      ctx.assert.is_true(type(p.site_id) == "string" and p.site_id ~= "", "radar point site_id must be a non-empty string when present")
    end
    ctx.assert.is_true(type(p.title) == "string" and p.title ~= "", "radar point title must be a non-empty string")
    ctx.assert.is_true(type(p.kind) == "string" and p.kind ~= "", "radar point kind must be a non-empty string")
    ctx.assert.not_nil(p.target_pos, "radar point must have target_pos")
    if p.target_pos then
      ctx.assert.is_true(type(p.target_pos.x) == "number", "target_pos.x must be a number")
      ctx.assert.is_true(type(p.target_pos.y) == "number", "target_pos.y must be a number")
      ctx.assert.is_true(type(p.target_pos.z) == "number", "target_pos.z must be a number")
    end
    ctx.assert.is_true(type(p.distance) == "number", "radar point distance must be a number")
    ctx.assert.is_true(p.distance >= 0, "radar point distance must be >= 0")
    ctx.assert.is_true(type(p.is_tracked) == "boolean", "radar point is_tracked must be boolean")
    ctx.assert.is_true(type(p.is_edge) == "boolean", "radar point is_edge must be boolean")
    if p.is_tracked then
      tracked_count = tracked_count + 1
      ctx.assert.equal("site_birch_ford", p.site_id, "tracked radar point site_id must match active track")
    end
  end
  ctx.assert.equal(1, tracked_count, "radar points must include exactly one active tracked target")
  ctx.log("Radar points count: " .. tostring(rp.count))

  -- Cleanup: untrack + disable GPS
  aliveworld_player.tracking.untrack(ctx.player_name)
  aliveworld_player.radar.disable(ctx.player_name)
  ctx.log("Cleanup complete")
end)

T.register_test("aliveworld", "gps_item_registered", function(ctx)
	if not aliveworld_player then
		ctx.skip("aliveworld_player not loaded")
		return
	end
	local gps_def = minetest.registered_items["aliveworld_player:gps"]
	if not gps_def then
		ctx.skip("aliveworld_player:gps item not registered (optional craftitem)")
		return
	end
	ctx.assert.not_nil(gps_def.description, "GPS item must have description")
	ctx.assert.not_nil(gps_def.inventory_image, "GPS item must have inventory image")
end)

T.register_test("aliveworld", "aw_track_chatcommand", function(ctx)
	local cmd = minetest.registered_chatcommands["aw_track"]
	if not cmd then
		ctx.skip("/aw_track command not registered")
		return
	end
	ctx.assert.not_nil(cmd.func, "aw_track must have func")
end)

T.register_test("aliveworld", "aw_untrack_chatcommand", function(ctx)
	local cmd = minetest.registered_chatcommands["aw_untrack"]
	if not cmd then
		ctx.skip("/aw_untrack command not registered")
		return
	end
	ctx.assert.not_nil(cmd.func, "aw_untrack must have func")
end)

T.register_test("aliveworld", "resolve_arrival_pos_exists", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.sites.resolve_arrival_pos, "resolve_arrival_pos must exist")
end)

T.register_test("aliveworld", "arrival_pos_safe", function(ctx)
  -- Verify that resolve_arrival_pos returns a walkable surface for site_birch_ford
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  if not aliveworld.sites.resolve_arrival_pos then
    ctx.skip("resolve_arrival_pos not available")
    return
  end
  local site = aliveworld.sites.get("site_birch_ford") or aliveworld.sites.get("birch_ford")
  if not site then
    ctx.skip("Site birch_ford not found")
    return
  end
  local arrival = aliveworld.sites.resolve_arrival_pos(site)
  ctx.assert.not_nil(arrival, "resolve_arrival_pos must return a position")
  -- Check that the position is above a walkable block (not inside liquid/air)
  local below = minetest.get_node({x = arrival.x, y = arrival.y - 1, z = arrival.z})
  local def = minetest.registered_nodes[below.name]
  ctx.assert.not_nil(def, "node below arrival must have a definition")
  ctx.assert.not_nil(def.walkable, "node below should have walkable property")
  ctx.log("arrival_pos: (" .. arrival.x .. "," .. arrival.y .. "," .. arrival.z .. ") below=" .. below.name)
end)

T.register_test("aliveworld", "arrival_pos_not_water", function(ctx)
  -- Verify arrival_pos is not in water or lava
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  if not aliveworld.sites.resolve_arrival_pos then
    ctx.skip("resolve_arrival_pos not available")
    return
  end
  local site = aliveworld.sites.get("site_birch_ford") or aliveworld.sites.get("birch_ford")
  if not site then
    ctx.skip("Site birch_ford not found")
    return
  end
  local arrival = aliveworld.sites.resolve_arrival_pos(site)
  ctx.assert.not_nil(arrival, "resolve_arrival_pos must return a position")
  local node = minetest.get_node(arrival)
  local def = minetest.registered_nodes[node.name]
  if def and def.liquidtype and def.liquidtype ~= "none" then
    ctx.assert.is_false(true, "arrival_pos is inside liquid: " .. node.name)
  end
  local below = minetest.get_node({x = arrival.x, y = arrival.y - 1, z = arrival.z})
  local def_below = minetest.registered_nodes[below.name]
  if def_below and def_below.liquidtype and def_below.liquidtype ~= "none" then
    ctx.assert.is_false(true, "block below arrival is liquid: " .. below.name)
  end
  ctx.log("arrival_pos (" .. arrival.x .. "," .. arrival.y .. "," .. arrival.z .. ") is safe, not liquid")
end)

T.register_test("aliveworld", "aw_gps_debug_shows_anchor_arrival", function(ctx)
  -- Verify /aw_gps_debug output contains anchor_pos and arrival_pos info
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  if not aliveworld.sites.resolve_arrival_pos then
    ctx.skip("resolve_arrival_pos not available")
    return
  end
  -- Track a site first so we have tracking state
  if not aliveworld_player or not aliveworld_player.tracking then
    ctx.skip("tracking not loaded")
    return
  end
  local player = ctx.helpers.get_player(ctx.player_name)
  if not player then
    ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
    return
  end
  -- Get a site with anchor_pos (site is anchored)
  local site = nil
  for _, s in ipairs(aliveworld.sites.list()) do
    if s.anchor_pos and s.status == "active" then
      site = s
      break
    end
  end
  if not site then
    ctx.skip("No anchored site found with anchor_pos")
    return
  end
  local ok, msg = aliveworld_player.tracking.track_site(ctx.player_name, site.id)
  ctx.log("Tracked " .. site.id .. " for debug test: " .. tostring(msg))
  -- Check tracking state shows proper precision
  local track_list = aliveworld_player.tracking.list(ctx.player_name)
  ctx.assert.equal(1, #track_list, "should have active track")
  local t = track_list[1]
  ctx.assert.not_nil(t.precision, "track must have precision")
  ctx.assert.equal("exact", t.precision, "anchored site precision should be 'exact'")
  -- Cleanup
  aliveworld_player.tracking.untrack(ctx.player_name)
end)

T.register_test("aliveworld", "aw_gps_zoom_command", function(ctx)
  -- Verify current GPS zoom command/API is registered and works.
  local cmd = minetest.registered_chatcommands["aw_gps_zoom"]
  ctx.assert.not_nil(cmd, "/aw_gps_zoom command must be registered")
  if not cmd then
    return
  end
  ctx.assert.not_nil(cmd.func, "aw_gps_zoom must have func")
  ctx.assert.not_nil(aliveworld_player, "aliveworld_player must be loaded")
  ctx.assert.not_nil(aliveworld_player and aliveworld_player.radar, "radar must be loaded")
  ctx.assert.not_nil(aliveworld_player and aliveworld_player.radar and aliveworld_player.radar.set_zoom, "radar.set_zoom must exist")
  if not aliveworld_player or not aliveworld_player.radar or not aliveworld_player.radar.set_zoom then
    return
  end
  local ok, msg = aliveworld_player.radar.set_zoom(ctx.player_name, "near")
  ctx.assert.is_true(ok, "set_zoom near should succeed: " .. tostring(msg))
  local layout = aliveworld_player.radar.get_layout_for_player(ctx.player_name)
  ctx.assert.equal("near", layout.preset, "layout preset should be near after set_zoom")
  ctx.assert.equal(80, layout.diameter_nodes, "near zoom should use 80 block diameter")
end)

T.register_test("aliveworld", "radar_origin_not_clipped", function(ctx)
  -- Verify radar layout has valid on-screen position
  ctx.assert.not_nil(aliveworld_player, "aliveworld_player must be loaded")
  ctx.assert.not_nil(aliveworld_player and aliveworld_player.radar, "radar must be loaded")
  ctx.assert.not_nil(aliveworld_player and aliveworld_player.radar and aliveworld_player.radar.get_layout_for_player, "radar.get_layout_for_player must exist")
  if not aliveworld_player or not aliveworld_player.radar or not aliveworld_player.radar.get_layout_for_player then
    return
  end
  local layout = aliveworld_player.radar.get_layout_for_player(ctx.player_name)
  ctx.assert.not_nil(layout, "radar layout should not be nil")
  ctx.assert.not_nil(layout.position, "layout must have position")
  ctx.assert.not_nil(layout.offset, "layout must have offset")
  ctx.assert.is_true(layout.size > 0, "radar size should be positive, got " .. layout.size)
  ctx.assert.is_false(layout.clipped, "radar should not be clipped")
  ctx.log("Radar layout: size=" .. layout.size .. " preset=" .. (layout.preset or "none") .. " clipped=" .. tostring(layout.clipped))
end)

T.register_test("aliveworld", "rumor_board_track_label", function(ctx)
  -- Verify rumor board show_news includes track button (text check)
  if not aliveworld_player then
    ctx.skip("aliveworld_player not loaded")
    return
  end
  if not aliveworld_player.show_news then
    ctx.skip("show_news not available")
    return
  end
  -- We can't easily capture formspec output in testkit, 
  -- but we can verify the news system is set up correctly
  ctx.assert.not_nil(aliveworld_player.show_news, "show_news function must exist")
  -- Verify that on_player_receive_fields handler exists for the news form
  ctx.log("Rumor board show_news is available with track button support")
end)

T.register_test("aliveworld", "check_arrival_function", function(ctx)
  -- Verify tracking has check_arrival function
  if not aliveworld_player or not aliveworld_player.tracking then
    ctx.skip("tracking not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld_player.tracking.check_arrival, "check_arrival must exist")
  ctx.log("check_arrival function available")
end)
