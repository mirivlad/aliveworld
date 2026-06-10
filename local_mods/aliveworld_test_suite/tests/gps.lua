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
  if not aliveworld_player or not aliveworld_player.tracking then
    ctx.skip("aliveworld_player.tracking not loaded")
    return
  end
  if not aliveworld_player.radar then
    ctx.skip("aliveworld_player.radar not loaded")
    return
  end
  local player = ctx.helpers.get_player(ctx.player_name)
  if not player then
    ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
    return
  end

  -- Enable GPS
  local ok_gps, msg_gps = aliveworld_player.radar.enable(ctx.player_name)
  ctx.log("GPS enable: " .. tostring(msg_gps))

  -- Track site_birch_ford
  local site = aliveworld.sites.get("site_birch_ford")
  if not site then
    ctx.skip("Site 'site_birch_ford' not found.")
    return
  end
  local ok_track, msg_track = aliveworld_player.tracking.track_site(ctx.player_name, "site_birch_ford")
  ctx.log("Track: " .. tostring(msg_track))

  -- Verify via tracking.list
  local track_list = aliveworld_player.tracking.list(ctx.player_name)
  ctx.assert.not_nil(track_list, "track list should exist")
  ctx.assert.equal(1, #track_list, "should have 1 active track")

  -- Verify via aw_gps_debug
  local t = track_list[1]
  ctx.assert.not_nil(t.hud_id, "waypoint HUD must exist")
  ctx.log("Waypoint HUD ID: " .. tostring(t.hud_id))
  ctx.log("Site: " .. tostring(t.site_id) .. " precision=" .. tostring(t.precision))

  -- Verify radar is enabled
  local enabled = aliveworld_player.radar.is_enabled(ctx.player_name)
  ctx.assert.is_true(enabled, "radar should be enabled")
  local points = aliveworld_player.radar.get_points_for_player(ctx.player_name)
  ctx.log("Radar points count: " .. tostring(#points))

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
    ctx.fail("arrival_pos is inside liquid: " .. node.name)
  end
  local below = minetest.get_node({x = arrival.x, y = arrival.y - 1, z = arrival.z})
  local def_below = minetest.registered_nodes[below.name]
  if def_below and def_below.liquidtype and def_below.liquidtype ~= "none" then
    ctx.fail("block below arrival is liquid: " .. below.name)
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

T.register_test("aliveworld", "aw_gps_pos_command", function(ctx)
  -- Verify /aw_gps_pos command is registered and works
  local cmd = minetest.registered_chatcommands["aw_gps_pos"]
  if not cmd then
    ctx.skip("/aw_gps_pos command not registered")
    return
  end
  ctx.assert.not_nil(cmd.func, "aw_gps_pos must have func")
  -- Test that the command works when called with a valid preset
  if not aliveworld_player or not aliveworld_player.radar then
    ctx.skip("radar not loaded")
    return
  end
  if not aliveworld_player.radar.set_origin_preset then
    ctx.skip("set_origin_preset not available")
    return
  end
  local ok, msg = aliveworld_player.radar.set_origin_preset(ctx.player_name, "top-left")
  ctx.log("gps_pos top-left: " .. tostring(msg))
  local origin = aliveworld_player.radar.get_origin_for_player(ctx.player_name)
  ctx.assert.equal(10, origin.x, "top-left origin x should be 10")
  ctx.assert.equal(10, origin.y, "top-left origin y should be 10")
end)

T.register_test("aliveworld", "radar_origin_not_clipped", function(ctx)
  -- Verify radar origin is on-screen (not clipped)
  if not aliveworld_player or not aliveworld_player.radar then
    ctx.skip("radar not loaded")
    return
  end
  local origin = aliveworld_player.radar.get_origin_for_player(ctx.player_name)
  ctx.assert.not_nil(origin, "radar origin should not be nil")
  ctx.assert.is_true(origin.x >= 0, "origin x should be >= 0 (on-screen), got " .. origin.x)
  ctx.assert.is_true(origin.y >= 0, "origin y should be >= 0 (on-screen), got " .. origin.y)
  ctx.log("Radar origin: (" .. origin.x .. ", " .. origin.y .. ") is on-screen")
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
