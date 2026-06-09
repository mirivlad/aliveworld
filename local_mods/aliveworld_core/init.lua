aliveworld = rawget(_G, "aliveworld") or {}
_G.aliveworld = aliveworld

local storage = minetest.get_mod_storage()

local function get_day()
    local day = storage:get_int("world_day")
    if day <= 0 then
        day = 1
        storage:set_int("world_day", day)
    end
    return day
end

local function add_chronicle(text)
    local old = storage:get_string("chronicle")
    local line = os.date("!%Y-%m-%dT%H:%M:%SZ") .. " | " .. text
    storage:set_string("chronicle", old .. line .. "\n")
end

aliveworld.get_day = get_day
aliveworld.add_chronicle = add_chronicle

minetest.register_chatcommand("aw_day", {
    description = "Show AliveWorld day",
    privs = {interact = true},
    func = function(name)
        return true, "AliveWorld day: " .. get_day()
    end
})

minetest.register_chatcommand("aw_chronicle", {
    description = "Show AliveWorld chronicle",
    privs = {interact = true},
    func = function(name)
        local chronicle = storage:get_string("chronicle")
        if chronicle == "" then
            return true, "Chronicle is empty."
        end
        return true, chronicle
    end
})

minetest.register_chatcommand("aw_tick", {
    description = "Force AliveWorld simulation tick",
    privs = {server = true},
    func = function(name)
        local day = get_day() + 1
        storage:set_int("world_day", day)
        add_chronicle("День " .. day .. ": мир сделал первый тестовый шаг.")
        return true, "AliveWorld tick complete. Day: " .. day
    end
})

local function do_tick()
    local day = get_day() + 1
    storage:set_int("world_day", day)
    add_chronicle("День " .. day .. ": мир живёт и развивается.")
    minetest.log("action", "[aliveworld_core] auto-tick: день " .. day)
    minetest.after(120, do_tick)
end

minetest.after(120, do_tick)

minetest.log("action", "[aliveworld_core] loaded")
