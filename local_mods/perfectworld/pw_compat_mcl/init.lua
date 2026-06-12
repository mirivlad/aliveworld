perfectworld = rawget(_G, "perfectworld") or {}
_G.perfectworld = perfectworld
perfectworld.compat = perfectworld.compat or {}

local materials = {
  dirt = "mcl_core:dirt",
  grass = "mcl_core:dirt_with_grass",
  cobble = "mcl_core:cobble",
  wood_planks = "mcl_core:wood",
  tree = "mcl_core:tree",
  stone = "mcl_core:stone",
  sandstone = "mcl_core:sandstone",
  desert_sand = "mcl_core:desert_sand",
  sand = "mcl_core:sand",
  gravel = "mcl_core:gravel",
  water = "mcl_core:water_source",
  air = "air",
  chest = "mcl_chests:chest",
  slab_wood = "mcl_stairs:slab_wood",
  fence = "mcl_fences:fence",
  torch = "mcl_torches:torch",
  lantern = "mcl_lanterns:lantern",
}

function perfectworld.compat.resolve(name)
  return materials[name] or name
end

function perfectworld.compat.is_replaceable(node_name)
  if not node_name or node_name == "air" or node_name == "ignore" then return true end
  local def = minetest.registered_nodes[node_name]
  return def and def.buildable_to == true or false
end

minetest.log("action", "[pw_compat_mcl] loaded")
