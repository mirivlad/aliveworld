-- aliveworld_test_suite/tests/rumors.lua
-- Test rumors module

local T = luanti_testkit

T.register_test("aliveworld", "rumors_module_loaded", function(ctx)
	if not aliveworld or not aliveworld.rumors then
		ctx.skip("aliveworld.rumors not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.rumors.list, "rumors.list must exist")
	ctx.assert.not_nil(aliveworld.rumors.get, "rumors.get must exist")
	ctx.assert.not_nil(aliveworld.rumors.save, "rumors.save must exist")
	ctx.assert.not_nil(aliveworld.rumors.create_from_event, "rumors.create_from_event must exist")
	ctx.assert.not_nil(aliveworld.rumors.expire_old, "rumors.expire_old must exist")
	ctx.assert.not_nil(aliveworld.rumors.next_id, "rumors.next_id must exist")
end)

T.register_test("aliveworld", "rumors_list_structure", function(ctx)
	if not aliveworld or not aliveworld.rumors then
		ctx.skip("aliveworld.rumors not loaded")
		return
	end
	local rumors = aliveworld.rumors.list()
	ctx.assert.not_nil(rumors, "rumors.list must return a table")
	ctx.log("Total rumors: " .. #rumors)

	for _, r in ipairs(rumors) do
		ctx.assert.not_nil(r.id, "each rumor must have id")
		ctx.assert.not_nil(r.status, "each rumor must have status")
		-- Verify status is valid
		local valid_status = {active = true, expired = true}
		ctx.assert.is_true(valid_status[r.status] ~= nil,
			"rumor status must be 'active' or 'expired', got '" .. tostring(r.status) .. "'")
		-- Either text_ru or text_en should exist
		local has_text = (r.text_ru and r.text_ru ~= "") or (r.text_en and r.text_en ~= "")
		if not has_text then
			ctx.log("Rumor " .. r.id .. " has no text_ru or text_en")
		end
		ctx.log("Rumor " .. r.id .. ": status=" .. r.status ..
			" event_id=" .. tostring(r.event_id) ..
			" text_en=" .. (r.text_en or ""))
	end
end)

T.register_test("aliveworld", "events_module_loaded", function(ctx)
	if not aliveworld or not aliveworld.events then
		ctx.skip("aliveworld.events not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.events.list, "events.list must exist")
	ctx.assert.not_nil(aliveworld.events.get, "events.get must exist")
	ctx.assert.not_nil(aliveworld.events.create, "events.create must exist")
	ctx.assert.not_nil(aliveworld.events.active_count, "events.active_count must exist")
end)

T.register_test("aliveworld", "world_events_chatcommands", function(ctx)
	local cmds = {"aw_events", "aw_event", "aw_rumors", "aw_rumor"}
	for _, cmd_name in ipairs(cmds) do
		local cmd = minetest.registered_chatcommands[cmd_name]
		if not cmd then
			ctx.log("Command /" .. cmd_name .. " not registered")
		else
			ctx.log("Command /" .. cmd_name .. " registered")
		end
	end
end)

T.register_test("aliveworld", "chronicle_has_events", function(ctx)
	if not aliveworld then
		ctx.skip("aliveworld not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.get_events, "get_events must exist")
	local events = aliveworld.get_events(5)
	ctx.assert.not_nil(events, "get_events must return a table")
	ctx.log("Chronicle events (last 5): " .. #events)
end)

T.register_test("aliveworld", "player_rumors_ui", function(ctx)
	if not aliveworld_player then
		ctx.skip("aliveworld_player not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld_player.show_news, "show_news must exist")
	ctx.assert.not_nil(aliveworld_player.show_world, "show_world must exist")
	ctx.assert.not_nil(aliveworld_player.show_chronicle, "show_chronicle must exist")
end)
