-- tests/planner.lua
-- PerfectWorld planner tests

local T = luanti_testkit

T.register_test("perfectworld", "planner_deterministic", function(ctx)
  local p1 = perfectworld.planner.plan_region(0, 0)
  local p2 = perfectworld.planner.plan_region(0, 0)
  ctx.assert.equal(p1.id, p2.id, "plan id must match across calls")
  ctx.assert.equal(
    p1.planner_version,
    p2.planner_version,
    "planner_version must match across calls"
  )
  ctx.assert.equal(
    #(p1.settlement_candidates or {}),
    #(p2.settlement_candidates or {}),
    "candidate count must be deterministic"
  )
  for i, c1 in ipairs(p1.settlement_candidates or {}) do
    local c2 = p2.settlement_candidates[i]
    ctx.assert.equal(c1.id, c2.id, "candidate id must be deterministic")
    ctx.assert.equal(c1.x, c2.x, "candidate x must be deterministic")
    ctx.assert.equal(c1.z, c2.z, "candidate z must be deterministic")
    ctx.assert.equal(c1.type, c2.type, "candidate type must be deterministic")
  end
end)

T.register_test("perfectworld", "planner_candidates_not_nil", function(ctx)
  local plan = perfectworld.planner.plan_region(0, 0)
  ctx.assert.not_nil(plan, "plan must not be nil")
  ctx.assert.not_nil(plan.settlement_candidates, "plan.candidates must not be nil")
  ctx.assert.is_true(type(plan.settlement_candidates) == "table", "candidates must be a table")
end)

T.register_test("perfectworld", "planner_candidate_structure", function(ctx)
  local plan = perfectworld.planner.plan_region(0, 0)
  for i, c in ipairs(plan.settlement_candidates or {}) do
    ctx.assert.not_nil(c.id, "candidate " .. i .. " must have id")
    ctx.assert.not_nil(c.type, "candidate " .. i .. " must have type")
    ctx.assert.not_nil(c.priority, "candidate " .. i .. " must have priority")
    ctx.assert.is_true(c.priority >= 1 and c.priority <= 5, "priority must be 1-5, got " .. tostring(c.priority))
    ctx.assert.is_true(c.connection_required == true, "candidate " .. i .. " must require connection")
    ctx.assert.equal(c.status, "candidate", "candidate " .. i .. " status must be candidate")
    ctx.assert.not_nil(c.x, "candidate " .. i .. " x must exist")
    ctx.assert.not_nil(c.z, "candidate " .. i .. " z must exist")
  end
end)

T.register_test("perfectworld", "planner_candidates_in_region", function(ctx)
  local REGION_SIZE = perfectworld.REGION_SIZE or 1024
  local margin = 80
  for rx = -1, 1 do
    for rz = -1, 1 do
      local plan = perfectworld.planner.plan_region(rx, rz)
      local r_min_x = rx * REGION_SIZE
      local r_min_z = rz * REGION_SIZE
      for i, c in ipairs(plan.settlement_candidates or {}) do
        local local_x = c.x - r_min_x
        local local_z = c.z - r_min_z
        ctx.assert.is_true(
          local_x >= margin,
          "candidate " .. i .. " in region (" .. rx .. "," .. rz .. ") local_x=" .. local_x .. " < margin=" .. margin
        )
        ctx.assert.is_true(
          local_x < REGION_SIZE - margin,
          "candidate " .. i .. " in region (" .. rx .. "," .. rz .. ") local_x=" .. local_x .. " >= " .. (REGION_SIZE - margin)
        )
        ctx.assert.is_true(
          local_z >= margin,
          "candidate " .. i .. " in region (" .. rx .. "," .. rz .. ") local_z=" .. local_z .. " < margin=" .. margin
        )
        ctx.assert.is_true(
          local_z < REGION_SIZE - margin,
          "candidate " .. i .. " in region (" .. rx .. "," .. rz .. ") local_z=" .. local_z .. " >= " .. (REGION_SIZE - margin)
        )
      end
    end
  end
end)

T.register_test("perfectworld", "planner_min_distance", function(ctx)
  for rx = -1, 1 do
    for rz = -1, 1 do
      local plan = perfectworld.planner.plan_region(rx, rz)
      local candidates = plan.settlement_candidates or {}
      for i, a in ipairs(candidates) do
        for j, b in ipairs(candidates) do
          if i < j then
            local dx = math.abs(a.x - b.x)
            local dz = math.abs(a.z - b.z)
            local dist = math.sqrt(dx * dx + dz * dz)
            ctx.assert.is_true(
              dist >= 200 - 1,
              "candidates too close in region (" .. rx .. "," .. rz .. "): " .. a.id .. " and " .. b.id .. " distance=" .. dist
            )
          end
        end
      end
    end
  end
end)

T.register_test("perfectworld", "planner_isolation", function(ctx)
  local plan = perfectworld.planner.plan_region(5, -3)
  local candidates_before = #(plan.settlement_candidates or {})
  if plan.settlement_candidates[1] then
    plan.settlement_candidates[1].id = "mutated"
  end
  local plan2 = perfectworld.planner.plan_region(5, -3)
  ctx.assert.equal(
    candidates_before,
    #(plan2.settlement_candidates or {}),
    "second plan must return identical data"
  )
  if plan2.settlement_candidates[1] then
    ctx.assert.is_true(plan2.settlement_candidates[1].id ~= "mutated", "plan_region must return copies")
  end
end)

T.register_test("perfectworld", "planner_request_order_independent", function(ctx)
  local a1 = perfectworld.planner.plan_region(2, -2)
  local b1 = perfectworld.planner.plan_region(-3, 4)
  local b2 = perfectworld.planner.plan_region(-3, 4)
  local a2 = perfectworld.planner.plan_region(2, -2)
  ctx.assert.equal(a1.id, a2.id, "region A id must be independent from request order")
  ctx.assert.equal(b1.id, b2.id, "region B id must be independent from request order")
  ctx.assert.equal(#(a1.settlement_candidates or {}), #(a2.settlement_candidates or {}), "region A candidate count must match")
  ctx.assert.equal(#(b1.settlement_candidates or {}), #(b2.settlement_candidates or {}), "region B candidate count must match")
end)

T.register_test("perfectworld", "planner_road_anchors_match_candidates", function(ctx)
  local plan = perfectworld.planner.plan_region(0, 0)
  ctx.assert.equal(#(plan.road_anchors or {}), #(plan.settlement_candidates or {}), "road anchor count must match candidate count")
  ctx.assert.equal(#(plan.reserved_areas or {}), #(plan.settlement_candidates or {}), "reserved area count must match candidate count")
end)

T.register_test("perfectworld", "materialize_chunk_places_test_structure_once", function(ctx)
  local selected_plan, selected_candidate
  for rx = -2, 2 do
    for rz = -2, 2 do
      local plan = perfectworld.planner.plan_region(rx, rz)
      if plan.settlement_candidates and plan.settlement_candidates[1] then
        selected_plan = plan
        selected_candidate = plan.settlement_candidates[1]
        break
      end
    end
    if selected_candidate then break end
  end

  if not selected_candidate then
    ctx.skip("no settlement candidate in scanned deterministic regions")
    return
  end

  local c = selected_candidate
  local ground_y = 0
  local minp = {x = c.x - 8, y = ground_y - 8, z = c.z - 8}
  local maxp = {x = c.x + 8, y = ground_y + 8, z = c.z + 8}
  if minetest.load_area then
    pcall(minetest.load_area, minp, maxp)
  end
  if minetest.get_node({x = c.x, y = ground_y, z = c.z}).name == "ignore" then
    minetest.emerge_area(minp, maxp)
    ctx.skip("candidate test area requested for emerge")
    return
  end

  perfectworld.planner._test_unmark_placed(c.id)

  for dx = -3, 3 do
    for dz = -3, 3 do
      minetest.set_node({x = c.x + dx, y = ground_y - 1, z = c.z + dz}, {name = perfectworld.compat.resolve("dirt")})
      for dy = ground_y, ground_y + 5 do
        minetest.set_node({x = c.x + dx, y = dy, z = c.z + dz}, {name = "air"})
      end
    end
  end

  perfectworld.planner.materialize_chunk(minp, maxp)
  ctx.assert.is_true(perfectworld.planner.is_placed(c.id), "candidate must be marked placed after materialization")

  local found_chest = false
  for y = -8, 260 do
    local node_name = minetest.get_node({x = c.x, y = y, z = c.z}).name
    if node_name == perfectworld.compat.resolve("chest") or node_name == "mcl_chests:chest_small" then
      found_chest = true
      break
    end
  end
  ctx.assert.is_true(found_chest, "test outpost must place center chest in candidate column")

  local placed_before = #perfectworld.planner.list_placed()
  perfectworld.planner.materialize_chunk(minp, maxp)
  local placed_after = #perfectworld.planner.list_placed()
  ctx.assert.equal(placed_before, placed_after, "second materialize_chunk call must not add duplicate placement records")

  perfectworld.planner._test_unmark_placed(c.id)
  ctx.log("materialized candidate " .. c.id .. " from plan " .. selected_plan.id)
end)
