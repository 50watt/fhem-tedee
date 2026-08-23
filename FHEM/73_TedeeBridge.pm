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
# 73_TedeeBridge.pm
# Reference-style wrapper for Tedee Bridge
###############################################################################

package main;

use strict;
use warnings;

use FHEM::Meta;
use FHEM::Devices::Tedee::Bridge;

sub TedeeBridge_Initialize {
  my ($hash) = @_;

  $hash->{DefFn}   = \&FHEM::Devices::Tedee::Bridge::Define;
  $hash->{UndefFn} = \&FHEM::Devices::Tedee::Bridge::Undef;
  $hash->{SetFn}   = \&FHEM::Devices::Tedee::Bridge::Set;
  $hash->{GetFn}   = \&FHEM::Devices::Tedee::Bridge::Get;
  $hash->{AttrFn}  = \&FHEM::Devices::Tedee::Bridge::Attr;
  $hash->{WriteFn} = \&FHEM::Devices::Tedee::Bridge::Write;
  $hash->{ParseFn} = \&FHEM::Devices::Tedee::Bridge::Parse;

  $hash->{Clients}   = ':TedeeDevice:';
  $hash->{MatchList} = { '1:TedeeDevice' => '^\{.*"(?:deviceId|id)".*\}$' };

  $hash->{AttrList} =
      'disable:0,1 '
    . 'webhookFWinstance '
    . 'webhookHttpHostname '
    . 'tokenMode:encrypted,plain '
    . 'cloudApiVersion '
    . 'cloudActivityRetryDelays '
    . 'debugReadings:0,1 '
    . $main::readingFnAttributes;

  return FHEM::Meta::InitMod(__FILE__, $hash);
}

1;

=pod

=encoding utf8

=item summary controls Tedee smart locks via local bridge API
=item summary_DE steuert Tedee Smart Locks über lokale Bridge API

=begin html

<a id="TedeeBridge"></a>
<h3>TedeeBridge</h3>
<p><code>TedeeBridge</code> connects FHEM with a Tedee Bridge using the local Tedee Bridge API. The bridge device is the IODev/transport device. It performs HTTP requests, registers callbacks and creates or updates <code>TedeeDevice</code> devices.</p>
<p>The local Tedee Bridge API is used for status and lock commands. Optional Tedee Cloud access can be configured with a PersonalKey to read recent device activity.</p>

<a id="TedeeBridge-define"></a>
<b>Define</b>
<ul><li><code>define &lt;name&gt; TedeeBridge &lt;HOST&gt; [&lt;PORT&gt;]</code></li></ul>
<b>Example</b>
<ul><li><code>define tedeeBridge1 TedeeBridge 192.0.2.10</code></li></ul>
<p><code>&lt;HOST&gt;</code> is the IP address or DNS name of the Tedee Bridge. <code>&lt;PORT&gt;</code> is optional and defaults to <code>80</code>. The local Bridge API token is not part of the define command.</p>

<a id="TedeeBridge-setup"></a>
<b>Recommended initial setup</b>
<ol>
<li>Enable the local Bridge API in the Tedee app.</li>
<li>Copy the local Bridge API token from the Tedee app.</li>
<li><code>define tedeeBridge1 TedeeBridge 192.0.2.10</code></li>
<li><code>set tedeeBridge1 token &lt;LOCAL_BRIDGE_TOKEN&gt;</code></li>
<li>The module continues setup automatically: bridge info, device list and callback check.</li>
<li>Optional cloud activity: create a PersonalKey at <code>portal.tedee.com</code> and use <code>set tedeeBridge1 cloudToken &lt;PERSONAL_KEY&gt;</code>.</li>
</ol>
<p>Setup progress is visible in <code>setupState</code> and <code>setupNext</code>.</p>

<a id="TedeeBridge-set"></a>
<b>Set</b>
<ul>
<li><code>token &lt;LOCAL_BRIDGE_TOKEN&gt;</code><br>Stores the local Bridge API token and starts setup automatically.<br>Example: <code>set tedeeBridge1 token abcdef123456</code></li>
<li><code>deleteToken</code><br>Deletes the stored local Bridge API token.<br>Example: <code>set tedeeBridge1 deleteToken</code></li>
<li><code>cloudToken &lt;PERSONAL_KEY&gt;</code><br>Stores a Tedee Cloud PersonalKey. This enables cloud activity readings on <code>TedeeDevice</code> devices.<br>Example: <code>set tedeeBridge1 cloudToken ey...</code></li>
<li><code>deleteCloudToken</code><br>Deletes the stored Tedee Cloud PersonalKey.<br>Example: <code>set tedeeBridge1 deleteCloudToken</code></li>
<li><code>getDeviceList</code><br>Reads all locks from <code>/v1.0/lock</code>, dispatches their status and creates missing <code>TedeeDevice</code> devices.<br>Example: <code>set tedeeBridge1 getDeviceList</code></li>
<li><code>info</code><br>Reads bridge information from <code>/v1.0/bridge</code> and updates <code>bridgeName</code>, <code>bridgeType</code>, <code>firmwareVersion</code>, <code>hardwareId</code>, <code>serverConnected</code>, <code>wifiFirmwareVersion</code>.<br>Example: <code>set tedeeBridge1 info</code></li>
<li><code>callbackRemove</code><br>Removes only callbacks whose URL exactly matches this module's own callback URL.<br>Example: <code>set tedeeBridge1 callbackRemove</code></li>
<li><code>resetCallback</code><br>Removes this module's own callback URL and registers it again.<br>Example: <code>set tedeeBridge1 resetCallback</code></li>
<li><code>refreshActivity [&lt;deviceId&gt;]</code><br>Reads the newest Tedee Cloud activity event. The newest event is requested immediately and then according to <code>cloudActivityRetryDelays</code> until a newer/plausible activity entry is seen. Without <code>&lt;deviceId&gt;</code>, the newest activity event is refreshed for all known devices. With <code>&lt;deviceId&gt;</code>, only the given device is refreshed.<br>Examples: <code>set tedeeBridge1 refreshActivity</code>, <code>set tedeeBridge1 refreshActivity 123456</code></li>
</ul>

<a id="TedeeBridge-get"></a>
<b>Get</b>
<ul>
<li><code>callbackList</code><br>Shows callback URLs registered on the Tedee Bridge.<br>Example: <code>get tedeeBridge1 callbackList</code></li>
<li><code>setup</code><br>Shows a setup summary based on <code>setupState</code> and <code>setupNext</code>.<br>Example: <code>get tedeeBridge1 setup</code></li>
<li><code>health</code><br>Shows a short bridge health summary.<br>Example: <code>get tedeeBridge1 health</code></li>
</ul>

<a id="TedeeBridge-readings"></a>
<b>Readings</b>
<ul>
<li><code>state</code> - main bridge state, e.g. <code>connected</code>, <code>initializing</code>, <code>initialized</code>, <code>error</code>, <code>disconnected</code>, <code>error</code>, <code>disabled</code>.</li>
<li><code>bridgeDetected</code> - <code>1</code> if the host looks like a Tedee Bridge before authentication.</li>
<li><code>bridgeDetection</code> - diagnostic text for bridge detection.</li>
<li><code>bridgeName</code> - name of the Tedee Bridge.</li>
<li><code>bridgeType</code> - bridge type, normally <code>hardware</code>.</li>
<li><code>firmwareVersion</code> - Tedee Bridge firmware version.</li>
<li><code>hardwareId</code> - bridge hardware identifier / serial number.</li>
<li><code>serverConnected</code> - cloud connection state reported by the bridge.</li>
<li><code>wifiFirmwareVersion</code> - Wi-Fi module firmware version.</li>
<li><code>tokenStored</code> - <code>1</code> if a local token is stored.</li>
<li><code>tokenValid</code> - <code>1</code> if the local token was accepted.</li>
<li><code>cloudTokenStored</code> - <code>1</code> if a Cloud PersonalKey is stored.</li>
<li><code>cloudStatus</code> - cloud activity status, e.g. <code>connected</code> or <code>http_error</code>.</li>
<li><code>callbackStatus</code> - callback status, e.g. <code>active</code>, <code>registered</code>, <code>missing</code>, <code>error</code>.</li>
<li><code>locksCount</code> - number of locks returned by the bridge.</li>
<li><code>activeLockId</code> - last/primary lock id seen by the bridge.</li>
<li><code>setupState</code> - guided setup state.</li>
<li><code>setupNext</code> - recommended next setup action.</li>
<li><code>bridgeHealth</code> - summarized health status, e.g. <code>ok</code> or <code>degraded</code>.</li>
<li><code>lastError</code> - last relevant error text.</li>
</ul>

<a id="TedeeBridge-attributes"></a>
<b>Attributes</b>
<ul>
<li><code>disable 0|1</code><br>Default: <code>0</code><br><code>0</code> = enabled.<br><code>1</code> = disabled.<br>Example: <code>attr tedeeBridge1 disable 1</code></li>
<li><code>webhookFWinstance &lt;FHEMWEB-device&gt;</code><br>FHEMWEB instance used for callback requests. Must be reachable by the Tedee Bridge via HTTP and suitable for callbacks.<br>Example: <code>attr tedeeBridge1 webhookFWinstance WEB</code></li>
<li><code>webhookHttpHostname &lt;IP-or-FQDN&gt;</code><br>IP address or DNS name used to build the callback URL.<br>Example: <code>attr tedeeBridge1 webhookHttpHostname 192.0.2.20</code></li>
<li><code>tokenMode encrypted|plain</code><br>Default: <code>encrypted</code><br><code>encrypted</code> = token is sent as Tedee encrypted URL parameter using timestamp and SHA-256 hash.<br><code>plain</code> = token is sent as plain <code>api_token</code> HTTP header.<br>Example: <code>attr tedeeBridge1 tokenMode encrypted</code></li>
<li><code>cloudApiVersion &lt;version&gt;</code><br>Default: <code>v37</code><br>Tedee Cloud API version used for activity requests.<br>Example: <code>attr tedeeBridge1 cloudApiVersion v37</code></li>
<li><code>cloudActivityRetryDelays &lt;seconds-list&gt;</code><br>Default: <code>0,1,2,4,8</code><br>Comma-separated retry delays for cloud activity refresh after local status changes or <code>statusRequest</code>. <code>0</code> means immediate refresh. Example: <code>attr tedeeBridge1 cloudActivityRetryDelays 0,1,2,4,8</code></li>
<li><code>debugReadings 0|1</code><br>Default: <code>0</code><br><code>0</code> = only normal bridge readings.<br><code>1</code> = additional diagnostics such as request labels, HTTP status codes, callback counters, device id lists or cloud diagnostics including cloudRetryAfter on HTTP 429.<br>Example: <code>attr tedeeBridge1 debugReadings 1</code></li>
<li><code>devStateIcon</code><br>Default example: <code>connected:10px-kreis-gruen:info disconnected:10px-kreis-rot:info error:10px-kreis-rot:info initialized:10px-kreis-gelb:info disabled:10px-kreis-gelb:info .*:10px-kreis-gelb:info</code><br>FHEM UI icon mapping. The module sets a default colored dot: green for connected, yellow for initialized/disabled or unclear state, red for disconnected/error.</li>
</ul>

<p>The module uses an internal queue and guarantees at least one second between local bridge API requests.</p>
<p>Das Modul verwendet eine interne Queue und garantiert mindestens eine Sekunde Abstand zwischen lokalen Bridge-API-Requests.</p>
<a id="TedeeBridge-rate-limit"></a>
<b>Rate limit</b>
<ul><li>The local Tedee Bridge API should not be called faster than one request per second.</li><li>The module queues local requests and processes them with a minimum spacing of one second.</li><li>Callbacks are preferred for live updates. Avoid frequent manual polling.</li></ul>

<p>Callbacks are registered and renewed automatically during setup and callback reset.</p>
<p>Callbacks werden während des Setups und beim Callback-Reset automatisch registriert und erneuert.</p>
<a id="TedeeBridge-security"></a>
<b>Security</b>
<ul><li>Store local bridge and cloud tokens only on a trusted FHEM host.</li><li>Do not expose FHEM or the local Tedee Bridge API directly to the Internet.</li><li>Use network segmentation/firewalling where possible.</li><li>Remote unlock/open commands are disabled by default on each <code>TedeeDevice</code> and must be enabled per device.</li></ul>

=end html

=begin html_DE

<a id="TedeeBridge"></a>
<h3>TedeeBridge</h3>

<p><code>TedeeBridge</code> verbindet FHEM mit einer Tedee Bridge über die lokale Tedee Bridge API. Das Bridge-Device ist das IODev-/Transport-Device. Es führt HTTP-Requests aus, registriert Callbacks und legt <code>TedeeDevice</code> Devices an bzw. aktualisiert diese.</p>
<p>Die lokale Tedee Bridge API wird für Status- und Schlossbefehle verwendet. Optional kann mit einem Tedee Cloud PersonalKey die Cloud-Activity gelesen werden.</p>

<a id="TedeeBridge-define"></a>
<b>Define</b>
<ul><li><code>define &lt;name&gt; TedeeBridge &lt;HOST&gt; [&lt;PORT&gt;]</code></li></ul>
<b>Beispiel</b>
<ul><li><code>define tedeeBridge1 TedeeBridge 192.0.2.10</code></li></ul>
<p><code>&lt;HOST&gt;</code> ist die IP-Adresse oder der DNS-Name der Tedee Bridge. <code>&lt;PORT&gt;</code> ist optional und standardmäßig <code>80</code>. Der lokale Bridge API Token ist nicht Teil des Define-Befehls.</p>

<a id="TedeeBridge-setup"></a>
<b>Empfohlenes initiales Setup</b>
<ol>
<li>In der Tedee App die lokale Bridge API aktivieren.</li>
<li>Den lokalen Bridge API Token aus der Tedee App kopieren.</li>
<li><code>define tedeeBridge1 TedeeBridge 192.0.2.10</code></li>
<li><code>set tedeeBridge1 token &lt;LOCAL_BRIDGE_TOKEN&gt;</code></li>
<li>Das Modul setzt das Setup automatisch fort: Bridge-Info, Device-Liste und Callback-Prüfung.</li>
<li>Optional für Cloud-Activity: auf <code>portal.tedee.com</code> einen PersonalKey erstellen und mit <code>set tedeeBridge1 cloudToken &lt;PERSONAL_KEY&gt;</code> speichern.</li>
</ol>
<p>Der Setup-Fortschritt ist in den Readings <code>setupState</code> und <code>setupNext</code> sichtbar.</p>

<a id="TedeeBridge-set"></a>
<b>Set</b>
<ul>
<li><code>token &lt;LOCAL_BRIDGE_TOKEN&gt;</code><br>Speichert den lokalen Bridge API Token und startet das Setup automatisch.<br>Beispiel: <code>set tedeeBridge1 token abcdef123456</code></li>
<li><code>deleteToken</code><br>Löscht den gespeicherten lokalen Bridge API Token.<br>Beispiel: <code>set tedeeBridge1 deleteToken</code></li>
<li><code>cloudToken &lt;PERSONAL_KEY&gt;</code><br>Speichert einen Tedee Cloud PersonalKey. Dadurch werden Cloud-Activity-Readings an <code>TedeeDevice</code> Devices möglich.<br>Beispiel: <code>set tedeeBridge1 cloudToken ey...</code></li>
<li><code>deleteCloudToken</code><br>Löscht den gespeicherten Tedee Cloud PersonalKey.<br>Beispiel: <code>set tedeeBridge1 deleteCloudToken</code></li>
<li><code>getDeviceList</code><br>Liest alle Schlösser über <code>/v1.0/lock</code>, dispatcht deren Status und legt fehlende <code>TedeeDevice</code> Devices an.<br>Beispiel: <code>set tedeeBridge1 getDeviceList</code></li>
<li><code>info</code><br>Liest Bridge-Informationen über <code>/v1.0/bridge</code> und aktualisiert <code>bridgeName</code>, <code>bridgeType</code>, <code>firmwareVersion</code>, <code>hardwareId</code>, <code>serverConnected</code> und <code>wifiFirmwareVersion</code>.<br>Beispiel: <code>set tedeeBridge1 info</code></li>
<li><code>callbackRemove</code><br>Löscht nur Callbacks, deren URL exakt der eigenen Callback-URL dieses Moduls entspricht.<br>Beispiel: <code>set tedeeBridge1 callbackRemove</code></li>
<li><code>resetCallback</code><br>Löscht die eigene Callback-URL dieses Moduls und registriert sie neu.<br>Beispiel: <code>set tedeeBridge1 resetCallback</code></li>
<li><code>refreshActivity [&lt;deviceId&gt;]</code><br>Liest den neuesten Tedee Cloud Activity-Eintrag. Der neueste Eintrag wird sofort und danach gemäß <code>cloudActivityRetryDelays</code> erneut abgefragt, bis ein neuer/plausibler Activity-Eintrag erkannt wurde. Ohne <code>&lt;deviceId&gt;</code> werden für alle bekannten Devices der neueste Activity-Eintrag aktualisiert. Mit <code>&lt;deviceId&gt;</code> wird nur das angegebene Device aktualisiert.<br>Beispiele: <code>set tedeeBridge1 refreshActivity</code>, <code>set tedeeBridge1 refreshActivity 123456</code></li>
</ul>

<a id="TedeeBridge-get"></a>
<b>Get</b>
<ul>
<li><code>callbackList</code><br>Zeigt die auf der Tedee Bridge registrierten Callback-URLs.<br>Beispiel: <code>get tedeeBridge1 callbackList</code></li>
<li><code>setup</code><br>Zeigt eine Setup-Zusammenfassung basierend auf <code>setupState</code> und <code>setupNext</code>.<br>Beispiel: <code>get tedeeBridge1 setup</code></li>
<li><code>health</code><br>Zeigt eine kurze Bridge-Diagnose.<br>Beispiel: <code>get tedeeBridge1 health</code></li>
</ul>

<a id="TedeeBridge-readings"></a>
<b>Readings</b>
<ul>
<li><code>state</code> - Hauptstatus der Bridge, z. B. <code>connected</code>, <code>initializing</code>, <code>initialized</code>, <code>error</code>, <code>disconnected</code>, <code>error</code>, <code>disabled</code>.</li>
<li><code>bridgeDetected</code> - <code>1</code>, wenn der Host vor der Authentifizierung wie eine Tedee Bridge aussieht.</li>
<li><code>bridgeDetection</code> - Diagnosetext zur Bridge-Erkennung.</li>
<li><code>bridgeName</code> - Name der Tedee Bridge.</li>
<li><code>bridgeType</code> - Bridge-Typ, normalerweise <code>hardware</code>.</li>
<li><code>firmwareVersion</code> - Firmwareversion der Tedee Bridge.</li>
<li><code>hardwareId</code> - Hardware-ID / Seriennummer der Bridge.</li>
<li><code>serverConnected</code> - Cloud-Verbindungsstatus laut Bridge.</li>
<li><code>wifiFirmwareVersion</code> - Firmwareversion des WLAN-Moduls.</li>
<li><code>tokenStored</code> - <code>1</code>, wenn ein lokaler Token gespeichert ist.</li>
<li><code>tokenValid</code> - <code>1</code>, wenn der lokale Token akzeptiert wurde.</li>
<li><code>cloudTokenStored</code> - <code>1</code>, wenn ein Cloud PersonalKey gespeichert ist.</li>
<li><code>cloudStatus</code> - Cloud-Activity-Status, z. B. <code>connected</code> oder <code>http_error</code>.</li>
<li><code>callbackStatus</code> - Callback-Status, z. B. <code>active</code>, <code>registered</code>, <code>missing</code>, <code>error</code>.</li>
<li><code>locksCount</code> - Anzahl der von der Bridge gelieferten Schlösser.</li>
<li><code>activeLockId</code> - zuletzt/primär erkannte Lock-ID.</li>
<li><code>setupState</code> - geführter Setup-Zustand.</li>
<li><code>setupNext</code> - empfohlener nächster Setup-Schritt.</li>
<li><code>bridgeHealth</code> - zusammengefasster Gesundheitszustand, z. B. <code>ok</code> oder <code>degraded</code>.</li>
<li><code>lastError</code> - letzte relevante Fehlermeldung.</li>
</ul>

<a id="TedeeBridge-attributes"></a>
<b>Attribute</b>
<ul>
<li><code>disable 0|1</code><br>Standard: <code>0</code><br><code>0</code> = Bridge Device aktiv.<br><code>1</code> = Bridge Device deaktiviert.<br>Beispiel: <code>attr tedeeBridge1 disable 1</code></li>
<li><code>webhookFWinstance &lt;FHEMWEB-Device&gt;</code><br>FHEMWEB Instanz für Callback-Requests. Die ausgewählte Instanz muss von der Tedee Bridge per HTTP erreichbar und für Callbacks geeignet sein.<br>Beispiel: <code>attr tedeeBridge1 webhookFWinstance WEB</code></li>
<li><code>webhookHttpHostname &lt;IP-oder-FQDN&gt;</code><br>IP-Adresse oder DNS-Name zum Aufbau der Callback-URL.<br>Beispiel: <code>attr tedeeBridge1 webhookHttpHostname 192.0.2.20</code></li>
<li><code>tokenMode encrypted|plain</code><br>Standard: <code>encrypted</code><br><code>encrypted</code> = Token wird als verschlüsselter Tedee URL-Parameter mit Timestamp und SHA-256 Hash gesendet.<br><code>plain</code> = Token wird als einfacher <code>api_token</code> HTTP Header gesendet.<br>Beispiel: <code>attr tedeeBridge1 tokenMode encrypted</code></li>
<li><code>cloudApiVersion &lt;version&gt;</code><br>Standard: <code>v37</code><br>Tedee Cloud API Version für Activity-Requests.<br>Beispiel: <code>attr tedeeBridge1 cloudApiVersion v37</code></li>
<li><code>debugReadings 0|1</code><br>Standard: <code>0</code><br><code>0</code> = nur normale Bridge-Readings.<br><code>1</code> = zusätzliche Diagnose-Readings wie Request-Labels, HTTP-Statuscodes, Callback-Zähler, Device-ID-Listen oder Cloud-Diagnosen inklusive cloudRetryAfter bei HTTP 429.<br>Beispiel: <code>attr tedeeBridge1 debugReadings 1</code></li>
<li><code>devStateIcon</code><br>Standardbeispiel: <code>connected:10px-kreis-gruen:info disconnected:10px-kreis-rot:info error:10px-kreis-rot:info initialized:10px-kreis-gelb:info disabled:10px-kreis-gelb:info .*:10px-kreis-gelb:info</code><br>FHEM UI Icon-Mapping. Das Modul setzt standardmäßig einen farbigen Punkt: grün für connected, gelb für initialized/disabled oder unklar, rot für disconnected/error.</li>
</ul>

<p>The module uses an internal queue and guarantees at least one second between local bridge API requests.</p>
<a id="TedeeBridge-rate-limit"></a>
<b>Ratenlimit</b>
<ul>
<li>Die lokale Tedee Bridge API sollte maximal mit einem Request pro Sekunde angesprochen werden.</li>
<li>Das Modul queued lokale Requests und verarbeitet sie mit mindestens einer Sekunde Abstand.</li>
<li>Für Live-Updates sind Callbacks vorzuziehen. Häufiges manuelles Polling sollte vermieden werden.</li>
</ul>

<p>Callbacks are registered and renewed automatically during setup and callback reset.</p>
<a id="TedeeBridge-security"></a>
<b>Sicherheit</b>
<ul>
<li>Lokale Bridge- und Cloud-Token nur auf einem vertrauenswürdigen FHEM Host speichern.</li>
<li>FHEM oder die lokale Tedee Bridge API nicht direkt ins Internet exponieren.</li>
<li>Nach Möglichkeit Netzwerksegmentierung oder Firewalling verwenden.</li>
<li>Remote-Öffnen ist an jedem <code>TedeeDevice</code> standardmäßig deaktiviert und muss pro Device aktiviert werden.</li>
</ul>

=end html_DE

=for :application/json;q=META.json 73_TedeeBridge.pm
{
  "abstract": "controls Tedee smart locks via local bridge API",
  "x_lang": { "de": { "abstract": "steuert Tedee Smart Locks über lokale Bridge API" } },
  "version": "v0.7.29",
  "author": [ "50watt" ],
  "license": [ "same as FHEM" ],
  "prereqs": { "runtime": { "requires": { "perl": "5.014", "strict": 0, "warnings": 0, "FHEM::Meta": 0 } } },
  "x_fhem_maintainer": [ "50watt" ],
  "x_fhem_support": { "forum": "https://forum.fhem.de/" },
  "x_fhem_abstract": "controls Tedee smart locks via local bridge API",
  "x_fhem_abstract_DE": "steuert Tedee Smart Locks über lokale Bridge API",
  "x_fhem_keywords": [ "Tedee", "smart lock", "bridge", "local API", "cloud", "home automation" ]
}
=end :application/json;q=META.json

=cut
