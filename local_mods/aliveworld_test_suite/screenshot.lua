-- aliveworld_test_suite/screenshot.lua
-- Screenshot management for awbot test client
-- Generates JSON metadata files alongside screenshots for the host-side tool

local modpath = minetest.get_modpath("aliveworld_test_suite")
local worldpath = minetest.get_worldpath()

local ss = {}

local current_session_id = os.date("%Y%m%d_%H%M%S")
local screenshot_count = 0

function ss.get_next_path()
  screenshot_count = screenshot_count + 1
  local filename = string.format("ss_%s_%03d.png", current_session_id, screenshot_count)
  return filename
end

function ss.write_metadata(screenshot_path, screenshot_kind, ui_report, extra)
  extra = extra or {}
  local meta = {
    screenshot = screenshot_path,
    screenshot_kind = screenshot_kind,
    timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    session_id = current_session_id,
    screenshot_number = screenshot_count,
    ui_state = {
      client_ui_dirty = ui_report.client_ui_dirty,
      known_open_ui = ui_report.known_open_ui,
      cleanup_count = ui_report.cleanup_count,
      restart_count = ui_report.restart_count,
      restored_count = ui_report.restored_count,
    },
    extra = extra,
  }

  local meta_path = worldpath .. "/" .. screenshot_path:gsub("%.png$", "") .. ".meta.json"
  local f = io.open(meta_path, "w")
  if f then
    f:write(minetest.write_json(meta))
    f:close()
    minetest.log("action", "[screenshot] metadata written: " .. meta_path)
  end

  local latest_path = worldpath .. "/screenshot_latest.meta.json"
  local fl = io.open(latest_path, "w")
  if fl then
    fl:write(minetest.write_json(meta))
    fl:close()
  end
end

function ss.read_latest_metadata()
  local f = io.open(worldpath .. "/screenshot_latest.meta.json", "r")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if content and content ~= "" then
    local ok, data = pcall(minetest.parse_json, content)
    if ok then return data end
  end
  return nil
end

function ss.get_session_id()
  return current_session_id
end

function ss.get_count()
  return screenshot_count
end

minetest.log("action", "[aliveworld_test_suite] screenshot module loaded")
return ss
