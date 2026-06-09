minetest.register_chatcommand("aw_status", {
    description = "AliveWorld status",
    privs = {server = true},
    func = function(name)
        local day = aliveworld.get_day()
        return true, "AliveWorld status: day=" .. day
    end
})

minetest.log("action", "[aliveworld_admin] loaded")
