-- aliveworld_test_suite/init.lua
-- AliveWorld test suite using Luanti TestKit

local modpath = minetest.get_modpath("aliveworld_test_suite")

-- Verify TestKit is available
if not luanti_testkit then
	minetest.log("error", "[aliveworld_test_suite] luanti_testkit not loaded! Tests will not be registered.")
	return
end

minetest.log("action", "[aliveworld_test_suite] registering tests...")

-- Load UI state and screenshot modules (must be first so tests can use them)
local ui_state = dofile(modpath .. "/ui_state.lua")
local screenshot = dofile(modpath .. "/screenshot.lua")

-- Register the suite
luanti_testkit.register_suite("aliveworld", {
	description = "AliveWorld integration tests",
})

-- Register cleanup handlers for UI types
ui_state.register_cleanup("formspec", function()
	local player_name = ui_state.get_report().player_name
	minetest.close_formspec(player_name, "")
	ui_state.mark_clean()
	return true, "formspec closed"
end)

-- Load test files
local test_files = {
	"direction",
	"gps",
	"radar",
	"anchors",
	"rumors",
	"tracking_state",
	"rumors_flow",
	"safety",
}

for _, file in ipairs(test_files) do
	local path = modpath .. "/tests/" .. file .. ".lua"
	local ok, err = pcall(dofile, path)
	if ok then
		minetest.log("action", "[aliveworld_test_suite] loaded tests/" .. file .. ".lua")
	else
		minetest.log("warning", "[aliveworld_test_suite] could not load tests/" .. file .. ".lua: " .. tostring(err))
	end
end

minetest.log("action", "[aliveworld_test_suite] loaded")

-- Track formspec openings to mark client as ui_dirty
local orig_show_formspec = minetest.show_formspec
minetest.show_formspec = function(player_name, formname, formspec)
	if player_name == ui_state.get_report().player_name then
		ui_state.mark_dirty("formspec")
	end
	return orig_show_formspec(player_name, formname, formspec)
end

-- Guard flags to prevent double test execution
local tests_in_progress = false
local initial_autorun_done = false

-- Auto-run tests when a test player connects
local function ensure_sites()
	if aliveworld and aliveworld.sites and aliveworld.sites.ensure_initial_settlement_sites then
		local n = aliveworld.sites.ensure_initial_settlement_sites()
		if n and n > 0 then
			minetest.log("action", "[aliveworld_test_suite] Created " .. n .. " settlement sites")
		end
	else
		minetest.log("action", "[aliveworld_test_suite] WARNING: aliveworld.sites not available")
	end
end

local function write_tests_complete_signal()
	local worldpath = minetest.get_worldpath()
	local signal = minetest.write_json({
		action = "tests_complete",
		timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
		stop_client = true,
	})
	local f = io.open(worldpath .. "/awbot_client.signal", "w")
	if f then
		f:write(signal)
		f:close()
		minetest.log("action", "[aliveworld_test_suite] stop signal written")
	end
end

local function run_all_tests(player_name)
	if tests_in_progress then
		minetest.log("warning", "[aliveworld_test_suite] tests already in progress, skipping duplicate run")
		return
	end
	tests_in_progress = true
	ensure_sites()
	ui_state.reset()
	minetest.log("action", "[aliveworld_test_suite] ========== RUNNING ALL TESTS ==========")
	luanti_testkit.run_all({player_name = player_name})
	minetest.log("action", "[aliveworld_test_suite] ========== TESTS COMPLETE ==========")
	tests_in_progress = false
	minetest.after(2, write_tests_complete_signal)
end

local function auto_run()
	if initial_autorun_done then
		return
	end
	initial_autorun_done = true
	local player_name = "awbot"
	local MAX_WAIT = 120  -- maximum seconds to wait for player
	local CHECK_INTERVAL = 5
	local elapsed = 0

	minetest.log("action", "[aliveworld_test_suite] auto-run: waiting up to " .. MAX_WAIT .. "s for player '" .. player_name .. "'")

	local function check_and_run()
		if tests_in_progress then
			minetest.log("action", "[aliveworld_test_suite] auto-run: tests in progress, skipping check")
			return
		end
		elapsed = elapsed + CHECK_INTERVAL
		local player = minetest.get_player_by_name(player_name)
		if player then
			minetest.log("action", "[aliveworld_test_suite] auto-run: player '" .. player_name .. "' online, running tests")
			run_all_tests(player_name)
		elseif elapsed < MAX_WAIT then
			minetest.log("action", "[aliveworld_test_suite] auto-run: player '" .. player_name .. "' not found (" .. elapsed .. "s elapsed), retrying...")
			minetest.after(CHECK_INTERVAL, check_and_run)
		else
			minetest.log("action", "[aliveworld_test_suite] auto-run: player '" .. player_name .. "' not found after " .. MAX_WAIT .. "s, running tests anyway")
			ensure_sites()
			run_all_tests(player_name)
		end
	end

	minetest.after(5, check_and_run)
end

-- Prepare for screenshot: safety checks, safe teleport, enable GPS/track, write state file
minetest.register_chatcommand("aw_prepare_shot", {
	params = "[site_id]",
	description = "Prepare awbot for world screenshot: safety checks, teleport, GPS/track restore",
	privs = {interact = true},
	func = function(player_name, params)
		local site_id = params ~= "" and params or "site_birch_ford"
		local result = ui_state.prepare_for_screenshot(site_id)
		if result.error then
			return false, "prepare_shot failed: " .. result.error
		end
		return true, "prepare_shot ok: " .. site_id
	end,
})

-- Try immediately
auto_run()
-- Note: on_joinplayer auto-test disabled during demo.
-- Re-enable by uncommenting the block below:
--[[
minetest.register_on_joinplayer(function(player)
	local name = player:get_player_name()
	minetest.log("action", "[aliveworld_test_suite] player joined: " .. name)
	if name == "awbot" then
		minetest.after(2, function()
			run_all_tests(name)
		end)
	end
end)
--]]
