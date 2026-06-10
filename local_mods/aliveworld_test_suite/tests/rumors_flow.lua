local T = luanti_testkit

T.register_test("aliveworld", "rumor_player_status_api", function(ctx)
  if not aliveworld or not aliveworld.rumors then
    ctx.skip("aliveworld.rumors not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.rumors.get_player_status, "get_player_status must exist")
  ctx.assert.not_nil(aliveworld.rumors.set_player_status, "set_player_status must exist")
  ctx.assert.not_nil(aliveworld.rumors.sync_status_from_tracking, "sync_status_from_tracking must exist")
  ctx.assert.not_nil(aliveworld.rumors.get_status_label, "get_status_label must exist")
  ctx.log("Rumor player status API loaded")
end)

T.register_test("aliveworld", "get_player_status_default_new", function(ctx)
  if not aliveworld or not aliveworld.rumors then
    ctx.skip("aliveworld.rumors not loaded")
    return
  end
  local status = aliveworld.rumors.get_player_status(ctx.player_name, "nonexistent_rumor")
  ctx.assert.equal("new", status, "unknown rumor should return 'new'")
  ctx.log("Default status for unknown rumor: " .. status)
end)

T.register_test("aliveworld", "set_and_get_player_status", function(ctx)
  if not aliveworld or not aliveworld.rumors then
    ctx.skip("aliveworld.rumors not loaded")
    return
  end
  local test_rumor = "test_rumor_" .. tostring(math.random(10000, 99999))

  local before = aliveworld.rumors.get_player_status(ctx.player_name, test_rumor)
  ctx.assert.equal("new", before, "initial status must be 'new'")

  aliveworld.rumors.set_player_status(ctx.player_name, test_rumor, "tracking")
  local after = aliveworld.rumors.get_player_status(ctx.player_name, test_rumor)
  ctx.assert.equal("tracking", after, "status must be updated to 'tracking'")

  aliveworld.rumors.set_player_status(ctx.player_name, test_rumor, "visited")
  local visited = aliveworld.rumors.get_player_status(ctx.player_name, test_rumor)
  ctx.assert.equal("visited", visited, "status must be updated to 'visited'")

  aliveworld.rumors.set_player_status(ctx.player_name, test_rumor, "verified")
  local verified = aliveworld.rumors.get_player_status(ctx.player_name, test_rumor)
  ctx.assert.equal("verified", verified, "status must be updated to 'verified'")

  ctx.log("Status flow test passed: new -> tracking -> visited -> verified")
end)

T.register_test("aliveworld", "per_player_isolation", function(ctx)
  if not aliveworld or not aliveworld.rumors then
    ctx.skip("aliveworld.rumors not loaded")
    return
  end
  if not ctx.player_name then
    ctx.skip("No player available")
    return
  end

  local test_id = "iso_test_" .. tostring(math.random(10000, 99999))
  aliveworld.rumors.set_player_status(ctx.player_name, test_id, "visited")

  -- Other players should not see this status
  local other_status = aliveworld.rumors.get_player_status("nonexistent_player_xyz", test_id)
  ctx.assert.equal("new", other_status, "other player must not see the status")
  ctx.log("Per-player isolation confirmed")
end)

T.register_test("aliveworld", "sync_status_from_tracking_tracked", function(ctx)
  if not aliveworld or not aliveworld.rumors then
    ctx.skip("aliveworld.rumors not loaded")
    return
  end
  if not aliveworld.tracking then
    ctx.skip("aliveworld.tracking not loaded")
    return
  end

  -- Find a rumor that maps to a site we can track
  local rumor_list = aliveworld.rumors.list()
  local target_rumor = nil
  for _, r in ipairs(rumor_list) do
    if r.status == "active" then
      target_rumor = r
      break
    end
  end
  if not target_rumor then
    ctx.skip("No active rumors to test sync")
    return
  end
  ctx.log("Found rumor " .. target_rumor.id .. " for event " .. tostring(target_rumor.event_id))

  -- Verify initial status
  local initial = aliveworld.rumors.get_player_status(ctx.player_name, target_rumor.id)
  ctx.log("Initial status for " .. target_rumor.id .. ": " .. initial)

  -- Note: Full sync requires actually tracking the event's site
  -- Just verify the function runs without error
  local ok, err = pcall(aliveworld.rumors.sync_status_from_tracking, ctx.player_name)
  ctx.assert.is_true(ok, "sync_status_from_tracking should not throw: " .. tostring(err))
  ctx.log("sync_status_from_tracking executed without error")
end)

T.register_test("aliveworld", "get_status_label_values", function(ctx)
  if not aliveworld or not aliveworld.rumors or not aliveworld.rumors.get_status_label then
    ctx.skip("rumors.get_status_label not available")
    return
  end
  local labels = {
    new = "[новый]",
    tracking = "[отслеживается]",
    visited = "[посещено]",
    verified = "[проверено]",
  }
  for status, expected in pairs(labels) do
    local actual = aliveworld.rumors.get_status_label(status)
    ctx.assert.equal(expected, actual, "label for '" .. status .. "' should match")
  end
  ctx.log("All status labels verified")
end)

T.register_test("aliveworld", "rumor_detail_formspec_available", function(ctx)
  if not aliveworld_player then
    ctx.skip("aliveworld_player not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld_player.show_rumor_detail, "show_rumor_detail must exist")
  ctx.assert.not_nil(aliveworld_player.show_news, "show_news must exist")
  ctx.log("Rumor detail formspec function available")
end)
