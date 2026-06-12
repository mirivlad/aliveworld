# PerfectWorld

PerfectWorld is a Luanti modpack for the physical shape of the world. It owns
regions, settlement candidates, future buildings, roads, farms, and later
population and transport.

AliveWorld stays frozen while this modpack grows. Later AliveWorld should observe
PerfectWorld's physical world and build events, rumors, chronicles, and quests on
top of it.

## Modules

| Module | Responsibility |
| --- | --- |
| `pw_core` | Shared `perfectworld` API, settings, world seed handling, stable IDs |
| `pw_planner` | Deterministic regional logical plans |
| `pw_structures` | Structure registry and placement API |
| `pw_roads` | Road network API skeleton |
| `pw_settlements` | Settlement type definitions |
| `pw_population` | Population API skeleton |
| `pw_debug` | `/pw_*` debug chat commands |
| `pw_compat_mcl` | Mineclonia node/material compatibility |
| `pw_tests` | Luanti TestKit coverage for PerfectWorld |

## Public API

```lua
perfectworld.get_version()
perfectworld.get_region_coords(pos)
perfectworld.get_region_id(rx, rz)

perfectworld.planner.plan_region(rx, rz)
perfectworld.planner.get_region_at_pos(pos)

perfectworld.structures.register(name, definition)
perfectworld.structures.get(name)
perfectworld.structures.list()
```

Future API placeholders are documented in `docs/perfectworld-architecture.md`.

## Commands

```text
/pw_status
/pw_region
/pw_plan
/pw_plan <rx> <rz>
```

Command output uses stable `key=value` lines so TestKit and remote-controller
checks can parse it.

## Current Behavior

- Region size defaults to `1024`.
- Each region gets a deterministic plan from world seed, region coordinates,
  planner version, and configuration.
- A region may contain 0 to 2 settlement candidates.
- Candidates currently use a small test outpost structure for validating
  planner-to-mapgen materialization.
- Mineclonia node names are resolved through `pw_compat_mcl`.

## Limitations

- No real villages, towns, farms, or economy yet.
- Roads are API skeletons only.
- Population is a skeleton only.
- The test outpost is temporary and intentionally easy to identify/remove.
- No global route pathfinding exists yet.
