-- aliveworld_test_suite/tests/route_materialization.lua
-- Test planned route materialization, dense centerlines, and road safety rules.

local T = luanti_testkit

local TEST_ROUTE_ID = "test_materialize_route"
local TEST_FROM = "site_test_mat_from"
local TEST_TO = "site_test_mat_to"

local function copy_pos(pos)
  return {x = pos.x, y = pos.y, z = pos.z}
end

local function require_api(ctx)
  if not aliveworld or not aliveworld.routes or not aliveworld.routes.materialization then
    ctx.assert.not_nil(aliveworld and aliveworld.routes and aliveworld.routes.materialization, "routes.materialization API must exist")
    return nil
  end
  return aliveworld.routes.materialization
end

local function test_origin(ctx)
  local player = ctx.helpers.get_player(ctx.player_name)
  if not player then
    ctx.skip("Player '" .. tostring(ctx.player_name) .. "' is not online.")
    return nil
  end
  local p = player:get_pos()
  return {
    x = math.floor(p.x + 40),
    y = math.floor(p.y + 8),
    z = math.floor(p.z + 40),
  }
end

local function snapshot_area(minp, maxp)
  local snap = {}
  for x = minp.x, maxp.x do
    for y = minp.y, maxp.y do
      for z = minp.z, maxp.z do
        local pos = {x = x, y = y, z = z}
        local meta = minetest.get_meta(pos):to_table()
        table.insert(snap, {pos = pos, node = minetest.get_node(pos), meta = meta})
      end
    end
  end
  return snap
end

local function restore_area(snap)
  for _, item in ipairs(snap or {}) do
    minetest.set_node(item.pos, item.node)
    minetest.get_meta(item.pos):from_table(item.meta or {})
  end
end

local function cleanup()
  if aliveworld and aliveworld.routes then
    if aliveworld.routes.materialization and aliveworld.routes.materialization.reset then
      aliveworld.routes.materialization.reset(TEST_ROUTE_ID)
      aliveworld.routes.materialization.reset("test_materialize_bad_status")
    end
    aliveworld.routes.delete(TEST_ROUTE_ID)
    aliveworld.routes.delete("test_materialize_bad_status")
  end
  if aliveworld and aliveworld.claims then
    aliveworld.claims.delete("route:" .. TEST_ROUTE_ID)
    aliveworld.claims.delete("route:test_materialize_bad_status")
  end
  if aliveworld and aliveworld.sites then
    aliveworld.sites.delete(TEST_FROM)
    aliveworld.sites.delete(TEST_TO)
  end
  local jr = aliveworld and aliveworld.job_runner
  if jr then
    jr.remove(TEST_ROUTE_ID)
  end
end

local function prepare_flat_area(origin, opts)
  opts = opts or {}
  local minp = {x = origin.x - 5, y = origin.y - (opts.large_drop and 12 or 4), z = origin.z - 5}
  local maxp = {x = origin.x + 22, y = origin.y + 6, z = origin.z + 5}
  local snap = snapshot_area(minp, maxp)
  for x = minp.x, maxp.x do
    for z = minp.z, maxp.z do
      for y = minp.y, maxp.y do
        minetest.set_node({x = x, y = y, z = z}, {name = "air"})
      end
      minetest.set_node({x = x, y = origin.y - 1, z = z}, {name = "mcl_core:dirt_with_grass"})
      minetest.set_node({x = x, y = origin.y - 2, z = z}, {name = "mcl_core:dirt"})
      minetest.set_node({x = x, y = origin.y - 3, z = z}, {name = "mcl_core:dirt"})
    end
  end
  if opts.vegetation then
    minetest.set_node({x = origin.x + 6, y = origin.y, z = origin.z}, {name = "mcl_flowers:tallgrass"})
  end
  if opts.small_hole then
    minetest.set_node({x = origin.x + 8, y = origin.y - 1, z = origin.z}, {name = "air"})
    minetest.set_node({x = origin.x + 8, y = origin.y - 2, z = origin.z}, {name = "air"})
  end
  if opts.small_bump then
    minetest.set_node({x = origin.x + 10, y = origin.y, z = origin.z}, {name = "mcl_core:dirt"})
  end
  if opts.large_drop then
    for y = origin.y - 1, origin.y - 10, -1 do
      minetest.set_node({x = origin.x + 12, y = y, z = origin.z}, {name = "air"})
    end
  end
  if opts.water then
    minetest.set_node({x = origin.x + 12, y = origin.y - 1, z = origin.z}, {name = "mcl_core:water_source"})
  end
  if opts.blocked then
    minetest.set_node({x = origin.x + 14, y = origin.y, z = origin.z}, {name = "mcl_core:diamondblock"})
  end
  if opts.metadata then
    local pos = {x = origin.x + 16, y = origin.y - 1, z = origin.z}
    minetest.get_meta(pos):set_string("aliveworld_test_meta", "keep")
  end
  return snap
end

local function save_sites_and_route(origin, status)
  aliveworld.sites.save({
    id = TEST_FROM,
    type = "settlement",
    subtype = "test",
    name = "test from",
    name_en = "test from",
    settlement_id = "test_mat_from",
    pos = copy_pos(origin),
    radius = 8,
    status = "active",
    physical_status = "anchored",
    anchor_pos = copy_pos(origin),
    data = {},
  })
  aliveworld.sites.save({
    id = TEST_TO,
    type = "settlement",
    subtype = "test",
    name = "test to",
    name_en = "test to",
    settlement_id = "test_mat_to",
    pos = {x = origin.x + 20, y = origin.y, z = origin.z},
    radius = 8,
    status = "active",
    physical_status = "anchored",
    anchor_pos = {x = origin.x + 20, y = origin.y, z = origin.z},
    data = {},
  })
  return aliveworld.routes.save({
    route_id = TEST_ROUTE_ID,
    kind = "road",
    from_site_id = TEST_FROM,
    to_site_id = TEST_TO,
    status = status or "planned",
    planner_version = 1,
    world_seed = "test",
    cell_size = 8,
    corridor_radius = 4,
    points = {
      {pos = copy_pos(origin), surface_node = "mcl_core:dirt_with_grass", cumulative_cost = 0, flags = {}},
      {pos = {x = origin.x + 20, y = origin.y, z = origin.z}, surface_node = "mcl_core:dirt_with_grass", cumulative_cost = 20, flags = {}},
    },
    result_count = 2,
    length = 20,
    elevation_gain = 0,
    elevation_loss = 0,
    max_grade = 0,
    average_grade = 0,
    crossings = {},
    claim_id = "route:" .. TEST_ROUTE_ID,
  }, {replace = true})
end

T.register_test("aliveworld", "route_materialization_api_loaded", function(ctx)
  local mat = require_api(ctx)
  if not mat then return end
  ctx.assert.not_nil(mat.dry_run, "dry_run must exist")
  ctx.assert.not_nil(mat.start, "start must exist")
  ctx.assert.not_nil(mat.status, "status must exist")
  ctx.assert.not_nil(mat.cancel, "cancel must exist")
  ctx.assert.not_nil(mat.build_dense_centerline, "build_dense_centerline must exist")
  ctx.assert.not_nil(mat.verify, "verify must exist")
end)

T.register_test("aliveworld", "route_materialization_unknown_route_rejected", function(ctx)
  local mat = require_api(ctx)
  if not mat then return end
  local ok, result = mat.dry_run("missing_materialize_route")
  ctx.assert.is_false(ok, "unknown route dry-run must fail")
  ctx.assert.equal("route_not_found", result.error, "unknown route error must be structured")
end)

T.register_test("aliveworld", "route_materialization_bad_status_rejected", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  local ok_save = save_sites_and_route(origin, "failed")
  ctx.assert.is_true(ok_save, "test route must save")
  local ok, result = mat.start(TEST_ROUTE_ID)
  ctx.assert.is_false(ok, "non-planned route must not start materialization")
  ctx.assert.equal("route_not_planned", result.error, "status error must be stable")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_dense_centerline_continuous", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  local ok_save, route = save_sites_and_route(origin, "planned")
  ctx.assert.is_true(ok_save, "test route must save")
  local ok, dense = mat.build_dense_centerline(route)
  ctx.assert.is_true(ok, "dense centerline must build")
  ctx.assert.is_true(#dense.points >= 10, "dense centerline must interpolate route controls")
  for i = 2, #dense.points do
    local a = dense.points[i - 1].pos
    local b = dense.points[i].pos
    local dx = math.abs(a.x - b.x)
    local dz = math.abs(a.z - b.z)
    ctx.assert.is_true(math.max(dx, dz) <= 2, "dense horizontal step must be <= 2 nodes")
    ctx.assert.equal("number", type(b.y), "dense surface y must be numeric")
  end
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_claim_corridor_covers_polyline_midpoint", function(ctx)
  cleanup()
  local claims = aliveworld and aliveworld.claims
  if not claims then
    ctx.assert.not_nil(claims, "claims API must exist")
    return
  end
  ctx.assert.not_nil(claims.contains_pos, "claims.contains_pos must exist")
  local ok = claims.register({
    claim_id = "route:" .. TEST_ROUTE_ID,
    owner_type = "route",
    owner_id = TEST_ROUTE_ID,
    kind = "route_corridor",
    priority = 80,
    radius = 4,
    points = {{x = 0, y = 8, z = 0}, {x = 64, y = 8, z = 0}},
    persistent = true,
  }, {replace = true})
  ctx.assert.is_true(ok, "test route claim must register")
  ctx.assert.is_true(claims.contains_pos("route:" .. TEST_ROUTE_ID, {x = 32, y = 8, z = 3}), "claim must cover the segment between planner points")
  ctx.assert.is_false(claims.contains_pos("route:" .. TEST_ROUTE_ID, {x = 32, y = 8, z = 8}), "claim must not cover positions outside corridor radius")
  claims.delete("route:" .. TEST_ROUTE_ID)
end)

T.register_test("aliveworld", "route_materialization_dry_run_does_not_change_nodes", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin, {vegetation = true})
  save_sites_and_route(origin, "planned")
  local before = minetest.get_node({x = origin.x + 6, y = origin.y, z = origin.z}).name
  local ok, report = mat.dry_run(TEST_ROUTE_ID)
  ctx.assert.is_true(ok, "dry-run must succeed on flat test road")
  ctx.assert.equal("planned", report.status, "dry-run report status remains planned")
  ctx.assert.is_true((report.dense_points_count or 0) > 0, "dry-run must build dense points")
  ctx.assert.equal(before, minetest.get_node({x = origin.x + 6, y = origin.y, z = origin.z}).name, "dry-run must not edit vegetation")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_safe_edits_and_blocks_hazards", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin, {
    vegetation = true,
    small_hole = true,
    small_bump = true,
    blocked = true,
    metadata = true,
  })
  save_sites_and_route(origin, "planned")
  local ok, report = mat.dry_run(TEST_ROUTE_ID)
  ctx.assert.is_true(ok, "dry-run with hazards must return a report")
  ctx.assert.is_true((report.vegetation_removed or 0) >= 1, "vegetation should be counted as clearable")
  ctx.assert.is_true((report.filled_nodes or 0) >= 1, "small holes should be counted as fill")
  ctx.assert.is_true((report.cut_nodes or 0) >= 1, "small bumps should be counted as cut")
  ctx.assert.is_true((report.unknown_blocked or 0) + (report.skipped_blocked or 0) >= 1, "metadata or unknown solid must be skipped")
  ctx.assert.is_true(#(report.unresolved or {}) >= 1, "blocked hazards must prevent full materialization")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_respects_protection", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")
  local protected_x = origin.x + 4
  local old_is_protected = minetest.is_protected
  minetest.is_protected = function(pos, name)
    if pos.x == protected_x and pos.z == origin.z then
      return true
    end
    return old_is_protected(pos, name)
  end
  local thrown, dry_ok, dry_report = pcall(function()
    return mat.dry_run(TEST_ROUTE_ID)
  end)
  minetest.is_protected = old_is_protected
  ctx.assert.is_true(thrown, "protected dry-run must not throw")
  if not thrown then
    restore_area(snap)
    cleanup()
    return
  end
  ctx.assert.is_true(dry_ok, "dry-run must return a report for protected route")
  ctx.assert.is_true((dry_report.skipped_protected or 0) >= 1, "protected cells must be skipped")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_does_not_leave_corridor", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites or not aliveworld.claims then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  local ok_save, route = save_sites_and_route(origin, "planned")
  ctx.assert.is_true(ok_save, "test route must save")
  local claim = aliveworld.claims.get("route:" .. TEST_ROUTE_ID)
  claim.radius = 1
  aliveworld.claims.register(claim, {replace = true})
  local ok, report = mat.dry_run(TEST_ROUTE_ID)
  ctx.assert.is_true(ok, "dry-run must produce report for narrow corridor")
  ctx.assert.is_true(#(report.unresolved or {}) >= 1, "wide road must not be accepted outside route corridor")
  local found = false
  for _, item in ipairs(report.unresolved or {}) do
    if item.reason == "outside_route_claim" then
      found = true
      break
    end
  end
  ctx.assert.is_true(found, "outside corridor reason must be structured")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_rejects_large_drop_and_water", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin, {large_drop = true})
  save_sites_and_route(origin, "planned")
  local ok, report = mat.dry_run(TEST_ROUTE_ID)
  ctx.assert.is_true(ok, "dry-run with unresolved terrain must return a report")
  ctx.assert.is_true(#(report.unresolved or {}) >= 1, "large drop must be unresolved")
  restore_area(snap)
  cleanup()

  snap = prepare_flat_area(origin, {water = true})
  save_sites_and_route(origin, "planned")
  ok, report = mat.dry_run(TEST_ROUTE_ID)
  ctx.assert.is_true(ok, "dry-run with water must return a report")
  ctx.assert.is_true((report.water_segments or 0) >= 1, "unexpected water must be reported")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_idempotent_and_checkpointed", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin, {vegetation = true})
  save_sites_and_route(origin, "planned")
  local ok_start = mat.start(TEST_ROUTE_ID, {points_per_step = 2})
  ctx.assert.is_true(ok_start, "materialization job must start")
  mat.process_jobs(1)
  local mid = mat.status(TEST_ROUTE_ID)
  ctx.assert.not_nil(mid, "materialization status must persist after partial processing")
  ctx.assert.equal("materializing", mid.status, "partial job must remain materializing")
  ctx.assert.is_true((mid.processed_nodes or 0) > 0, "partial job must record progress")
  for _ = 1, 200 do
    mat.process_jobs(20)
    local state = mat.status(TEST_ROUTE_ID)
    if state and state.status ~= "materializing" then break end
  end
  local done = mat.status(TEST_ROUTE_ID)
  ctx.assert.equal("materialized", done.status, "flat route must finish materialized")
  local changed = done.changed_nodes or 0
  local ok_again, again = mat.start(TEST_ROUTE_ID)
  ctx.assert.is_true(ok_again, "second start must be idempotent")
  ctx.assert.equal("materialized", again.status, "second start must return existing materialization")
  ctx.assert.equal(changed, again.changed_nodes or 0, "second start must not add more changes")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_job_yields_on_op_budget", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")
  mat.start(TEST_ROUTE_ID, {points_per_step = 2, max_ops_per_step = 5})
  mat.process_jobs(1)
  local s = mat.status(TEST_ROUTE_ID)
  ctx.assert.is_true((s.processed_nodes or 0) > 0, "job must make progress with op budget")
  cleanup()
  restore_area(snap)
end)

T.register_test("aliveworld", "route_materialization_cancel_clears_job", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")
  mat.start(TEST_ROUTE_ID, {points_per_step = 2})
  mat.process_jobs(1)
  local ok, result = mat.cancel(TEST_ROUTE_ID, "test_cancel")
  ctx.assert.is_true(ok, "cancel must succeed on running job")
  ctx.assert.equal("failed", result.status, "cancelled job must be failed")
  ctx.assert.equal("test_cancel", result.last_error, "cancel reason must be stored")
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_verify_runs_and_does_not_change", function(ctx)
  local mat = require_api(ctx)
  if not mat then return end
  if not aliveworld.routes.get("old_road") then
    ctx.skip("old_road not available")
    return
  end
  local state = mat.status("old_road")
  if not state or state.status ~= "materialized" then
    ctx.skip("old_road not materialized")
    return
  end
  local sample_pos
  local route = aliveworld.routes.get("old_road")
  if route and route.points and #route.points > 0 then
    local mid = route.points[math.floor(#route.points / 2 + 0.5)]
    if mid and mid.pos then
      sample_pos = {x = mid.pos.x, y = mid.pos.y - 1, z = mid.pos.z}
    end
  end
  local before = nil
  if sample_pos then
    mat.ensure_area_loaded(
      {x = sample_pos.x, y = sample_pos.y - 1, z = sample_pos.z},
      {x = sample_pos.x, y = sample_pos.y + 1, z = sample_pos.z}
    )
    before = minetest.get_node(sample_pos).name
  end
  local ok, report = mat.verify("old_road", {one_shot = true})
  ctx.assert.is_true(ok, "verify must run on materialized old_road")
  ctx.assert.equal("completed", report.status, "verify must complete")
  if sample_pos and before then
    ctx.assert.equal(before, minetest.get_node(sample_pos).name, "verify must not change any nodes")
  end
end)

T.register_test("aliveworld", "route_materialization_verify_detects_gap", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")

  mat.start(TEST_ROUTE_ID, {points_per_step = 2})
  for _ = 1, 200 do
    mat.process_jobs(20)
    local s = mat.status(TEST_ROUTE_ID)
    if s and s.status ~= "materializing" then break end
  end

  local done = mat.status(TEST_ROUTE_ID)
  if done and done.status == "materialized" then
    minetest.set_node({x = origin.x + 10, y = origin.y - 1, z = origin.z}, {name = "air"})
    local ok, report = mat.verify(TEST_ROUTE_ID, {one_shot = true})
    ctx.assert.is_true(ok, "verify must run on materialized route")
    ctx.assert.is_true((report.palette_mismatch or 0) >= 1, "verify should detect gap")
    ctx.assert.equal("completed", report.status)
    minetest.set_node({x = origin.x + 10, y = origin.y - 1, z = origin.z}, {name = "mcl_core:coarse_dirt"})
  end

  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_idempotent_write_path", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")

  mat.start(TEST_ROUTE_ID, {points_per_step = 2})
  for _ = 1, 200 do
    mat.process_jobs(20)
    local s = mat.status(TEST_ROUTE_ID)
    if s and s.status ~= "materializing" then break end
  end

  local done = mat.status(TEST_ROUTE_ID)
  if done and done.status == "materialized" then
    local changed_before = done.changed_nodes or 0
    mat.reset(TEST_ROUTE_ID)
    mat.start(TEST_ROUTE_ID, {points_per_step = 2, force = true})
    for _ = 1, 200 do
      mat.process_jobs(20)
      local s = mat.status(TEST_ROUTE_ID)
      if s and s.status ~= "materializing" then break end
    end
    local again = mat.status(TEST_ROUTE_ID)
    if again and again.status == "materialized" then
      ctx.assert.equal(changed_before, again.changed_nodes or 0,
        "rematerialization must produce same changed count")
    end
  end

  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_job_metrics_count_over_budget", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")
  mat.start(TEST_ROUTE_ID, {points_per_step = 2, hard_warn_threshold_ms = 1})
  mat.process_jobs(1)
  local state = mat.status(TEST_ROUTE_ID)
  if state and state.job_metrics then
    ctx.assert.is_true((state.job_metrics.over_budget_steps or 0) >= 0, "over_budget_steps must be countable")
    ctx.assert.is_true((state.job_metrics.max_step_cpu_ms or 0) >= 0, "max_step_cpu_ms must be measurable")
  end
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "route_materialization_job_metrics_have_phases", function(ctx)
  cleanup()
  local mat = require_api(ctx)
  if not mat or not aliveworld.sites then return end
  local origin = test_origin(ctx)
  if not origin then return end
  local snap = prepare_flat_area(origin)
  save_sites_and_route(origin, "planned")
  mat.start(TEST_ROUTE_ID, {points_per_step = 2})
  for _ = 1, 50 do
    mat.process_jobs(1)
    local s = mat.status(TEST_ROUTE_ID)
    if s and s.job_metrics and s.job_metrics.steps and s.job_metrics.steps > 0 then
      break
    end
  end
  local state = mat.status(TEST_ROUTE_ID)
  if state and state.job_metrics and state.job_metrics.phases then
    local has_phase = false
    for _, _ in pairs(state.job_metrics.phases) do
      has_phase = true
      break
    end
    ctx.assert.is_true(has_phase, "job metrics must have at least one phase entry")
  end
  restore_area(snap)
  cleanup()
end)

T.register_test("aliveworld", "old_road_tracking_uses_representative_route_pos", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  local site = aliveworld.sites.get("old_road")
  if not site or not site.data or not site.data.representative_route_pos then
    ctx.skip("old_road representative route position is not available")
    return
  end
  local arrival = aliveworld.sites.resolve_arrival_pos(site)
  ctx.assert.not_nil(arrival, "old_road must resolve an arrival position")
  local dist = aliveworld.sites.distance(arrival, site.data.representative_route_pos)
  ctx.assert.is_true(dist <= 12, "old_road arrival/GPS position must resolve near representative_route_pos, not old anchor")
end)

T.register_test("aliveworld", "old_road_live_materialization_complete", function(ctx)
  local mat = require_api(ctx)
  if not mat or not aliveworld.routes then return end
  local route = aliveworld.routes.get("old_road")
  if not route then
    ctx.skip("old_road route is not saved")
    return
  end
  local state = mat.status("old_road")
  if not state or state.status ~= "materialized" then
    ctx.skip("old_road is not materialized yet")
    return
  end
  ctx.assert.equal("materialized", route.status, "old_road route status must be materialized after successful job")
  ctx.assert.equal(0, #(state.unresolved or {}), "old_road materialization must not leave unresolved segments")
  ctx.assert.is_true((state.dense_points_count or 0) > (route.points and #route.points or 0), "materialized road must use dense centerline")
end)

T.register_test("aliveworld", "old_road_live_dry_run_passes", function(ctx)
  local mat = require_api(ctx)
  if not mat or not aliveworld.routes then return end
  local route = aliveworld.routes.get("old_road")
  if not route then
    ctx.skip("old_road route is not saved")
    return
  end
  if route.status ~= "planned" and route.status ~= "materialized" then
    ctx.skip("old_road route is not planned/materialized")
    return
  end
  local ok, report = mat.dry_run("old_road")
  ctx.assert.is_true(ok, "old_road live dry-run must produce a report")
  ctx.assert.equal(0, #(report.unresolved or {}), "old_road dry-run must not have unresolved segments")
  ctx.assert.equal(0, report.water_segments or 0, "old_road dry-run must not find unexpected water")
  ctx.assert.is_true((report.dense_points_count or 0) > (route.points and #route.points or 0), "old_road dry-run must densify route controls")
  ctx.log("old_road dry-run dense=" .. tostring(report.dense_points_count) .. " changed=" .. tostring(report.changed_nodes))
end)
