local T = luanti_testkit

T.register_test("aliveworld", "shared_tracking_api", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.tracking.track_site, "track_site must exist")
  ctx.assert.not_nil(aliveworld.tracking.untrack, "untrack must exist")
  ctx.assert.not_nil(aliveworld.tracking.get_active_track, "get_active_track must exist")
  ctx.assert.not_nil(aliveworld.tracking.describe_track, "describe_track must exist")
  ctx.assert.not_nil(aliveworld.tracking.check_arrival, "check_arrival must exist")
  ctx.assert.not_nil(aliveworld.tracking.reset_arrival_ack, "reset_arrival_ack must exist")
  ctx.assert.not_nil(aliveworld.tracking.restore_player, "restore_player must exist")
  ctx.assert.not_nil(aliveworld.tracking.get_debug_info, "get_debug_info must exist")
  ctx.log("Shared tracking API fully loaded")
end)

T.register_test("aliveworld", "track_site_returns_result_table", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  if not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  local site = aliveworld.sites.get("site_birch_ford")
  if not site then
    ctx.skip("site_birch_ford not found")
    return
  end
  local result = aliveworld.tracking.track_site(ctx.player_name, "site_birch_ford")
  ctx.assert.not_nil(result, "track_site must return a result")
  ctx.assert.not_nil(result.ok, "result must have 'ok' field")
  if result.ok then
    ctx.assert.equal(ctx.player_name, result.player_name, "result player_name must match")
    ctx.assert.equal("site_birch_ford", result.resolved_site_id, "result must have resolved_site_id")
    ctx.assert.not_nil(result.title, "result must have title")
    ctx.assert.not_nil(result.target_pos, "result must have target_pos")
    ctx.log("Track result: " .. minetest.pos_to_string(result.target_pos) .. " precision=" .. tostring(result.precision))
  else
    ctx.log("track_site result: " .. tostring(result.error))
  end
  aliveworld.tracking.untrack(ctx.player_name)
end)

T.register_test("aliveworld", "get_active_track_after_track", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  aliveworld.tracking.untrack(ctx.player_name)
  local before = aliveworld.tracking.get_active_track(ctx.player_name)
  ctx.assert.is_nil(before, "no active track before tracking")

  local result = aliveworld.tracking.track_site(ctx.player_name, "site_birch_ford")
  if not result.ok then
    ctx.skip("track_site failed: " .. tostring(result.error))
    return
  end

  local after = aliveworld.tracking.get_active_track(ctx.player_name)
  ctx.assert.not_nil(after, "active track must exist after track_site")
  ctx.assert.equal("site_birch_ford", after.site_id, "track site_id must match")
  ctx.assert.not_nil(after.target_pos, "track must have target_pos")
  ctx.assert.equal(false, after.has_arrived, "has_arrived should be false initially")
  ctx.log("Active track: " .. after.site_id .. " at " .. minetest.pos_to_string(after.target_pos))

  aliveworld.tracking.untrack(ctx.player_name)
end)

T.register_test("aliveworld", "untrack_clears_active_track", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  aliveworld.tracking.track_site(ctx.player_name, "site_birch_ford")
  local ok, msg = aliveworld.tracking.untrack(ctx.player_name)
  ctx.assert.is_true(ok, "untrack should succeed")
  local after = aliveworld.tracking.get_active_track(ctx.player_name)
  ctx.assert.is_nil(after, "active track must be nil after untrack")
  ctx.log("Untrack successful")
end)

T.register_test("aliveworld", "describe_track_output", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  aliveworld.tracking.untrack(ctx.player_name)

  local no_track = aliveworld.tracking.describe_track(ctx.player_name)
  ctx.assert.not_nil(no_track, "describe_track should return table even without track")
  ctx.assert.not_nil(no_track.line, "describe_track must have 'line' field")
  ctx.log("No track: " .. no_track.line)

  local result = aliveworld.tracking.track_site(ctx.player_name, "site_birch_ford")
  if not result.ok then
    ctx.skip("track_site failed: " .. tostring(result.error))
    return
  end
  local with_track = aliveworld.tracking.describe_track(ctx.player_name)
  ctx.assert.not_nil(with_track, "describe_track must return table")
  ctx.assert.not_nil(with_track.line, "describe_track must have 'line' field")
  ctx.assert.is_true(#with_track.line > 0, "track description must not be empty")
  ctx.log("Track description: " .. with_track.line)

  aliveworld.tracking.untrack(ctx.player_name)
end)

T.register_test("aliveworld", "reset_arrival_ack_works", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  local result = aliveworld.tracking.reset_arrival_ack(ctx.player_name)
  ctx.assert.not_nil(result, "reset_arrival_ack should return a result")
  ctx.assert.is_true(result.ok, "reset_arrival_ack should succeed")
  ctx.log("reset_arrival_ack ok: " .. tostring(result.count or 0) .. " cleared")
end)

T.register_test("aliveworld", "get_debug_info_structure", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  local player = ctx.helpers.get_player(ctx.player_name)
  if not player then
    ctx.skip("Player '" .. ctx.player_name .. "' is not online.")
    return
  end
  -- Track a site first so get_debug_info has full data
  aliveworld.tracking.untrack(ctx.player_name)
  local available = false
  if aliveworld.sites then
    local site = aliveworld.sites.get("site_birch_ford")
    if site then
      local result = aliveworld.tracking.track_site(ctx.player_name, "site_birch_ford")
      if not result.ok then
        ctx.skip("track_site failed: " .. tostring(result.error))
        return
      end
      available = true
    end
  end
  local info = aliveworld.tracking.get_debug_info(ctx.player_name)
  ctx.assert.not_nil(info, "get_debug_info must return a table")
  ctx.assert.not_nil(info.player_name, "debug info must have player_name")
  if available then
    ctx.assert.not_nil(info.active_track, "debug info must have active_track when tracking")
    ctx.assert.equal("site_birch_ford", info.active_track.site_id, "active_track site_id must match")
  else
    ctx.assert.equal(false, info.has_track, "has_track should be false when no site available")
  end
  ctx.assert.not_nil(info.arrival_ack, "debug info must have arrival_ack")
  ctx.log("Debug info player=" .. info.player_name .. " track=" .. tostring(info.active_track and info.active_track.site_id or "none"))
  -- Cleanup
  aliveworld.tracking.untrack(ctx.player_name)
end)

T.register_test("aliveworld", "track_site_abstract_precision", function(ctx)
  if not aliveworld or not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end
  if not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end

  local site = nil
  for _, s in ipairs(aliveworld.sites.list()) do
    if s.physical_status ~= "anchored" then
      site = s
      break
    end
  end
  if not site then
    ctx.skip("No abstract site found")
    return
  end

  local result = aliveworld.tracking.track_site(ctx.player_name, site.id)
  if not result.ok then
    ctx.skip("track_site failed: " .. tostring(result.error))
    return
  end
  ctx.log("Abstract site " .. site.id .. " precision=" .. tostring(result.precision) .. " physical=" .. tostring(result.physical_status))
  ctx.assert.equal("abstract", result.physical_status, "abstract site should have 'abstract' physical_status")
  ctx.assert.equal("approximate", result.precision, "abstract site should have 'approximate' precision")

  aliveworld.tracking.untrack(ctx.player_name)
end)
