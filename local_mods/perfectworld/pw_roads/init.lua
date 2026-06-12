perfectworld = rawget(_G, "perfectworld") or {}
_G.perfectworld = perfectworld
perfectworld.roads = perfectworld.roads or {}

function perfectworld.roads.get_network()
  return {}
end

function perfectworld.roads.list_routes()
  return {}
end

minetest.log("action", "[pw_roads] loaded (skeleton)")
