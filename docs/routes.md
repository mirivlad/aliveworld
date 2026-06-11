# AliveWorld Routes

AliveWorld routes are persistent logical plans for future roads. A `planned`
route does not place blocks, bridges, signs, schematics, NPCs, or any other
world nodes.

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
  status = "planned",
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
- `materialized`: reserved for future physical road placement.

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

Route corridors may cross other route corridors and future event areas, but they
conflict with unrelated `site_core` claims. Conflicts return structured reasons
instead of being ignored.

## Commands

- `/aw_routes`: list saved routes.
- `/aw_route <route_id>`: show route summary, metrics, bbox, planner version,
  and claim state.
- `/aw_route_plan <route_id>`: start a budgeted route planning job.
- `/aw_route_replan <route_id>`: force a budgeted replanning job.
- `/aw_route_debug <route_id>`: show saved route and current planning job state.

`/aw_route_plan old_road` plans the canonical Old Road route from Birch Ford to
Stone Gully. Both endpoint sites must exist, have `anchor_pos`, and have
`physical_status` of `anchored` or `materialized`.

## Old Road Semantics

The logical site `old_road` is linked to route `old_road` after successful
planning through `site.data.route_id` and `site.data.representative_route_pos`.
Its existing `anchor_pos` is not migrated or used as a required waypoint.
