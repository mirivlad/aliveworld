-- claims.lua
-- Minimal persistent spatial claim registry for AliveWorld planning.

local storage = minetest.get_mod_storage()
local CLAIMS_KEY = "aliveworld_claims"

local claims = {}

aliveworld.claims = {}

local CLAIM_KINDS = {
  site_core = true,
  site_reserved = true,
  route_corridor = true,
  event_area = true,
}

local function copy_table(src)
  local dst = {}
  for k, v in pairs(src or {}) do
    if type(v) == "table" then
      dst[k] = copy_table(v)
    else
      dst[k] = v
    end
  end
  return dst
end

local function save_all()
  storage:set_string(CLAIMS_KEY, minetest.write_json(claims))
end

local function load_all()
  local raw = storage:get_string(CLAIMS_KEY)
  if raw and raw ~= "" then
    local ok, data = pcall(minetest.parse_json, raw)
    if ok and data then
      claims = data
    end
  end
end

local function distance2d(a, b)
  local dx = (a.x or 0) - (b.x or 0)
  local dz = (a.z or 0) - (b.z or 0)
  return math.sqrt(dx * dx + dz * dz)
end

local function validate_claim(claim)
  if type(claim) ~= "table" then
    return false, {error = "invalid_claim", field = "claim"}
  end
  if not claim.claim_id or claim.claim_id == "" then
    return false, {error = "invalid_claim", field = "claim_id"}
  end
  if not CLAIM_KINDS[claim.kind or ""] then
    return false, {error = "invalid_claim", field = "kind"}
  end
  if type(claim.points) ~= "table" or #claim.points == 0 then
    return false, {error = "invalid_claim", field = "points"}
  end
  for i, p in ipairs(claim.points) do
    if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" or type(p.z) ~= "number" then
      return false, {error = "invalid_claim", field = "points", index = i}
    end
  end
  claim.radius = tonumber(claim.radius) or 0
  claim.priority = tonumber(claim.priority) or 0
  return true
end

local function compatible(a, b, opts)
  opts = opts or {}
  if a.claim_id == b.claim_id then return true end
  if a.owner_type == b.owner_type and a.owner_id == b.owner_id then return true end
  if opts.allowed_owner_ids and b.owner_id and opts.allowed_owner_ids[b.owner_id] then return true end
  if a.kind == "route_corridor" and b.kind == "route_corridor" then return true end
  if a.kind == "event_area" and b.kind == "route_corridor" then return true end
  if a.kind == "route_corridor" and b.kind == "event_area" then return true end
  return false
end

function aliveworld.claims.check(claim, opts)
  local ok, err = validate_claim(copy_table(claim))
  if not ok then return false, err end
  local candidate = copy_table(claim)
  for _, existing in pairs(claims) do
    if not compatible(candidate, existing, opts) then
      for ai, ap in ipairs(candidate.points) do
        for bi, bp in ipairs(existing.points or {}) do
          local limit = (candidate.radius or 0) + (existing.radius or 0)
          local dist = distance2d(ap, bp)
          if dist <= limit then
            return false, {
              error = "claim_conflict",
              claim_id = candidate.claim_id,
              conflicting_claim_id = existing.claim_id,
              conflicting_owner_type = existing.owner_type,
              conflicting_owner_id = existing.owner_id,
              conflicting_kind = existing.kind,
              point_index = ai,
              conflicting_point_index = bi,
              distance = math.floor(dist + 0.5),
              required_clearance = limit,
            }
          end
        end
      end
    end
  end
  return true, {status = "ok"}
end

function aliveworld.claims.register(claim, opts)
  opts = opts or {}
  local candidate = copy_table(claim)
  local ok, err = validate_claim(candidate)
  if not ok then return false, err end
  if not opts.replace and claims[candidate.claim_id] then
    return false, {error = "claim_exists", claim_id = candidate.claim_id}
  end
  local previous = claims[candidate.claim_id]
  claims[candidate.claim_id] = nil
  local check_ok, conflict = aliveworld.claims.check(candidate, opts)
  if not check_ok then
    claims[candidate.claim_id] = previous
    return false, conflict
  end
  candidate.version = candidate.version or 1
  candidate.persistent = candidate.persistent ~= false
  claims[candidate.claim_id] = candidate
  save_all()
  return true, copy_table(candidate)
end

function aliveworld.claims.get(claim_id)
  local claim = claims[claim_id]
  return claim and copy_table(claim) or nil
end

function aliveworld.claims.delete(claim_id)
  if not claims[claim_id] then return false end
  claims[claim_id] = nil
  save_all()
  return true
end

function aliveworld.claims.list()
  local res = {}
  for _, claim in pairs(claims) do
    table.insert(res, copy_table(claim))
  end
  table.sort(res, function(a, b) return (a.claim_id or "") < (b.claim_id or "") end)
  return res
end

function aliveworld.claims.reset()
  claims = {}
  save_all()
end

load_all()

minetest.log("action", "[aliveworld_core] claims module loaded")
