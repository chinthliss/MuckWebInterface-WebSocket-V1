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

( 
A program to provide websocket functionality between the muck and a web client.

This version works on top of the MuckWebInterface and is simplified since it doesn't require a HTTP stream.
 
The initial connection requires a 'token' that is retrieved from the main webpage, ensuring it handles authentication.

Present support - Websockets should now be universal and all the browsers that don't support them have been retired.

Assumes the muck takes time to re-use descrs, in particular that their is sufficient time to see a descr is disconnected before it is re-used.

Present understanding of descrnotify: will append a \r\n AND strip additional trailing ones. Will always trigger a descrflush.

Message are sent over channels, programs register to 'watch' a channel.
On each message the program looks for functions on registered programs in the form 'on<messsage>' and passes them the message.
These functions are called with the arguments 'channel, message, session, player, data'; Player may be #-1.

Communication is sent in the form of a three letter code prefixing the line. Message formats used:
MSGChannel,Message,Data
  Standard message sent over a channel. Data is JSON encoded
SYSMessage,Data
  System messages without a channel.
Ping / Pong - handled at the transport level if websocket but a system message on httpStreaming

Underlying transmission code attempts to minimize the amount encoding by not doing it for every recipient
Approximate transmission route:
[Public send request functions through various SendToX methods]
[Requests broken down into a list of sessions and the message, ending in sendMessageToSessions]
[Message is encoded appropriately once and sent to each websocket]

The session object stored in connectionsBySession:
    session: A copy of our session ID
    descr: Descr using session presently
    pid: PID of client process
    player: Associated player dbref
    account: Associated account - stored so we're not reliant on player for the reference
    channels: String list of channels joined
    connectedAt: Time of connection
    properties: keyValue list if properties set on a session
    ping: Last performance between ping sent and ping received
    lastPingOut: Systime_precise a pending ping was issued.
    lastPingIn: Systime_precise a pending ping was received

Properties on program:
    debugLevel: Present debug level. Only read on load, as it's then cached due to constant use.
    @channels/<channel>/<programDbref>:<program creation date> - Programs to receive messages for a channel.
    disabled:If Y the system will prevent any connections
)

(TBC: Ensure no references to firstconnect or lastconnection remain)

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

$pubdef : (Clear present _defs)

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

  (Whether session is valid and connected)
: isSession?[ str:session -- bool:result ]
    connectionsBySession @ session @ array_getitem if 1 else 0 then
; PUBLIC isSession? 

(Verifies string has no invalid characters for UTF8)
(At the moment this is anything with a value >= 128 since the last bit is used to express multi-byte characters in UTF8)
(Also stripping anything beneath 32 since, whilst supported by UTF8, HTML doesn't handle such.)
: ensureValidUTF8[ str:input -- str:output ]
    input @ string? not if "Invalid arguments" abort then
    input @ "[^\\x20-\\x7E]" "" reg_all regsub
;

: webSocketSendFrame (d:descr a:frameHeader ?:framepayload -- ) (Actually only works with strings but leaving some room for extension)
    dup string? not if "WebSocketSendFrame was called with a payload that isn't a string!" logError pop pop pop exit then
    _startLogPacket
        "WebSocket Out. Descr " 4 pick intostr strcat ": " strcat 3 pick foreach nip itoh strcat " " strcat repeat "| " strcat over strcat
    _stopLogPacket
    rot rot foreach nip (? d c)
        over swap notify_descriptor_char
    repeat
    swap descrnotify
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

(Returns a frame header of the given type. Because of issues converting text from the muck to UTF-8 it returns it as an array of ints)
: webSocketCreateFrameHeader[ int:opCode int:isFinal int:payloadSize -- arr:header ]
    (First byte contains type and whether this is the final frame)
    { opCode @ isFinal @ if 128 bitor then }list
    (Following byte uses first bit to specify if we're masked, which is always 0, then 7 bits of length.)
    (Depending on the size we'll either use 0, 2 or 8 additional bytes)
    payloadSize @ 2 + (Two additional bytes for the /r/n the muck will append)
    dup 126 < if (Fits in one byte)
        swap array_appenditem
    else swap
        over 65536 < if (Start with 126, then use two bytes to represent length)
            126 swap array_appenditem
            over -8 bitshift swap array_appenditem
            swap 255 bitand swap array_appenditem
        else (Start with 127 then use eight bytes to represent length)
            127 swap array_appenditem
            over 255 56 bitshift bitand swap array_appenditem
            over 255 48 bitshift bitand swap array_appenditem
            over 255 40 bitshift bitand swap array_appenditem
            over 255 32 bitshift bitand swap array_appenditem
            over 255 24 bitshift bitand swap array_appenditem
            over 255 16 bitshift bitand swap array_appenditem
            over 255  8 bitshift bitand swap array_appenditem
            swap 255 bitand swap array_appenditem
        then
    then
;

: webSocketCreateTextFrameHeader[ str:text -- arr:frameHeader ]
   1 1 text @ strlen webSocketCreateFrameHeader
;

: webSocketCreateClosingFrameHeader[ str:content -- arr:frameHeader ] (Takes content since the spec says to reflect any provided content in acknowledgements)
   8 1 content @ strlen webSocketCreateFrameHeader
;

: webSocketCreatePingFrameHeader[ str:content -- arr:frameHeader ]
   9 1 content @ strlen webSocketCreateFrameHeader
;

: webSocketCreatePongFrameHeader[ str:response -- arr:frameHeader ]
   10 1 response @ strlen webSocketCreateFrameHeader
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

: dispatchStringToSessions[ arr:sessions str:string -- ]
    string @ ensureValidUTF8 string !
    { }list var! descrs
    var session
    sessions @ dup array? not if pop exit then
    foreach nip session !
        connectionsBySession @ session @ array_getitem ?dup if
            dup "descr" array_getitem
            (S: sessionDetails Descr)
            dup descr? not if
                _startLogWarning
                    "Attempt to send string to invalid descr (possibly due to timely disconnect) on: " session @ sessionToString strcat
                _stopLogWarning
                (session @ deleteSession) (Don't delete here due to word not being available.)
                pop pop continue
            then
            descrs @ array_appenditem descrs !
        else
            _startLogWarning
                "Attempt to send string to a session that doesn't exist (possibly due to timely disconnect): " session @ strcat
            _stopLogWarning
        then
    repeat
    string @ webSocketCreateTextFrameHeader var! frameHeader
    $ifdef trackbandwidth
        descrs @ array_count string @ strlen frameHeader @ array_count + 2 + * "websocket_out" trackBandwidthCounts
    $endif
    descrs @ foreach nip frameHeader @ string @ webSocketSendFrame repeat
;

: prepareSystemMessage[ str:message ?:data -- str:encoded ]
    "SYS" message @ strcat "," strcat data @ encodeJson strcat
;

(Utility to continue a system message through and ensure it's logged)
: sendSystemMessageToSessions[ arr:sessions str:message ?:data -- ]
    message @ data @ prepareSystemMessage
    _startLogPacket
        { }list var! debugOutput
        sessions @ foreach nip
            "[>>] " message @ strcat " " strcat swap strcat ": " strcat over dup "," instr strcut nip strcat
            debugOutput @ array_appenditem debugOutput !
        repeat
        debugOutput @
    _stopLogPacketMultiple
    $ifdef trackBandwidth
        sessions @ array_count over strlen * 2 + "system_out" trackBandwidthCounts
    $endif
    sessions @ swap dispatchStringToSessions
;

: prepareMessage[ str:channel str:message ?:data -- str:encoded ]
    "MSG" channel @ strcat "," strcat message @ strcat "," strcat data @ encodeJson strcat
;

(This is the root function for sending - all sendTo functions break down their requirements to call this one)
(It assumes argument checking has been performed already)
: sendMessageToSessions[ arr:sessions str:channel str:message any:data -- ]
    sessions @ sessionsByChannel @ channel @ array_getitem ?dup if array_intersect else pop exit then (filter)
    ?dup not if exit then
    channel @ message @ data @ prepareMessage
    $ifdef trackBandwidth
        dup strlen 3 pick array_count * "channel_" channel @ strcat "_out" strcat trackBandwidthCounts
    $endif
    _startLogPacket
        { }list var! debugOutput
        sessions @ foreach nip
            "[>>][" channel @ strcat "." strcat message @ strcat "] " strcat swap strcat ": " strcat
            (Trim down to data part of outgoing string rather than processing it again)
            over dup "," instr strcut nip dup "," instr strcut nip strcat
            debugOutput @ array_appenditem debugOutput !
        repeat
        debugOutput @
    _stopLogPacketMultiple
    dispatchStringToSessions
;

: sendToSessions[ arr:sessions str:channel str:message any:data -- ]
    sessions @ array? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    sessions @ channel @ message @ data @ sendMessageToSessions
; PUBLIC sendToSessions 

: sendToSession[ str:session str:channel str:message any:data -- ]
    session @ string? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    session @ "" stringcmp not if "Session can't be blank" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    { session @ }list channel @ message @ data @ sendMessageToSessions
; PUBLIC sendToSession 

: sendToChannel[ str:channel str:message any:data -- ]
    channel @ string? message @ string? AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    sessionsByChannel @ channel @ array_getitem ?dup if channel @ message @ data @ sendMessageToSessions then
; PUBLIC sendToChannel 

: sendToPlayer[ dbref:player str:channel str:message any:data -- ]
    player @ dbref? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    player @ ok? not if "Player must be valid" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    playersSessionsByChannel @ { channel @ player @ int }list array_nested_get
    ?dup if
        channel @ message @ data @ sendMessageToSessions
    then
; PUBLIC sendToPlayer 

: sendToPlayers[ arr:players str:channel str:message any:data -- ]
    players @ array? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    { }list (Combined list) var player
    players @ foreach nip player !
        playersSessionsByChannel @ { channel @ player @ int }list array_nested_get
        ?dup if
            array_union
        then
    repeat
    channel @ message @ data @ sendMessageToSessions
; PUBLIC sendToPlayers 

: sendToAccount[ aid:account str:channel str:message any:data -- ]
    account @ int? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    account @ not if "Account can't be blank" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    accountsSessionsByChannel @ { channel @ account @ int }list array_nested_get
    ?dup if
        channel @ message @ data @ sendMessageToSessions
    then
; PUBLIC sendToAccount 

(Separate so that it can be called by internal processes)
: handleChannelCallbacks[ str:triggeringSession dbref:triggeringPlayer str:channel str:message any:data -- ]
    _startLogPacket
        "Handling message from " triggeringSession @ strcat "/" strcat triggeringPlayer @ unparseobj strcat " on MUCK: " strcat channel @ strcat ":" strcat message @ strcat
    _stopLogPacket
    depth var! startDepth
    "on" message @ strcat var! functionToCall var programToCall
    prog "@channels/" channel @ strcat "/" strcat array_get_propvals foreach (ProgramAsInt CreationDate)
        dup int? not if pop pop continue then
        swap atoi dbref dup program? not if pop pop continue then
        swap over timestamps 3 popn = not if pop pop continue then
        programToCall !
        programToCall @ functionToCall @ cancall? if
            channel @ message @ triggeringSession @ triggeringPlayer @ data @ programToCall @ functionToCall @
            7 try call catch_detailed
                var! error
                _startLogWarning
                "ERROR whilst handling " channel @ strcat "." strcat message @ strcat ": " strcat error @ unparseCatchDetailedError strcat
                _stopLogWarning
                programToCall @ owner dup ok? if
                    "[LiveConnect] The program " programToCall @ unparseobj strcat " crashed whilst handling '" strcat message @ strcat "'. Error: " strcat error @ unparseCatchDetailedError strcat notify
                else pop then
            endcatch
            (Check for misbehaving functions)
            depth startDepth @ > if
                _startLogWarning
                debug_line_str
                "Stack left with " depth 2 - (One for debug line, one for this line) startDepth @ - intostr strcat " extra item(s) after processing message " strcat
                channel @ strcat "." strcat message @ strcat ". Debug line=" strcat swap strcat
                _stopLogWarning
                debug_line_str
                programToCall @ owner dup ok? if
                    dup "[LiveConnect] The program " programToCall @ unparseobj strcat " left items on the stack after handling '" strcat message @ strcat "'. Debug line follows: " strcat notify
                    swap notify
                else pop pop then
                depth startDepth @ - popn
            then
        else
            _startLogTrivial
                "Couldn't find or call " programToCall @ unparseobj strcat ":" strcat functionToCall @ strcat " to handle an incoming packet (maybe intentional)" strcat
            _stopLogTrivial
        then
    repeat
;

( Note - also called when a connection changes player)
: handleJoinChannel[ str: session str:channel -- ]
    0 var! announceSession 0 var! announcePlayer 0 var! announceAccount
    connectionsBySession @ session @ array_getitem
    ?dup not if
        _startLogWarning
            "Attempt at unknown session " session @ strcat " trying to join channel: " strcat channel @ strcat "(Possibly okay if disconnected whilst joining)" strcat
        _stopLogWarning
        exit
    then
    dup var! sessionDetails
    dup "player" array_getitem ?dup not if #-1 then var! player
    "account" array_getitem var! account
    sessionDetails @ "channels" array_getitem
    dup channel @ array_findval not if
        channel @ swap array_appenditem
        sessionDetails @ "channels" array_setitem dup sessionDetails !
        connectionsBySession @ session @ array_setitem connectionsBySession !
        _startLogTrivial
            "Session " session @ strcat " joining channel " strcat channel @ strcat
        _stopLogTrivial
        (Cache - sessionsByChannel)
        sessionsByChannel @ channel @ array_getitem
        ?dup not if
            _startLogInfo
                "Channel now active: " channel @ strcat
            _stopLogInfo
            { }list
        then
        dup session @ array_findval not if
            session @ swap array_appenditem
            sessionsByChannel @ channel @ array_setitem sessionsByChannel !
            1 announceSession !
        else
            pop
            "Session " session @ strcat " joined channel '" strcat channel @ strcat "' but was already in sessionsByChannel list." strcat logerror
        then
    else pop then
    player @ ok? if (Handled separately as we're also called when player changes, though the caller should have removed old player references.)
        (Cache - playersSessionsByChannel)
        playersSessionsByChannel @ channel @ array_getitem ?dup not if { }dict then (ListForChannel)
        dup player @ int array_getitem ?dup not if { }list 1 announcePlayer ! then (ListForChannel ListForPlayer)
        dup session @ array_findval not if
            session @ swap array_appenditem
            swap player @ int array_setitem
            playersSessionsByChannel @ channel @ array_setitem playersSessionsByChannel !
        else pop pop then
        (Cache - accountsSessionsByChannel)
        accountsSessionsByChannel @ channel @ array_getitem ?dup not if { }dict then (ListForChannel)
        dup account @ array_getitem ?dup not if { }list 1 announceAccount ! then (ListForChannel ListForPlayer)
        dup session @ array_findval not if
            session @ swap array_appenditem
            swap account @ array_setitem
            accountsSessionsByChannel @ channel @ array_setitem accountsSessionsByChannel !
        else pop pop then
    then
    (Do external announcements first, since internal ones may cause callbacks to send messages out of order)
    announceSession @ if
        session @ channel @ "sessionConnected" systime sendToSession
    then
    announcePlayer @ if
        session @ channel @ "playerConnected" systime sendToSession
    then
    announceAccount @ if
        session @ channel @ "accountConnected" systime sendToSession
    then
    (Internal announcements)
    announceSession @ if
        session @ player @ channel @ "sessionEnteredChannel" session @ handleChannelCallbacks
    then
    announcePlayer @ if
        session @ player @ channel @ "playerEnteredChannel" player @ handleChannelCallbacks
    then
    announceAccount @ if
        session @ player @ channel @ "accountEnteredChannel" account @ handleChannelCallbacks
    then
;

(Utility function to call handleJoinChannel multiple times)
: handleJoinChannels[ str:session arr:channels -- ]
    channels @ foreach nip session @ swap handleJoinChannel repeat
;

(Removes from channel, updates appropriate caches and does player/account announcements if required)
(Should probably only be called from removePlayerFromSession?)
(Used retroactively - should NOT actually refer to sessionDetails as the reference may be out of date or gone.)
(Player may be a non-valid object reference from it being deleted)
: removePlayerSessionFromChannel[ str:session dbref:player int:account str:channel  -- ]
    _startLogTrivial
        "Removing Player:Session " player @ unparseobj strcat ":" strcat session @ strcat " from channel " strcat channel @ strcat
    _stopLogTrivial
    0 var! announcePlayer
    0 var! announceAccount
    player @ #-1 dbcmp not if ( Player could have been deleted so can't use ok? here)
        (Cache - playersSessionsByChannel)
        playersSessionsByChannel @ channel @ array_getitem ?dup if (ListByPlayersSessions)
            dup player @ int array_getitem ?dup if (ChannelPlayerSessionList PlayerSessionList)
                dup session @ array_findval ?dup if
                    foreach nip array_delitem repeat (ChannelPlayerSessionList PlayerSessionList SessionList)
                    ?dup if
                        swap player @ int array_setitem
                    else
                        player @ int array_delitem
                        1 announcePlayer ! (Last instance of player on channel)
                    then
                    (ChannelPlayerSessionList PlayerSessionList)
                    ?dup if
                        playersSessionsByChannel @ channel @ array_setitem
                    else
                        playersSessionsByChannel @ channel @ array_delitem
                    then
                    playersSessionsByChannel !
                else pop pop then
            else pop then
        then
        (Cache - accountsSessionsByChannel)
        accountsSessionsByChannel @ channel @ array_getitem ?dup if (ListByAccountsSessions)
            dup account @ array_getitem ?dup if (ChannelAccountSessionList AccountSessionList)
                dup session @ array_findval ?dup if
                    foreach nip array_delitem repeat (ChannelAccountSessionList AccountSessionList SessionList)
                    ?dup if
                        swap account @ array_setitem
                    else
                        account @ array_delitem
                        1 announceAccount ! (Last instance of account on channel)
                    then
                    (ChannelAccountSessionList AccountSessionList)
                    ?dup if
                        accountsSessionsByChannel @ channel @ array_setitem
                    else
                        accountsSessionsByChannel @ channel @ array_delitem
                    then
                    accountsSessionsByChannel !
                else pop pop then
            else pop then
        then
    then
    announcePlayer @ if
        session @ player @ channel @ "playerExitedChannel" player @ handleChannelCallbacks
    then
    announceAccount @ if
        session @ player @ channel @ "accountExitedChannel" account @ handleChannelCallbacks
    then
;

(Handles the non-channel specific removal parts of a player)
(Used retroactively - should NOT actually refer to sessionDetails as the reference may be out of date or gone.)
(Player may be a non-valid object reference from it being deleted)
: removePlayerFromSession[ str:session dbref:player int:account array:channels -- ]
    _startLogTrivial
        "Removing Player " player @ unparseobj strcat " from " strcat " session " strcat session @ strcat
    _stopLogTrivial
    channels @ foreach nip session @ player @ account @ 4 rotate removePlayerSessionFromChannel repeat
    sessionsByPlayer @ player @ int array_getitem
    ?dup if
        dup session @ array_findval ?dup if
            foreach nip array_delitem repeat
            ?dup if
                sessionsByPlayer @ player @ int array_setitem sessionsByPlayer !
            else
                sessionsByPlayer @ player @ int array_delitem sessionsByPlayer !
                (Last player session gone)
                _startLogTrivial
                "Doing _disconnect notification for " player @ unparseobj strcat
                _stopLogTrivial
                var propQueueEntry
                prog "_disconnect" array_get_propvals foreach swap propQueueEntry ! (S: prog)
                    dup string? if dup "$" instring if match else atoi then then dup dbref? not if dbref then
                    dup program? if
                        player @ 0 rot "wwwDisconnect" 4 try enqueue pop catch "Failed to enqueue _disconnect event '" propQueueEntry @ strcat "'." strcat logError endcatch
                    else pop (-prog) then
                repeat
            then
        else pop then
    then
;

(Removes from channel, updates appropriate caches and does session/player/account announcements if required)
(Doesn't handle player:session and account:session so should be called after removePlayerFromSession.)
: removeSessionFromChannel[ str:session dbref:player str:channel -- ]
    0 var! announceSession
    (Cache - sessionsByChannel)
    sessionsByChannel @ channel @ array_getitem ?dup if
        dup session @ array_findval ?dup if
            foreach nip array_delitem repeat
            ?dup if
                sessionsByChannel @ channel @ array_setitem sessionsByChannel !
            else
                sessionsByChannel @ channel @ array_delitem sessionsByChannel !
                _startLogInfo
                    "Channel inactive (last session left): " channel @ strcat
                _stopLogInfo
            then
            1 announceSession !
        else pop then
    then
    announceSession @ if
        session @ player @ channel @ "sessionExitedChannel" session @ handleChannelCallbacks
    then
;

: deleteSession[ str:session -- ]
    connectionsBySession @ session @ array_getitem ?dup if
        _startLogTrivial
            "Deleting session " session @ strcat
        _stopLogTrivial
        dup "channels" array_getitem var! channels
        dup "descr" array_getitem var! sessionDescr
        dup "connectionType" array_getitem var! connectionType
        dup "player" array_getitem ?dup not if #-1 else then var! player
        "account" array_getitem var! account
        player @ #-1 dbcmp not if session @ player @ account @ channels @ removePlayerFromSession then
        channels @ ?dup if
            foreach nip session @ player @ rot removeSessionFromChannel repeat
        then
        (Previously cleared session details first, trying to hold onto them until here now in case a callback tries to refer to them)
        connectionsBySession @ session @ array_delitem connectionsBySession !
        (Cleanly disconnect descr, though this will trigger pidwatch for full clearing up.)
        sessionDescr @ descr? if
            _startLogTrivial
                "Disconnecting still connected descr " sessionDescr @ intostr strcat " associated with " strcat session @ strcat
            _stopLogTrivial
            connectionType @ "httpstream" stringcmp not if
                sessionDescr @ "0" descrnotify
                sessionDescr @ "\r\n" descrnotify (This should output 0\r\n\r\n to close a http stream)
            else
                sessionDescr @ "" webSocketCreateClosingFrameHeader "" webSocketSendFrame
            then
            sessionDescr @ descrboot
        then
    else
      "Attempt to delete a non-existing session: " session @ strcat logError
    then
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
		"connectedAt" connectedAt @
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
    var eventArguments
    var eventName
    var toPing
    var session 
    var sessionDetails    
    { }dict var! clientPIDs (In the form pid:descr)
    "Server Process Started on PID " pid intostr strcat "." strcat logNotice
    prog "@lastUptime" systime setprop
    background 1 "heartbeat" timer_start
    begin 1 while
        event_wait eventName ! eventArguments !
        eventName @ case
            "TIMER.heartbeat" stringcmp not when
                serverProcess @ pid = not if "ServerProcess shutting down since we don't match the expected pid of " serverProcess @ intostr strcat logError exit then
                heartbeatTime "heartbeat" timer_start
                { }list toPing !
                connectionsBySession @ foreach
                    sessionDetails ! session !
                    sessionDetails @ "pid" array_getitem ispid? not if
                        _startLogTrivial
                            "Disconnecting " session @ sessionToString strcat " due to PID being dead." strcat
                        _stopLogTrivial
                        session @ deleteSession continue
                    then
                    sessionDetails @ "descr" array_getitem descr? not if
                        _startLogTrivial
                            "Disconnecting " session @ sessionToString strcat " due to descr being disconnected." strcat
                        _stopLogTrivial
                        session @ deleteSession continue
                    then
                    (Ping related)
                    sessionDetails @ "lastPingOut" array_getitem sessionDetails @ "lastPingIn" array_getitem
                    over over > if (If lastPingOut is higher we're expecting a response. On initial connect or reconnect both are 0)
                        pop systime_precise swap - maxPing > if
                            _startLogTrivial
                                "Disconnecting " session @ sessionToString strcat " due to no response to ping." strcat
                            _stopLogTrivial
                            session @ deleteSession continue
                        then
                    else (Otherwise we're eligible to be pinged)
                        nip (keep last in) sessionDetails @ "connectedAt" array_getitem math.max
                        systime_precise swap - (Time since last ping or initial connection)
                        pingFrequency - 0 > if
                            1 sessionDetails @ "descr" array_getitem ?dup if toPing @ array_appenditem toPing ! then
                        else 0 then
                        if (update lastPingOut record)
                            systime_precise sessionDetails @ "lastPingOut" array_setitem
                            dup sessionDetails ! connectionsBySession @ session @ array_setitem connectionsBySession !
                        then
                    then
                repeat
                _startLogTrivial
                    "Heartbeat. Connections: " connectionsBySession @ array_count intostr strcat
                    ". Caches - ByChannel: " strcat sessionsByChannel @ array_count intostr strcat
                    ", ByPlayer: " strcat sessionsByPlayer @ array_count intostr strcat
                    ", SessionsByPlayerByChannel: " strcat playersSessionsByChannel @ array_count intostr strcat
                    ", SessionsByAccountByChannel: " strcat accountsSessionsByChannel @ array_count intostr strcat
                    ". Outgoing Pings: " strcat toPing @ array_count intostr strcat
                _stopLogTrivial
                toPing @ ?dup if
                    systime_precise intostr dup webSocketCreatePingFrameHeader swap
                    (S: ArrayOfDescrs PingFrameHeader PingFramePayload)
                    $ifdef trackBandwidth
                        3 pick array_count 3 pick array_count 3 pick strlen 2 + + * "websocket_out" trackBandwidthCounts
                    $endif
                    rot foreach nip
                        3 pick 3 pick webSocketSendFrame
                    repeat
                    pop pop
                then
            end
            default
                "ERROR: Heartbeat thread got an unrecognized event: " swap strcat logError
            end
        endcase
        depth ?dup if "Heartbeat's stack had " swap intostr strcat " item(s). Debug_line follows:" strcat logError debug_line_str logError depth popn then
    repeat
;

: main
    ensureInit
    command @ "Queued event." stringcmp not if (Queued startup)
        dup "Startup" stringcmp not if exit then (The ensureinit command will trigger the actual startup as well as ensure structures are ready)
        dup "ServerStartup" stringcmp not if
            pop serverDaemon (This should run indefinitely)
            "Server Process somehow stoped." logError
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