# Inspired by the Nuki module from CoolTux
# This module interacts with door locks.
# The user is responsible for ensuring safe operation.
# The authors take no responsibility for misuse or security issues.
#
# Copyright:
#   Copyright (C) 2026 50watt
#
# License:
#   This module is released under the same terms as FHEM.
#
# Disclaimer:
#   This module can control door locks. Use it at your own risk.
#   The author and contributors are not responsible for any damage,
#   security issue, lockout, unauthorized access, or other consequences
#   caused by installation, configuration, automation rules, network
#   exposure, credentials handling, or use of this module.
#   You are personally responsible for a secure FHEM installation,
#   secure storage of tokens, network access control, and for deciding
#   whether remote unlock/unlatch commands are enabled.
###############################################################################
# lib/FHEM/Devices/Tedee/Device.pm
# Tedee Device core - Reference-style device layer
###############################################################################

package FHEM::Devices::Tedee::Device;

use strict;
use warnings;
use Encode qw(encode is_utf8);
use FHEM::Meta;
use GPUtils qw(GP_Import);

our $Tedee_CTZ_Absent;
BEGIN {
    eval {
        require FHEM::Utility::CTZ;
        FHEM::Utility::CTZ->import(qw(convertTimeZone reqModFail));
        1;
    } or $Tedee_CTZ_Absent = 1;
}


BEGIN {
    GP_Import(qw(init_done defs modules));
}

# try to use JSON::MaybeXS wrapper
#   for chance of better performance + open code
eval {
    require JSON::MaybeXS;
    import JSON::MaybeXS qw(decode_json encode_json);
    1;
} or do {
    eval {
        local $ENV{PERL_JSON_BACKEND} =
          'Cpanel::JSON::XS,JSON::XS,JSON::PP,JSON::backportPP'
          unless (defined($ENV{PERL_JSON_BACKEND}));

        require JSON;
        import JSON qw(decode_json encode_json);
        1;
    } or do {
        eval {
            require Cpanel::JSON::XS;
            import Cpanel::JSON::XS qw(decode_json encode_json);
            1;
        } or do {
            eval {
                require JSON::XS;
                import JSON::XS qw(decode_json encode_json);
                1;
            } or do {
                eval {
                    require JSON::PP;
                    import JSON::PP qw(decode_json encode_json);
                    1;
                } or do {
                    require JSON::backportPP;
                    import JSON::backportPP qw(decode_json encode_json);
                    1;
                };
            };
        };
    };
};

our $VERSION = '0.7.30';

######## Begin Device


# --- Tedee device mappings ----------------------------------------------------

my %deviceTypes = (
    1  => 'bridge',
    2  => 'lock_pro',
    3  => 'keypad',
    4  => 'lock_go',
    5  => 'gate',
    6  => 'dry_contact',
    8  => 'door_sensor',
    10 => 'keypad_pro',
);

my %lockStates = (
    0  => 'uncalibrated',
    1  => 'calibrating',
    2  => 'unlocked',
    3  => 'semi_locked',
    4  => 'unlocking',
    5  => 'locking',
    6  => 'locked',
    7  => 'pulled',
    8  => 'pulling',
    9  => 'unknown',
    18 => 'updating',
);

my %doorStates = (
    0 => 'not_paired',
    1 => 'closed',
    2 => 'opened',
    3 => 'unknown',
    4 => 'calibrating',
);

my %eventTypes = (
    32    => 'LockedRemote',
    33    => 'UnlockedRemote',
    34    => 'LockedButton',
    35    => 'UnlockedButton',
    36    => 'LockedAuto',
    37    => 'UnlockedAuto',
    38    => 'LockedManual',
    39    => 'UnlockedManual',
    40    => 'Jammed',
    41    => 'PowerOff',
    42    => 'PowerOn',
    43    => 'Calibration',
    46    => 'BatteryCharging',
    47    => 'PartiallyOpenManual',
    48    => 'PartiallyOpenButton',
    49    => 'PartiallyOpenAuto',
    50    => 'BatteryStopCharging',
    51    => 'PulledRemote',
    52    => 'PulledAuto',
    53    => 'PulledManual',
    54    => 'PartiallyOpenRemote',
    55    => 'PulledAutoByRemote',
    56    => 'PostponedLock',
    57    => 'UnlockedHomeKit',
    58    => 'PartiallyOpenHomeKit',
    59    => 'LockedHomeKit',
    60    => 'PulledHomeKit',
    61    => 'UnlockByPin',
    62    => 'IncorrectPin',
    63    => 'PullSpringByPin',
    64    => 'PartiallyOpenByPin',
    65    => 'LockedByKeypadWithPin',
    66    => 'LockedByKeypadWithoutPin',
    67    => 'LockForceUnlocked',
    68    => 'LockForceUnlockedByPin',
    74    => 'LockUncalibrated',
    75    => 'UnauthorizedPin',
    76    => 'PulledAutoByPin',
    77    => 'UnlockedByFingerprint',
    78    => 'ForceUnlockedByFingerprint',
    79    => 'PartiallyOpenByFingerprint',
    80    => 'PulledByFingerprint',
    81    => 'PulledAutoByFingerprint',
    83    => 'DoorOpened',
    84    => 'DoorClosed',
    85    => 'DoorSensorUncalibrated',
    86    => 'DoorOpenTooLong',
    87    => 'LockPulledByAutoUnlock',
    88    => 'LockUnlockedByMatter',
    89    => 'LockPartiallyOpenByMatter',
    90    => 'LockLockedByMatter',
    91    => 'LockPullSpringByMatter',
    92    => 'LockPullSpringAutoByMatter',
    93    => 'LockForceUnlockedByMatter',
    224   => 'FirmwareUpdateByBridge',
    225   => 'FirmwareUpdateByMobile',
    226   => 'LockedByAccessLink',
    227   => 'LockedByBridgeApi',
    228   => 'UnlockedByAccessLink',
    229   => 'UnlockedByBridgeApi',
    230   => 'PulledByAccessLink',
    231   => 'PulledByBridgeApi',
    232   => 'PartiallyOpenByAccessLink',
    233   => 'PartiallyOpenByBridgeApi',
    234   => 'PulledAutoByAccessLink',
    235   => 'PulledAutoByBridgeApi',
    10000 => 'GateUnlockedByRemote',
    10001 => 'GateUnlockedByAccessLink',
);

my %activitySources = (
    0 => 'Device',
    1 => 'Mobile',
    2 => 'Portal',
    3 => 'BridgeApi',
    4 => 'CloudApi',
    5 => 'AutoUnlock',
);

sub DeviceType {
    my $code = shift;
    return '' if !defined($code) || $code eq '';
    return $deviceTypes{$code} // "unknown_$code";
}

sub LockState {
    my $code = shift;
    return '' if !defined($code) || $code eq '';
    return $lockStates{$code} // "unknown_$code";
}

sub DoorState {
    my $code = shift;
    return '' if !defined($code) || $code eq '';
    return $doorStates{$code} // "unknown_$code";
}

sub EventText {
    my $code = shift;
    return '' if !defined($code) || $code eq '';
    return $eventTypes{$code} // "unknown_$code";
}

sub SourceText {
    my $code = shift;
    return '' if !defined($code) || $code eq '';
    return $activitySources{$code} // "unknown_$code";
}

sub Define {
    my $hash = shift;
    my $def  = shift // return;

    return $@ unless (FHEM::Meta::SetInternals($hash));
    my $version = FHEM::Meta::Get($hash, 'version') || $VERSION;
    our $VERSION = $version;

    my ($name, undef, $deviceId, $iodev, $deviceType) = split(m{\s+}xms, $def);
    return 'too few parameters: define <name> TedeeDevice <deviceId> <IODev> [deviceType]'
      if (!defined($name) || !defined($deviceId) || !defined($iodev));

    $deviceType //= 2;

    $hash->{DEVICEID}       = $deviceId;
    $hash->{LOCKID}         = $deviceId if ($deviceType == 2 || $deviceType == 4);
    $hash->{DEVICETYPEID}   = $deviceType;
    $hash->{BRIDGE}         = $iodev;
    $hash->{MODULE_VERSION} = $VERSION;
    $hash->{STATE}          = 'Initialized';
    $hash->{NOTIFYDEV}      = 'global,autocreate,' . $name;

    ::CommandAttr(undef, "$name IODev $iodev")
      if (!::AttrVal($name, 'IODev', ''));

    ::AssignIoPort($hash, $iodev) if (!$hash->{IODev});

    ::CommandAttr(undef, "$name room Tedee")
      if (::AttrVal($name, 'room', 'none') eq 'none');

    ::CommandAttr(undef, "$name model " . ($deviceTypes{$deviceType} // "unknown_$deviceType"))
      if (::AttrVal($name, 'model', 'none') eq 'none');

    if ($deviceType == 2 || $deviceType == 4) {
        ::CommandAttr(undef, "$name icon smartlock_locked")
          if (!::AttrVal($name, 'icon', ''));
        ::CommandAttr(undef, "$name webCmd lock:statusRequest:unlock:unlatch")
          if (!::AttrVal($name, 'webCmd', ''));
        ::CommandAttr(undef, "$name devStateIcon locked:smartlock_locked\@green unlocked:smartlock_unlocked\@red semi_locked:smartlock_unlocked\@orange unlocking:smartlock_unlocked\@orange locking:smartlock_locked\@orange pulled:smartlock_unlocked\@orange pulling:smartlock_unlocked\@orange uncalibrated:it_unknown\@gray calibrating:refresh\@orange updating:refresh\@orange unknown:it_unknown\@gray disconnected:message_attention\@red .*:it_unknown\@gray")
          if (!::AttrVal($name, 'devStateIcon', ''));
    }

    $main::modules{TedeeDevice}{defptr}{$deviceId} = $hash;

    ::readingsSingleUpdate($hash, 'state', 'defined', 1);

    return;
}

sub Undef {
    my $hash = shift;
    delete($main::modules{TedeeDevice}{defptr}{ $hash->{DEVICEID} })
      if (defined $hash->{DEVICEID});
    return;
}

sub Attr { return; }

sub Notify {
    my $hash = shift;
    my $dev  = shift // return;

    return if (::IsDisabled($hash->{NAME}));

    my $events = ::deviceEvents($dev, 1);
    return if (!$events);

    if ($dev->{NAME} eq 'global') {
        foreach my $event (@{$events}) {
            next if ($event !~ /^RENAMED\s+(\S+)\s+(\S+)$/x);

            my $oldName = $1;
            my $newName = $2;

            next
              if ($hash->{NAME} ne $oldName
              && $hash->{NAME} ne $newName);

            # Keep FHEM notify internals consistent after a user rename.
            # Depending on FHEM's rename processing order, NAME may still
            # contain the old name or may already contain the new name here.
            $hash->{NOTIFYDEV} = 'global,autocreate,' . $newName;
            $hash->{NTFY_ORDER} = '50-' . $newName;

            last;
        }
    }

    GetUpdate($hash)
      if (
        (
             grep { /^INITIALIZED$/x } @{$events}
          or grep { /^REREADCFG$/x } @{$events}
          or grep { /^DEFINED.$hash->{NAME}$/x } @{$events}
          or grep { /^MODIFIED.$hash->{NAME}$/x } @{$events}
        )
        && $dev->{NAME} eq 'global'
        && $main::init_done
      );

    return;
}

sub RequestCloudActivityIfAvailable {
    my $hash  = shift;
    my $iodev = $hash->{IODev};

    return if ( !defined($iodev) );
    return if ( !defined( $iodev->{NAME} ) );

    my $deviceId = $hash->{DEVICEID} // $hash->{LOCKID};
    return if ( !defined($deviceId) );

    my $bridgeName = $iodev->{NAME};
    return if ( ::ReadingsVal( $bridgeName, 'cloudTokenStored', 0 ) != 1 );

    ::CommandSet( undef, $bridgeName . ' refreshActivity ' . $deviceId );

    return;
}

sub UnlockDisabledText {
    my $hash = shift;
    my $name = $hash->{NAME};

    my $lang = lc( ::AttrVal( 'global', 'language', 'EN' ) // 'en' );

    if ( $lang =~ m/^de/ ) {
        return
            "unlock/unlatch ist deaktiviert.\n\n"
          . "Zum Aktivieren für dieses Schloss:\n"
          . "attr $name allowUnlock 1\n\n";
    }

    return
        "unlock/unlatch is disabled.\n\n"
      . "Enable it for this lock:\n"
      . "attr $name allowUnlock 1\n\n";
}

sub Set {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "set $name needs at least one argument !";

    $cmd = 'statusRequest' if ($cmd eq 'status' || $cmd eq 'sync');

    if ($cmd eq 'statusRequest') {
        GetUpdate($hash);
        return;
    }

    if ($cmd eq 'lock' || $cmd eq 'unlock' || $cmd eq 'unlatch') {
        return UnlockOrUnlatch($hash, $cmd)
          if ($cmd eq 'unlock' || $cmd eq 'unlatch');
        return Write($hash, $cmd);
    }

    my $list = 'statusRequest:noArg';
    $list .= ' lock:noArg unlock:noArg unlatch:noArg'
      if ($hash->{DEVICETYPEID} == 2 || $hash->{DEVICETYPEID} == 4);

    return 'Unknown argument ' . $cmd . ', choose one of ' . $list;
}

sub Get {
    my $hash = shift;
    my $name = shift;
    my $cmd  = shift // return "get $name needs at least one argument !";

    return 'Unknown argument ' . $cmd . ', choose one of status:noArg'
      if ($cmd ne 'status');

    return GetUpdate($hash);
}

sub UnlockOrUnlatch {
    my ($hash, $fn) = @_;
    my $name = $hash->{NAME};

    my $bridge = $hash->{IODev} ? $hash->{IODev}->{NAME} : $hash->{BRIDGE};
    my $allow = ::AttrVal($name, 'allowUnlock', 0);
    return UnlockDisabledText($hash)
      if (!$allow);

    return Write($hash, $fn);
}

sub GetUpdate {
    my $hash = shift;
    return if (::IsDisabled($hash->{NAME}));
    my $ret = Write($hash, 'statusRequest');
    RequestCloudActivityIfAvailable($hash);

    return $ret;
}

# The device uses IOWrite; all HTTP communication is handled by the bridge.
sub Write {
    my ($hash, $fn) = @_;

    my $iodev = $hash->{IODev};
    if (!$iodev && $hash->{BRIDGE} && defined($main::defs{ $hash->{BRIDGE} })) {
        $iodev = $main::defs{ $hash->{BRIDGE} };
        $hash->{IODev} = $iodev;
    }

    return 'No IODev assigned' if (!$iodev);

    my $payload = encode_json({
        deviceId   => $hash->{DEVICEID},
        deviceType => $hash->{DEVICETYPEID},
    });

    return ::IOWrite($hash, $fn, $payload);
}



sub WriteActivityReadings {
    my $hash     = shift;
    my $activity = shift;
    my $name     = $hash->{NAME};

    my $event  = EventText( $activity->{event} );
    my $source = SourceText( $activity->{source} );
    my $user   = $activity->{username} // '-';
    my $date   = $activity->{date}     // '';

    $user = Encode::encode( 'UTF-8', $user ) if Encode::is_utf8($user);

    ::readingsBulkUpdate( $hash, 'lastAction',       $event );
    ::readingsBulkUpdate( $hash, 'lastActionUser',   $user );
    ::readingsBulkUpdate( $hash, 'lastActionSource', $source );
    my $localDate = TedeeCloudDateToLocal($date);

    ::readingsBulkUpdate( $hash, 'lastActionDate',   $localDate );
    ::readingsBulkUpdate( $hash, 'lastActionSummary',
        $event . ' by ' . $user . ' via ' . $source . ' at ' . $localDate );

    if ( ::AttrVal( $name, 'debugReadings', 0 ) ) {
        ::readingsBulkUpdate( $hash, 'lastActionDateUTC', $date )
          if defined($date);
        ::readingsBulkUpdate( $hash, 'lastActionCode', $activity->{event} )
          if defined( $activity->{event} );
        ::readingsBulkUpdate( $hash, 'lastActionSourceCode', $activity->{source} )
          if defined( $activity->{source} );
        ::readingsBulkUpdate( $hash, 'lastActionId', $activity->{id} )
          if defined( $activity->{id} );
        ::readingsBulkUpdate( $hash, 'activityRefreshAttempt', $activity->{_activityRefreshAttempt} )
          if defined( $activity->{_activityRefreshAttempt} );
        ::readingsBulkUpdate( $hash, 'activityRefreshDelay', $activity->{_activityRefreshDelay} )
          if defined( $activity->{_activityRefreshDelay} );
        ::readingsBulkUpdate( $hash, 'activityRefreshPlanned', $activity->{_activityRefreshPlanned} )
          if defined( $activity->{_activityRefreshPlanned} );
        ::readingsBulkUpdate( $hash, 'activityPendingSince', $activity->{_activityPendingSince} )
          if defined( $activity->{_activityPendingSince} );
        ::readingsBulkUpdate( $hash, 'activityLagSeconds', $activity->{_activityLagSeconds} )
          if defined( $activity->{_activityLagSeconds} );
        ::readingsBulkUpdate( $hash, 'activityIsNew', $activity->{_activityIsNew} )
          if defined( $activity->{_activityIsNew} );

    }

    return;
}


sub DebugReadingUpdate {
    my ($hash, $reading, $value) = @_;
    return if (!::AttrVal($hash->{NAME}, 'debugReadings', 0));
    ::readingsBulkUpdate($hash, $reading, defined($value) ? $value : '');
}

sub Clean {
    my ($txt) = @_;
    return '' if (!defined($txt));
    $txt =~ s/[\r\n]+/ /g;
    $txt =~ s/^\s+|\s+$//g;
    return is_utf8($txt) ? encode('UTF-8', $txt) : $txt;
}


sub Parse {
    my $hash = shift;
    my $json = shift // return;
    my $name = $hash->{NAME};

    ::Log3( $name, 5, "TedeeDevice ($name) - Parse with result: $json" );

    if ( $json !~ m{\A[\[{].*[}\]]\z}xms ) {
        ::Log3( $name, 3, "TedeeDevice ($name) - invalid json detected: $json" );
        return "TedeeDevice ($name) - invalid json detected: $json";
    }

    my $decode_json = eval { decode_json($json) };
    if ($@) {
        ::Log3( $name, 3, "TedeeDevice ($name) - JSON error while request: $@" );
        return;
    }

    ::Log3( $name, 5, "TedeeDevice ($name) - TEDDEE RAW: $json" );

    if ( ref($decode_json) ne 'HASH' ) {
        ::Log3( $name, 2, "TedeeDevice ($name) - got wrong status message" );
        return;
    }

    my $deviceId =
         $decode_json->{deviceId}
      // $decode_json->{tedeeId}
      // $decode_json->{id};

    return if ( !defined($deviceId) );

    if ( my $dhash = $main::modules{TedeeDevice}{defptr}{$deviceId} ) {
        my $dname = $dhash->{NAME};

        WriteReadings( $dhash, $decode_json );
        ::Log3( $dname, 4,
            "TedeeDevice ($dname) - find logical device: $dhash->{NAME}" );

        return $dhash->{NAME};
    }
    else {
        my $deviceName = ::makeDeviceName( $decode_json->{name} // 'tedee.device.' . $deviceId );
        my $deviceType = $decode_json->{type} // 2;

        ::Log3( $name, 4,
                "TedeeDevice ($name) - autocreate new device "
              . $deviceName
              . " with tedeeId $deviceId, model $deviceType" );

        return
            'UNDEFINED '
          . $deviceName
          . " TedeeDevice $deviceId "
          . $hash->{NAME} . ' '
          . $deviceType;
    }

    return;
}


sub TedeeCloudDateToLocal {
    my $date = shift;

    return $date if ( !defined($date) || $date eq '' || $date eq '-' );

    return $date if ($Tedee_CTZ_Absent);

    # Tedee Cloud timestamps are UTC and usually look like:
    # 2026-05-04T16:13:58.249 or 2026-05-04T16:13:58.249Z
    # Let CTZ parse the original string via pattern instead of normalizing it.
    my $params = {
        name      => 'TedeeDevice',
        pattern   => '%Y-%m-%dT%H:%M:%S',
        dtstring  => $date,
        tzcurrent => 'UTC',
        tzconv    => 'local',
        writelog  => 0,
    };

    my ( $err, $converted ) = convertTimeZone($params);

    return ( !$err && defined($converted) && $converted ne '' )
      ? $converted
      : $date;
}




sub WriteReadings {
    my $hash = shift;
    my $data = shift // return;
    my $name = $hash->{NAME};

    ::readingsBeginUpdate($hash);

    if ( defined( $data->{success} ) ) {
        my $commandOk =
          ( $data->{success} eq 'true' || $data->{success} == 1 )
          ? 'true'
          : 'false';

        if ( defined( $hash->{helper}{lockAction} ) ) {
            ::readingsBulkUpdate( $hash, 'state',
                $commandOk eq 'true'
                ? $hash->{helper}{lockAction}
                : 'response error' );
            delete $hash->{helper}{lockAction};
        }
    }

    if ( defined( $data->{tedeeMessageType} )
        && $data->{tedeeMessageType} eq 'activity' )
    {
        WriteActivityReadings( $hash, $data );
        ::readingsEndUpdate( $hash, 1 );
        return;
    }

    if ( defined( $data->{activity} )
        && ref( $data->{activity} ) eq 'HASH' )
    {
        WriteActivityReadings( $hash, $data->{activity} );
        ::readingsEndUpdate( $hash, 1 );
        return;
    }

    my $deviceId =
         $data->{id}
      // $data->{deviceId}
      // $data->{tedeeId}
      // $hash->{DEVICEID}
      // $hash->{LOCKID};

    my $type = $data->{type} // $hash->{DEVICETYPEID};

    ::readingsBulkUpdate( $hash, 'tedeeId', $deviceId )
      if defined($deviceId);
    ::readingsBulkUpdate( $hash, 'deviceType', DeviceType($type) )
      if defined($type);

    ::readingsBulkUpdate( $hash, 'name',
        Encode::is_utf8( $data->{name} )
        ? Encode::encode( 'UTF-8', $data->{name} )
        : $data->{name} )
      if defined( $data->{name} );

    ::readingsBulkUpdate( $hash, 'serialNumber', $data->{serialNumber} )
      if defined( $data->{serialNumber} );
    ::readingsBulkUpdate( $hash, 'firmwareVersion', $data->{version} )
      if defined( $data->{version} );
    ::readingsBulkUpdate( $hash, 'rssi', $data->{rssi} )
      if defined( $data->{rssi} );
    ::readingsBulkUpdate( $hash, 'paired', 'true' );

    if ( defined( $data->{state} ) ) {
        my $stateText = LockState( $data->{state} );
        ::readingsBulkUpdate( $hash, 'lockStateCode', $data->{state} );
        ::readingsBulkUpdate( $hash, 'lockState', $stateText );
        ::readingsBulkUpdate( $hash, 'state', $stateText );
    }

    if ( defined( $data->{doorState} ) ) {
        ::readingsBulkUpdate( $hash, 'doorStateCode', $data->{doorState} );
        ::readingsBulkUpdate( $hash, 'doorState', DoorState( $data->{doorState} ) );
    }

    if ( defined( $data->{batteryLevel} ) ) {
        ::readingsBulkUpdate( $hash, 'batteryPercent', $data->{batteryLevel} );
        ::readingsBulkUpdate( $hash, 'batteryState',
            $data->{batteryLevel} <= 20 ? 'low' : 'ok' );
    }

    if ( defined( $data->{isCharging} ) ) {
        ::readingsBulkUpdate( $hash, 'batteryCharging',
            $data->{isCharging} ? 'true' : 'false' );
    }

    if ( defined( $data->{isConnected} ) ) {
        ::readingsBulkUpdate( $hash, 'isConnected', $data->{isConnected} );
    }

    # These settings directly affect command semantics and therefore belong
    # to the normal operational readings, not only to debug output.
    if ( defined( $data->{deviceSettings} )
        && ref( $data->{deviceSettings} ) eq 'HASH' )
    {
        ::readingsBulkUpdate(
            $hash,
            'pullSpringEnabled',
            $data->{deviceSettings}{pullSpringEnabled}
        ) if defined( $data->{deviceSettings}{pullSpringEnabled} );

        ::readingsBulkUpdate(
            $hash,
            'autoPullSpringEnabled',
            $data->{deviceSettings}{autoPullSpringEnabled}
        ) if defined( $data->{deviceSettings}{autoPullSpringEnabled} );
    }

    if ( ::AttrVal( $name, 'debugReadings', 0 ) ) {
        ::readingsBulkUpdate( $hash, 'raw_type', $data->{type} )
          if defined( $data->{type} );
        ::readingsBulkUpdate( $hash, 'raw_state', $data->{state} )
          if defined( $data->{state} );
        ::readingsBulkUpdate( $hash, 'raw_doorState', $data->{doorState} )
          if defined( $data->{doorState} );
        ::readingsBulkUpdate( $hash, 'deviceRevision', $data->{deviceRevision} )
          if defined( $data->{deviceRevision} );
        ::readingsBulkUpdate( $hash, 'jammed', $data->{jammed} )
          if defined( $data->{jammed} );
        if ( defined( $data->{deviceSettings} )
            && ref( $data->{deviceSettings} ) eq 'HASH' )
        {
            for my $k ( sort keys %{ $data->{deviceSettings} } ) {
                next if ref( $data->{deviceSettings}{$k} );
                ::readingsBulkUpdate( $hash, 'deviceSettings_' . $k,
                    $data->{deviceSettings}{$k} );
            }
        }
    }

    ::readingsEndUpdate( $hash, 1 );
    ::Log3( $name, 5, "TedeeDevice ($name) - readings updated" );
    return;
}

1;
