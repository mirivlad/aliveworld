-- aliveworld_test_suite/tests/direction.lua
-- Test direction/sites API functions

local T = luanti_testkit
local SITE_BIRCH_FORD = "birch_ford"
local TEST_POS = {x = 245, y = 23, z = -145}
local TARGET_POS = {x = 320, y = 8, z = -180}

T.register_test("aliveworld", "direction_api_exists", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.sites.distance, "sites.distance must exist")
	ctx.assert.not_nil(aliveworld.sites.direction_index, "sites.direction_index must exist")
	ctx.assert.not_nil(aliveworld.sites.direction_name_en, "sites.direction_name_en must exist")
	ctx.assert.not_nil(aliveworld.sites.direction_name_ru, "sites.direction_name_ru must exist")
	ctx.assert.not_nil(aliveworld.sites.format_direction_en, "sites.format_direction_en must exist")
	ctx.assert.not_nil(aliveworld.sites.format_direction_ru, "sites.format_direction_ru must exist")
end)

T.register_test("aliveworld", "distance_calculation", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local dist = aliveworld.sites.distance(TEST_POS, TARGET_POS)
	-- dx = 75, dz = -35 -> sqrt(75^2 + 35^2) = sqrt(5625+1225) = sqrt(6850) ≈ 82.76 -> floor => 83
	ctx.assert.equal(dist, 83, "distance should be ~83 blocks")
end)

T.register_test("aliveworld", "cardinal_directions", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local DIR = aliveworld.sites

	-- (0,0) -> (100,0) = east
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=100,z=0}), "east", "0->+x is east")
	-- (0,0) -> (-100,0) = west
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=-100,z=0}), "west", "0->-x is west")
	-- (0,0) -> (0,-100) = north (note: -z = north in Luanti)
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=0,z=-100}), "north", "0->-z is north")
	-- (0,0) -> (0,100) = south
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=0,z=100}), "south", "0->+z is south")
end)

T.register_test("aliveworld", "intercardinal_directions", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local DIR = aliveworld.sites

	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=100,z=-100}), "north-east", "+x,-z is north-east")
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=100,z=100}), "south-east", "+x,+z is south-east")
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=-100,z=-100}), "north-west", "-x,-z is north-west")
	ctx.assert.equal(DIR.direction_name_en({x=0,z=0}, {x=-100,z=100}), "south-west", "-x,+z is south-west")
end)

T.register_test("aliveworld", "direction_birch_ford_regression", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	-- expected: from (245,23,-145) to (320,8,-180) = north-east
	-- dx = 75, dz = -35 -> dx positive, dz negative -> north-east
	local dir = aliveworld.sites.direction_name_en(TEST_POS, TARGET_POS)
	ctx.assert.equal(dir, "north-east",
		"from (245,23,-145) to (320,8,-180) expected north-east, got " .. tostring(dir))
end)

T.register_test("aliveworld", "distance_birch_ford_regression", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local dist = aliveworld.sites.distance(TEST_POS, TARGET_POS)
	ctx.assert.equal(dist, 83,
		"distance from (245,23,-145) to (320,8,-180) expected ~83, got " .. tostring(dist))
end)

T.register_test("aliveworld", "compass_site", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	-- Require player for position reference
	local player = ctx.helpers.get_player(ctx.player_name)
	if not player then
		ctx.skip("Player '" .. ctx.player_name .. "' is not online. Start a test client and reconnect.")
		return
	end
	-- Find the birch_ford site
	local site = aliveworld.sites.get(SITE_BIRCH_FORD)
	if not site then
		ctx.skip("Site '" .. SITE_BIRCH_FORD .. "' not found. Run /aw_sites_init first.")
		return
	end
	-- Teleport player to reference position
	ctx.helpers.set_pos(ctx.player_name, TEST_POS)
	ctx.helpers.wait(0.1)

	-- Check direction from player to site
	local dir_en = aliveworld.sites.direction_name_en(TEST_POS, site.pos)
	local dir_ru = aliveworld.sites.direction_name_ru(TEST_POS, site.pos)
	ctx.assert.not_nil(dir_en, "direction_name_en must return a string")
	ctx.assert.not_nil(dir_ru, "direction_name_ru must return a string")
	ctx.log("Direction from TEST_POS to " .. SITE_BIRCH_FORD .. ": " .. dir_en .. " / " .. dir_ru)
end)

T.register_test("aliveworld", "distance_decreases", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local player = ctx.helpers.get_player(ctx.player_name)
	if not player then
		ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
		return
	end
	local site = aliveworld.sites.get(SITE_BIRCH_FORD)
	if not site then
		ctx.skip("Site '" .. SITE_BIRCH_FORD .. "' not found.")
		return
	end
	-- Measure distance from far point
	local far_pos = {x = 1000, y = 23, z = 1000}
	local far_dist = aliveworld.sites.distance(far_pos, site.pos)

	-- Measure distance from near point (the TEST_POS)
	local near_dist = aliveworld.sites.distance(TEST_POS, site.pos)

	ctx.assert.is_true(near_dist < far_dist,
		"distance from TEST_POS must be less than from far away point. near=" .. near_dist .. ", far=" .. far_dist)
	ctx.log("Near distance: " .. near_dist .. ", far distance: " .. far_dist)
end)
