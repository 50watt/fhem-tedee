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
# 74_TedeeDevice.pm
# Reference-style wrapper for Tedee Device
###############################################################################

package main;

use strict;
use warnings;

use FHEM::Meta;
use FHEM::Devices::Tedee::Device;

sub TedeeDevice_Initialize {
  my ($hash) = @_;

  $hash->{DefFn}    = \&FHEM::Devices::Tedee::Device::Define;
  $hash->{UndefFn}  = \&FHEM::Devices::Tedee::Device::Undef;
  $hash->{SetFn}    = \&FHEM::Devices::Tedee::Device::Set;
  $hash->{GetFn}    = \&FHEM::Devices::Tedee::Device::Get;
  $hash->{AttrFn}   = \&FHEM::Devices::Tedee::Device::Attr;
  $hash->{NotifyFn} = \&FHEM::Devices::Tedee::Device::Notify;
  $hash->{ParseFn}  = \&FHEM::Devices::Tedee::Device::Parse;
  $hash->{Match}    = '^\\{.*"(?:deviceId|id)".*\\}$';

  $hash->{AttrList} =
      'IODev '
    . 'disable:0,1 '
    . 'allowUnlock:0,1 '
    . 'debugReadings:0,1 '
    . $main::readingFnAttributes;

  return FHEM::Meta::InitMod(__FILE__, $hash);
}

1;

=pod

=encoding utf8

=item summary controls a Tedee smart lock device
=item summary_DE steuert ein Tedee Schloss Device

=begin html

<a id="TedeeDevice"></a>
<h3>TedeeDevice</h3>
<p><code>TedeeDevice</code> represents one Tedee lock device. It is created by <code>TedeeBridge</code> and uses the bridge as IODev. The device parses local status data and optional cloud activity data.</p>

<a id="TedeeDevice-define"></a>
<b>Define</b>
<ul><li><code>define &lt;name&gt; TedeeDevice &lt;deviceId&gt; &lt;IODev&gt; &lt;deviceType&gt;</code></li></ul>
<b>Example</b>
<ul><li><code>define tedeeLock1 TedeeDevice 123456 tedeeBridge1 2</code></li></ul>
<p>Normally, TedeeDevice devices are created automatically by the bridge.</p>

<a id="TedeeDevice-set"></a>
<b>Set</b>
<ul>
<li><code>statusRequest</code><br>Reads current status from the local Tedee Bridge API and updates <code>state</code>, <code>lockState</code>, <code>lockStateCode</code>, <code>doorState</code>, <code>doorStateCode</code>, <code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code>, <code>deviceType</code>, <code>firmwareVersion</code>, <code>name</code>, <code>tedeeId</code>, <code>serialNumber</code>, <code>rssi</code>, <code>isConnected</code>, <code>paired</code>. If a cloud token is configured, it may also update <code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (local FHEM/Raspberry Pi time using FHEM::Utility::CTZ convertTimeZone with an explicit Tedee timestamp pattern; if CTZ is not available, the original UTC value is kept), <code>lastActionSummary</code>.<br>Example: <code>set tedeeLock1 statusRequest</code></li>
<li><code>lock</code><br>Locks the device.<br>Example: <code>set tedeeLock1 lock</code></li>
<li><code>unlock</code><br>Unlocks the device. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>
<li><code>unlatch</code><br>Pulls the spring / opens the latch. Requires <code>allowUnlock 1</code>.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>
</ul>

<a id="TedeeDevice-get"></a>
<b>Get</b>
<ul><li><code>status</code><br>Depending on the installed module version, returns or refreshes the status. For active refresh use <code>set &lt;name&gt; statusRequest</code>.<br>Example: <code>get tedeeLock1 status</code></li></ul>

<a id="TedeeDevice-readings"></a>
<b>Readings</b>
<ul>
<li><code>state</code> - main lock state, e.g. <code>locked</code>, <code>unlocked</code>, <code>semi_locked</code>, <code>locking</code>, <code>unlocking</code>, <code>pulled</code>, <code>pulling</code>, <code>uncalibrated</code>, <code>updating</code>, <code>unknown</code>.</li>
<li><code>lockState</code> / <code>lockStateCode</code> - mapped Tedee lock state and original numeric code. Example: <code>2</code> = unlocked, <code>6</code> = locked.</li>
<li><code>doorState</code> / <code>doorStateCode</code> - mapped Tedee door sensor state and original numeric code. <code>0</code> means no paired door sensor.</li>
<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - battery level, charging state and derived state.</li>
<li><code>deviceType</code>, <code>firmwareVersion</code>, <code>name</code>, <code>tedeeId</code>, <code>serialNumber</code>, <code>rssi</code>, <code>isConnected</code>, <code>paired</code> - device identity/connectivity readings.</li>
<li><code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (local FHEM/Raspberry Pi time using FHEM::Utility::CTZ convertTimeZone with an explicit Tedee timestamp pattern; if CTZ is not available, the original UTC value is kept), <code>lastActionSummary</code> - optional cloud activity readings.</li>
</ul>

<a id="TedeeDevice-attributes"></a>
<b>Attributes</b>
<ul>
<li><code>IODev</code><br>Associated <code>TedeeBridge</code> device. Usually set automatically.<br>Example: <code>attr tedeeLock1 IODev tedeeBridge1</code></li>
<li><code>allowUnlock 0|1</code><br>Default: <code>0</code><br><code>0</code> = <code>unlock</code> and <code>unlatch</code> are blocked.<br><code>1</code> = <code>unlock</code> and <code>unlatch</code> are allowed.<br>Example: <code>attr tedeeLock1 allowUnlock 1</code></li>
<li><code>debugReadings 0|1</code><br>Default: <code>0</code><br><code>0</code> = only normal readings.<br><code>1</code> = additional diagnostics such as <code>raw_type</code>, <code>raw_state</code>, <code>raw_doorState</code>, <code>deviceRevision</code>, <code>jammed</code>, <code>deviceSettings_*</code>, <code>lastActionCode</code>, <code>lastActionSourceCode</code>, <code>lastActionId</code>.<br>Example: <code>attr tedeeLock1 debugReadings 1</code></li>
<li><code>disable 0|1</code><br>Default: <code>0</code><br><code>0</code> = device enabled.<br><code>1</code> = device disabled.<br>Example: <code>attr tedeeLock1 disable 1</code></li>
</ul>

<a id="TedeeDevice-security"></a>
<b>Security</b>
<ul><li><code>unlock</code> and <code>unlatch</code> are disabled by default.</li><li>Enable these commands only for locks where remote opening is intended.</li></ul>

=end html

=begin html_DE

<a id="TedeeDevice"></a>
<h3>TedeeDevice</h3>

<p><code>TedeeDevice</code> repräsentiert ein Tedee Schloss Device. Es wird von <code>TedeeBridge</code> angelegt und verwendet die Bridge als IODev. Das Device verarbeitet lokale Statusdaten und optionale Cloud-Activity-Daten.</p>

<a id="TedeeDevice-define"></a>
<b>Define</b>
<ul><li><code>define &lt;name&gt; TedeeDevice &lt;deviceId&gt; &lt;IODev&gt; &lt;deviceType&gt;</code></li></ul>
<b>Beispiel</b>
<ul><li><code>define tedeeLock1 TedeeDevice 123456 tedeeBridge1 2</code></li></ul>
<p>Normalerweise werden TedeeDevice Devices automatisch von der Bridge angelegt.</p>

<a id="TedeeDevice-set"></a>
<b>Set</b>
<ul>
<li><code>statusRequest</code><br>Liest den aktuellen Status über die lokale Tedee Bridge API und aktualisiert <code>state</code>, <code>lockState</code>, <code>lockStateCode</code>, <code>doorState</code>, <code>doorStateCode</code>, <code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code>, <code>deviceType</code>, <code>firmwareVersion</code>, <code>name</code>, <code>tedeeId</code>, <code>serialNumber</code>, <code>rssi</code>, <code>isConnected</code> und <code>paired</code>. Wenn ein Cloud-Token konfiguriert ist, können zusätzlich <code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (lokale FHEM/Raspberry-Pi-Zeit über FHEM::Utility::CTZ convertTimeZone mit explizitem Tedee-Zeitstempel-Pattern; falls CTZ nicht verfügbar ist, bleibt der UTC-Originalwert erhalten) und <code>lastActionSummary</code> aktualisiert werden.<br>Beispiel: <code>set tedeeLock1 statusRequest</code></li>
<li><code>lock</code><br>Verriegelt das Schloss.<br>Beispiel: <code>set tedeeLock1 lock</code></li>
<li><code>unlock</code><br>Entriegelt das Schloss. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlock</code></li>
<li><code>unlatch</code><br>Zieht die Falle / öffnet die Tür. Erfordert <code>allowUnlock 1</code>.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code><br><code>set tedeeLock1 unlatch</code></li>
</ul>

<a id="TedeeDevice-get"></a>
<b>Get</b>
<ul><li><code>status</code><br>Gibt je nach installierter Modulversion den Status zurück bzw. aktualisiert ihn. Für eine aktive Aktualisierung <code>set &lt;name&gt; statusRequest</code> verwenden.<br>Beispiel: <code>get tedeeLock1 status</code></li></ul>

<a id="TedeeDevice-readings"></a>
<b>Readings</b>
<ul>
<li><code>state</code> - Hauptstatus des Schlosses, z. B. <code>locked</code>, <code>unlocked</code>, <code>semi_locked</code>, <code>locking</code>, <code>unlocking</code>, <code>pulled</code>, <code>pulling</code>, <code>uncalibrated</code>, <code>updating</code>, <code>unknown</code>.</li>
<li><code>lockState</code> / <code>lockStateCode</code> - gemappter Tedee Schlossstatus und originaler numerischer Code. Beispiel: <code>2</code> = unlocked, <code>6</code> = locked.</li>
<li><code>doorState</code> / <code>doorStateCode</code> - gemappter Tedee Türsensorstatus und originaler numerischer Code. <code>0</code> bedeutet kein gekoppelter Türsensor.</li>
<li><code>batteryPercent</code>, <code>batteryCharging</code>, <code>batteryState</code> - Batteriestand, Ladestatus und abgeleiteter Batteriestatus.</li>
<li><code>deviceType</code>, <code>firmwareVersion</code>, <code>name</code>, <code>tedeeId</code>, <code>serialNumber</code>, <code>rssi</code>, <code>isConnected</code>, <code>paired</code> - Device-Identität und Verbindung.</li>
<li><code>lastAction</code>, <code>lastActionUser</code>, <code>lastActionSource</code>, <code>lastActionDate</code> (local FHEM/Raspberry Pi time using FHEM::Utility::CTZ convertTimeZone with an explicit Tedee timestamp pattern; if CTZ is not available, the original UTC value is kept), <code>lastActionSummary</code> - optionale Cloud-Activity-Readings.</li>
</ul>

<a id="TedeeDevice-attributes"></a>
<b>Attribute</b>
<ul>
<li><code>IODev</code><br>Zugehöriges <code>TedeeBridge</code> Device. Wird normalerweise automatisch gesetzt.<br>Beispiel: <code>attr tedeeLock1 IODev tedeeBridge1</code></li>
<li><code>allowUnlock 0|1</code><br>Standard: <code>0</code><br><code>0</code> = <code>unlock</code> und <code>unlatch</code> sind gesperrt.<br><code>1</code> = <code>unlock</code> und <code>unlatch</code> sind erlaubt.<br>Beispiel: <code>attr tedeeLock1 allowUnlock 1</code></li>
<li><code>debugReadings 0|1</code><br>Standard: <code>0</code><br><code>0</code> = nur normale Readings.<br><code>1</code> = zusätzliche Diagnose-Readings wie <code>raw_type</code>, <code>raw_state</code>, <code>raw_doorState</code>, <code>deviceRevision</code>, <code>jammed</code>, <code>deviceSettings_*</code>, <code>lastActionCode</code>, <code>lastActionSourceCode</code>, <code>lastActionDateUTC</code>, <code>lastActionId</code>, <code>activityRefreshAttempt</code>, <code>activityRefreshDelay</code>, <code>activityRefreshPlanned</code>, <code>activityPendingSince</code>, <code>activityLagSeconds</code> und <code>activityIsNew</code>.<br>Beispiel: <code>attr tedeeLock1 debugReadings 1</code></li>
<li><code>disable 0|1</code><br>Standard: <code>0</code><br><code>0</code> = Device aktiv.<br><code>1</code> = Device deaktiviert.<br>Beispiel: <code>attr tedeeLock1 disable 1</code></li>
</ul>

<a id="TedeeDevice-security"></a>
<b>Sicherheit</b>
<ul>
<li><code>unlock</code> und <code>unlatch</code> sind standardmäßig deaktiviert.</li>
<li>Diese Befehle nur für Schlösser aktivieren, bei denen Remote-Öffnen gewünscht ist.</li>
</ul>

=end html_DE

=for :application/json;q=META.json 74_TedeeDevice.pm
{
  "abstract": "controls a Tedee smart lock device",
  "x_lang": { "de": { "abstract": "steuert ein Tedee Schloss Device" } },
  "version": "v0.7.29",
  "author": [ "50watt" ],
  "license": [ "same as FHEM" ],
  "prereqs": { "runtime": { "requires": { "perl": "5.014", "strict": 0, "warnings": 0, "FHEM::Meta": 0 } } },
  "x_fhem_maintainer": [ "50watt" ],
  "x_fhem_support": { "forum": "https://forum.fhem.de/" },
  "x_fhem_abstract": "controls a Tedee smart lock device",
  "x_fhem_abstract_DE": "steuert ein Tedee Schloss Device",
  "x_fhem_keywords": [ "Tedee", "smart lock", "bridge", "local API", "cloud", "home automation" ]
}
=end :application/json;q=META.json

=cut
