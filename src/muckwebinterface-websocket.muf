!!@program muckwebinterface-websocket.muf
!!q
!!@reg muckwebinterface-websocket.muf=www/mwi/websocket
!!@set $www/mwi/websocket=W4
!!@set $www/mwi/websocket=L
!!@set $www/mwi/websocket=_type:noheader
!!@action websocket=#0,$www/mwi/websocket
!!@propset $www=dbref:_/www/mwi/ws:$www/mwi/websocket

@program $www/mwi/websocket
1 999999 d
i

( Work in progress )

$version 0.0
 
$include $lib/kta/strings
$include $lib/kta/misc
$include $lib/kta/proto
$include $lib/kta/json
$include $lib/account
 
$def allowCrossDomain 1        (Whether to allow cross-domain connections. This should only really be on during testing/development.)
$def heartbeatTime 2           (How frequently the heartbeat event triggers)
$def pingFrequency 4           (How often websocket connections are pinged)
$def maxPing 12                (If a ping request isn't responded to in this amount of seconds the connection will be flagged as disconnected)
 
$def protocolVersion "1" (Only clients that meet such are allowed to connect)
 
$ifdef is_dev
   $def allowCrossDomain 1
$endif

(Log levels:
   Error
   Notice  - Always output, core things
   Warning - Things that could be an error but might not be
   Info - Information above the individual session level, e.g. player or channel
   Trivial - Inner process information on an individual session level
   Packet - Really low level stuff such as building messages for ports
)
$def debugLevelWarning 1
$def debugLevelInfo 2
$def debugLevelTrivial 3
$def debugLevelAll 4
 
(Rest of the logs are optional depending on if they're turned on and thus behind gates to save processing times)
(For readibility the code between them should be indented)
$def _startLogWarning debugLevel @ debugLevelWarning >= if
$def _stopLogWarning "Warn" getLogPrefix swap strcat logstatus then
 
$def _startLogInfo debugLevel @ debugLevelInfo >= if
$def _stopLogInfo "Info" getLogPrefix swap strcat logstatus then
 
$def _startLogTrivial debugLevel @ debugLevelTrivial >= if
$def _stopLogTrivial "Spam" getLogPrefix swap strcat logstatus then
 
$def _startLogPacket debugLevel @ debugLevelAll >= if
$def _stopLogPacket "Pack" getLogPrefix swap strcat logstatus then
$def _stopLogPacketMultiple foreach nip "Pack" getLogPrefix swap strcat logstatus repeat then

svar connectionsBySession (Main collection of sessions)
svar sessionsByChannel ( {channel:[sessions]} )
svar sessionsByPlayer ( {playerAsInt:[sessions]} )
svar playersSessionsByChannel ( {channel:{player:[sessions]}} )
svar accountsSessionsByChannel ( {channel:{account:[sessions]}} )
svar serverProcess (PID of the server daemon)
svar bandwidthCounts
svar debugLevel (Loaded from disk on initialization but otherwise in memory to stop constant proprefs)

: getLogPrefix (s -- s) (Outputs the log prefix for the given type)
   "[MWI-WS " swap 4 right strcat " " strcat pid serverProcess @ over = if pop "" else intostr then 8 right strcat "] " strcat
;
 
: logError (s -- ) (Output definite problems)
  "!ERR" getLogPrefix swap strcat logstatus
;
 
: logNotice (s -- ) (Output important notices)
  "----" getLogPrefix swap strcat logstatus
;

: getSessions ( -- arr) (Return the session collection)
   connectionsBySession @
; archcall getSessions
 
: getCaches ( -- arr arr arr arr) (Return the caches)
   sessionsByChannel @
   sessionsByPlayer @
   playersSessionsByChannel @
   accountsSessionsByChannel @
; archcall getCaches 
 
: getDescrs ( -- arr) (Returns descrs the program is using)
   { }list
   connectionsBySession @ foreach nip
      "descr" array_getitem ?dup if
         swap array_appenditem
      then
   repeat
; PUBLIC getDescrs 
 
: getBandwidthCounts ( -- arr)
   bandwidthCounts @
; archcall getBandwidthCounts 
 
(Record bandwidth in the relevant bucket.)
: trackBandwidthCounts[ int:bytes str:bucket -- ]
   bandwidthCounts @ bucket @ array_getitem ?dup not if { }dict then
   "%Y/%m/%d %k" systime timefmt (S: thisBucket cacheableName)
   over if
      over over array_getitem dup not if (Remove oldest) (S: thisBucket cacheableName value)
         rot dup array_count 24 > if dup array_first pop array_delitem then rot rot
      then
   else nip { }dict swap 0 then (No entries exist, new bucket AND new value)
   bytes @ + rot rot array_setitem
   bandwidthCounts @ bucket @ array_setitem bandwidthCounts !
;
 
  (Produces a string with the items in sessionDetails for logging and debugging)
: sessionDetailsToString[ arr:details -- str:result ]
   details @ not if "[Invalid/Disconnected session]" exit then
   "Session " details @ "session" array_getitem dup not if pop "[NOSESSIONID]" then strcat "[" strcat
      "Descr:" details @ "descr" array_getitem intostr strcat strcat
      ", PID:" details @ "pid" array_getitem intostr strcat strcat
      ", Player:" details @ "player" array_getitem dup ok? if name else pop "-INVALID-" then strcat strcat
      ", Connection:" details @ "connectionType" array_getitem dup not if pop "???" then strcat strcat
   "]" strcat
;
 
  (Utility function - ideally call sessionDetails if already in possession of them)
: sessionToString[ str:session -- str:result ]
   connectionsBySession @ session @ array_getitem sessionDetailsToString
;

: ensureInit
   (Ensures variables are configured and server daemon is running)
   connectionsBySession @ dictionary? not if
      { }dict connectionsBySession !
      { }dict sessionsByChannel !
      { }dict sessionsByPlayer !
      { }dict playersSessionsByChannel !
      { }dict accountsSessionsByChannel !
      { }dict bandwidthCounts !
      "Initialised data structures." logNotice
      prog "debugLevel" getpropval debugLevel !
   then
   serverProcess @ ?dup if ispid? not if
      "Server process has stopped, attempting to restart." logError
      0 serverProcess !
   then then
   serverProcess @ not if
      0 prog "ServerStartup" queue serverProcess ! (Need to set immediately to prevent loops)
   then
;

  (Returns a value for the next session)
: createNewSessionID ( -- s)
   systime_precise intostr "-" "." subst "-" strcat random 1000 % intostr base64encode strcat
   ("select uuid()" mysql_value) ($lib/mysql - raw query)
   (mysql_uuid) ($lib/mysql)
   (get_uuid) ($lib/uuid)
;

: webSocketCreateAcceptKey (s -- s) (creates an accept key based upon the given handshake key as per the Websocket protocol)
  "258EAFA5-E914-47DA-95CA-C5AB0DC85B11" strcat (Magic key that gets added onto all requests)
  sha1hash
  $ifdef isprim(hex2base64str)
    hex2base64str (Special command to do the whole thing)
  $else
    (The base 64 encoding needs to encode the hex values not the string representation of them so we need to split this into sets of 2 and convert hex to chars)
    (NOTE: Earlier versions of ProtoMuck were unable to handle nullchars which would cause issues.)
    (This can be tested for - '0 itoc base64encode' should return 'AA==')
    "" over strlen 2 / 1 swap 1 for 2 * 1 - 3 pick swap 2 midstr htoi itoc strcat repeat base64encode swap pop
  $endif
;

: handleClientConnecting
	descr descr? not if exit then (Connections can be dropped immediately)
	prog "disabled" getpropstr "Y" instring if
		descr "HTTP/1.1 503 Service Unavailable\r\n" descrnotify descr "\r\n" descrnotify exit
	then
	systime var! connectedAt
	event_wait pop var! rawWebData
	
	(Ensure correct protocol version)
	rawWebData @ { "data" "CGIdata" "protocolVersion" 0 }list array_nested_get ?dup not if "" then
	protocolVersion stringcmp if
		descr "HTTP/1.1 400 Bad Request\r\n" descrnotify descr "\r\n" descrnotify
		descr "\r\n" descrnotify (This should only send only \r\n)
		descr "MWI-Websocket client is out of date, the muck expected a higher version." descrnotify
		exit
	then
	
	(At this point we're definitely trying to accept a websocket)
	_startLogPacket
		"New WebSocket connection from descr " descr intostr strcat
	_stopLogPacket
	
	rawWebData @ { "data" "HeaderData" "Sec-WebSocket-Key" }list array_nested_get ?dup not if
		_startLogWarning
			"Rejected new WebSocket connection from descr " descr intostr strcat " due to it missing the websocket key header. " strcat
		_stopLogWarning
		descr "HTTP/1.1 400 Bad Request\r\n" descrnotify descr "\r\n" descrnotify exit
	then
	webSocketCreateAcceptKey var! acceptKey
	{
		"HTTP/1.1 101 Switching Protocols"
		"Server: " version strcat
		"Connection: Upgrade"
		"Upgrade: websocket"
		allowCrossDomain if "Access-Control-Allow-Origin: *" then
		"Sec-WebSocket-Accept: " acceptKey @ strcat
		"Sec-WebSocket-Protocol: mwi"
	}list "\r\n" array_join
	$ifdef trackBandwidth
		dup strlen 4 + (2 \r\n's are going to get sent) "websocket_out" trackBandwidthCounts
	$endif
	descr swap descrnotify
	descr "\r\n" descrnotify (Since descrnotify trims excess \r\n's this will only output one)

	createNewSessionID var! session
	{
		"descr" descr
		"pid" pid
		"channels" { }list
		"properties" { }dict
		"connected" connectedAt
		"session" session @
	}dict var! sessionDetails
	sessionDetails @ connectionsBySession @ session @ array_setitem connectionsBySession !

	_startLogPacket
		"Descr " descr intostr strcat " now associated with " strcat session @ sessionToString strcat
	_stopLogPacket
	(TBC: Need to call handleSetPlayer later, when player is set!)
	(clientProcess)
	
	
	_startLogTrivial
		"Client process on " descr intostr strcat " ran for " strcat systime connectedAt @ - intostr strcat "s." strcat
	_stopLogTrivial

	
	sessionDetails @ arrayDump
;	
 
: serverDaemon
   "Server Process Started on PID " pid intostr strcat "." strcat logNotice
   prog "@lastUptime" systime setprop

;

: main
   ensureInit
   command @ "Queued event." stringcmp not if (Queued startup)
      dup "Startup" stringcmp not if exit then (The ensureinit command will trigger the actual startup as well as ensure structures are ready)
      dup "ServerStartup" stringcmp not if
         serverDaemon
         "Server Process somehow stoped." logError (Here to catch any unintentional exits)
      then
      exit
   then
   (Is this a connection?)
   command @ "(WWW)" stringcmp not if pop handleClientConnecting exit then
   me @ mlevel 5 > not if "Wiz-only command." .tell exit then
   
	dup "#debug" instring 1 = if
		6 strcut nip strip
		dup "" stringcmp not if
			"Valid values are: off, warning, info, trivial, all" .tell
			exit
		then
		0 "" (Level String)
		3 pick "off"      stringcmp not if pop pop 0                 "Off (Core notices and errors only)" then
		3 pick "warning"  stringcmp not if pop pop debugLevelWarning "Warning" then
		3 pick "info"     stringcmp not if pop pop debugLevelInfo    "Info" then
		3 pick "trivial"  stringcmp not if pop pop debugLevelTrivial "Trivial (Spammy)" then
		3 pick "all"      stringcmp not if pop pop debugLevelAll     "All (Super Spammy)" then
		rot pop dup if
			"Debug level set to: " swap strcat dup logNotice .tell
			debugLevel ! prog "debugLevel" debugLevel @ setprop
		else
			pop pop
			"Didn't recognize that debug level!" .tell
		then
		exit
	then
	
	"Work in progress" .tell


;
.
c
q