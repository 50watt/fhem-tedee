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
# lib/FHEM/Devices/Tedee/Bridge.pm
# Tedee Bridge implementation
###############################################################################

package FHEM::Devices::Tedee::Bridge;

use strict;
use warnings;
use GPUtils qw(GP_Import);
use Digest::SHA qw(sha256_hex);
use Time::HiRes qw(gettimeofday);
use Encode qw(encode is_utf8);
use FHEM::Devices::Tedee::Device;

BEGIN {
  GP_Import(qw(defs attr data));
}

our $VERSION = '0.7.29';

my $API_VERSION  = 'v1.0';
my $WEBHOOK_PATH = 'tedee';

my ($json_encode, $json_decode);

BEGIN {
  eval {
    require JSON::MaybeXS;
    $json_encode = \&JSON::MaybeXS::encode_json;
    $json_decode = \&JSON::MaybeXS::decode_json;
    1;
  } or eval {
    require JSON;
    $json_encode = \&JSON::encode_json;
    $json_decode = \&JSON::decode_json;
    1;
  } or eval {
    require JSON::PP;
    $json_encode = \&JSON::PP::encode_json;
    $json_decode = \&JSON::PP::decode_json;
    1;
  };
}

sub Define {
  my ($hash, $def) = @_;
  my @a = split(/\s+/, $def);

  return 'Usage: define <name> TedeeBridge <host> [port]' if @a < 3;

  my $name = $a[0];

  $hash->{HOST}           = $a[2];
  $hash->{PORT}           = $a[3] // 80;
  $hash->{API_VERSION}    = $API_VERSION;
  $hash->{MODULE_VERSION} = $VERSION;
  $hash->{WEBHOOK_PATH}   = $WEBHOOK_PATH;

  ::CommandAttr(undef, "$name room Tedee") if !::AttrVal($name, 'room', '');
  ::CommandAttr(undef, "$name icon mqtt_bridge_1") if !::AttrVal($name, 'icon', '');
  ::CommandAttr(undef, "$name devStateIcon connected:10px-kreis-gruen:info disconnected:10px-kreis-rot:info error:10px-kreis-rot:info initialized:10px-kreis-gelb:info disabled:10px-kreis-gelb:info .*:10px-kreis-gelb:info") if !::AttrVal($name, 'devStateIcon', '');
  ::CommandAttr(undef, "$name tokenMode encrypted") if !::AttrVal($name, 'tokenMode', '');

  if (!::AttrVal($name, 'webhookFWinstance', '') && defined($main::defs{WEB}) && (($main::defs{WEB}{TYPE} // '') eq 'FHEMWEB')) {
    ::CommandAttr(undef, "$name webhookFWinstance WEB");
  }

  AddExtension($hash);

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'tokenStored', TokenExists($hash) ? 1 : 0);
  ::readingsBulkUpdate($hash, 'cloudTokenStored', CloudTokenExists($hash) ? 1 : 0);
  ::readingsBulkUpdate($hash, 'state', 'initialized');
  ::readingsBulkUpdate($hash, 'setupState', TokenExists($hash) ? '2/6 local bridge token stored' : '1/6 waiting for local bridge token');
  ::readingsBulkUpdate($hash, 'setupNext', TokenExists($hash) ? "set $name info" : "Open Tedee app, enable Bridge API, then: set $name token <LOCAL_BRIDGE_TOKEN>");
  ::readingsEndUpdate($hash, 1);

  CheckBridgeIdentity($hash);

  if ( TokenExists($hash) ) {
    ::InternalTimer(
      ::gettimeofday() + 1,
      \&FHEM::Devices::Tedee::Bridge::AutoSetup,
      $hash
    );
  }

  return undef;
}


sub CheckBridgeIdentity {
  my ($hash) = @_;

  my $url = "http://$hash->{HOST}:$hash->{PORT}/";

  ::HttpUtils_NonblockingGet({
    url      => $url,
    method   => 'GET',
    timeout  => 5,
    hash     => $hash,
    callback => sub {
      my ($param, $err, $data) = @_;
      my $h = $param->{hash};

      if ($err) {
        ::readingsBeginUpdate($h);
        ::readingsBulkUpdate($h, 'bridgeDetected', 0);
        ::readingsBulkUpdate($h, 'bridgeDetection', 'no response');
        ::readingsBulkUpdate($h, 'state', 'no bridge');
        ::readingsBulkUpdate($h, 'setupState', '0/6 no Tedee Bridge detected');
        ::readingsBulkUpdate($h, 'setupNext', 'Check HOST/IP or define TedeeBridge with the correct bridge IP');
        ::readingsEndUpdate($h, 1);
        return;
      }

      my $isTedee = (defined($data) && $data =~ /storage-bridge\.tedee\.com\/local-api/);

      ::readingsBeginUpdate($h);
      ::readingsBulkUpdate($h, 'bridgeDetected', $isTedee ? 1 : 0);
      ::readingsBulkUpdate($h, 'bridgeDetection', $isTedee ? 'tedee local api ui' : 'unknown device');

      if ($isTedee) {
        ::readingsBulkUpdate($h, 'state', 'initialized');
        ::readingsBulkUpdate($h, 'setupState', TokenExists($h) ? '2/6 local bridge token stored' : '1/6 waiting for local bridge token');
        ::readingsBulkUpdate($h, 'setupNext', TokenExists($h) ? "set $h->{NAME} info" : "Open Tedee app, enable Bridge API, then: set $h->{NAME} token <LOCAL_BRIDGE_TOKEN>");
      } else {
        ::readingsBulkUpdate($h, 'state', 'no bridge');
        ::readingsBulkUpdate($h, 'setupState', '0/6 no Tedee Bridge detected');
        ::readingsBulkUpdate($h, 'setupNext', 'Check HOST/IP or define TedeeBridge with the correct bridge IP');
      }

      ::readingsEndUpdate($h, 1);
    },
  });

  return undef;
}


sub Undef {
  my ($hash, $arg) = @_;
  RemoveExtension($hash);
  ::RemoveInternalTimer($hash);

  # Development/no-backward-compat behavior: deleting the bridge also deletes
  # locally stored bridge and cloud tokens.
  ::setKeyValue($hash->{NAME} . '_token', undef);
  ::setKeyValue($hash->{NAME} . '_cloudToken', undef);

  return undef;
}

sub Attr {
  my ($cmd, $name, $attrName, $attrVal) = @_;
  return undef if !defined($main::defs{$name});

  my $hash = $main::defs{$name};

  if ($attrName eq 'webhookFWinstance' || $attrName eq 'webhookHttpHostname') {
    RemoveExtension($hash);
    ::InternalTimer(gettimeofday() + 1, __PACKAGE__ . '::ReaddExtension', $hash);
  }

  return undef;
}

sub Set {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd  = shift @a // '';

  $cmd = 'info'           if $cmd eq 'bridge';
  $cmd = 'getDeviceList'  if $cmd eq 'scan' || $cmd eq 'autocreate';
  $cmd = 'callbackRemove' if $cmd eq 'deleteCallbacks';

  my %dispatch = (
    token            => sub { return SetToken($hash, @a) },
    deleteToken      => sub { return DeleteToken($hash) },
    cloudToken       => sub { return SetCloudToken($hash, @a) },
    deleteCloudToken => sub { return DeleteCloudToken($hash) },
    refreshActivity  => sub { return RefreshActivity($hash, @a) },
    info             => sub { return Request($hash, 'GET', 'bridge', undef, \&ParseBridge, 'GET bridge') },
    getDeviceList    => sub { return Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock') },
    resetCallback    => sub { return ResetCallback($hash) },
    callbackRemove   => sub { return DeleteCallbacks($hash) },
  );

  return 'Unknown argument ' . $cmd . ', choose one of '
    . 'token cloudToken deleteToken:noArg deleteCloudToken:noArg '
    . 'info:noArg getDeviceList:noArg resetCallback:noArg callbackRemove:noArg refreshActivity'
    if !exists($dispatch{$cmd});

  return $dispatch{$cmd}->();
}


sub BuildLocalRequest {
  my ($hash, $method, $path, $body) = @_;

  my $name = $hash->{NAME};
  my $url = "http://$hash->{HOST}:$hash->{PORT}/$API_VERSION/$path";
  my $token = TokenHeader($hash, $method, $path, $body);
  my $mode = ::AttrVal($name, 'tokenMode', 'encrypted');

  my $headers = "accept: application/json";
  if ($mode eq 'plain') {
    $headers .= "\r\napi_token: $token";
  } else {
    my $sep = ($url =~ /\?/) ? '&' : '?';
    $url .= $sep . "api_token=$token";
  }

  if (defined($body)) {
    $headers .= "\r\nContent-Type: application/json";
    $headers .= "\r\nContent-Length: " . length($body);
  }

  return ($url, $headers);
}

sub RequestBlocking {
  my ($hash, $method, $path, $body) = @_;

  my ($url, $headers) = BuildLocalRequest($hash, $method, $path, $body);

  my $param = {
    url     => $url,
    method  => $method,
    header  => $headers,
    data    => $body,
    timeout => 8,
  };

  my ($err, $data) = ::HttpUtils_BlockingGet($param);
  my $code = $param->{code} // '';

  return ($err, $data, $code);
}

sub CallbackListText {
  my ($hash) = @_;

  my ($err, $data, $code) = RequestBlocking($hash, 'GET', 'callback', undef);
  return "Error reading callback list: $err" if $err;
  return "Error reading callback list: HTTP $code\n$data" if $code && $code !~ /^2/;

  my $j = DecodeJson($hash, $data);
  return "No callback list received" if !$j;

  my $items = ref($j) eq 'ARRAY' ? $j : ($j->{result} // []);
  my $ownUrl = CallbackUrl($hash);

  my $out = "Callback List:\n";
  $out .= "Own callback URL: $ownUrl\n\n";
  $out .= "No callbacks registered\n" if !@$items;

  foreach my $cb (@$items) {
    my $id     = $cb->{id} // '-';
    my $url    = $cb->{url} // '-';
    my $method = $cb->{method} // '-';
    my $own    = ($url eq $ownUrl) ? ' (this device)' : '';
    $out .= "ID: $id  Method: $method  URL: $url$own\n";
  }

  return $out;
}


sub Get {
  my ($hash, @a) = @_;
  my $name = shift @a;
  my $cmd  = shift @a // '';

  $cmd = 'callbackList'  if $cmd eq 'callback';
  my %dispatch = (
    setup         => sub { return SetupText($hash) },
    health        => sub { return HealthText($hash) },
    callbackList  => sub { return CallbackListText($hash) },  );

  return 'Unknown argument ' . $cmd . ', choose one of '
    . join(' ', map { "$_:noArg" } sort keys %dispatch)
    if !exists($dispatch{$cmd});

  return $dispatch{$cmd}->();
}

# Reference-style central I/O dispatcher.
# TedeeDevice never performs HTTP itself. It only calls IOWrite().
sub Write {
  my ($hash, $fn, $msg) = @_;

  return 'Device disabled' if ::AttrVal($hash->{NAME}, 'disable', 0);

  my $obj = {};
  if (defined($msg) && $msg =~ /^\s*\{/) {
    $obj = DecodeJson($hash, $msg) || {};
  } else {
    $obj->{deviceId} = $msg if defined($msg);
  }

  my $deviceId = $obj->{deviceId} // $obj->{lockId};
  return 'missing device id' if !defined($deviceId) || $deviceId eq '';

  if ($fn eq 'statusRequest') {
    return Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock');
  }

  if ($fn eq 'lock') {
    return Request($hash, 'POST', "lock/$deviceId/lock", '{}', \&ParseCommandResponse, "POST lock/$deviceId/lock");
  }

  if ($fn eq 'unlock') {
    return Request($hash, 'POST', "lock/$deviceId/unlock", '{}', \&ParseCommandResponse, "POST lock/$deviceId/unlock");
  }

  if ($fn eq 'unlatch') {
    return Request($hash, 'POST', "lock/$deviceId/pull", '{}', \&ParseCommandResponse, "POST lock/$deviceId/pull");
  }

  return "Unknown write function $fn";
}

sub Parse {
  my ($hash, $msg) = @_;
  return undef;
}

sub SetToken {
  my ($hash, $token) = @_;
  return 'Usage: set <name> token <LOCAL_BRIDGE_TOKEN>' if !defined($token) || $token eq '';

  my $name = $hash->{NAME};
  ::setKeyValue("${name}_token", $token);

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'tokenStored', 1);
  ::readingsBulkUpdate($hash, 'state', 'initialized');
  ::readingsBulkUpdate($hash, 'setupState', '2/6 token stored');
  ::readingsBulkUpdate($hash, 'setupNext', "set $name info");
  ::readingsEndUpdate($hash, 1);
  UpdateSetupState($hash);
  AutoSetup($hash);

  return Request($hash, 'GET', 'bridge', undef, \&ParseBridge, 'GET bridge');
}

sub AutoSetup {
  my $hash = shift;
  my $name = $hash->{NAME};

  return undef if ( !TokenExists($hash) );

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'state', 'initializing');
  ::readingsBulkUpdate($hash, 'setupState', '2/6 local bridge token stored, setup running');
  ::readingsBulkUpdate($hash, 'setupNext', 'automatic setup in progress');
  ::readingsEndUpdate($hash, 1);

  Request($hash, 'GET', 'bridge', undef, \&ParseBridge, 'GET bridge');
  Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock');
  Request($hash, 'GET', 'callback', undef, \&ParseCallbackList, 'GET callback');

  return undef;
}

sub DeleteToken {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::setKeyValue("${name}_token", undef);

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'tokenStored', 0);
  ::readingsBulkUpdate($hash, 'tokenValid', 0);
  ::readingsBulkUpdate($hash, 'state', 'initialized');
  ::readingsBulkUpdate($hash, 'setupState', '1/6 waiting for token');
  ::readingsBulkUpdate($hash, 'setupNext', "set $name token <LOCAL_BRIDGE_TOKEN>");
  ::readingsEndUpdate($hash, 1);
  UpdateSetupState($hash);

  return undef;
}

sub TokenExists {
  my ($hash) = @_;
  my $token = ::getKeyValue($hash->{NAME} . '_token');
  return (defined($token) && $token ne '') ? 1 : 0;
}

sub EncryptedToken {
  my ($hash, $plainToken) = @_;

  # Tedee encrypted local API tokens include a millisecond timestamp.
  # When FHEM sends two requests immediately after each other, both can happen
  # in the same millisecond. Make the timestamp strictly monotonic per bridge.
  my $timestamp = int(time() * 1000);
  my $last = $hash->{helper}{lastEncryptedTokenTimestamp} // 0;
  $timestamp = $last + 1 if $timestamp <= $last;
  $hash->{helper}{lastEncryptedTokenTimestamp} = $timestamp;

  my $digest = sha256_hex($plainToken . $timestamp);
  return $digest . $timestamp;
}

sub TokenHeader {
  my ($hash, $method, $path, $body) = @_;

  my $token = ::getKeyValue($hash->{NAME} . '_token');
  return '' if !defined($token);

  my $mode = ::AttrVal($hash->{NAME}, 'tokenMode', 'encrypted');
  return $token if $mode eq 'plain';

  return EncryptedToken($hash, $token);
}

sub Request {
  my ($hash, $method, $path, $body, $callback, $label) = @_;

  # Tedee Bridge API documentation recommends max. 1 request per second.
  # Queue local bridge requests and execute them one by one.
  my $q = $hash->{helper}{requestQueue} ||= [];
  push @$q, [$method, $path, $body, $callback, $label];

  RunRequestQueue($hash);
  return undef;
}

sub RunRequestQueue {
  my ($hash) = @_;

  return if $hash->{helper}{requestRunning};
  my $q = $hash->{helper}{requestQueue} ||= [];
  return if !@$q;

  my $now = time();
  my $last = $hash->{helper}{lastLocalRequestEpoch} // 0;
  my $wait = 1.0 - ($now - $last);

  if ($wait > 0) {
    ::RemoveInternalTimer($hash, __PACKAGE__ . '::RunRequestQueue');
    ::InternalTimer($now + $wait, __PACKAGE__ . '::RunRequestQueue', $hash);
    return;
  }

  my $next = shift @$q;
  $hash->{helper}{requestRunning} = 1;
  $hash->{helper}{lastLocalRequestEpoch} = $now;

  return RequestNow($hash, @$next);
}

sub FinishRequest {
  my ($hash) = @_;
  delete $hash->{helper}{requestRunning};
  ::InternalTimer(time() + 1.0, __PACKAGE__ . '::RunRequestQueue', $hash);
}

sub RequestNow {
  my ($hash, $method, $path, $body, $callback, $label) = @_;

  my $name = $hash->{NAME};
  return 'Device disabled' if ::AttrVal($name, 'disable', 0);

  my $url = "http://$hash->{HOST}:$hash->{PORT}/$API_VERSION/$path";
  my $token = TokenHeader($hash, $method, $path, $body);
  my $mode = ::AttrVal($name, 'tokenMode', 'encrypted');

  my $headers = "accept: application/json";
  if ($mode eq 'plain') {
    $headers .= "\r\napi_token: $token";
  } else {
    my $sep = ($url =~ /\?/) ? '&' : '?';
    $url .= $sep . "api_token=$token";
    $headers .= "\r\nWWW-Authenticate: Token\r\nContent-Type: application/json";
  }
  $headers .= "\r\nContent-Length: " . length($body) if defined($body);

  Debug($hash, 4, "HTTP $method $url");
  Debug($hash, 5, "HTTP body " . ($body // '')) if defined($body);

  if (DebugReadings($hash)) {
    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate($hash, 'lastRequest', $label || "$method $path");
    ::readingsBulkUpdate($hash, 'lastHttpCode', '');
    ::readingsEndUpdate($hash, 1);
  }

  ::HttpUtils_NonblockingGet({
    url      => $url,
    method   => $method,
    header   => $headers,
    data     => $body,
    timeout  => 8,
    hash     => $hash,
    request  => $label || "$method $path",
    callback => sub {
      my ($param, $err, $data) = @_;
      my $h = $param->{hash};
      my $code = $param->{code} // '';

      Debug($h, 4, 'HTTP response ' . ($code || '-') . ' for ' . ($param->{request} // ''));
      Debug($h, 5, 'HTTP data ' . ($data // '')) if defined($data);

      if ($err) {
        ::readingsBeginUpdate($h);
        ::readingsBulkUpdate($h, 'state', 'error');
        DebugReadingUpdate($h, 'localApiStatus', 'error');
        DebugReadingUpdate($h, 'localApiLastError', $err);
        DebugReadingUpdate($h, 'localApiLastErrorTime', Now());
        ::readingsBulkUpdate($h, 'lastError', $err);
        DebugReadingUpdate($h, 'lastHttpCode', $code);
        ::readingsEndUpdate($h, 1);
        UpdateHealth($h, 'http error');
        FinishRequest($h);
        return;
      }

      if ($code && $code !~ /^2/) {
        my $req = $param->{request} // '';

        ::readingsBeginUpdate($h);
        DebugReadingUpdate($h, 'lastHttpCode', $code);
        DebugReadingUpdate($h, 'localApiStatus', 'http_error');
        ::readingsBulkUpdate($h, 'lastError', "HTTP $code");

        # Only /bridge is treated as authoritative token verification.
        # A 401 on a follow-up request must not reset the whole setup state.
        if (($code eq '401' || $code eq '403') && $req eq 'GET bridge') {
          ::readingsBulkUpdate($h, 'tokenValid', 0);
          ::readingsBulkUpdate($h, 'state', 'token error');
          ::readingsBulkUpdate($h, 'setupState', '2/6 token invalid');
          ::readingsBulkUpdate($h, 'setupNext', "set $h->{NAME} token <LOCAL_BRIDGE_TOKEN>");
        } else {
          ::readingsBulkUpdate($h, 'state', 'http error');
        }

        ::readingsEndUpdate($h, 1);
        UpdateHealth($h, 'http status');
        FinishRequest($h);
        return;
      }

      ::readingsBeginUpdate($h);
      DebugReadingUpdate($h, 'lastHttpCode', $code);
      DebugReadingUpdate($h, 'localApiStatus', 'connected');
      DebugReadingUpdate($h, 'lastLocalApiSuccess', Now());

      # Any successful response from the authenticated local API proves that
      # the configured Tedee Bridge is reachable. This also corrects a stale
      # negative result from the optional UI detection performed at startup.
      ::readingsBulkUpdate($h, 'bridgeDetected', 1);
      ::readingsBulkUpdate($h, 'bridgeDetection', 'tedee local api');
      ::readingsBulkUpdate($h, 'state', 'connected');
      ::readingsBulkUpdate($h, 'tokenValid', 1);
      ::readingsBulkUpdate($h, 'lastError', '');
      ::readingsEndUpdate($h, 1);

      $callback->($h, $data, $code, $param);
      FinishRequest($h);
    },
  });

  return undef;
}

sub ParseBridge {
  my ($hash, $data, $code, $param) = @_;
  my $j = DecodeJson($hash, $data);
  return if !$j;

  ::readingsBeginUpdate($hash);
  my $bridgeName = Clean($j->{name}) || $hash->{NAME};
  ::readingsBulkUpdate($hash, 'bridgeName', $bridgeName);
  ::CommandAttr(undef, "$hash->{NAME} alias $bridgeName") if $bridgeName && !::AttrVal($hash->{NAME}, 'alias', '');
  ::readingsBulkUpdate($hash, 'bridgeType', 'hardware');
  ::readingsBulkUpdate($hash, 'hardwareId', $j->{serialNumber} // '');
  ::readingsBulkUpdate($hash, 'serverConnected', $j->{isConnected} // '');
  ::readingsBulkUpdate($hash, 'firmwareVersion', $j->{version} // '');
  ::readingsBulkUpdate($hash, 'wifiFirmwareVersion', $j->{wifiVersion} // '');
  DebugReadingUpdate($hash, 'bridgeSsid', Clean($j->{ssid}) // '');
  ::readingsBulkUpdate($hash, 'state', 'connected');
  ::readingsBulkUpdate($hash, 'setupState', '3/6 bridge connected');
  ::readingsBulkUpdate($hash, 'setupNext', "set $hash->{NAME} getDeviceList");
  ::readingsEndUpdate($hash, 1);

  UpdateHealth($hash, 'bridge');

  # Tedee convenience: after successful token verification, discover locks.
  Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock') if ($code && $code =~ /^2/);
}

sub ParseDevices {
  my ($hash, $data, $code, $param) = @_;
  my $j = DecodeJson($hash, $data);
  return if !$j;

  my $items = [];
  if (ref($j) eq 'ARRAY') {
    $items = $j;
  } elsif (ref($j->{result}) eq 'ARRAY') {
    $items = $j->{result};
  } elsif (ref($j->{locks}) eq 'ARRAY') {
    $items = $j->{locks};
  }

  my $count = scalar(@$items);

  RememberDeviceIds( $hash, $items );

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'locksCount', $count);
  ::readingsBulkUpdate($hash, 'activeLockId', $items->[0]{id} // $items->[0]{deviceId} // '') if $count;
  ::readingsBulkUpdate($hash, 'state', 'connected');
  ::readingsBulkUpdate($hash, 'setupState', $count ? '4/6 locks discovered' : '3/6 no locks found');
  ::readingsBulkUpdate($hash, 'setupNext', $count ? "set $hash->{NAME} resetCallback" : "set $hash->{NAME} getDeviceList");
  ::readingsEndUpdate($hash, 1);

  foreach my $lock (@$items) {
    next if ref($lock) ne 'HASH';
    AutocreateDevice($hash, $lock);
    $lock->{tedeeMessageType} = 'deviceStatus';
    $lock->{deviceId} //= $lock->{id};
    ::Dispatch($hash, $json_encode->($lock), undef);
  }

  UpdateHealth($hash, 'locks');
  UpdateSetupState($hash);
  RefreshActivity($hash) if CloudTokenExists($hash);
}

sub ParseCommandResponse {
  my ($hash, $data, $code, $param) = @_;

  ::readingsBeginUpdate($hash);
  DebugReadingUpdate($hash, 'commandLastHttpCode', $code // '');
  DebugReadingUpdate($hash, 'commandLastResult', ($code && $code =~ /^2/) ? 'ok' : 'unknown');
  ::readingsEndUpdate($hash, 1);

  UpdateSetupState($hash);
  Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock');
  RefreshActivity($hash) if CloudTokenExists($hash);
}

sub DecodeJson {
  my ($hash, $data) = @_;
  return undef if !defined($data) || $data eq '';

  my $j;
  eval { $j = $json_decode->($data); 1; };
  if ($@) {
    ::readingsSingleUpdate($hash, 'lastError', "JSON error: $@", 1);
    return undef;
  }

  return $j;
}

sub AutocreateDevice {
  my ($hash, $device) = @_;
  my $id = $device->{id} // $device->{deviceId};
  return if !$id;

  my $type = $device->{type} // $device->{deviceType} // 2;

  # The Tedee device ID is the stable identity. A user may rename the FHEM
  # device, so checking only the default name would create a duplicate after
  # "set <bridge> getDeviceList".
  my $existingDevice = FindDevice($hash, $id);
  return if defined($existingDevice);

  my $dev = "tedee.device.$id";
  return if defined($main::defs{$dev});

  my $err = ::CommandDefine(undef, "$dev TedeeDevice $id $hash->{NAME} $type");
  if ($err) {
    ::readingsSingleUpdate($hash, 'lastAutocreateError', $err, 1);
    return;
  }

  my $alias = Clean($device->{name}) || "Tedee Device $id";
  ::CommandAttr(undef, "$dev alias $alias");
}

sub FindDevice {
  my ($hash, $id) = @_;

  foreach my $d (keys %main::defs) {
    next if (($main::defs{$d}{TYPE} // '') ne 'TedeeDevice');
    return $d if (($main::defs{$d}{DEVICEID} // '') eq "$id");
  }

  return undef;
}

sub SetCloudToken {
  my ($hash, $token) = @_;
  return 'Usage: set <name> cloudToken <PERSONAL_ACCESS_TOKEN>' if !defined($token) || $token eq '';

  my $name = $hash->{NAME};
  ::setKeyValue("${name}_cloudToken", $token);

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'cloudTokenStored', 1);
  ::readingsBulkUpdate($hash, 'cloudStatus', 'initialized');
  ::readingsEndUpdate($hash, 1);

  UpdateSetupState($hash);
  return RefreshActivity($hash);
}

sub DeleteCloudToken {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  ::setKeyValue("${name}_cloudToken", undef);

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'cloudTokenStored', 0);
  ::readingsBulkUpdate($hash, 'cloudStatus', 'not configured');
  ::readingsEndUpdate($hash, 1);

  UpdateSetupState($hash);
  return undef;
}

sub CloudTokenExists {
  my ($hash) = @_;
  my $token = ::getKeyValue($hash->{NAME} . '_cloudToken');
  return (defined($token) && $token ne '') ? 1 : 0;
}

sub RememberDeviceIds {
  my $hash  = shift;
  my $items = shift;

  return undef if ( ref($items) ne 'ARRAY' );

  my @ids;
  for my $device ( @{$items} ) {
    next if ( ref($device) ne 'HASH' );

    my $id = $device->{id} // $device->{deviceId};
    next if ( !defined($id) );

    push @ids, $id;

    $hash->{helper}->{devices}->{$id} = {
      type => $device->{type} // '',
      name => $device->{name} // '',
    };
  }

  $hash->{helper}->{deviceIds} = \@ids;
  DebugReadingUpdate( $hash, 'deviceIds', join( ',', @ids ) );

  return undef;
}

sub DeviceIds {
  my $hash = shift;

  if ( defined( $hash->{helper}->{deviceIds} )
    && ref( $hash->{helper}->{deviceIds} ) eq 'ARRAY'
    && scalar( @{ $hash->{helper}->{deviceIds} } ) > 0 )
  {
    return @{ $hash->{helper}->{deviceIds} };
  }

  my $activeLockId = ::ReadingsVal( $hash->{NAME}, 'activeLockId', '' );
  return $activeLockId ? ($activeLockId) : ();
}

sub CloudActivityRetryDelays {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $raw = ::AttrVal($name, 'cloudActivityRetryDelays', '0,1,2,4,8');
  my @delays;

  for my $part (split /,/, $raw) {
    $part =~ s/^\s+|\s+$//g;
    next if $part eq '';
    next if $part !~ m/^\d+(?:\.\d+)?$/;
    push @delays, 0 + $part;
  }

  @delays = (0, 1, 2, 4, 8) if !@delays;

  my %seen;
  @delays = sort { $a <=> $b } grep { !$seen{$_}++ } @delays;

  return @delays;
}

sub RefreshActivity {
  my ($hash, $deviceId) = @_;
  my $name = $hash->{NAME};

  return 'Set cloud token first: set ' . $name . ' cloudToken <PERSONAL_KEY>'
    if ( !CloudTokenExists($hash) );

  my @deviceIds = defined($deviceId) && $deviceId ne ''
    ? ($deviceId)
    : DeviceIds($hash);

  return 'No lock known yet. Run set ' . $name . ' getDeviceList first.'
    if ( !scalar(@deviceIds) );

  my @delays = CloudActivityRetryDelays($hash);
  my $deviceOffset = 0;

  for my $id (@deviceIds) {
    $hash->{helper}{cloudActivityPending}{$id}{sinceEpoch} = ::gettimeofday();
    $hash->{helper}{cloudActivityPending}{$id}{sinceText}  = Now();
    $hash->{helper}{cloudActivityPending}{$id}{done}       = 0;
    $hash->{helper}{cloudActivityPending}{$id}{planned}    = join(',', @delays);

    my $attempt = 0;
    for my $delay (@delays) {
      ::InternalTimer(
        ::gettimeofday() + $delay + $deviceOffset,
        \&FHEM::Devices::Tedee::Bridge::RefreshActivityOne,
        {
          hash     => $hash,
          deviceId => $id,
          attempt  => $attempt,
          delay    => $delay,
        }
      );
      $attempt++;
    }

    $deviceOffset += 0.1;
  }

  return undef;
}

sub RefreshActivityOne {
  my $arg = shift;

  my $hash    = $arg->{hash};
  my $id      = $arg->{deviceId};
  my $attempt = $arg->{attempt} // 0;

  return undef if ( !defined($hash) || !defined($id) );

  my $pending = $hash->{helper}{cloudActivityPending}{$id};
  return undef if ( $attempt > 0 && ref($pending) eq 'HASH' && $pending->{done} );

  return CloudRequest(
    $hash,
    'GET',
    'my/deviceactivity?deviceId=' . $id . '&elements=1',
    undef,
    \&ParseCloudActivity,
    'GET my/deviceactivity?deviceId=' . $id . '&elements=1',
    {
      activityAttempt => $attempt,
      activityDelay   => $arg->{delay} // 0,
    }
  );
}




sub CloudRequest {
  my ($hash, $method, $path, $body, $callback, $label, $extra) = @_;
  $extra ||= {};

  my $name = $hash->{NAME};
  my $token = ::getKeyValue($name . '_cloudToken');
  return 'No cloud token stored' if !defined($token) || $token eq '';

  my $cloudVersion = ::AttrVal($name, 'cloudApiVersion', 'v37');
  my $url = "https://api.tedee.com/api/$cloudVersion/$path";
  my $headers = "accept: application/json\r\nAuthorization: PersonalKey $token";

  my ($requestDeviceId) = $path =~ m{deviceId=([^&]+)}xms;

  Debug($hash, 4, "CLOUD HTTP $method $url");
  Debug($hash, 5, "CLOUD body " . ($body // '')) if defined($body);

  if (DebugReadings($hash)) {
    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate($hash, 'cloudLastRequest', $label || "$method $path");
    ::readingsBulkUpdate($hash, 'cloudLastHttpCode', '');
    ::readingsEndUpdate($hash, 1);
  }

  ::HttpUtils_NonblockingGet({
    url      => $url,
    method   => $method,
    header   => $headers,
    data     => $body,
    timeout  => 12,
    hash     => $hash,
    request  => $label || "$method $path",
      requestDeviceId => $requestDeviceId,
      activityAttempt => $extra->{activityAttempt},
      activityDelay   => $extra->{activityDelay},
    callback => sub {
      my ($param, $err, $data) = @_;
      my $h = $param->{hash};
      my $code = $param->{code} // '';

      Debug($h, 4, 'CLOUD HTTP response ' . ($code || '-') . ' for ' . ($param->{request} // ''));
      Debug($h, 5, 'CLOUD data ' . ($data // '')) if defined($data);

      if ($err) {
        ::readingsBeginUpdate($h);
        ::readingsBulkUpdate($h, 'cloudStatus', 'error');
        DebugReadingUpdate($h, 'cloudLastError', $err);
        DebugReadingUpdate($h, 'cloudLastHttpCode', $code);
        ::readingsEndUpdate($h, 1);
        return;
      }

      if ($code && $code !~ /^2/) {
        my $retryAfter = '';
        my $httpHeader = $param->{httpheader} // $param->{headers} // '';
        if ( $httpHeader =~ m/^Retry-After:\s*(\S+)/mix ) {
          $retryAfter = $1;
        }

        ::readingsBeginUpdate($h);
        ::readingsBulkUpdate($h, 'cloudStatus', $code == 429 ? 'rate_limited' : 'http_error');
        DebugReadingUpdate($h, 'cloudLastError', "HTTP $code");
        DebugReadingUpdate($h, 'cloudLastHttpCode', $code);
        DebugReadingUpdate($h, 'cloudRetryAfter', $retryAfter) if $code == 429;
        ::readingsEndUpdate($h, 1);
        return;
      }

      ::readingsBeginUpdate($h);
      ::readingsBulkUpdate($h, 'cloudStatus', 'connected');
      DebugReadingUpdate($h, 'cloudLastHttpCode', $code);
      DebugReadingUpdate($h, 'cloudLastError', '');
      DebugReadingUpdate($h, 'cloudLastActivityRefresh', Now());
      ::readingsEndUpdate($h, 1);

      $callback->($h, $data, $code, $param);
    },
  });

  return undef;
}

sub ParseCloudActivity {
  my ($hash, $data, $code, $param) = @_;
  my $j = DecodeJson($hash, $data);
  return if !$j;

  my $items = ref($j) eq 'ARRAY' ? $j : ($j->{result} // []);
  my $count = scalar(@$items);

  ::readingsBeginUpdate($hash);
  DebugReadingUpdate($hash, 'cloudActivityCount', $count);
  ::readingsEndUpdate($hash, 1);

  return if !$count;

  my $last = $items->[0];
  my $deviceId = $last->{deviceId} // $param->{requestDeviceId} // ::ReadingsVal($hash->{NAME}, 'activeLockId', '');
  return if !$deviceId;

  my $activityId = $last->{id} // '';
  my $pending = $hash->{helper}{cloudActivityPending}{$deviceId} || {};
  my $previousId = $hash->{helper}{cloudActivityLastId}{$deviceId} // '';
  my $newActivity = ( $activityId ne '' && $activityId ne $previousId ) ? 1 : 0;

  my $lag = '';
  if ( defined( $pending->{sinceEpoch} ) ) {
    $lag = sprintf('%.3f', ::gettimeofday() - $pending->{sinceEpoch});
  }

  if ($newActivity) {
    $hash->{helper}{cloudActivityPending}{$deviceId}{done} = 1;
  }

  $hash->{helper}{cloudActivityLastId}{$deviceId} = $activityId if $activityId ne '';

  $last->{tedeeMessageType} = 'activity';
  $last->{deviceId} = $deviceId;
  $last->{_activityRefreshAttempt} = $param->{activityAttempt} // 0;
  $last->{_activityRefreshDelay}   = $param->{activityDelay} // 0;
  $last->{_activityRefreshPlanned} = $pending->{planned} // '';
  $last->{_activityPendingSince}   = $pending->{sinceText} // '';
  $last->{_activityLagSeconds}     = $lag;
  $last->{_activityIsNew}          = $newActivity ? 1 : 0;

  ::Dispatch($hash, $json_encode->($last), undef);
  UpdateSetupState($hash);

}

sub ResetCallback {
  my ($hash) = @_;
  return 'Set token first' if !TokenExists($hash);

  my $err = ValidateWebhook($hash);
  return $err if $err;

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'callbackStatus', 'resetting');
  ::readingsBulkUpdate($hash, 'setupState', '5/6 callback registering');
  ::readingsEndUpdate($hash, 1);

  return Request($hash, 'GET', 'callback', undef, \&ParseCallbacksForDelete, 'GET callback');
}

sub ParseCallbackList {
  my ($hash, $data, $code, $param) = @_;
  my $j = DecodeJson($hash, $data);
  return if !$j;

  my $items = ref($j) eq 'ARRAY' ? $j : ($j->{result} // []);
  my $url = CallbackUrl($hash);
  my $found = 0;

  foreach my $cb (@$items) {
    $found = 1 if (($cb->{url} // '') eq $url);
  }

  ::readingsBeginUpdate($hash);
  DebugReadingUpdate($hash, 'callbacksCount', scalar(@$items));
  ::readingsBulkUpdate($hash, 'callbackStatus', $found ? 'registered' : 'missing');
  ::readingsEndUpdate($hash, 1);

  return undef;
}

sub ParseCallbacksForDelete {
  my ($hash, $data, $code, $param) = @_;
  my $j = DecodeJson($hash, $data);
  return if !$j;

  my $items = ref($j) eq 'ARRAY' ? $j : ($j->{result} // []);
  my $ownUrl = CallbackUrl($hash);

  # Reference-like safety: do not remove callbacks registered by other services.
  # Only remove callback entries whose URL is exactly our own callback URL.
  my @ids = map { $_->{id} }
            grep { defined($_->{id}) && (($_->{url} // '') eq $ownUrl) }
            @$items;

  $hash->{helper}{deleteCallbackIds} = \@ids;

  return RegisterCallback($hash) if !@ids;

  my $id = shift @ids;
  $hash->{helper}{deleteCallbackIds} = \@ids;

  return Request($hash, 'DELETE', "callback/$id", undef, \&ParseDeleteCallback, "DELETE callback/$id");
}

sub ParseDeleteCallback {
  my ($hash, $data, $code, $param) = @_;
  my $ids = $hash->{helper}{deleteCallbackIds} || [];

  if (@$ids) {
    my $id = shift @$ids;
    $hash->{helper}{deleteCallbackIds} = $ids;
    return Request($hash, 'DELETE', "callback/$id", undef, \&ParseDeleteCallback, "DELETE callback/$id");
  }

  return RegisterCallback($hash);
}

sub RegisterCallback {
  my ($hash) = @_;
  my $url = CallbackUrl($hash);

  return 'No callback URL' if !$url;

  my $body = $json_encode->({ url => $url, method => 'GET', headers => [] });

  if (DebugReadings($hash)) {
    ::readingsBeginUpdate($hash);
    ::readingsBulkUpdate($hash, 'callbackStatus', 'registering');
    ::readingsBulkUpdate($hash, 'callbackUrl', $url);
    ::readingsEndUpdate($hash, 1);
  }

  return Request($hash, 'POST', 'callback', $body, \&ParseRegisterCallback, 'POST callback');
}

sub ParseRegisterCallback {
  my ($hash, $data, $code, $param) = @_;

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'callbackStatus', 'registered - waiting for event');
  ::readingsBulkUpdate($hash, 'setupState', '5/6 callback registered');
  ::readingsBulkUpdate($hash, 'setupNext', 'operate lock once to verify callback');
  ::readingsEndUpdate($hash, 1);

  return Request($hash, 'GET', 'callback', undef, \&ParseCallbackList, 'GET callback');
}

sub DeleteCallbacks {
  my ($hash) = @_;
  return Request($hash, 'GET', 'callback', undef, \&ParseCallbacksForDelete, 'GET callback');
}

sub ValidateWebhook {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $fw = ::AttrVal($name, 'webhookFWinstance', '');

  return "Set attr $name webhookFWinstance WEB" if !$fw;
  return "webhookFWinstance '$fw' does not exist" if !defined($main::defs{$fw});
  return "webhookFWinstance '$fw' is not TYPE=FHEMWEB" if (($main::defs{$fw}{TYPE} // '') ne 'FHEMWEB');

  return "webhookFWinstance '$fw' has basicAuth, Tedee callback needs unauthenticated HTTP"
    if ::AttrVal($fw, 'basicAuth', '') ne '';

  my $https = ::AttrVal($fw, 'HTTPS', ::AttrVal($fw, 'SSL', ''));
  return "webhookFWinstance '$fw' uses HTTPS/SSL, Tedee callback needs plain HTTP"
    if $https && $https ne '0';

  return undef;
}

sub CallbackBase {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $fw = ::AttrVal($name, 'webhookFWinstance', '');

  return '' if !$fw || !defined($main::defs{$fw});

  my $port = $main::defs{$fw}{PORT};
  if (!$port) {
    my $def = $main::defs{$fw}{DEF} // '';
    ($port) = $def =~ /(\d+)/;
  }

  my $host = ::AttrVal($name, 'webhookHttpHostname', '');
  if (!$host) {
    my $ip = qx(hostname -I 2>/dev/null);
    $ip =~ s/^\s+|\s+$//g;
    ($host) = split(/\s+/, $ip);
  }

  $host ||= '127.0.0.1';
  return "http://$host:$port/fhem";
}

sub CallbackUrl {
  my ($hash) = @_;
  my $base = CallbackBase($hash);
  return '' if !$base;
  return "$base/$WEBHOOK_PATH";
}

sub AddExtension {
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $path = $WEBHOOK_PATH;

  $main::data{FWEXT}{"/$path"}{deviceName} = $name;
  $main::data{FWEXT}{"/$path"}{FUNC}       = __PACKAGE__ . '::CGI';
  $main::data{FWEXT}{"/$path"}{LINK}       = $path;

  Debug($hash, 3, "registered webhook endpoint /$path");
}

sub RemoveExtension {
  my ($hash) = @_;
  delete $main::data{FWEXT}{"/$WEBHOOK_PATH"};
}

sub ReaddExtension {
  my ($hash) = @_;
  AddExtension($hash);
}

sub CGI {
  my ($request) = @_;

  my $name = $main::data{FWEXT}{"/$WEBHOOK_PATH"}{deviceName};
  return ('text/plain; charset=utf-8', 'No TedeeBridge device') if !$name || !defined($main::defs{$name});

  my $hash = $main::defs{$name};

  Debug($hash, 3, 'webhook received');
  Debug($hash, 5, 'webhook raw ' . ($request // ''));

  my %q;
  if ($request && $request =~ /\?(.+)$/) {
    foreach my $p (split(/&/, $1)) {
      my ($k, $v) = split(/=/, $p, 2);
      next if !defined($k);
      $q{$k} = defined($v) ? $v : '';
    }
  }

  ::readingsBeginUpdate($hash);
  DebugReadingUpdate($hash, 'lastWebhookReceived', Now());
  DebugReadingUpdate($hash, 'lastWebhookEvent', $q{event} || $q{eventName} || 'received');
  ::readingsBulkUpdate($hash, 'callbackStatus', 'active');
  ::readingsBulkUpdate($hash, 'state', 'callback active');
  ::readingsBulkUpdate($hash, 'setupState', '6/6 core ready');
  ::readingsBulkUpdate($hash, 'setupNext', 'ready');
  ::readingsEndUpdate($hash, 1);

  Request($hash, 'GET', 'lock', undef, \&ParseDevices, 'GET lock');

  return ('text/plain; charset=utf-8', 'OK');
}


sub UpdateSetupState {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $bridgeDetected = ::ReadingsVal($name, 'bridgeDetected', 1);
  my $tokenStored = ::ReadingsVal($name, 'tokenStored', 0);
  my $tokenValid  = ::ReadingsVal($name, 'tokenValid', 0);
  my $locksCount  = ::ReadingsVal($name, 'locksCount', 0);
  my $callback    = ::ReadingsVal($name, 'callbackStatus', '');
  my $cloudToken  = ::ReadingsVal($name, 'cloudTokenStored', 0);
  my $cloud       = ::ReadingsVal($name, 'cloudStatus', '');

  my ($state, $next);

  if (!$bridgeDetected) {
    $state = '0/6 no Tedee Bridge detected';
    $next  = 'Check HOST/IP or define TedeeBridge with the correct bridge IP';
  } elsif (!$tokenStored) {
    $state = '1/6 waiting for local bridge token';
    $next  = 'Open Tedee app, enable Bridge API, then: set ' . $name . ' token <LOCAL_BRIDGE_TOKEN>';
  } elsif (!$tokenValid) {
    $state = '2/6 local bridge token invalid';
    $next  = 'Check tokenMode/encrypted setting in Tedee app, then set ' . $name . ' token <LOCAL_BRIDGE_TOKEN>';
  } elsif (!$locksCount) {
    $state = '3/6 bridge connected, waiting for locks';
    $next  = 'set ' . $name . ' getDeviceList';
  } elsif ($callback ne 'active') {
    $state = '5/6 callback registered, waiting for event';
    $next  = 'Operate the lock once or change a harmless setting in the Tedee app to verify callback';
  } elsif (!$cloudToken) {
    $state = '6/6 local ready';
    $next  = 'optional: create PersonalKey at portal.tedee.com, then set ' . $name . ' cloudToken <PERSONAL_KEY>';
  } elsif ($cloud ne 'connected') {
    $state = '6/6 local ready, cloud pending';
    $next  = 'set ' . $name . ' refreshActivity';
  } else {
    $state = '6/6 ready with cloud';
    $next  = 'ready';
  }

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'setupState', $state);
  ::readingsBulkUpdate($hash, 'setupNext', $next);
  ::readingsEndUpdate($hash, 1);

  return undef;
}


sub UpdateHealth {
  my ($hash, $reason) = @_;
  my $portOk = PortOpen($hash->{HOST}, $hash->{PORT} || 80);
  my $callback = ::ReadingsVal($hash->{NAME}, 'callbackStatus', '');

  my $health = 'degraded';
  if ($portOk && $callback eq 'active') {
    $health = 'ok';
  } elsif (!$portOk && $callback eq 'active') {
    $health = 'broken_local_api';
  } elsif (!$portOk) {
    $health = 'offline';
  }

  ::readingsBeginUpdate($hash);
  ::readingsBulkUpdate($hash, 'bridgeHealth', $health);
  DebugReadingUpdate($hash, 'bridgePort80', $portOk ? 'open' : 'closed');
  DebugReadingUpdate($hash, 'bridgeHealthLastCheck', Now());
  ::readingsEndUpdate($hash, 1);

  return "bridgeHealth=$health";
}

sub HealthText {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $portOk = PortOpen($hash->{HOST}, $hash->{PORT} || 80);
  my $tokenValid = ::ReadingsVal($name, 'tokenValid', 0);
  my $locksCount = ::ReadingsVal($name, 'locksCount', 0);
  my $callback = ::ReadingsVal($name, 'callbackStatus', '-');
  my $cloud = ::ReadingsVal($name, 'cloudStatus', '-');

  UpdateHealth($hash, 'manual');

  my $localApiStatus = ($portOk && $tokenValid) ? 'connected' : ($portOk ? 'reachable, token not verified' : 'not reachable');

  return join("\n",
    'bridgeHealth: ' . ::ReadingsVal($name, 'bridgeHealth', '-'),
    'bridgePort80: ' . ($portOk ? 'open' : 'closed'),
    'localApiStatus: ' . $localApiStatus,
    'tokenValid: ' . $tokenValid,
    'locksCount: ' . $locksCount,
    'callbackStatus: ' . $callback,
    'cloudStatus: ' . $cloud,
  );
}

sub SetupText {
  my ($hash) = @_;
  my $name = $hash->{NAME};

  return join("\n",
    'Setup: ' . ::ReadingsVal($name, 'setupState', 'unknown'),
    'Next: ' . ::ReadingsVal($name, 'setupNext', '-'),
    'Token: ' . ::ReadingsVal($name, 'tokenStored', '0'),
    'Callback: ' . ::ReadingsVal($name, 'callbackStatus', '-'),
  );
}

sub PortOpen {
  my ($host, $port) = @_;
  return 0 if !$host || !$port;

  my $ok = 0;
  eval {
    require IO::Socket::INET;
    my $sock = IO::Socket::INET->new(
      PeerAddr => $host,
      PeerPort => $port,
      Proto    => 'tcp',
      Timeout  => 1,
    );
    if ($sock) {
      close($sock);
      $ok = 1;
    }
  };

  return $ok ? 1 : 0;
}

sub FhemText {
  my ($txt) = @_;
  return '' if !defined($txt);
  return is_utf8($txt) ? encode('UTF-8', $txt) : $txt;
}

sub Clean {
  my ($txt) = @_;
  return '' if !defined($txt);
  $txt =~ s/[\r\n]+/ /g;
  $txt =~ s/^\s+|\s+$//g;
  return FhemText($txt);
}

sub DebugReadings {
  my ($hash) = @_;
  return ::AttrVal($hash->{NAME}, 'debugReadings', 0) ? 1 : 0;
}

sub DebugReadingUpdate {
  my ($hash, $reading, $value) = @_;
  return if !DebugReadings($hash);
  ::readingsBulkUpdate($hash, $reading, defined($value) ? $value : '');
}

sub Debug {
  my ($hash, $level, $msg) = @_;
  return if !$hash;
  ::Log3($hash->{NAME}, $level, $hash->{NAME} . ': ' . $msg);
}

sub Now {
  return ::FmtDateTime(time());
}

1;sub CreateUri {
    my $hash   = shift;
    my $method = shift;
    my $path   = shift;
    my $body   = shift;

    return BuildLocalRequest( $hash, $method, $path, $body );
}


