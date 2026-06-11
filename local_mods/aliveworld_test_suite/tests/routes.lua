-- aliveworld_test_suite/tests/routes.lua
-- Test route planning, spatial claims, and terrain-aware route costs.

local T = luanti_testkit

local function require_routes(ctx)
	if not aliveworld or not aliveworld.routes then
		ctx.assert.not_nil(aliveworld and aliveworld.routes, "aliveworld.routes API must exist")
		return nil
	end
	return aliveworld.routes
end

local function require_claims(ctx)
	if not aliveworld or not aliveworld.claims then
		ctx.assert.not_nil(aliveworld and aliveworld.claims, "aliveworld.claims API must exist")
		return nil
	end
	return aliveworld.claims
end

local function copy_pos(pos)
	return {x = pos.x, y = pos.y, z = pos.z}
end

local function make_site(id, settlement_id, pos, anchored)
	return {
		id = id,
		type = "settlement",
		subtype = "village",
		name = id,
		name_en = id,
		settlement_id = settlement_id,
		pos = copy_pos(pos),
		radius = 24,
		status = "active",
		physical_status = anchored and "anchored" or "abstract",
		anchor_pos = anchored and copy_pos(pos) or nil,
		data = {},
	}
end

local function cleanup_test_state()
	if aliveworld and aliveworld.routes then
		aliveworld.routes.delete("test_route")
		aliveworld.routes.delete("test_route_blocked")
		aliveworld.routes.delete("old_road_test")
	end
	if aliveworld and aliveworld.claims then
		aliveworld.claims.delete("route:test_route")
		aliveworld.claims.delete("route:test_route_blocked")
		aliveworld.claims.delete("site:test_claim_core")
	end
	if aliveworld and aliveworld.sites then
		aliveworld.sites.delete("site_test_from")
		aliveworld.sites.delete("site_test_to")
		aliveworld.sites.delete("site_test_unanchored")
		aliveworld.sites.delete("site_test_claim_core")
	end
end

T.register_test("aliveworld", "routes_api_loaded", function(ctx)
	local routes = require_routes(ctx)
	if not routes then return end
	ctx.assert.not_nil(routes.get, "routes.get must exist")
	ctx.assert.not_nil(routes.plan_route, "routes.plan_route must exist")
	ctx.assert.not_nil(routes.start_plan_route, "routes.start_plan_route must exist")
	ctx.assert.not_nil(routes.get_graph, "routes.get_graph must exist")
	ctx.assert.not_nil(routes.validate_route, "routes.validate_route must exist")
	local claims = require_claims(ctx)
	if not claims then return end
	ctx.assert.not_nil(claims.register, "claims.register must exist")
	ctx.assert.not_nil(claims.check, "claims.check must exist")
end)

T.register_test("aliveworld", "route_unknown_returns_structured_error", function(ctx)
	local routes = require_routes(ctx)
	if not routes then return end
	local ok, result = routes.plan_route("missing_route_for_test")
	ctx.assert.is_false(ok, "unknown route must not plan")
	ctx.assert.equal(type(result), "table", "unknown route result must be a table")
	ctx.assert.equal("route_not_found", result.error, "unknown route error must be stable")
end)

T.register_test("aliveworld", "route_unknown_endpoint_rejected", function(ctx)
	local routes = require_routes(ctx)
	if not routes then return end
	local ok, result = routes.plan_route("test_route", {
		route_id = "test_route",
		from_site_id = "site_missing_from",
		to_site_id = "site_missing_to",
		sync = true,
	})
	ctx.assert.is_false(ok, "unknown endpoint must reject route planning")
	ctx.assert.equal("endpoint_not_found", result.error, "endpoint error must be stable")
	ctx.assert.is_nil(routes.get("test_route"), "failed endpoint validation must not save a route")
end)

T.register_test("aliveworld", "route_unanchored_endpoint_rejected", function(ctx)
	cleanup_test_state()
	local routes = require_routes(ctx)
	if not routes then return end
	if not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	aliveworld.sites.save(make_site("site_test_from", "test_from", {x = 0, y = 8, z = 0}, true))
	aliveworld.sites.save(make_site("site_test_unanchored", "test_unanchored", {x = 32, y = 8, z = 0}, false))
	local ok, result = routes.plan_route("test_route", {
		route_id = "test_route",
		from_site_id = "site_test_from",
		to_site_id = "site_test_unanchored",
		sync = true,
	})
	ctx.assert.is_false(ok, "unanchored endpoint must reject route planning")
	ctx.assert.equal("endpoint_not_anchored", result.error, "unanchored endpoint error must be stable")
	ctx.assert.is_nil(routes.get("test_route"), "failed anchor validation must not save a route")
	cleanup_test_state()
end)

T.register_test("aliveworld", "route_cost_orders_flat_slope_steep_water", function(ctx)
	if not aliveworld or not aliveworld.terrain or not aliveworld.terrain.route_step_cost then
		ctx.assert.not_nil(aliveworld and aliveworld.terrain and aliveworld.terrain.route_step_cost, "terrain.route_step_cost must exist")
		return
	end
	local base = {
		pos = {x = 0, y = 8, z = 0},
		flags = {},
		buildable_ratio = 1,
		solid_ratio = 1,
		water_ratio = 0,
		area_score = 1,
		surface_node = "mcl_core:dirt_with_grass",
	}
	local flat = aliveworld.terrain.route_step_cost(base, {
		pos = {x = 8, y = 8, z = 0},
		flags = {},
		buildable_ratio = 1,
		solid_ratio = 1,
		water_ratio = 0,
		area_score = 1,
	}, {step_distance = 8, previous_direction = nil})
	local slope = aliveworld.terrain.route_step_cost(base, {
		pos = {x = 8, y = 10, z = 0},
		flags = {},
		buildable_ratio = 1,
		solid_ratio = 1,
		water_ratio = 0,
		area_score = 1,
	}, {step_distance = 8, previous_direction = nil})
	local steep = aliveworld.terrain.route_step_cost(base, {
		pos = {x = 8, y = 15, z = 0},
		flags = {steep = true},
		buildable_ratio = 0.8,
		solid_ratio = 1,
		water_ratio = 0,
		area_score = 0.8,
	}, {step_distance = 8, previous_direction = nil})
	local water = aliveworld.terrain.route_step_cost(base, {
		pos = {x = 8, y = 8, z = 0},
		flags = {water = true},
		buildable_ratio = 0.2,
		solid_ratio = 0.3,
		water_ratio = 1,
		area_score = 0.5,
	}, {step_distance = 16, water_run = 2, previous_direction = nil})
	ctx.assert.is_true(flat.cost < slope.cost, "flat dry route step must cost less than moderate slope")
	ctx.assert.is_true(slope.cost < steep.cost, "moderate slope must cost less than steep slope")
	ctx.assert.is_true(steep.cost < water.cost, "steep slope must cost less than deep/long water crossing")
end)

T.register_test("aliveworld", "route_plans_and_persists_between_anchors", function(ctx)
	cleanup_test_state()
	local routes = require_routes(ctx)
	local claims = require_claims(ctx)
	if not routes or not claims then return end
	if not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	aliveworld.sites.save(make_site("site_test_from", "test_from", {x = 0, y = 8, z = 0}, true))
	aliveworld.sites.save(make_site("site_test_to", "test_to", {x = 48, y = 8, z = 0}, true))
	local ok, route = routes.plan_route("test_route", {
		route_id = "test_route",
		kind = "road",
		from_site_id = "site_test_from",
		to_site_id = "site_test_to",
		sync = true,
		test_mode = "straight_loaded",
		cell_size = 8,
	})
	ctx.assert.is_true(ok, "test route must plan between anchored endpoints")
	if not ok then
		cleanup_test_state()
		return
	end
	ctx.assert.equal("planned", route.status, "planned route status must be saved")
	ctx.assert.is_true(#route.points >= 2, "planned route must contain at least two points")
	ctx.assert.equal(route.result_count, #route.points, "result_count must match points")
	ctx.assert.is_true(route.length > 0, "route length must be positive")
	ctx.assert.equal(type(route.points[1].pos.x), "number", "route point x must be numeric")
	local first = route.points[1].pos
	local last = route.points[#route.points].pos
	ctx.assert.is_true(aliveworld.sites.distance(first, {x = 0, y = 8, z = 0}) <= 12, "route must start near from anchor")
	ctx.assert.is_true(aliveworld.sites.distance(last, {x = 48, y = 8, z = 0}) <= 12, "route must end near to anchor")
	local saved = routes.get("test_route")
	ctx.assert.not_nil(saved, "route must be readable after save")
	ctx.assert.equal(#route.points, #saved.points, "saved route must keep points")
	local ok2, again = routes.plan_route("test_route", {sync = true})
	ctx.assert.is_true(ok2, "idempotent plan must return saved route")
	ctx.assert.equal(minetest.write_json(route.points), minetest.write_json(again.points), "idempotent route points must not change")
	local claim = claims.get("route:test_route")
	ctx.assert.not_nil(claim, "route corridor claim must be created")
	ctx.assert.equal("route_corridor", claim.kind, "route claim kind must be route_corridor")
	cleanup_test_state()
end)

T.register_test("aliveworld", "route_rejects_incompatible_site_core_claim", function(ctx)
	cleanup_test_state()
	local routes = require_routes(ctx)
	local claims = require_claims(ctx)
	if not routes or not claims then return end
	if not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	aliveworld.sites.save(make_site("site_test_from", "test_from", {x = 0, y = 8, z = 0}, true))
	aliveworld.sites.save(make_site("site_test_to", "test_to", {x = 48, y = 8, z = 0}, true))
	local ok_claim = claims.register({
		claim_id = "site:test_claim_core",
		owner_type = "site",
		owner_id = "site_test_claim_core",
		kind = "site_core",
		priority = 100,
		radius = 12,
		points = {{x = 24, y = 8, z = 0}},
		persistent = true,
	})
	ctx.assert.is_true(ok_claim, "test site_core claim must register")
	local ok, result = routes.plan_route("test_route_blocked", {
		route_id = "test_route_blocked",
		from_site_id = "site_test_from",
		to_site_id = "site_test_to",
		sync = true,
		test_mode = "straight_loaded",
		cell_size = 8,
	})
	ctx.assert.is_false(ok, "route through incompatible site_core must be rejected")
	ctx.assert.equal("claim_conflict", result.error, "claim conflict error must be stable")
	ctx.assert.is_nil(routes.get("test_route_blocked"), "failed claim validation must not save route")
	ctx.assert.is_nil(claims.get("route:test_route_blocked"), "failed claim validation must not leave route claim")
	cleanup_test_state()
end)

T.register_test("aliveworld", "old_road_live_plan_endpoints_anchored", function(ctx)
	local routes = require_routes(ctx)
	if not routes then return end
	if not aliveworld.sites then
		ctx.skip("aliveworld.sites not loaded")
		return
	end
	local birch = aliveworld.sites.get("birch_ford")
	local stone = aliveworld.sites.get("stone_gully")
	if not birch or not birch.anchor_pos or (birch.physical_status ~= "anchored" and birch.physical_status ~= "materialized") then
		ctx.skip("birch_ford is not anchored in runtime state")
		return
	end
	if not stone or not stone.anchor_pos or (stone.physical_status ~= "anchored" and stone.physical_status ~= "materialized") then
		ctx.skip("stone_gully is not anchored in runtime state")
		return
	end
	local ok, route = routes.plan_old_road({sync = true, force_replan = true})
	ctx.assert.is_true(ok, "old_road must plan in current carpathian dev world")
	if not ok then return end
	ctx.assert.equal("old_road", route.route_id, "old road route id must be stable")
	ctx.assert.equal(birch.id, route.from_site_id, "old road from endpoint must be Birch Ford canonical site id")
	ctx.assert.equal(stone.id, route.to_site_id, "old road to endpoint must be Stone Gully canonical site id")
	ctx.assert.is_true(#route.points >= 2, "old road route must contain control points")
	ctx.assert.is_true(route.length > 0, "old road length must be positive")
	ctx.assert.not_nil(route.claim_id, "old road must have a route claim id")
	local old_road_site = aliveworld.sites.get("old_road")
	if old_road_site then
		ctx.assert.equal("old_road", old_road_site.data and old_road_site.data.route_id, "old_road logical site must link to route")
		ctx.assert.not_nil(old_road_site.data and old_road_site.data.representative_route_pos, "old_road logical site must keep representative route position")
	end
end)
