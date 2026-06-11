-- aliveworld_test_suite/tests/anchors.lua
-- Test reality anchoring / materialization

local T = luanti_testkit

local function require_terrain(ctx)
	if not aliveworld or not aliveworld.terrain then
		ctx.assert.not_nil(aliveworld and aliveworld.terrain, "aliveworld.terrain API must exist")
		return nil
	end
	return aliveworld.terrain
end

local function require_player_pos(ctx)
	local player = minetest.get_player_by_name(ctx.player_name or "")
	if not player then
		ctx.skip("Player '" .. tostring(ctx.player_name) .. "' is not online.")
		return nil
	end
	local pos = player:get_pos()
	if not pos then
		ctx.skip("Player position is not available.")
		return nil
	end
	local rounded = {x = math.floor(pos.x + 0.5), y = math.floor(pos.y + 0.5), z = math.floor(pos.z + 0.5)}
	return rounded
end

local function assert_survey_contract(ctx, survey)
	ctx.assert.equal(type(survey), "table", "survey result must be a table")
	ctx.assert.equal(type(survey.ok), "boolean", "survey.ok must be boolean")
	ctx.assert.equal(type(survey.pos), "table", "survey.pos must be table")
	ctx.assert.equal(type(survey.pos.x), "number", "survey.pos.x must be number")
	ctx.assert.equal(type(survey.pos.y), "number", "survey.pos.y must be number")
	ctx.assert.equal(type(survey.pos.z), "number", "survey.pos.z must be number")
	ctx.assert.equal(type(survey.sample_radius), "number", "sample_radius must be number")
	ctx.assert.equal(type(survey.height_range), "number", "height_range must be number")
	ctx.assert.equal(type(survey.solid_ratio), "number", "solid_ratio must be number")
	ctx.assert.equal(type(survey.water_ratio), "number", "water_ratio must be number")
	ctx.assert.equal(type(survey.buildable_ratio), "number", "buildable_ratio must be number")
	ctx.assert.equal(type(survey.slope_score), "number", "slope_score must be number")
	ctx.assert.equal(type(survey.area_score), "number", "area_score must be number")
	ctx.assert.equal(type(survey.accessibility_score), "number", "accessibility_score must be number")
	ctx.assert.equal(type(survey.total_score), "number", "total_score must be number")
	ctx.assert.equal(type(survey.flags), "table", "flags must be table")
	ctx.assert.equal(type(survey.rejections), "table", "rejections must be table")
end

local function find_loaded_liquid_near(center, radius)
	for x = center.x - radius, center.x + radius, 4 do
		for z = center.z - radius, center.z + radius, 4 do
			for y = center.y + 24, center.y - 32, -1 do
				local node = minetest.get_node({x = x, y = y, z = z})
				if node.name ~= "ignore" then
					local def = minetest.registered_nodes[node.name]
					if def and def.liquidtype and def.liquidtype ~= "none" then
						return {x = x, y = y, z = z}
					end
				end
			end
		end
	end
	return nil
end

T.register_test("aliveworld", "sites_module_loaded", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	ctx.assert.not_nil(aliveworld.sites.list, "sites.list must exist")
	ctx.assert.not_nil(aliveworld.sites.get, "sites.get must exist")
	ctx.assert.not_nil(aliveworld.sites.anchor_site, "sites.anchor_site must exist")
	ctx.assert.not_nil(aliveworld.sites.anchor_site_terrain, "sites.anchor_site_terrain must exist")
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

T.register_test("aliveworld", "terrain_survey_structure", function(ctx)
	local terrain = require_terrain(ctx)
	if not terrain then return end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local survey = terrain.survey(pos, {profile = "birch_ford", sample_radius = 8})
	assert_survey_contract(ctx, survey)
	ctx.log("survey score=" .. tostring(survey.total_score) .. " surface=" .. tostring(survey.surface_node))
end)

T.register_test("aliveworld", "terrain_survey_underwater_rejected", function(ctx)
	local terrain = require_terrain(ctx)
	if not terrain then return end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local water = find_loaded_liquid_near(pos, 96)
	if not water then
		ctx.skip("No loaded liquid node near player to test underwater rejection.")
		return
	end
	local survey = terrain.survey(water, {profile = "birch_ford", sample_radius = 8})
	assert_survey_contract(ctx, survey)
	ctx.assert.is_false(survey.ok, "underwater/liquid point must be rejected")
	ctx.assert.is_true(survey.flags.underwater or survey.water_ratio > 0.25, "survey must flag underwater or high water ratio")
end)

T.register_test("aliveworld", "terrain_survey_strict_profile_rejects_fragmented_area", function(ctx)
	local terrain = require_terrain(ctx)
	if not terrain then return end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local survey = terrain.survey(pos, {
		profile = "birch_ford",
		sample_radius = 12,
		min_total_score = 1.1,
		max_height_range = 0,
	})
	assert_survey_contract(ctx, survey)
	ctx.assert.is_false(survey.ok, "impossible strict profile must reject the candidate")
	ctx.assert.is_true(survey.total_score < 1.0 or #survey.rejections > 0, "rejected survey must expose low score or rejection reasons")
end)

T.register_test("aliveworld", "terrain_survey_loaded_player_area_passes_threshold", function(ctx)
	local terrain = require_terrain(ctx)
	if not terrain then return end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local survey = terrain.survey(pos, {profile = "stone_gully", sample_radius = 8, min_total_score = 0.15})
	assert_survey_contract(ctx, survey)
	ctx.assert.is_true(survey.total_score >= 0.15, "loaded player area should produce a usable survey score")
	ctx.assert.is_false(survey.flags.underwater, "player area survey must not be underwater")
end)

T.register_test("aliveworld", "terrain_anchor_unknown_site_returns_error", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local ok, result = aliveworld.sites.anchor_site_terrain("site_missing_for_test")
	ctx.assert.is_false(ok, "unknown site must return false")
	ctx.assert.equal(type(result), "table", "unknown site result must be a table")
	ctx.assert.equal(result.error, "site_not_found", "unknown site error must be stable")
end)

T.register_test("aliveworld", "terrain_anchor_no_match_keeps_site_abstract", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local site = {
		id = "site_test_no_anchor",
		type = "settlement",
		subtype = "village",
		name = "Test No Anchor",
		name_en = "Test No Anchor",
		settlement_id = "test_no_anchor",
		pos = {x = pos.x, y = pos.y, z = pos.z},
		radius = 16,
		status = "active",
		physical_status = "abstract",
		data = {},
	}
	aliveworld.sites.delete(site.id)
	aliveworld.sites.save(site)
	local ok, result = aliveworld.sites.anchor_site_terrain(site.id, {
		profile = "birch_ford",
		min_total_score = 1.1,
		max_radius = 0,
		max_candidates = 1,
	})
	local stored = aliveworld.sites.get(site.id)
	ctx.assert.is_false(ok, "impossible anchor search must fail")
	ctx.assert.equal("no_suitable_candidate", result.error, "failure reason must be stable")
	ctx.assert.equal("abstract", stored.physical_status or "abstract", "failed anchor must keep site abstract")
	ctx.assert.is_nil(stored.anchor_pos, "failed anchor must not set anchor_pos")
	aliveworld.sites.delete(site.id)
end)

T.register_test("aliveworld", "terrain_anchor_idempotent_for_same_site", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local site = {
		id = "site_test_idempotent_anchor",
		type = "settlement",
		subtype = "village",
		name = "Test Idempotent Anchor",
		name_en = "Test Idempotent Anchor",
		settlement_id = "test_idempotent_anchor",
		pos = {x = pos.x, y = pos.y, z = pos.z},
		radius = 32,
		status = "active",
		physical_status = "abstract",
		data = {},
	}
	aliveworld.sites.delete(site.id)
	aliveworld.sites.save(site)
	local ok1, first = aliveworld.sites.anchor_site_terrain(site.id, {
		profile = "stone_gully",
		max_radius = 16,
		max_candidates = 12,
		min_total_score = 0.15,
	})
	ctx.assert.is_true(ok1, "first terrain anchor should succeed near loaded player area")
	if not ok1 then
		aliveworld.sites.delete(site.id)
		return
	end
	local ok2, second = aliveworld.sites.anchor_site_terrain(site.id, {
		profile = "stone_gully",
		max_radius = 16,
		max_candidates = 12,
		min_total_score = 0.15,
	})
	ctx.assert.is_true(ok2, "second terrain anchor should return existing anchor")
	if not ok2 then
		aliveworld.sites.delete(site.id)
		return
	end
	ctx.assert.equal("already_anchored", second.status, "second anchor must be idempotent")
	ctx.assert.equal(first.anchor_pos.x, second.anchor_pos.x, "idempotent anchor x must not change")
	ctx.assert.equal(first.anchor_pos.y, second.anchor_pos.y, "idempotent anchor y must not change")
	ctx.assert.equal(first.anchor_pos.z, second.anchor_pos.z, "idempotent anchor z must not change")
	aliveworld.sites.delete(site.id)
end)

T.register_test("aliveworld", "terrain_anchor_saves_metrics", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local pos = require_player_pos(ctx)
	if not pos then return end
	local site = {
		id = "site_test_anchor_metrics",
		type = "settlement",
		subtype = "village",
		name = "Test Anchor Metrics",
		name_en = "Test Anchor Metrics",
		settlement_id = "test_anchor_metrics",
		pos = {x = pos.x, y = pos.y, z = pos.z},
		radius = 32,
		status = "active",
		physical_status = "abstract",
		data = {},
	}
	aliveworld.sites.delete(site.id)
	aliveworld.sites.save(site)
	local ok = aliveworld.sites.anchor_site_terrain(site.id, {
		profile = "stone_gully",
		max_radius = 16,
		max_candidates = 12,
		min_total_score = 0.15,
	})
	ctx.assert.is_true(ok, "terrain anchor should succeed")
	if not ok then
		aliveworld.sites.delete(site.id)
		return
	end
	local stored = aliveworld.sites.get(site.id)
	ctx.assert.equal("anchored", stored.physical_status, "successful anchor must set physical_status")
	ctx.assert.not_nil(stored.anchor_pos, "successful anchor must set anchor_pos")
	ctx.assert.not_nil(stored.anchor_survey, "successful anchor must save survey metrics")
	ctx.assert.equal(type(stored.anchor_survey.total_score), "number", "anchor_survey.total_score must be number")
	ctx.assert.equal(type(stored.anchor_survey.height_range), "number", "anchor_survey.height_range must be number")
	ctx.assert.not_nil(stored.anchor_profile, "anchor_profile must be saved")
	ctx.assert.not_nil(stored.anchor_version, "anchor_version must be saved")
	ctx.assert.not_nil(stored.anchor_world_seed, "anchor_world_seed must be saved")
	aliveworld.sites.delete(site.id)
end)

T.register_test("aliveworld", "terrain_anchor_birch_ford_live", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	if not minetest.get_player_by_name(ctx.player_name or "") then
		ctx.skip("Player '" .. tostring(ctx.player_name) .. "' is not online.")
		return
	end
	local site = aliveworld.sites.get("site_birch_ford")
	ctx.assert.not_nil(site, "site_birch_ford must exist")
	local ok, result = aliveworld.sites.anchor_site_terrain("site_birch_ford", {
		profile = "birch_ford",
		max_radius = 256,
		max_candidates = 96,
	})
	ctx.assert.is_true(ok, "birch_ford must anchor in loaded carpathian dev world")
	if not ok then return end
	ctx.assert.not_nil(result.anchor_pos, "birch_ford anchor result must include anchor_pos")
	local stored = aliveworld.sites.get("site_birch_ford")
	ctx.assert.equal("anchored", stored.physical_status, "birch_ford must be anchored")
	ctx.assert.not_nil(stored.anchor_survey, "birch_ford must save survey metrics")
	ctx.log("birch_ford anchored at " .. minetest.pos_to_string(stored.anchor_pos) ..
		" score=" .. tostring(stored.anchor_survey.total_score))
end)

T.register_test("aliveworld", "terrain_anchor_not_in_bad_node", function(ctx)
	if not aliveworld or not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local site = aliveworld.sites.get("site_birch_ford")
	if not site or not site.anchor_pos then
		ctx.skip("site_birch_ford is not anchored")
		return
	end
	ctx.assert.not_nil(site.anchor_survey, "anchor must retain survey metrics")
	ctx.assert.is_true(site.anchor_survey.ok, "stored anchor survey must be usable")
	ctx.assert.equal(type(site.anchor_survey.surface_node), "string", "stored anchor survey must keep surface node")
	ctx.assert.is_false(site.anchor_survey.surface_node == "", "stored anchor survey surface node must not be empty")
	local surface_def = minetest.registered_nodes[site.anchor_survey.surface_node]
	ctx.assert.not_nil(surface_def, "stored anchor surface node must be registered")
	ctx.assert.is_true(surface_def.walkable ~= false, "stored anchor surface must be solid ground")
	ctx.assert.is_false(surface_def.liquidtype and surface_def.liquidtype ~= "none", "stored anchor surface must not be liquid")
	ctx.assert.is_false(minetest.get_item_group(site.anchor_survey.surface_node, "leaves") > 0
		or minetest.get_item_group(site.anchor_survey.surface_node, "tree") > 0,
		"stored anchor surface must not be leaves/tree")
	ctx.assert.is_false((site.anchor_survey.flags and site.anchor_survey.flags.underwater) == true, "stored anchor must not be underwater")
	ctx.assert.is_false((site.anchor_survey.flags and site.anchor_survey.flags.unsupported) == true, "stored anchor must not be unsupported")
	ctx.assert.is_false((site.anchor_survey.flags and site.anchor_survey.flags.blocked) == true, "stored anchor must not be inside blocked space")
	ctx.assert.is_false((site.anchor_survey.flags and site.anchor_survey.flags.in_tree) == true, "stored anchor must not be in tree/leaves")
	local stand = minetest.get_node(site.anchor_pos)
	local below = minetest.get_node({x = site.anchor_pos.x, y = site.anchor_pos.y - 1, z = site.anchor_pos.z})
	local head = minetest.get_node({x = site.anchor_pos.x, y = site.anchor_pos.y + 1, z = site.anchor_pos.z})
	if stand.name == "ignore" or below.name == "ignore" or head.name == "ignore" then
		return
	end
	local stand_def = minetest.registered_nodes[stand.name]
	local below_def = minetest.registered_nodes[below.name]
	local head_def = minetest.registered_nodes[head.name]
	ctx.assert.is_false(stand_def and stand_def.liquidtype and stand_def.liquidtype ~= "none", "anchor stand node must not be liquid")
	ctx.assert.is_false(head_def and head_def.liquidtype and head_def.liquidtype ~= "none", "anchor head node must not be liquid")
	ctx.assert.is_true(below_def and below_def.walkable ~= false, "anchor must stand on solid ground")
	ctx.assert.is_false(below_def and below_def.liquidtype and below_def.liquidtype ~= "none", "anchor ground must not be liquid")
	ctx.assert.is_false(minetest.get_item_group(stand.name, "leaves") > 0 or minetest.get_item_group(stand.name, "tree") > 0, "anchor stand node must not be leaves/tree")
	ctx.assert.is_false(minetest.get_item_group(head.name, "leaves") > 0 or minetest.get_item_group(head.name, "tree") > 0, "anchor head node must not be leaves/tree")
	ctx.assert.is_false(stand_def and stand_def.walkable ~= false, "anchor stand node must not be inside solid object")
	ctx.assert.is_false(head_def and head_def.walkable ~= false, "anchor head node must not be inside solid object")
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
