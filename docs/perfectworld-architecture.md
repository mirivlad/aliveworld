# PerfectWorld Architecture

PerfectWorld is the new physical-world layer for this repository. It is
responsible for settlements, roads, buildings, farms, and later residents and
transport. AliveWorld remains frozen until PerfectWorld provides a real populated
world that AliveWorld can observe.

## Responsibility Boundary

```text
PerfectWorld
    -> physical settlements, roads, buildings, farms
    -> simulation of physical changes
    -> AliveWorld events, rumors, chronicles, quests
```

PerfectWorld does not create rumors or chronicles. AliveWorld should later read
PerfectWorld state instead of inventing abstract events first and materializing
physical evidence afterwards.

## Regional Planner

The world is divided into logical regions. The default region size is
`1024 x 1024` nodes on X/Z and can be changed with:

```text
perfectworld.region_size = 1024
```

The regional plan is the source of truth. A mapgen chunk does not make global
decisions about whether a village, road, or landmark exists. It only materializes
the part of an already determined regional plan that intersects the generated
area.

`perfectworld.planner.plan_region(rx, rz)` returns a plan with:

```lua
{
  id = "region_<stable_id>",
  rx = rx,
  rz = rz,
  minp = {x = ..., y = -64, z = ...},
  maxp = {x = ..., y = 256, z = ...},
  planner_version = 1,
  settlement_candidates = {},
  landmarks = {},
  road_anchors = {},
  reserved_areas = {},
}
```

Settlement candidates are proposals, not construction promises:

```lua
{
  id = "settlement_<stable_id>",
  type = "farm" | "hamlet" | "village",
  x = ...,
  z = ...,
  priority = ...,
  connection_required = true,
  status = "candidate",
}
```

## Determinism

Plans must depend only on:

- world seed;
- region coordinates;
- planner version;
- PerfectWorld configuration.

The current seed mixer hashes those values as strings into a local 31-bit seed.
It does not use the global random generator and does not use a simple sum, so
regions such as `(0, 1)` and `(1, 0)` do not collide through commutative mixing.

The following calls must return equivalent plans:

```lua
perfectworld.planner.plan_region(0, 0)
perfectworld.planner.plan_region(0, 0)
```

Request order must not matter:

```text
plan A -> plan B
plan B -> plan A
```

## Logical Plan vs Materialization

The logical plan describes intended objects. Materialization is the physical
placement of nodes into generated map areas.

The first implementation materializes settlement candidates as a temporary test
outpost. This validates:

- planner-to-mapgen wiring;
- stable coordinates;
- duplicate prevention through placement records;
- chunk selection based on planned objects.

The test outpost is not a final farm, hamlet, or village building.

## Structures

Structures are registered through:

```lua
perfectworld.structures.register(name, definition)
perfectworld.structures.get(name)
perfectworld.structures.list()
```

Definitions allow future `.mts` schematics, Lua schematics, and procedural
generators:

```lua
{
  size = {x = 5, y = 4, z = 5},
  categories = {"settlement", "farm"},
  weight = 1,
  allowed_settlement_types = {"farm", "hamlet", "village"},
  terrain_requirements = {},
  connectors = {},
  schematic = nil,
  generator = function(pos, param2, def) end,
}
```

Mineclonia nodes are resolved through `pw_compat_mcl`. Core planning code should
not depend on `mcl_*` node names.

## Future Roads

`pw_roads` currently defines the API boundary only. Future work should add:

- local settlement paths;
- roads between settlements;
- regional roads;
- trade routes.

Road planning should consume regional plans and road anchors. It should not let
individual mapgen chunks independently decide long-distance roads.

## Future AliveWorld Integration

AliveWorld should be unfrozen only after PerfectWorld can provide enough real
physical state for events to reference:

- physical farms, hamlets, and villages;
- basic road network;
- structure registry with real buildings;
- mapgen-safe materialization;
- basic population and economic state.

At that point AliveWorld can observe PerfectWorld settlements, roads, residents,
and changes, then produce events, rumors, chronicles, and quests from real world
state.
