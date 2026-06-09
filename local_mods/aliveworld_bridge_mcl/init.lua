aliveworld = rawget(_G, "aliveworld") or {}
_G.aliveworld = aliveworld

local function get_season_key(world_time)
  local m = world_time.month
  if m >= 1 and m <= 3 then return "spring" end
  if m >= 4 and m <= 6 then return "summer" end
  if m >= 7 and m <= 9 then return "autumn" end
  return "winter"
end

local SEASONS = {
  spring = {key = "spring", label_ru = "Весна", label_en = "Spring"},
  summer = {key = "summer", label_ru = "Лето", label_en = "Summer"},
  autumn = {key = "autumn", label_ru = "Осень", label_en = "Autumn"},
  winter = {key = "winter", label_ru = "Зима", label_en = "Winter"},
}

local FOOD_BY_SEASON = {
  spring = {key = "scarce", label_ru = "скудно", label_en = "scarce", availability = 0.3, items = {"mcl_core:apple"}},
  summer = {key = "abundant", label_ru = "обильно", label_en = "abundant", availability = 0.7, items = {"mcl_farming:bread", "mcl_core:apple"}},
  autumn = {key = "plentiful", label_ru = "изобильно", label_en = "plentiful", availability = 0.9, items = {"mcl_farming:bread", "mcl_core:apple"}},
  winter = {key = "critical", label_ru = "критично", label_en = "critical", availability = 0.1, items = {"mcl_core:apple"}},
}

local WOOD_BY_SEASON = {
  spring = {key = "available", label_ru = "доступно", label_en = "available", availability = 0.8, groups = {"tree", "wood"}},
  summer = {key = "abundant", label_ru = "полный рост", label_en = "abundant", availability = 1.0, groups = {"tree", "wood"}},
  autumn = {key = "limited", label_ru = "ограниченно", label_en = "limited", availability = 0.5, groups = {"tree", "wood"}},
  winter = {key = "difficult", label_ru = "сложно", label_en = "difficult", availability = 0.2, groups = {"tree", "wood"}},
}

local DANGER_BY_SEASON = {
  spring = {key = "moderate", label_ru = "умеренная", label_en = "moderate", level = 0.4, mobs = {"mobs_mc:zombie", "mobs_mc:spider"}},
  summer = {key = "high", label_ru = "высокая", label_en = "high", level = 0.8, mobs = {"mobs_mc:zombie", "mobs_mc:skeleton", "mobs_mc:spider"}},
  autumn = {key = "elevated", label_ru = "повышенная", label_en = "elevated", level = 0.5, mobs = {"mobs_mc:zombie", "mobs_mc:skeleton"}},
  winter = {key = "low", label_ru = "низкая", label_en = "low", level = 0.2, mobs = {"mobs_mc:zombie"}},
}

aliveworld.bridge = {
  game = "mineclonia",
  food_items = {"mcl_farming:bread", "mcl_core:apple"},
  wood_groups = {"tree", "wood"},
  danger_mobs = {"mobs_mc:zombie", "mobs_mc:skeleton", "mobs_mc:spider"},

  get_season = function(world_time)
    return SEASONS[get_season_key(world_time)]
  end,

  get_food_profile = function(world_time)
    return FOOD_BY_SEASON[get_season_key(world_time)]
  end,

  get_wood_profile = function(world_time)
    return WOOD_BY_SEASON[get_season_key(world_time)]
  end,

  get_danger_profile = function(world_time)
    return DANGER_BY_SEASON[get_season_key(world_time)]
  end,

  get_environment_profile = function(world_time)
    local k = get_season_key(world_time)
    return {
      season = SEASONS[k],
      food = FOOD_BY_SEASON[k],
      wood = WOOD_BY_SEASON[k],
      danger = DANGER_BY_SEASON[k],
    }
  end,
}

minetest.log("action", "[aliveworld_bridge_mcl] loaded")
