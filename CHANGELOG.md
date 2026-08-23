# Changelog

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
