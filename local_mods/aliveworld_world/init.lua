-- aliveworld_world/init.lua
-- Physical world markers for AliveWorld sites and events

dofile(minetest.get_modpath("aliveworld_world") .. "/materialization.lua")

-- Node definitions

local function make_marker_node(description, tile)
  return {
    description = description,
    drawtype = "signlike",
    tiles = {tile},
    inventory_image = tile,
    wield_image = tile,
    paramtype = "light",
    paramtype2 = "wallmounted",
    sunlight_propagates = true,
    walkable = false,
    groups = {dig_immediate = 2, attached_node = 1},
    selection_box = {
      type = "wallmounted",
      wall_top = {-0.45, 0.4375, -0.45, 0.45, 0.5, 0.45},
      wall_bottom = {-0.45, -0.5, -0.45, 0.45, -0.4375, 0.45},
      wall_side = {-0.5, -0.45, -0.45, -0.4375, 0.45, 0.45},
    },
    collision_box = {
      type = "wallmounted",
      wall_top = {-0.45, 0.4375, -0.45, 0.45, 0.5, 0.45},
      wall_bottom = {-0.45, -0.5, -0.45, 0.45, -0.4375, 0.45},
      wall_side = {-0.5, -0.45, -0.45, -0.4375, 0.45, 0.45},
    },
    on_rightclick = function(pos, node, clicker, itemstack, pointed_thing)
      if not clicker or not clicker:is_player() then
        return itemstack
      end
      local meta = minetest.get_meta(pos)
      local marker_id = meta:get_string("aliveworld_marker_id")
      if marker_id and marker_id ~= "" and aliveworld.materialization then
        local marker_obj = aliveworld.materialization.get(marker_id)
        if marker_obj then
          local site = nil
          if aliveworld.sites and aliveworld.sites.get then
            site = aliveworld.sites.get(marker_obj.site_id)
          end
          if site then
            if site.type == "event" and site.event_id and aliveworld.events and aliveworld.events.get then
              local event = aliveworld.events.get(site.event_id)
              if event and aliveworld_player and aliveworld_player.get_display_text then
                local text = aliveworld_player.get_display_text(event)
                minetest.chat_send_player(clicker:get_player_name(),
                  "AliveWorld: " .. (site.name or site.name_en) .. " — " .. text)
                return itemstack
              end
            end
            minetest.chat_send_player(clicker:get_player_name(),
              "AliveWorld: " .. (site.name or site.name_en))
            return itemstack
          end
        end
      end
      minetest.chat_send_player(clicker:get_player_name(), "AliveWorld marker")
      return itemstack
    end,
  }
end

local marker_tiles = {}

-- Settlement marker: road sign / post
marker_tiles.settlement_marker = "aliveworld_rumor_board_front.png"

-- Road warning sign
marker_tiles.road_warning_sign = "aliveworld_rumor_board_front.png"

-- Supply crate
marker_tiles.supply_crate = "aliveworld_rumor_board_front.png"

-- Camp marker
marker_tiles.camp_marker = "aliveworld_rumor_board_front.png"

-- Notice stake
marker_tiles.notice_stake = "aliveworld_rumor_board_front.png"

-- Event marker
marker_tiles.event_marker = "aliveworld_rumor_board_front.png"

minetest.register_node("aliveworld_world:settlement_marker",
  make_marker_node("AliveWorld Settlement Marker", marker_tiles.settlement_marker))

minetest.register_node("aliveworld_world:road_warning_sign",
  make_marker_node("AliveWorld Road Warning Sign", marker_tiles.road_warning_sign))

minetest.register_node("aliveworld_world:supply_crate",
  make_marker_node("AliveWorld Supply Crate", marker_tiles.supply_crate))

minetest.register_node("aliveworld_world:camp_marker",
  make_marker_node("AliveWorld Camp Marker", marker_tiles.camp_marker))

minetest.register_node("aliveworld_world:notice_stake",
  make_marker_node("AliveWorld Notice Stake", marker_tiles.notice_stake))

minetest.register_node("aliveworld_world:event_marker",
  make_marker_node("AliveWorld Event Marker", marker_tiles.event_marker))

-- Chat commands

minetest.register_chatcommand("aw_anchor_site", {
  params = "<site_id>",
  description = "Place physical anchor marker for a site",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_anchor_site <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local ok, result = aliveworld.materialization.materialize_site(site)
    if ok then
      local marker = result
      return true, string.format("Site %s anchored at (%d,%d,%d) marker=%s",
        param, marker.pos.x, marker.pos.y, marker.pos.z, marker.id)
    end
    return false, result
  end,
})

minetest.register_chatcommand("aw_anchor_near", {
  params = "<player_name> [radius]",
  description = "Place physical markers for abstract sites near a player",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_anchor_near <player_name> [radius]"
    end
    local pname, radius_str = param:match("^(%S+)%s+(%S+)$")
    if not pname then
      pname = param
      radius_str = nil
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local radius = radius_str and tonumber(radius_str) or 256
    local ok, msg, count = aliveworld.materialization.materialize_near_player(pname, radius)
    return ok, msg
  end,
})

minetest.register_chatcommand("aw_markers", {
  params = "",
  description = "List all materialization markers",
  privs = {server = true},
  func = function()
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local list = aliveworld.materialization.list()
    if #list == 0 then
      return true, "No markers."
    end
    local lines = {}
    table.insert(lines, string.format("%-16s %-14s %-14s %-10s %-14s %s",
      "ID", "Site", "Event", "Type", "Status", "Pos"))
    table.insert(lines, string.rep("-", 90))
    for _, m in ipairs(list) do
      table.insert(lines, string.format("%-16s %-14s %-14s %-10s %-14s (%d,%d,%d)",
        m.id, m.site_id or "", m.event_id or "", m.type, m.status, m.pos.x, m.pos.y, m.pos.z))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_marker", {
  params = "<id>",
  description = "Show detailed marker information",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_marker <id>"
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local marker = aliveworld.materialization.get(param)
    if not marker then
      return false, "Marker not found: " .. param
    end
    local lines = {}
    table.insert(lines, string.format("Marker: %s", marker.id))
    table.insert(lines, string.format("Site: %s", marker.site_id or "none"))
    table.insert(lines, string.format("Event: %s", marker.event_id or "none"))
    table.insert(lines, string.format("Type: %s", marker.type))
    table.insert(lines, string.format("Status: %s", marker.status))
    table.insert(lines, string.format("Pos: (%d,%d,%d)", marker.pos.x, marker.pos.y, marker.pos.z))
    table.insert(lines, string.format("Created: day %d", marker.created_day or 0))
    if marker.expires_day then
      table.insert(lines, string.format("Expires: day %d", marker.expires_day))
    end
    if marker.nodes and #marker.nodes > 0 then
      table.insert(lines, string.format("Nodes placed: %d", #marker.nodes))
    end
    return true, table.concat(lines, "\n")
  end,
})

minetest.register_chatcommand("aw_materialize_site", {
  params = "<site_id>",
  description = "Materialize a site as physical POI",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_materialize_site <site_id>"
    end
    if not aliveworld.sites then
      return false, "Sites module not loaded"
    end
    local site = aliveworld.sites.get(param)
    if not site then
      return false, "Site not found: " .. param
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local ok, result = aliveworld.materialization.materialize_site(site)
    if ok then
      return true, "Site " .. param .. " materialized."
    end
    return false, result
  end,
})

minetest.register_chatcommand("aw_materialize_event", {
  params = "<event_id>",
  description = "Materialize an event as physical POI",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_materialize_event <event_id>"
    end
    if not aliveworld.events then
      return false, "Events module not loaded"
    end
    local event = aliveworld.events.get(param)
    if not event then
      return false, "Event not found: " .. param
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local ok, result = aliveworld.materialization.materialize_event(event)
    if ok then
      return true, "Event " .. param .. " materialized."
    end
    return false, result
  end,
})

minetest.register_chatcommand("aw_materialize_near", {
  params = "<player_name> [radius]",
  description = "Materialize event sites near a player",
  privs = {server = true},
  func = function(_, param)
    if not param or param == "" then
      return false, "Usage: /aw_materialize_near <player_name> [radius]"
    end
    local pname, radius_str = param:match("^(%S+)%s+(%S+)$")
    if not pname then
      pname = param
      radius_str = nil
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    local radius = radius_str and tonumber(radius_str) or 256
    local ok, msg, count = aliveworld.materialization.materialize_near_player(pname, radius)
    return ok, msg
  end,
})

minetest.register_chatcommand("aw_markers_reset", {
  params = "[confirm]",
  description = "Clear marker registry (does NOT remove placed nodes)",
  privs = {server = true},
  func = function(_, param)
    if not param or param ~= "confirm" then
      return false, "WARNING: this clears marker registry but does NOT remove placed nodes. Use /aw_markers_reset confirm"
    end
    if not aliveworld.materialization then
      return false, "Materialization module not loaded"
    end
    aliveworld.materialization.reset()
    return true, "Marker registry cleared. Placed nodes remain in world."
  end,
})

-- Add materialization expire_old to aliveworld_core tick

minetest.log("action", "[aliveworld_world] loaded")
