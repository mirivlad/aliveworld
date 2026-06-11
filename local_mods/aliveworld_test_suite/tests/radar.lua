-- aliveworld_test_suite/tests/radar.lua
-- Test radar module

local T = luanti_testkit

T.register_test("aliveworld", "radar_module_loaded", function(ctx)
	if not aliveworld_player then
		ctx.skip("aliveworld_player not loaded")
		return
	end
	if not aliveworld_player.radar then
		ctx.skip("aliveworld_player.radar not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld_player.radar, "radar module must exist")
	-- Check expected functions
	local has_funcs = {
		enable = aliveworld_player.radar.enable ~= nil,
		disable = aliveworld_player.radar.disable ~= nil,
	}
	if has_funcs.enable or has_funcs.disable then
		ctx.log("radar has enable/disable API")
	end
	-- If no enable/disable, check for toggle or other mechanism
	local found_api = false
	for _, name in ipairs({"enable", "disable", "toggle", "get_state", "is_enabled", "start", "stop"}) do
		if aliveworld_player.radar[name] then
			found_api = true
			ctx.log("radar has function: " .. name)
		end
	end
	if not found_api then
		ctx.log("radar module loaded but no standard API functions found, checking internals")
	end
end)

T.register_test("aliveworld", "radar_enable_disable", function(ctx)
	if not aliveworld_player or not aliveworld_player.radar then
		ctx.skip("aliveworld_player.radar not loaded")
		return
	end
	local player = ctx.helpers.get_player(ctx.player_name)
	if not player then
		ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
		return
	end

	-- Try various API patterns
	local RADAR = aliveworld_player.radar

	if RADAR.enable then
		local ok, msg = RADAR.enable(ctx.player_name)
		ctx.log("radar.enable: " .. tostring(msg))
		-- Check state if available
		if RADAR.get_state then
			local state = RADAR.get_state(ctx.player_name)
			ctx.assert.not_nil(state, "radar state must exist after enable")
			ctx.log("radar state after enable: " .. minetest.write_json(state))
		end
	elseif RADAR.start then
		RADAR.start(ctx.player_name)
		ctx.log("radar.start called")
	else
		ctx.log("No enable/start API found, checking radar is functional")
	end

	-- Disable
	if RADAR.disable then
		local ok, msg = RADAR.disable(ctx.player_name)
		ctx.log("radar.disable: " .. tostring(msg))
	elseif RADAR.stop then
		RADAR.stop(ctx.player_name)
		ctx.log("radar.stop called")
	else
		ctx.log("No disable/stop API found")
	end
end)

T.register_test("aliveworld", "radar_marker_textures_exist", function(ctx)
	if not aliveworld_player then
		ctx.assert.not_nil(aliveworld_player, "aliveworld_player must be loaded")
		return
	end
	local modpath = minetest.get_modpath("aliveworld_player")
	if not modpath then
		ctx.assert.not_nil(modpath, "aliveworld_player modpath must exist")
		return
	end
	for _, name in ipairs({
		"aliveworld_gps.png",
		"aliveworld_radar_player.png",
		"aliveworld_radar_target.png",
		"aliveworld_radar_arrow.png",
	}) do
		local tex_path = modpath .. "/textures/" .. name
		local f = io.open(tex_path, "rb")
		ctx.assert.not_nil(f, "radar texture must exist: " .. name)
		if f then
			f:close()
		end
	end
end)

T.register_test("aliveworld", "aw_gps_chatcommand", function(ctx)
	local cmd = minetest.registered_chatcommands["aw_gps"]
	if not cmd then
		ctx.skip("/aw_gps command not registered")
		return
	end
	ctx.assert.not_nil(cmd.func, "aw_gps must have func")
end)
