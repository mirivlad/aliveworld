local T = luanti_testkit

T.register_test("aliveworld", "is_safe_standing_pos_exists", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.sites.is_safe_standing_pos, "is_safe_standing_pos must exist")
  ctx.assert.not_nil(aliveworld.sites.resolve_observer_pos, "resolve_observer_pos must exist")
  ctx.assert.not_nil(aliveworld.sites.resolve_marker_pos, "resolve_marker_pos must exist")
  ctx.log("All safety position functions available")
end)

T.register_test("aliveworld", "resolve_observer_pos_returns_safe", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  if not aliveworld.sites.resolve_observer_pos then
    ctx.skip("resolve_observer_pos not available")
    return
  end
  local site = aliveworld.sites.get("site_birch_ford")
  if not site then
    ctx.skip("site_birch_ford not found")
    return
  end
  local obs = aliveworld.sites.resolve_observer_pos(site)
  if not obs then
    ctx.log("No safe observer position found for site_birch_ford (may be unloaded)")
    return
  end
  ctx.assert.not_nil(obs.x, "observer pos must have x")
  ctx.assert.not_nil(obs.y, "observer pos must have y")
  ctx.assert.not_nil(obs.z, "observer pos must have z")
  ctx.log("Observer pos: (" .. obs.x .. "," .. obs.y .. "," .. obs.z .. ")")
end)

T.register_test("aliveworld", "resolve_marker_pos_fallback", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  if not aliveworld.sites.resolve_marker_pos then
    ctx.skip("resolve_marker_pos not available")
    return
  end
  local site = aliveworld.sites.get("site_birch_ford")
  if not site then
    ctx.skip("site_birch_ford not found")
    return
  end
  local marker = aliveworld.sites.resolve_marker_pos(site)
  if marker then
    ctx.log("Marker pos: (" .. marker.x .. "," .. marker.y .. "," .. marker.z .. ")")
  else
    ctx.log("No marker pos resolved - site may be abstract")
  end
end)

T.register_test("aliveworld", "resolve_display_pos_exists", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.sites.get_display_pos, "get_display_pos must exist")
  ctx.log("get_display_pos available")
end)

T.register_test("aliveworld", "clue_marker_api", function(ctx)
  if not aliveworld or not aliveworld.sites then
    ctx.skip("aliveworld.sites not loaded")
    return
  end
  ctx.assert.not_nil(aliveworld.sites.place_clue_marker, "place_clue_marker must exist")
  ctx.assert.not_nil(aliveworld.sites.get_clue_texts, "get_clue_texts must exist")
  ctx.assert.not_nil(aliveworld.sites.cleanup_old_clues, "cleanup_old_clues must exist")

  local text = aliveworld.sites.get_clue_texts("flood")
  ctx.assert.not_nil(text, "get_clue_texts must return a string")
  ctx.assert.is_true(#text > 0, "clue text must not be empty")
  ctx.log("Flood clue text: " .. text)

  local default_text = aliveworld.sites.get_clue_texts("unknown_type")
  ctx.assert.not_nil(default_text, "unknown type should return default text")
  ctx.log("Default clue text: " .. default_text)
end)
