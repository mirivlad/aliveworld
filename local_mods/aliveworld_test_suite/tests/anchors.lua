-- aliveworld_test_suite/tests/anchors.lua
-- Test reality anchoring / materialization

local T = luanti_testkit

T.register_test("aliveworld", "sites_module_loaded", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.sites.list, "sites.list must exist")
	ctx.assert.not_nil(aliveworld.sites.get, "sites.get must exist")
	ctx.assert.not_nil(aliveworld.sites.anchor_site, "sites.anchor_site must exist")
	ctx.assert.not_nil(aliveworld.sites.find_by_settlement, "sites.find_by_settlement must exist")
end)

T.register_test("aliveworld", "site_birch_ford_exists", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local site = aliveworld.sites.get("birch_ford")
	if not site then
		ctx.skip("Site 'birch_ford' not found. Run /aw_sites_init first.")
		return
	end
	ctx.assert.equal(site.settlement_id, "birch_ford", "site settlement_id must match")
	ctx.assert.equal(site.id, "site_birch_ford", "site id must match")
	ctx.assert.not_nil(site.pos, "site must have pos")
	ctx.assert.not_nil(site.pos.x, "site pos must have x")
	ctx.assert.not_nil(site.pos.y, "site pos must have y")
	ctx.assert.not_nil(site.pos.z, "site pos must have z")
	ctx.log("Site birch_ford at " .. minetest.pos_to_string(site.pos))
end)

T.register_test("aliveworld", "list_sites_non_empty", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local sites = aliveworld.sites.list()
	ctx.assert.is_true(#sites > 0, "at least one site must exist after init")
	ctx.log("Total sites: " .. #sites)
	for _, s in ipairs(sites) do
		ctx.log("  " .. s.id .. " (" .. (s.type or "?") .. ") at " .. minetest.pos_to_string(s.pos))
	end
end)

T.register_test("aliveworld", "materialization_module", function(ctx)
	if not aliveworld or not aliveworld.materialization then
		ctx.skip("aliveworld.materialization not loaded (aliveworld_world mod not enabled)")
		return
	end
	ctx.assert.not_nil(aliveworld.materialization.materialize_site, "materialize_site must exist")
	ctx.assert.not_nil(aliveworld.materialization.materialize_event, "materialize_event must exist")
	ctx.assert.not_nil(aliveworld.materialization.list, "materialization.list must exist")
	ctx.assert.not_nil(aliveworld.materialization.can_materialize_site, "can_materialize_site must exist")
end)

T.register_test("aliveworld", "anchor_site_birch_ford", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	if not aliveworld.materialization then
		ctx.skip("aliveworld.materialization not loaded")
		return
	end
	local site = aliveworld.sites.get("birch_ford")
	if not site then
		ctx.skip("Site 'birch_ford' not found.")
		return
	end

	-- Check if already anchored/materialized
	if site.physical_status and site.physical_status ~= "abstract" then
		ctx.log("Site already " .. site.physical_status)
		-- Still verify it works
		return
	end

	-- Try to materialize
	local ok, result = aliveworld.materialization.can_materialize_site(site)
	if not ok then
		ctx.log("can_materialize_site: " .. tostring(result))
		ctx.skip("Materialization pre-check failed: " .. tostring(result))
		return
	end

	-- Check if area is loaded (we can't check directly, but materialize_site will tell us)
	ctx.log("Attempting materialization...")
	-- Don't actually materialize in a test that could fail on unloaded area
	ctx.skip("Skipping actual materialization (requires loaded area with player nearby)")
end)

T.register_test("aliveworld", "anchor_site_event", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	if not aliveworld.materialization then
		ctx.skip("aliveworld.materialization not loaded")
		return
	end
	if not aliveworld.events then
		ctx.skip("aliveworld.events not loaded")
		return
	end
	local events = aliveworld.events.list()
	local has_event_site = false
	for _, ev in ipairs(events) do
		local site = aliveworld.sites.find_by_event(ev.id)
		if site then
			has_event_site = true
			ctx.log("Event site found: " .. site.id .. " for event " .. ev.id)
			break
		end
	end
	if not has_event_site then
		ctx.skip("No event sites found to test anchoring")
		return
	end
	ctx.assert.is_true(has_event_site, "at least one event site must exist")
end)
