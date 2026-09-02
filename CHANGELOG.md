# Changelog

## v0.7.30 - 2026-09-02

### Changed

- `unlock` now always unlocks without pulling the spring, independent of the Tedee automatic pull-spring setting.
- `unlatch` now consistently unlocks if necessary and pulls the spring.
- With Tedee auto-pull enabled, `unlatch` uses the native Tedee unlock operation so unlocking and spring pulling are performed as one coordinated operation without additional FHEM-side delay.
- With Tedee auto-pull disabled, `unlatch` waits for confirmed `unlocked` state before requesting the spring pull; a short delay is therefore expected.
- `pullSpringEnabled` and `autoPullSpringEnabled` are exposed as regular readings.
- `unlatch` is rejected when spring pulling is known to be disabled.
- Commandref documents that Tedee app pull-spring setting changes may only be transferred after leaving or closing the corresponding settings page.


## 0.7.29

First GitHub release candidate.

- Local Tedee Bridge API support
- Automatic lock discovery and `TedeeDevice` creation
- Rename-safe device discovery based on Tedee `DEVICEID`
- Local request queue with at least one second between Bridge API requests
- Automatic callback registration and renewal
- Optional Tedee Cloud activity integration
- Cloud activity retry scheduling
- Local time conversion for Cloud activity timestamps
- Multi-device-capable internal device mapping
- English and German FHEM Commandref documentation
- Safe default: `unlock` and `unlatch` disabled unless explicitly enabled
- Bridge state, setup state and cloud state handled separately
