perfectworld = perfectworld or {}
perfectworld.planner = perfectworld.planner or {}

local REGION_SIZE = perfectworld.REGION_SIZE
local MARGIN = 80
local MIN_DISTANCE = 200
local cache = {}
local storage = minetest.get_mod_storage()
local PLACED_KEY = "pw_placed_settlements"

local function det_prng(seed)
	local state = seed
	return function()
		state = (state * 1103515245 + 12345) % 2147483648
		return state / 2147483648
	end
end

local deep_copy = perfectworld.core.deep_copy

local function read_placed()
	local raw = storage:get_string(PLACED_KEY)
	if raw and raw ~= "" then
		local ok, data = pcall(minetest.parse_json, raw)
		if ok and type(data) == "table" then
			return data
		end
	end
	return {}
end

local function write_placed(data)
	storage:set_string(PLACED_KEY, minetest.write_json(data))
end

function perfectworld.planner.plan_region(rx, rz)
	local cache_key = rx .. "_" .. rz
	local cached = cache[cache_key]
	if cached then
		return deep_copy(cached)
	end

	local base_seed = perfectworld.region_seed(rx, rz, perfectworld.PLANNER_VERSION)
	local prng = det_prng(base_seed + perfectworld.PLANNER_VERSION * 1000003)

	local minp = {x = rx * REGION_SIZE, y = -64, z = rz * REGION_SIZE}
	local maxp = {x = (rx + 1) * REGION_SIZE - 1, y = 256, z = (rz + 1) * REGION_SIZE - 1}

	local settlement_candidates = {}
	local reserved_areas = {}
	local road_anchors = {}

	local r = prng()
	local num_candidates
	if r < 0.3 then
		num_candidates = 0
	elseif r < 0.8 then
		num_candidates = 1
	else
		num_candidates = 2
	end

	for i = 0, num_candidates - 1 do
		local x, z
		local valid = false
		for _attempt = 1, 50 do
			x = minp.x + MARGIN + math.floor(prng() * (REGION_SIZE - 2 * MARGIN))
			z = minp.z + MARGIN + math.floor(prng() * (REGION_SIZE - 2 * MARGIN))

			valid = true
			for _, existing in ipairs(settlement_candidates) do
				local dx = existing.x - x
				local dz = existing.z - z
				if dx * dx + dz * dz < MIN_DISTANCE * MIN_DISTANCE then
					valid = false
					break
				end
			end

			if valid then
				break
			end
		end

		if not valid then
			break
		end

		local type_roll = prng()
		local stype
		if type_roll < 0.6 then
			stype = "farm"
		elseif type_roll < 0.9 then
			stype = "hamlet"
		else
			stype = "village"
		end

		local priority
		if stype == "farm" then
			priority = 1 + math.floor(prng() * 2)
		elseif stype == "hamlet" then
			priority = 2 + math.floor(prng() * 3)
		else
			priority = 4 + math.floor(prng() * 2)
		end

		local candidate_id = perfectworld.core.stable_id("settlement", rx, rz, i, x, z, stype)

		table.insert(settlement_candidates, {
			id = candidate_id,
			index = i,
			x = x,
			z = z,
			type = stype,
			priority = priority,
			connection_required = true,
			status = "candidate",
		})

		table.insert(reserved_areas, {
			id = perfectworld.core.stable_id("reserve", candidate_id),
			kind = "settlement_candidate",
			ref = candidate_id,
			minp = {x = x - 12, y = -64, z = z - 12},
			maxp = {x = x + 12, y = 256, z = z + 12},
		})

		table.insert(road_anchors, {
			id = perfectworld.core.stable_id("road_anchor", candidate_id),
			ref = candidate_id,
			x = x,
			z = z,
			kind = "settlement_connection",
		})
	end

	local plan = {
		id = perfectworld.get_region_id(rx, rz),
		rx = rx,
		rz = rz,
		minp = minp,
		maxp = maxp,
		planner_version = perfectworld.PLANNER_VERSION,
		settlement_candidates = settlement_candidates,
		landmarks = {},
		road_anchors = road_anchors,
		reserved_areas = reserved_areas,
	}

	cache[cache_key] = deep_copy(plan)
	return deep_copy(plan)
end

function perfectworld.planner.get_region_at_pos(pos)
	local rx, rz = perfectworld.get_region_coords(pos)
	return perfectworld.planner.plan_region(rx, rz)
end

-- Track placed settlements to avoid duplicates
function perfectworld.planner.is_placed(settlement_id)
	return read_placed()[settlement_id] == true
end

function perfectworld.planner.mark_placed(settlement_id)
	local data = read_placed()
	data[settlement_id] = true
	write_placed(data)
end

function perfectworld.planner.list_placed()
	local data = read_placed()
	local res = {}
	for id, _ in pairs(data) do
		table.insert(res, id)
	end
	table.sort(res)
	return res
end

function perfectworld.planner._test_unmark_placed(settlement_id)
	local data = read_placed()
	data[settlement_id] = nil
	write_placed(data)
end

-- Materialize a settlement candidate at its planned position
local function materialize_candidate(candidate)
	local x = candidate.x
	local z = candidate.z
	local sid = candidate.id

	if perfectworld.planner.is_placed(sid) then
		return false, "already_placed"
	end

	-- Find surface Y at (x, z)
	local y = nil
	for y_test = 256, -64, -1 do
		local node = minetest.get_node({x = x, y = y_test, z = z})
		if node.name ~= "air" and node.name ~= "ignore" then
			y = y_test + 1
			break
		end
	end
	if not y then
		return false, "no_surface_found"
	end

	-- Place test structure
	if perfectworld.structures and perfectworld.structures.place then
		local ok, err = perfectworld.structures.place("pw_test_outpost", {x = x, y = y, z = z})
		if not ok then
			return false, "place_failed: " .. tostring(err)
		end
	end

	perfectworld.planner.mark_placed(sid)
	return true, {x = x, y = y, z = z}
end

-- Called during mapgen for every generated chunk
function perfectworld.planner.materialize_chunk(minp, maxp)
	local rx_min, rz_min = perfectworld.get_region_coords(minp)
	local rx_max, rz_max = perfectworld.get_region_coords(maxp)

	for rx = rx_min, rx_max do
		for rz = rz_min, rz_max do
			local plan = perfectworld.planner.plan_region(rx, rz)
			for _, candidate in ipairs(plan.settlement_candidates or {}) do
				if candidate.x >= minp.x and candidate.x <= maxp.x
				   and candidate.z >= minp.z and candidate.z <= maxp.z then
					if not perfectworld.planner.is_placed(candidate.id) then
						materialize_candidate(candidate)
					end
				end
			end
		end
	end
end

-- Register mapgen hook
minetest.register_on_generated(function(minp, maxp)
	perfectworld.planner.materialize_chunk(minp, maxp)
end)

minetest.log("action", "[pw_planner] loaded")
