# End-to-End Verification Report

## Server
- Server started at 2026-06-10 21:21:29
- No crashes, auto-tick continues

## Client
- awbot connected at 2026-06-11 01:59:33 on display :102
- All rc commands received and processed

## Commands Executed

| # | Screenshot | Command | Result |
|---|-----------|---------|--------|
| 00 | spawn | (initial connection) | awbot joins game |
| 01 | rumor_board | /aw_rumors | List of rumors displayed |
| 02 | rumor_detail | /aw_rumor rumor_000249 | Rumor details shown |
| 03 | track_started | /aw_gps on + /aw_track site_birch_ford | Waypoint: "Берёзовый Брод" (localized), dist: 367 blocks, precision: "примерная область" |
| 04 | radar_testpattern | /aw_gps_testpattern on | "Test pattern включён. Видны маркеры: центр (белый), N(красный), E(зелёный), S(синий), W(жёлтый)" |
| 05 | gps_hud_debug | /aw_gps_hud_debug | "=== Radar HUD Debug ===" |
| 06 | arrival_teleport | /teleport (320,8,-180) | Teleported to site_birch_ford |
| 07 | arrival_point | (at site) | Arrival triggered |
| 08 | rumor_after_arrival | /aw_rumor rumor_000249 | Rumor status updated |
| 09 | version_info | /aw_version | Runtime info displayed |

## Arrival
- `[tracking] arrival: awbot at site_birch_ford dist=0 kind=abstract` ✅
- `[aliveworld_core] clue marker: no suitable node found for site_birch_ford` (expected in test env)

## GPS System
- Radar enabled: ✅
- Test pattern: ✅ (white center, colored cardinal markers)
- HUD debug: ✅
- Waypoint shows localized name (Берёзовый Брод): ✅
- Distance shown: ✅ (367 blocks)
- Precision shown: ✅ (примерная область)

## Known Issues
- Clue marker placement fails: no default:torch/etc nodes in test environment
- Screenshot display :102 vs script default :99 (needs alignment)
- Deprecation warning: hud_elem_type → type in tracking.lua:80,93
- luatest assertion `is_nil` missing in tracking_state tests
