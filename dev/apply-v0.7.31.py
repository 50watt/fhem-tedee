#!/usr/bin/env python3
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / "lib/FHEM/Devices/Tedee/Bridge.pm"
DEVICE = ROOT / "lib/FHEM/Devices/Tedee/Device.pm"
WRAPPER = ROOT / "FHEM/74_TedeeDevice.pm"


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f"Patch anchor not found: {label}")
    return text.replace(old, new, 1)


def backup(path: Path) -> None:
    backup_path = path.with_name(path.name + ".bak-v0.7.30")
    if not backup_path.exists():
        shutil.copy2(path, backup_path)


for path in (BRIDGE, DEVICE, WRAPPER):
    backup(path)

bridge = BRIDGE.read_text()

bridge = replace_once(
    bridge,
    "our $VERSION = '0.7.30';",
    "our $VERSION = '0.7.31';",
    "Bridge version",
)

bridge = replace_once(
    bridge,
    "my $API_VERSION  = 'v1.0';\nmy $WEBHOOK_PATH = 'tedee';",
    "my $API_VERSION           = 'v1.0';\n"
    "my $WEBHOOK_PATH          = 'tedee';\n"
    "my $UNLATCH_TIMEOUT       = 15;\n"
    "my $UNLATCH_POLL_INTERVAL = 1.5;",
    "unlatch constants",
)

bridge = replace_once(
    bridge,
    """  if ($fn eq 'lock') {\n    return Request($hash, 'POST', \"lock/$deviceId/lock\", '{}', \\&ParseCommandResponse, \"POST lock/$deviceId/lock\");\n  }\n\n  if ($fn eq 'unlock') {\n    # Mode 3 explicitly suppresses automatic spring pulling. This keeps the\n    # FHEM command \"unlock\" deterministic even when Tedee auto-pull is enabled.\n    return RequestUnlockMode($hash, $deviceId, 3);\n  }\n""",
    """  if ($fn eq 'lock') {\n    # An explicit lock command supersedes a pending multi-step unlatch.\n    # Cancelling it prevents a delayed status update from pulling the spring\n    # after the user has already issued a different command.\n    CancelPendingUnlatch($hash, $deviceId, 'lock command');\n    return Request($hash, 'POST', \"lock/$deviceId/lock\", '{}', \\&ParseCommandResponse, \"POST lock/$deviceId/lock\");\n  }\n\n  if ($fn eq 'unlock') {\n    # An explicit unlock command also supersedes a pending unlatch sequence.\n    CancelPendingUnlatch($hash, $deviceId, 'unlock command');\n\n    # Mode 3 explicitly suppresses automatic spring pulling. This keeps the\n    # FHEM command \"unlock\" deterministic even when Tedee auto-pull is enabled.\n    return RequestUnlockMode($hash, $deviceId, 3);\n  }\n""",
    "explicit command cancellation",
)

bridge = replace_once(
    bridge,
    """sub StartUnlatch {\n""",
    """sub CancelPendingUnlatch {\n  my ($hash, $deviceId, $reason) = @_;\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH';\n  return undef if !exists($pendingAll->{$deviceId});\n\n  delete $pendingAll->{$deviceId};\n  Debug($hash, 4, \"unlatch sequence for device $deviceId cancelled: $reason\")\n    if defined($reason) && $reason ne '';\n\n  return undef;\n}\n\nsub StartUnlatch {\n""",
    "cancel helper",
)

old_process = """sub ProcessPendingUnlatch {\n  my ($hash) = @_;\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH';\n\n  for my $deviceId (keys %{$pendingAll}) {\n    my $pending = $pendingAll->{$deviceId};\n    next if ref($pending) ne 'HASH';\n\n    # Never keep a command sequence alive indefinitely. A later user command\n    # must not accidentally complete an old unlatch request.\n    if (time() - ($pending->{startedEpoch} // 0) > 15) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, \"unlatch sequence for device $deviceId timed out\");\n      next;\n    }\n\n    my $device = $hash->{helper}{devices}{$deviceId} || {};\n    my $state = $device->{state};\n    my $pullSpring = $device->{pullSpringEnabled};\n    my $autoPull = $device->{autoPullSpringEnabled};\n\n    # The setting may only become known after the status refresh that started\n    # the pending operation. Abort safely instead of sending a pull request.\n    if (defined($pullSpring) && !$pullSpring) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, \"unlatch rejected for device $deviceId: pull spring disabled\");\n      next;\n    }\n\n    next if !defined($state);\n\n    if (($pending->{phase} // '') eq 'need_decision') {\n      if ($state == 2) {\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n        next;\n      }\n\n      if ($state == 6 || $state == 3) {\n        if (defined($autoPull) && $autoPull) {\n          delete $pendingAll->{$deviceId};\n          RequestUnlockDefault($hash, $deviceId);\n        } else {\n          $pending->{phase} = 'waiting_unlocked';\n          RequestUnlockMode($hash, $deviceId, 3);\n        }\n        next;\n      }\n\n      # Transitional states are left pending and will be evaluated again on\n      # the next callback/status refresh.\n      next;\n    }\n\n    if (($pending->{phase} // '') eq 'waiting_unlocked') {\n      if ($state == 2) {\n        # Remove the pending marker before sending the final request so no\n        # callback can trigger a duplicate pull operation.\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n      } elsif ($state == 7 || $state == 8) {\n        # Defensive cleanup: the lock is already pulled/pulling.\n        delete $pendingAll->{$deviceId};\n      }\n    }\n  }\n\n  return undef;\n}\n"""

new_process = """sub ScheduleUnlatchStatusPoll {\n  my ($hash) = @_;\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH' || !keys %{$pendingAll};\n  return undef if $hash->{helper}{unlatchPollScheduled};\n\n  # Callbacks remain the preferred fast path. The timer is only a fallback for\n  # bridges that report a transitional state such as \"unlocking\" but do not\n  # send another callback when the final \"unlocked\" state is reached.\n  $hash->{helper}{unlatchPollScheduled} = 1;\n  ::InternalTimer(\n    gettimeofday() + $UNLATCH_POLL_INTERVAL,\n    __PACKAGE__ . '::PollPendingUnlatch',\n    $hash\n  );\n\n  return undef;\n}\n\nsub PollPendingUnlatch {\n  my ($hash) = @_;\n\n  delete $hash->{helper}{unlatchPollScheduled};\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH' || !keys %{$pendingAll};\n\n  # Expire stale sequences before issuing another bridge request. This keeps\n  # an old unlatch command from being completed by a much later status change.\n  my $now = time();\n  for my $deviceId (keys %{$pendingAll}) {\n    my $pending = $pendingAll->{$deviceId};\n    next if ref($pending) ne 'HASH';\n\n    if ($now - ($pending->{startedEpoch} // 0) > $UNLATCH_TIMEOUT) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, \"unlatch sequence for device $deviceId timed out\");\n    }\n  }\n\n  return undef if !keys %{$pendingAll};\n\n  # The central request queue continues to enforce Tedee's local API rate\n  # limit. One GET refreshes all locks, so multiple pending devices do not\n  # create additional per-lock requests.\n  return Request(\n    $hash,\n    'GET',\n    'lock',\n    undef,\n    \\&ParseDevices,\n    'GET lock for unlatch poll'\n  );\n}\n\nsub ProcessPendingUnlatch {\n  my ($hash) = @_;\n\n  my $pendingAll = $hash->{helper}{unlatchPending};\n  return undef if ref($pendingAll) ne 'HASH';\n\n  for my $deviceId (keys %{$pendingAll}) {\n    my $pending = $pendingAll->{$deviceId};\n    next if ref($pending) ne 'HASH';\n\n    # Never keep a command sequence alive indefinitely. A later user command\n    # must not accidentally complete an old unlatch request.\n    if (time() - ($pending->{startedEpoch} // 0) > $UNLATCH_TIMEOUT) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, \"unlatch sequence for device $deviceId timed out\");\n      next;\n    }\n\n    my $device = $hash->{helper}{devices}{$deviceId} || {};\n    my $state = $device->{state};\n    my $pullSpring = $device->{pullSpringEnabled};\n    my $autoPull = $device->{autoPullSpringEnabled};\n\n    # The setting may only become known after the status refresh that started\n    # the pending operation. Abort safely instead of sending a pull request.\n    if (defined($pullSpring) && !$pullSpring) {\n      delete $pendingAll->{$deviceId};\n      Debug($hash, 3, \"unlatch rejected for device $deviceId: pull spring disabled\");\n      next;\n    }\n\n    if (!defined($state)) {\n      ScheduleUnlatchStatusPoll($hash);\n      next;\n    }\n\n    if (($pending->{phase} // '') eq 'need_decision') {\n      if ($state == 2) {\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n        next;\n      }\n\n      if ($state == 6 || $state == 3) {\n        if (defined($autoPull) && $autoPull) {\n          delete $pendingAll->{$deviceId};\n          RequestUnlockDefault($hash, $deviceId);\n        } else {\n          $pending->{phase} = 'waiting_unlocked';\n          RequestUnlockMode($hash, $deviceId, 3);\n        }\n        next;\n      }\n\n      # Transitional states are actively re-polled. This avoids depending on a\n      # second callback that may never arrive after an \"unlocking\" update.\n      ScheduleUnlatchStatusPoll($hash);\n      next;\n    }\n\n    if (($pending->{phase} // '') eq 'waiting_unlocked') {\n      if ($state == 2) {\n        # Remove the pending marker before sending the final request so no\n        # callback or poll can trigger a duplicate pull operation.\n        delete $pendingAll->{$deviceId};\n        RequestUnlockMode($hash, $deviceId, 4);\n      } elsif ($state == 7 || $state == 8) {\n        # Defensive cleanup: the lock is already pulled/pulling.\n        delete $pendingAll->{$deviceId};\n      } else {\n        # Re-check the local bridge while the lock is still transitional. The\n        # request queue prevents the polling fallback from exceeding Tedee's\n        # documented request rate.\n        ScheduleUnlatchStatusPoll($hash);\n      }\n    }\n  }\n\n  return undef;\n}\n"""

bridge = replace_once(
    bridge,
    old_process,
    new_process,
    "ProcessPendingUnlatch",
)

BRIDGE.write_text(bridge)

device = DEVICE.read_text()
device = replace_once(
    device,
    "our $VERSION = '0.7.30';",
    "our $VERSION = '0.7.31';",
    "Device version",
)
DEVICE.write_text(device)

wrapper = WRAPPER.read_text()
wrapper = replace_once(
    wrapper,
    '"version": "v0.7.30"',
    '"version": "v0.7.31"',
    "wrapper metadata version",
)
WRAPPER.write_text(wrapper)

print("Applied Tedee v0.7.31 development patch.")
print("Changed:")
print(f"  {BRIDGE.relative_to(ROOT)}")
print(f"  {DEVICE.relative_to(ROOT)}")
print(f"  {WRAPPER.relative_to(ROOT)}")
print("Backups use suffix .bak-v0.7.30 and are not intended for commit.")
