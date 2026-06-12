perfectworld = perfectworld or {}
perfectworld.structures = perfectworld.structures or {}

local structures = {}

local function deep_copy(t)
	if type(t) ~= "table" then
		return t
	end
	local copy = {}
	for k, v in pairs(t) do
		copy[k] = deep_copy(v)
	end
	return copy
end

local function is_replaceable(pos)
	local node = minetest.get_node(pos)
	if perfectworld.compat and perfectworld.compat.is_replaceable then
		return perfectworld.compat.is_replaceable(node.name)
	end
	return node.name == "air" or node.name == "ignore"
end

local function material(name)
	if perfectworld.compat and perfectworld.compat.resolve then
		return perfectworld.compat.resolve(name)
	end
	return name
end

function perfectworld.structures.register(name, definition)
	assert(type(name) == "string", "name must be a string")
	assert(type(definition) == "table", "definition must be a table")
	assert(type(definition.generator) == "function" or definition.schematic ~= nil, "generator or schematic must be provided")
	assert(type(definition.size) == "table", "size must be a table")

	local copy = deep_copy(definition)
	copy.name = name
	structures[name] = copy
end

function perfectworld.structures.get(name)
	local def = structures[name]
	if not def then
		return nil
	end
	return deep_copy(def)
end

function perfectworld.structures.list()
	local result = {}
	for name, _ in pairs(structures) do
		table.insert(result, name)
	end
	table.sort(result)
	return result
end

function perfectworld.structures.place(name, pos, param2)
	local def = structures[name]
	if not def then
		return false, "structure '" .. name .. "' not registered"
	end

	param2 = param2 or 0

	local success, err
	if type(def.generator) == "function" then
		success, err = pcall(def.generator, pos, param2, def)
	elseif def.schematic then
		success, err = pcall(minetest.place_schematic, pos, def.schematic, param2, nil, true)
	else
		return false, "structure '" .. name .. "' has no generator or schematic"
	end

	if not success then
		return false, "placement failed: " .. tostring(err)
	end

	return true
end

-- Pre-register test structure
perfectworld.structures.register("pw_test_outpost", {
	size = {x = 5, y = 4, z = 5},
	categories = {"settlement", "outpost"},
	weight = 1,
	allowed_settlement_types = {"farm", "hamlet", "village"},
	terrain_requirements = {},
	connectors = {},
	generator = function(pos, param2, def)
		local p = {x = pos.x, y = pos.y, z = pos.z}

		for dx = -2, 2 do
			for dz = -2, 2 do
				for dy = 1, 3 do
					minetest.set_node({x = p.x + dx, y = p.y + dy, z = p.z + dz}, {name = "air"})
				end
			end
		end

		-- 5x5 platform at y=0 (replaces ground)
		for dx = -2, 2 do
			for dz = -2, 2 do
				minetest.set_node(
					{x = p.x + dx, y = p.y, z = p.z + dz},
					{name = material("dirt")}
				)
			end
		end

		-- Corner cobblestone posts with wooden slabs on top
		local corners = {
			{x = p.x - 2, z = p.z - 2},
			{x = p.x - 2, z = p.z + 2},
			{x = p.x + 2, z = p.z - 2},
			{x = p.x + 2, z = p.z + 2},
		}

		for _, corner in ipairs(corners) do
			local post_bottom = {x = corner.x, y = p.y + 1, z = corner.z}
			minetest.set_node(post_bottom, {name = material("cobble")})

			local post_top = {x = corner.x, y = p.y + 2, z = corner.z}
			minetest.set_node(post_top, {name = material("cobble")})

			local slab_pos = {x = corner.x, y = p.y + 3, z = corner.z}
			minetest.set_node(slab_pos, {name = material("slab_wood")})
		end

		-- Chest in center
		local chest_pos = {x = p.x, y = p.y + 1, z = p.z}
		minetest.set_node(chest_pos, {name = material("chest")})
	end,
})

minetest.log("action", "[pw_structures] loaded")
