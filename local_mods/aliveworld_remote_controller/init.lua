-- remote_controller.lua
-- Acts as a remote control for AliveWorld.
-- Polls a JSON file in the worldpath and executes commands.
-- To trigger: write JSON to /config/.minetest/worlds/aliveworld/rc_cmd.json
-- Supported external command formats:
--   {"command":"teleport","pos":{"x":0,"y":4,"z":0},"player":"awbot"}
--   {"command":"runchat","chatcmd":"aw_gps","params":"on","player":"awbot"}

local worldpath = minetest.get_worldpath()
local rc_file = worldpath .. "/rc_cmd.json"
local last_mtime = 0

minetest.register_globalstep(function(dtime)
	-- Poll every 2 seconds
	local stat = io.open(rc_file, "r")
	if not stat then return end
	local mtime = stat:read("*a")
	stat:close()
	
	if mtime == last_mtime or #mtime == 0 then return end
	last_mtime = mtime
	
	-- Parse JSON
	local ok, data = pcall(minetest.parse_json, mtime)
	if not ok or not data then
		minetest.log("warning", "[rc_controller] Invalid JSON in rc_cmd.json")
		return
	end
	
	local cmd = data.command
	local player = data.player or "awbot"
	
	if cmd == "teleport" and data.pos then
		local pos = data.pos
		if player == "all" then
			for _, p in ipairs(minetest.get_connected_players()) do
				p:set_pos(pos)
			end
		else
			local pobj = minetest.get_player_by_name(player)
			if pobj then
				pobj:set_pos(pos)
				minetest.log("action", "[rc_controller] Teleported " .. player .. " to " .. minetest.pos_to_string(pos))
			end
		end
	elseif cmd == "runchat" and data.chatcmd then
		-- Execute a registered chat command for the player
		local cdef = minetest.registered_chatcommands[data.chatcmd]
		if cdef then
			local ok, msg = cdef.func(player, data.params or "")
			minetest.log("action", "[rc_controller] /" .. data.chatcmd .. " " .. (data.params or "") .. " as " .. player .. " -> " .. tostring(ok) .. ": " .. tostring(msg))
		else
			minetest.log("warning", "[rc_controller] Chat command /" .. data.chatcmd .. " not found")
		end
	elseif cmd == "whereami" then
		local pobj = minetest.get_player_by_name(player)
		if pobj then
			local pos = pobj:get_pos()
			minetest.log("action", "[rc_controller] " .. player .. " is at " .. minetest.pos_to_string(pos))
		end
	elseif cmd == "runall" then
		-- Run all tests with specified player
		if luanti_testkit and luanti_testkit.run_all then
			luanti_testkit.run_all({player_name = player})
			minetest.log("action", "[rc_controller] Running all tests for " .. player)
		end
	elseif cmd == "kick" then
		-- Kick a player from the server
		local target = data.target or player
		minetest.kick_player(target, "remote controller requested disconnect")
		minetest.log("action", "[rc_controller] Kicked " .. target .. " from server")
	else
		minetest.log("warning", "[rc_controller] Unknown command: " .. tostring(cmd))
	end
	
	-- Remove the file after processing
	os.remove(rc_file)
end)

minetest.log("action", "[rc_controller] loaded")
