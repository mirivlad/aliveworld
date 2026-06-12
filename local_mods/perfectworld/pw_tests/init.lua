local modpath = minetest.get_modpath("pw_tests")

if not luanti_testkit then
  minetest.log("error", "[pw_tests] luanti_testkit not loaded!")
  return
end

luanti_testkit.register_suite("perfectworld", {
  description = "PerfectWorld integration tests",
})

local test_files = {
  "core",
  "planner",
}

for _, file in ipairs(test_files) do
  local path = modpath .. "/tests/" .. file .. ".lua"
  local ok, err = pcall(dofile, path)
  if ok then
    minetest.log("action", "[pw_tests] loaded tests/" .. file .. ".lua")
  else
    minetest.log("warning", "[pw_tests] could not load tests/" .. file .. ".lua: " .. tostring(err))
  end
end

minetest.log("action", "[pw_tests] loaded")
