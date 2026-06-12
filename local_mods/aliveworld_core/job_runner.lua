-- job_runner.lua
-- Reusable budgeted time-sliced job runner for long world operations.

aliveworld.job_runner = aliveworld.job_runner or {}
local runner = aliveworld.job_runner

local jobs = {}

local function monotonic_us()
  return minetest.get_us_time()
end

local DEFAULTS = {
  target_budget_ms = 25,
  hard_warn_threshold_ms = 50,
  max_ops_per_step = 50,
  persist_interval_steps = 5,
}

local function ensure_phase(job, phase)
  if not job.metrics.phases[phase] then
    job.metrics.phases[phase] = {calls = 0, total_ms = 0, max_ms = 0}
  end
end

local function record_phase_time(job, phase, elapsed_ms)
  ensure_phase(job, phase)
  local pm = job.metrics.phases[phase]
  pm.calls = pm.calls + 1
  pm.total_ms = pm.total_ms + elapsed_ms
  if elapsed_ms > pm.max_ms then pm.max_ms = elapsed_ms end
end

local function update_step_metrics(job, cpu_ms, emerged_ms)
  local m = job.metrics
  m.steps = m.steps + 1
  m.total_cpu_ms = m.total_cpu_ms + cpu_ms
  m.total_emerge_wait_ms = m.total_emerge_wait_ms + (emerged_ms or 0)
  if cpu_ms > m.max_step_cpu_ms then m.max_step_cpu_ms = cpu_ms end
  if cpu_ms > (job.config.hard_warn_threshold_ms or DEFAULTS.hard_warn_threshold_ms) then
    m.over_budget_steps = m.over_budget_steps + 1
  end
end

function runner.create(id, config, handlers)
  if jobs[id] then return false, "job_exists" end
  local cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  if config then
    for k, v in pairs(config) do
      if cfg[k] ~= nil then cfg[k] = v end
    end
  end
  local job = {
    id = id,
    status = "running",
    phase = "init",
    config = cfg,
    handlers = handlers or {},
    checkpoint = {},
    metrics = {
      steps = 0,
      total_cpu_ms = 0,
      max_step_cpu_ms = 0,
      over_budget_steps = 0,
      total_emerge_wait_ms = 0,
      phases = {},
    },
    created_us = monotonic_us(),
    started_us = nil,
    completed_us = nil,
    error = nil,
    persist_step_counter = 0,
  }
  jobs[id] = job
  return true, job
end

function runner.get(id)
  return jobs[id]
end

function runner.cancel(id, reason)
  local job = jobs[id]
  if not job then return false, "not_found" end
  if job.status ~= "running" then return false, "not_running" end
  job.status = "cancelled"
  job.error = reason or "cancelled"
  job.completed_us = monotonic_us()
  if job.handlers.on_cleanup then
    pcall(job.handlers.on_cleanup, job)
  end
  if job.handlers.on_persist then
    pcall(job.handlers.on_persist, job)
  end
  return true
end

function runner.remove(id)
  jobs[id] = nil
end

function runner.process_jobs()
  for id, job in pairs(jobs) do
    if job.status == "running" then
      if not job.started_us then job.started_us = monotonic_us() end
      local step_start = monotonic_us()
      local ok, result = pcall(job.handlers.on_step, job)
      local step_end = monotonic_us()
      local cpu_elapsed_ms = math.floor((step_end - step_start) / 1000)
      if not ok then
        job.status = "failed"
        job.error = tostring(result)
        job.completed_us = monotonic_us()
        if job.handlers.on_cleanup then
          pcall(job.handlers.on_cleanup, job)
        end
        if job.handlers.on_persist then
          pcall(job.handlers.on_persist, job)
        end
        minetest.log("error", "[job_runner] job " .. tostring(id) .. " failed: " .. tostring(result))
      elseif type(result) == "table" then
        local status = result.status
        update_step_metrics(job, cpu_elapsed_ms, result.emerged_ms or 0)
        local prev_phase = job.phase
        if result.phase and result.phase ~= prev_phase then
          job.phase = result.phase
        end
        record_phase_time(job, job.phase, cpu_elapsed_ms)
        job.persist_step_counter = job.persist_step_counter + 1
        if status == "done" then
          job.status = "done"
          job.completed_us = monotonic_us()
          if job.handlers.on_complete then
            pcall(job.handlers.on_complete, job, result)
          end
          if job.handlers.on_cleanup then
            pcall(job.handlers.on_cleanup, job)
          end
          if job.handlers.on_persist then
            pcall(job.handlers.on_persist, job)
          end
        elseif status == "failed" then
          job.status = "failed"
          job.error = result.error or "unknown"
          job.completed_us = monotonic_us()
          if job.handlers.on_cleanup then
            pcall(job.handlers.on_cleanup, job)
          end
          if job.handlers.on_persist then
            pcall(job.handlers.on_persist, job)
          end
        elseif status == "yield" then
          if job.persist_step_counter >= job.config.persist_interval_steps then
            job.persist_step_counter = 0
            if job.handlers.on_persist then
              pcall(job.handlers.on_persist, job)
            end
          end
          if cpu_elapsed_ms > job.config.hard_warn_threshold_ms then
            minetest.log("warning", string.format(
              "[job_runner] step %s %s cpu=%dms phase=%s (exceeds %dms threshold)",
              id, job.phase, cpu_elapsed_ms, job.phase, job.config.hard_warn_threshold_ms
            ))
          end
        end
      end
    end
  end
end

function runner.job_status(id)
  local job = jobs[id]
  if not job then return nil end
  local m = job.metrics
  return {
    id = job.id,
    status = job.status,
    phase = job.phase,
    error = job.error,
    steps = m.steps,
    total_cpu_ms = m.total_cpu_ms,
    max_step_cpu_ms = m.max_step_cpu_ms,
    over_budget_steps = m.over_budget_steps,
    total_emerge_wait_ms = m.total_emerge_wait_ms,
    phases = m.phases,
    config = {
      target_budget_ms = job.config.target_budget_ms,
      hard_warn_threshold_ms = job.config.hard_warn_threshold_ms,
      max_ops_per_step = job.config.max_ops_per_step,
    },
  }
end

function runner.list()
  local res = {}
  for id, job in pairs(jobs) do
    table.insert(res, {id = id, status = job.status, phase = job.phase})
  end
  return res
end

function runner.cleanup()
  for id, job in pairs(jobs) do
    if job.status ~= "running" then
      if job.handlers.on_cleanup then
        pcall(job.handlers.on_cleanup, job)
      end
      jobs[id] = nil
    end
  end
end

minetest.log("action", "[aliveworld_core] job_runner module loaded")
