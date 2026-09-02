#!/usr/bin/env python3
"""Apply the v0.7.30 Tedee unlock/unlatch development changes.

The script intentionally uses exact replacements and aborts if the expected
v0.7.29 source blocks are not present. This keeps the development patch small,
reviewable and safe to apply to the dedicated v0.7.30-dev branch.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(
            f"Expected exactly one match in {path.relative_to(ROOT)}, found {count}"
        )
    path.write_text(text.replace(old, new, 1), encoding="utf-8")


bridge = ROOT / "lib/FHEM/Devices/Tedee/Bridge.pm"
device = ROOT / "lib/FHEM/Devices/Tedee/Device.pm"
wrapper = ROOT / "FHEM/74_TedeeDevice.pm"

replace_once(bridge, "our $VERSION = '0.7.29';", "our $VERSION = '0.7.30';")
replace_once(device, "our $VERSION = '0.7.29';", "our $VERSION = '0.7.30';")

replace_once(
    bridge,
    '''  if ($fn eq 'unlock') {\n    return Request($hash, 'POST', "lock/$deviceId/unlock", '{}', \\&ParseCommandResponse, "POST lock/$deviceId/unlock");\n  }\n\n  if ($fn eq 'unlatch') {\n    return Request($hash, 'POST', "lock/$deviceId/pull", '{}', \\&ParseCommandResponse, "POST lock/$deviceId/pull");\n  }\n\n  return "Unknown write function $fn";\n}\n\nsub Parse {''',
    '''  if ($fn eq 'unlock') {\n    # Mode 3 explicitly suppresses automatic spring pulling. This keeps the\n    # FHEM command "unlock" deterministic even when Tedee auto-pull is enabled.\n    return RequestUnlockMode($hash, $deviceId, 3);\n  }\n\n  if ($fn eq 'unlatch') {\n    # "unlatch" is a high-level FHEM operation: unlock when necessary and\n    # finally pull the spring. The exact request sequence depends on the\n    # current state and on Tedee's auto-pull setting.\n    return StartUnlatch($hash, $deviceId);\n  }\n\n  return "Unknown write function $fn";\n}\n\nsub RequestUnlockMode {\n  my ($hash, $deviceId, $mode) = @_;\n\n  return Request(\n    $hash,\n    'POST',\n    "lock/$deviceId/unlock",\n    '{}',\n    \\&ParseCommandResponse,\n    "POST lock/$deviceId/unlock mode=$mode",\n    "mode: $mode"\n  );\n}\n\nsub StartUnlatch {\n  my ($hash, $deviceId) = @_;\n\n  my $device = $hash->{helper}{devices}{$deviceId} || {};\n  my $state = $device->{state};\n  my $autoPull = $device->{autoPullSpringEnabled};\n\n  delete $hash->{helper}{unlatchPending}{$deviceId};\n\n  # An already unlocked lock only needs the pull operation.\n  if (defined($state) && $state == 2) {\n    return RequestUnlockMode($hash, $deviceId, 4);\n  }\n\n  # With Tedee auto-pull enabled, mode 4 performs unlock + pull in one\n  # operation when starting from locked/semi-locked.\n  if (defined($state) && ($state == 6 || $state == 3)\n      && defined($autoPull) && $autoPull) {\n    return RequestUnlockMode($hash, $deviceId, 4);\n  }\n\n  # Without auto-pull (or if its value is not known), first unlock explicitly\n  # without pulling. The follow-up mode 4 is sent only after the bridge has\n  # confirmed state=unlocked. This avoids sleeps and blind double commands.\n  if (defined($state) && ($state == 6 || $state == 3)) {\n    $hash->{helper}{unlatchPending}{$deviceId} = {\n      phase        => 'waiting_unlocked',\n      startedEpoch => time(),\n    };\n    return RequestUnlockMode($hash, $deviceId, 3);\n  }\n\n  # If the cached state is missing or transitional, refresh it first. The\n  # pending operation is evaluated by ProcessPendingUnlatch() afterwards.\n  $hash->{helper}{unlatchPending}{$deviceId} = {\n    phase        => 'need_decision',\n    startedEpoch => time(),\n  };\n\n  return Request($hash, 'GET', 'lock', undef, \\&ParseDevices, 'GET lock for unlatch');\n}\n\nsub ProcessPendingUnlatch {\n  my ($hash) = @_;\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH';\n\n  for my $deviceId (keys %{$pendingAll}) {\n    my $pending = $pendingAll->{$deviceId};\n    next if ref($pending) ne 'HASH';\n\n    # Never keep a command sequence alive indefinitely. A later user command\n    # must not accidentally complete an old unlatch request.\n    if (time() - ($pending->{startedEpoch} // 0) > 15) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, "unlatch sequence for device $deviceId timed out");\n      next;\n    }\n\n    my $device = $hash->{helper}{devices}{$deviceId} || {};\n    my $state = $device->{state};\n    my $autoPull = $device->{autoPullSpringEnabled};\n    next if !defined($state);\n\n    if (($pending->{phase} // '') eq 'need_decision') {\n      if ($state == 2) {\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n        next;\n      }\n\n      if ($state == 6 || $state == 3) {\n        if (defined($autoPull) && $autoPull) {\n          delete $pendingAll->{$deviceId};\n          RequestUnlockMode($hash, $deviceId, 4);\n        } else {\n          $pending->{phase} = 'waiting_unlocked';\n          RequestUnlockMode($hash, $deviceId, 3);\n        }\n        next;\n      }\n\n      # Transitional states are left pending and will be evaluated again on\n      # the next callback/status refresh.\n      next;\n    }\n\n    if (($pending->{phase} // '') eq 'waiting_unlocked') {\n      if ($state == 2) {\n        # Remove the pending marker before sending the final request so no\n        # callback can trigger a duplicate pull operation.\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n      } elsif ($state == 7 || $state == 8) {\n        # Defensive cleanup: the lock is already pulled/pulling.\n        delete $pendingAll->{$deviceId};\n      }\n    }\n  }\n\n  return undef;\n}\n\nsub Parse {''',
)

replace_once(
    bridge,
    "sub Request {\n  my ($hash, $method, $path, $body, $callback, $label) = @_;",
    "sub Request {\n  my ($hash, $method, $path, $body, $callback, $label, $extraHeaders) = @_;",
)
replace_once(
    bridge,
    "  push @$q, [$method, $path, $body, $callback, $label];",
    "  push @$q, [$method, $path, $body, $callback, $label, $extraHeaders];",
)
replace_once(
    bridge,
    "sub RequestNow {\n  my ($hash, $method, $path, $body, $callback, $label) = @_;",
    "sub RequestNow {\n  my ($hash, $method, $path, $body, $callback, $label, $extraHeaders) = @_;",
)
replace_once(
    bridge,
    '''  $headers .= "\\r\\nContent-Length: " . length($body) if defined($body);\n\n  Debug($hash, 4, "HTTP $method $url");''',
    '''  $headers .= "\\r\\nContent-Length: " . length($body) if defined($body);\n  $headers .= "\\r\\n$extraHeaders"\n    if defined($extraHeaders) && $extraHeaders ne '';\n\n  Debug($hash, 4, "HTTP $method $url");''',
)

replace_once(
    bridge,
    "  RememberDeviceIds( $hash, $items );\n\n  ::readingsBeginUpdate($hash);",
    "  RememberDeviceIds( $hash, $items );\n  ProcessPendingUnlatch($hash);\n\n  ::readingsBeginUpdate($hash);",
)

replace_once(
    bridge,
    '''    $hash->{helper}->{devices}->{$id} = {\n      type => $device->{type} // '',\n      name => $device->{name} // '',\n    };''',
    '''    $hash->{helper}->{devices}->{$id} = {\n      type  => $device->{type} // '',\n      name  => $device->{name} // '',\n      state => $device->{state},\n      pullSpringEnabled =>\n        ref($device->{deviceSettings}) eq 'HASH'\n          ? $device->{deviceSettings}{pullSpringEnabled}\n          : undef,\n      autoPullSpringEnabled =>\n        ref($device->{deviceSettings}) eq 'HASH'\n          ? $device->{deviceSettings}{autoPullSpringEnabled}\n          : undef,\n    };''',
)

replace_once(
    device,
    '''    if ( defined( $data->{isConnected} ) ) {\n        ::readingsBulkUpdate( $hash, 'isConnected', $data->{isConnected} );\n    }\n\n    if ( ::AttrVal( $name, 'debugReadings', 0 ) ) {''',
    '''    if ( defined( $data->{isConnected} ) ) {\n        ::readingsBulkUpdate( $hash, 'isConnected', $data->{isConnected} );\n    }\n\n    # These settings directly affect command semantics and therefore belong\n    # to the normal operational readings, not only to debug output.\n    if ( defined( $data->{deviceSettings} )\n        && ref( $data->{deviceSettings} ) eq 'HASH' )\n    {\n        ::readingsBulkUpdate(\n            $hash,\n            'pullSpringEnabled',\n            $data->{deviceSettings}{pullSpringEnabled}\n        ) if defined( $data->{deviceSettings}{pullSpringEnabled} );\n\n        ::readingsBulkUpdate(\n            $hash,\n            'autoPullSpringEnabled',\n            $data->{deviceSettings}{autoPullSpringEnabled}\n        ) if defined( $data->{deviceSettings}{autoPullSpringEnabled} );\n    }\n\n    if ( ::AttrVal( $name, 'debugReadings', 0 ) ) {''',
)

replace_once(
    wrapper,
    '<li><code>unlock</code><br>Unlocks the device. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>\n<li><code>unlatch</code><br>Pulls the spring / opens the latch. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>',
    '<li><code>unlock</code><br>Unlocks the lock without pulling the spring, regardless of the Tedee automatic pull-spring setting. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>\n<li><code>unlatch</code><br>Unlocks the lock if necessary and pulls the spring / opens the latch. If Tedee automatic pull-spring is enabled, the lock can perform both actions directly. Otherwise the module first unlocks without pulling and sends the pull operation after the unlocked state has been confirmed. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>',
)
replace_once(
    wrapper,
    '<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - battery level, charging state and derived state.</li>',
    '<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - battery level, charging state and derived state.</li>\n<li><code>pullSpringEnabled</code>, <code>autoPullSpringEnabled</code> - Tedee pull-spring configuration used by the command logic.</li>',
)
replace_once(
    wrapper,
    '<li><code>unlock</code><br>Entriegelt das Schloss. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>\n<li><code>unlatch</code><br>Zieht die Falle / öffnet die Tür. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>',
    '<li><code>unlock</code><br>Entriegelt das Schloss ohne die Türfalle zu ziehen, unabhängig von der Tedee-Einstellung für das automatische Einziehen der Türfalle. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>\n<li><code>unlatch</code><br>Entriegelt das Schloss bei Bedarf und zieht anschließend die Türfalle / öffnet die Tür. Ist das automatische Einziehen der Türfalle in Tedee aktiviert, kann das Schloss beide Aktionen direkt ausführen. Andernfalls entriegelt das Modul zunächst ohne Ziehen und führt die Pull-Aktion nach bestätigtem Status <code>unlocked</code> aus. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>',
)
replace_once(
    wrapper,
    '<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - Batteriestand, Ladestatus und abgeleiteter Batteriestatus.</li>',
    '<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - Batteriestand, Ladestatus und abgeleiteter Batteriestatus.</li>\n<li><code>pullSpringEnabled</code>, <code>autoPullSpringEnabled</code> - Tedee-Konfiguration der Türfallen-Funktion, die von der Befehlslogik berücksichtigt wird.</li>',
)
replace_once(
    wrapper,
    '<li><code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (local FHEM/Raspberry Pi time using FHEM::Utility::CTZ convertTimeZone with an explicit Tedee timestamp pattern; if CTZ is not available, the original UTC value is kept), <code>lastActionSummary</code> - optionale Cloud-Activity-Readings.</li>',
    '<li><code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (lokale FHEM/Raspberry-Pi-Zeit über <code>FHEM::Utility::CTZ</code>; falls CTZ nicht verfügbar ist, bleibt der ursprüngliche UTC-Wert erhalten), <code>lastActionSummary</code> - optionale Cloud-Activity-Readings.</li>',
)

print("v0.7.30 development changes applied successfully.")
