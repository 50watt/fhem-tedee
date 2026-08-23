# FHEM Tedee

FHEM modules for controlling Tedee smart locks through the Tedee Bridge local API, with optional Tedee Cloud activity information.

## Requirements

- FHEM
- Perl 5.14 or newer
- A Tedee smart lock paired with a Tedee Bridge
- Local Bridge API enabled on the Tedee Bridge
- Network connectivity from FHEM to the Tedee Bridge
- Internet access for the Tedee Bridge for Tedee's certificate handling

No additional CPAN modules should normally be required on a standard FHEM installation.

The module uses Perl/FHEM components such as `Digest::SHA`, `Time::HiRes`, `Encode`, `IO::Socket::INET`, `GPUtils` and `FHEM::Meta`. JSON support is selected from available backends and falls back to `JSON::PP`. `FHEM::Utility::CTZ` is optional and is used, when available, to convert Tedee Cloud timestamps from UTC to the local FHEM time zone.

No MQTT broker or external daemon is required.

## Hardware support

This module has currently been tested with one Tedee lock installation. Multi-device support is implemented, but installations with multiple Tedee locks have not yet been validated by the author.

## Local Bridge API token

Tedee's Bridge API must first be enabled in the Tedee mobile app:

1. Open the Tedee app.
2. Open the selected Bridge.
3. Go to **Settings → API**.
4. Enable the Bridge API.
5. Copy the displayed token.
6. Keep **Encrypted Token** enabled for normal use.

Store the token in FHEM:

```text
set tedeeBridge1 token <LOCAL_BRIDGE_TOKEN>
```

The module defaults to encrypted token authentication.

## Optional Tedee Cloud PersonalKey

Cloud access is optional. It is used for activity information such as the last action and the user responsible for it.

Create a Tedee API PersonalKey in the Tedee web portal and store it in FHEM:

```text
set tedeeBridge1 cloudToken <PERSONAL_KEY>
```

The PersonalKey is stored by FHEM and is not part of the device definition.

## Installation

Repository layout:

```text
FHEM/73_TedeeBridge.pm
FHEM/74_TedeeDevice.pm
lib/FHEM/Devices/Tedee/Bridge.pm
lib/FHEM/Devices/Tedee/Device.pm
README.md
CHANGELOG.md
LICENSE
```

For a standard FHEM installation under `/opt/fhem`, copy only the four module files:

```bash
sudo cp FHEM/73_TedeeBridge.pm /opt/fhem/FHEM/
sudo cp FHEM/74_TedeeDevice.pm /opt/fhem/FHEM/

sudo mkdir -p /opt/fhem/lib/FHEM/Devices/Tedee
sudo cp lib/FHEM/Devices/Tedee/Bridge.pm /opt/fhem/lib/FHEM/Devices/Tedee/
sudo cp lib/FHEM/Devices/Tedee/Device.pm /opt/fhem/lib/FHEM/Devices/Tedee/

sudo chown fhem:dialout   /opt/fhem/FHEM/73_TedeeBridge.pm   /opt/fhem/FHEM/74_TedeeDevice.pm   /opt/fhem/lib/FHEM/Devices/Tedee/Bridge.pm   /opt/fhem/lib/FHEM/Devices/Tedee/Device.pm

sudo chmod 644   /opt/fhem/FHEM/73_TedeeBridge.pm   /opt/fhem/FHEM/74_TedeeDevice.pm   /opt/fhem/lib/FHEM/Devices/Tedee/Bridge.pm   /opt/fhem/lib/FHEM/Devices/Tedee/Device.pm
```

Restart FHEM after installation so the wrapper and `lib` modules are loaded consistently.

## Setup

Define the Bridge using its local IP address or hostname:

```text
define tedeeBridge1 TedeeBridge 192.0.2.10
```

Store the local Bridge API token:

```text
set tedeeBridge1 token <LOCAL_BRIDGE_TOKEN>
```

The module then reads Bridge information, discovers locks and registers the callback automatically. Missing `TedeeDevice` devices are created automatically during device discovery.

Optional Cloud activity:

```text
set tedeeBridge1 cloudToken <PERSONAL_KEY>
```

Useful setup checks:

```text
get tedeeBridge1 setup
get tedeeBridge1 health
```

## Security

Remote `unlock` and `unlatch` are disabled by default on each `TedeeDevice`.

Enable them only where remote opening is intended:

```text
attr tedeeLock1 allowUnlock 1
```

Plain Bridge API tokens are intended only for development. Use encrypted token mode for normal operation.

This module interacts with door locks. The user is responsible for ensuring safe operation. The authors take no responsibility for misuse or security issues.

## Documentation

Complete FHEM Commandref documentation is included in both English and German:

- `FHEM/73_TedeeBridge.pm`
- `FHEM/74_TedeeDevice.pm`

## Credits

Inspired by the FHEM Nuki modules by CoolTux. The Tedee implementation intentionally follows established FHEM/Nuki patterns where they fit the Tedee APIs.

## License

GPL-2.0. See `LICENSE`.
