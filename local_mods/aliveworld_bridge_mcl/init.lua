aliveworld = rawget(_G, "aliveworld") or {}
_G.aliveworld = aliveworld

aliveworld.bridge = {
    game = "mineclonia",
    food_items = {
        "mcl_farming:bread",
        "mcl_core:apple"
    },
    wood_groups = {
        "tree",
        "wood"
    },
    danger_mobs = {
        "mobs_mc:zombie",
        "mobs_mc:skeleton",
        "mobs_mc:spider"
    }
}

minetest.log("action", "[aliveworld_bridge_mcl] loaded")
