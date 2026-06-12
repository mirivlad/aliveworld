# AliveWorld Routes

AliveWorld routes are persistent logical plans for roads. A `planned` route
does not place blocks, bridges, signs, schematics, NPCs, or any other world
nodes. A `materialized` route has been physically written as a simple road bed
by the route materializer.

## Route Contract

Routes are stored by `aliveworld_core` in mod storage under
`aliveworld_routes`.

Stable fields:

```lua
{
  route_id = "old_road",
  kind = "road",
  from_site_id = "site_birch_ford",
  to_site_id = "site_stone_gully",
  from_logical_id = "birch_ford",
  to_logical_id = "stone_gully",
  status = "planned", -- or "materialized"
  planner_version = 1,
  world_seed = "5565029253200206738",
  cell_size = 16,
  corridor_radius = 4,
  points = {
    {
      pos = {x = 336, y = 7, z = -196},
      surface_node = "mcl_core:dirt_with_grass",
      cumulative_cost = 0,
      flags = {},
    },
  },
  result_count = 34,
  length = 1135,
  elevation_gain = 12,
  elevation_loss = 12,
  max_grade = 0.133,
  average_grade = 0.019,
  crossings = {},
  bbox = {
    min = {x = -356, y = 4, z = -196},
    max = {x = 336, y = 11, z = 292},
  },
  planning = {
    candidates_examined = 2051,
    nodes_expanded = 1576,
    elapsed_ms = 0,
    total_cost = 0,
  },
  settings = {
    cell_size = 16,
    max_nodes = 9000,
    nodes_per_step = 80,
  },
  claim_id = "route:old_road",
}
```

Route statuses currently used:

- `planned`: route control points and corridor are saved, but the world is not
  physically changed.
- `materialized`: the route's saved control points remain unchanged, and a
  separate materialization state records the physical road job.

The planner is deterministic for the same world seed, planner version, route id,
endpoint anchors, and settings. Tie-breaks use stable grid keys rather than
randomness.

## Spatial Claims

Claims are stored by `aliveworld_core` in mod storage under
`aliveworld_claims`.

Minimal claim contract:

```lua
{
  claim_id = "route:old_road",
  owner_type = "route",
  owner_id = "old_road",
  kind = "route_corridor",
  priority = 80,
  radius = 4,
  points = {{x = 336, y = 7, z = -196}},
  persistent = true,
  version = 1,
}
```

Supported claim kinds:

- `site_core`
- `site_reserved`
- `route_corridor`
- `event_area`

Route corridors are continuous polylines, not isolated point claims. Distance
checks consider route segments between saved planner points, so the corridor has
no holes between distant controls. Route corridors may cross other route
corridors and future event areas, but they conflict with unrelated `site_core`
claims. Conflicts return structured reasons instead of being ignored.

## Route Materialization

Physical road placement is tracked separately from the canonical route plan in
mod storage under `aliveworld_route_materialization`.

Materialization state contract (version 2):

```lua
{
  route_id = "old_road",
  materializer_version = 2,
  status = "materialized", -- planned, materializing, materialized, failed
  started_at = "2026-06-12T06:01:50Z",
  completed_at = "2026-06-12T06:02:28Z",
  processed_segments = 33,
  processed_nodes = 2880,
  road_width = 3,
  shoulder_width = 1,
  dense_points_count = 576,
  changed_nodes = 2728,
  vegetation_removed = 0,
  leaves_removed = 0,
  trunks_removed = 0,
  snow_removed = 0,
  filled_nodes = 122,
  cut_nodes = 142,
  skipped_protected = 0,
  skipped_blocked = 0,
  unknown_blocked = 0,
  metadata_protected = 0,
  other_replaced = 0,
  water_segments = 0,
  warnings = {},
  unresolved = {},
  checkpoint = {dense_index = 577, phase = "mutate"},
  settings = {
    centerline_step = 2,
    max_cut = 4,
    max_fill = 7,
    points_per_step = 2,
    max_ops_per_step = 10,
    target_budget_ms = 25,
    hard_warn_threshold_ms = 50,
    persist_interval_steps = 5,
  },
  job_metrics = {
    steps = 0,
    total_cpu_ms = 0,
    max_step_cpu_ms = 0,
    over_budget_steps = 0,
    total_emerge_wait_ms = 0,
    phases = {
      emerge = {calls = 0, total_ms = 0, max_ms = 0},
      scan = {calls = 0, total_ms = 0, max_ms = 0},
      profile = {calls = 0, total_ms = 0, max_ms = 0},
      mutate = {calls = 0, total_ms = 0, max_ms = 0},
    },
  },
}
```

The materializer densifies saved planner controls to a centerline with a maximum
step of 2 nodes. It samples the real surface for each dense point and then
writes a 3-node road bed plus one-node shoulders inside the route claim. The
current palette is selected from registered Mineclonia nodes:

- surface: `mcl_core:coarse_dirt`, fallback `mcl_core:dirt`
- shoulder: `mcl_core:dirt_with_grass`, fallback `mcl_core:dirt`
- fill/base: `mcl_core:dirt`, fallback `mcl_core:coarse_dirt` or
  `mcl_core:stone`

The first materializer version does not build bridges, tunnels, signs, ruins,
settlements, NPCs, or events. Unexpected liquid is reported as unresolved rather
than filled or bridged.

Node edits are conservative. The materializer may clear safe vegetation, leaves,
snow layers, and clearly natural tree material inside the road bed. It may cut
small natural bumps and fill bounded natural holes. It does not replace unknown
solid nodes, protected nodes, nodes with metadata or inventory, or cells outside
the route corridor. Large unresolved terrain causes a failed job instead of
silently materializing a broken route.

Clearance statistics are broken down by category:
- `vegetation_removed`: grass, flowers, flora, saplings, bushes
- `leaves_removed`: leaf blocks (leafdecay group)
- `trunks_removed`: tree/wood blocks (tree group)
- `snow_removed`: snow layers
- `unknown_blocked`: non-natural solid that could not be cleared
- `metadata_protected`: nodes with metadata or inventory
- `other_replaced`: other non-solid or unknown walkable nodes

Jobs use a shared budgeted runner (`aliveworld.job_runner`) that enforces both
operation count and wall-clock time limits per globalstep. Key settings:

- `target_budget_ms`: soft budget in milliseconds (default 25). The step yields
  when this is exceeded and work remains.
- `hard_warn_threshold_ms`: warning threshold (default 50). Steps exceeding this
  are logged and counted in `job_metrics.over_budget_steps`.
- `max_ops_per_step`: maximum node operations per step (default 10). Combined
  with time budget for deterministic throttling.

Budget measurement uses `minetest.get_us_time()` (monotonic microseconds). CPU
step time excludes asynchronous emerge wait; emerge wait is tracked separately
as `total_emerge_wait_ms` in job metrics.

Checkpoint persistence is throttled: writes happen after each processed chunk
or every `persist_interval_steps` steps (default 5), not after every individual
node edit. The checkpoint stores the next dense centerline index and current
phase, so a restart resumes a `materializing` route. A completed materialization
is idempotent: repeated normal starts return the saved state and do not widen or
raise the road. A force replan of the route clears stale materialization state
for that route.

Per-cell surface sampling uses a lightweight column scan
(`local_surface_at`) instead of the expensive terrain survey
(`terrain.route_sample` → `terrain.survey`) that was the source of prior
>800ms steps. Results are cached per XZ position in `surface_cache` to avoid
re-scanning overlapping cells between adjacent dense points. The cache is
stored in memory only and discarded on restart.

Dry-run uses the same dense centerline, profile, claim, palette, and safety
checks but does not modify nodes. It reports predicted changed/cleared/fill/cut
counts, protected or blocked cells, unexpected water, warnings, and unresolved
segments.

## Verify Mode

The materializer provides a synchronous verify scan for already materialized
routes. It checks each cell of the dense centerline for:
- Palette node present within ±3 blocks of the expected road Y
- Unexpected water in the road bed
- Position inside the route corridor claim

Verify does not modify nodes, claims, or persistent state. It requires the
route to have `status = "materialized"`. The report includes counts of palette
mismatches, water encounters, and outside-corridor cells.

## Commands

- `/aw_routes`: list saved routes.
- `/aw_route <route_id>`: show route summary, metrics, bbox, planner version,
  and claim state.
- `/aw_route_plan <route_id>`: start a budgeted route planning job.
- `/aw_route_replan <route_id>`: force a budgeted replanning job.
- `/aw_route_debug <route_id>`: show saved route and current planning job state.
- `/aw_route_materialize <route_id> dry-run`: analyze materialization without
  changing the world.
- `/aw_route_materialize <route_id>`: start or resume a budgeted materialization
  job.
- `/aw_route_materialize_status <route_id>`: show progress, counters, warnings,
  unresolved count, checkpoint, and materializer version.
- `/aw_route_materialize_cancel <route_id>`: cancel a running job with a
  controlled `failed` state.
- `/aw_route_materialize_verify <route_id>`: run synchronous verify scan on a
  materialized route. Reports palette mismatches, unexpected water, and
  outside-corridor cells without modifying the world.
- `/aw_route_materialize_debug <route_id>`: show route summary, materialization
  summary, palette, settings, job metrics (steps, CPU total/max, over-budget
  count, phase peaks), and first warnings/unresolved items.

`/aw_route_plan old_road` plans the canonical Old Road route from Birch Ford to
Stone Gully. Both endpoint sites must exist, have `anchor_pos`, and have
`physical_status` of `anchored` or `materialized`.

## Old Road Semantics

The logical site `old_road` is linked to route `old_road` after successful
planning through `site.data.route_id` and `site.data.representative_route_pos`.
Its existing `anchor_pos` is not migrated or used as a required waypoint.
GPS and tracking resolve route-linked `old_road` through
`representative_route_pos`, not the old off-corridor marker anchor. After full
physical materialization, the logical site may have `physical_status =
"materialized"` while the old marker remains untouched.
