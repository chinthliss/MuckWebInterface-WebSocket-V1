!!@program muckwebinterface-websocket.muf
!!q
!!@reg muckwebinterface-websocket.muf=www/mwi/websocket
!!@set $www/mwi/websocket=W4
!!@set $www/mwi/websocket=L
!!@set $www/mwi/websocket=A
!!@set $www/mwi/websocket=_type:noheader
!!@action websocket=#0,$www/mwi/websocket
!!@propset $www=dbref:_/www/mwi/ws:$www/mwi/websocket

@edit $www/mwi/websocket
1 999999 d
i

( 
A program to provide websocket functionality between the muck and a webpage via a websocket.
It provides functionality to support the webpage, it is NOT the program that handles the direct webclient.

This version works on top of the MuckWebInterface and is greatly simplified from the previous version since it doesn't require a HTTP stream.
 
The initial connection requires a 'token' that is retrieved from the main webpage, ensuring it handles authentication.

Present support - Websockets should now be universal and all the browsers that don't support them have been retired.

Assumes the muck takes time to re-use descrs, in particular that their is sufficient time to see a descr is disconnected before it is re-used.

Message are sent over channels, programs register to 'watch' a channel.
On each message the program looks for functions on registered programs in the form 'on<messsage>' and passes them the message.
These functions are called with the arguments 'channel, message, descr, player, data'; Player may be #-1.

Communication is sent in the form of a three letter code prefixing the line. Message formats used:
MSGChannel,Message,Data       Standard message sent over a channel. Data is JSON encoded
SYSMessage,Data               System messages without a channel.
Ping / Pong                   Handled at the transport level

Underlying transmission code attempts to minimize the amount encoding by not doing it for every recipient
Approximate transmission route:
[Public send request functions through various SendToX methods]
[Requests broken down into a list of descrs and the message, ending in sendMessageToDescrs]
[Message is encoded appropriately once and sent to each websocket]

The connection details stored in connections:
    descr: Descr for connection. The dictionary is also indexed by this.
    pid: PID of client process
    player: Associated player dbref
    account: Associated account - stored so we're not reliant on player for the reference
    channels: String list of channels joined
    connectedAt: Time of connection
    acceptedAt: Time connection handshake completed
    properties: keyValue list if properties set on a connection
    ping: Last performance between ping sent and ping received
    lastPingOut: Systime_precise a pending ping was issued.
    lastPingIn: Systime_precise a pending ping was received

Properties on program:
    debugLevel: Present debug level. Only read on load, as it's then cached due to constant use.
    @channels/<channel>/<programDbref>:<program creation date> - Programs to receive messages for a channel.
    disabled:If Y the system will prevent any connections
)

(TBC: Ensure no references to firstconnect, lastconnection, connectiontype, upgrading or httpstream remain)

$version 0.0
 
$include $lib/kta/strings
$include $lib/kta/misc
$include $lib/kta/proto
$include $lib/kta/json
$include $lib/account
$include $lib/websocketIO

$pubdef : (Clear present _defs)

$libdef websocketIssueAuthenticationToken
$libdef getConnections
$libdef getCaches
$libdef getDescrs
$libdef getBandwidthCounts
$libdef connectionsFromPlayer
$libdef playerUsingChannel?
$libdef accountUsingChannel?
$libdef playersOnChannel
$libdef playersOnWeb
$libdef setConnectionProperty
$libdef getConnectionProperty
$libdef delConnectionProperty
$libdef sendToDescrs
$libdef sendToDescr
$libdef sendToChannel
$libdef sendToPlayer
$libdef sendToPlayers
$libdef sendToAccount

$def allowCrossDomain 1        (Whether to allow cross-domain connections. This should only really be on during testing/development.)
$def heartbeatTime 2           (How frequently the heartbeat event triggers)
$def pingFrequency 4           (How often websocket connections are pinged)
$def maxPing 12                (If a ping request isn't responded to in this amount of seconds the connection will be flagged as disconnected)
 
$def protocolVersion "1" (Only clients that meet such are allowed to connect)
 
$ifdef is_dev
   $def allowCrossDomain 1
$endif

(Log levels:
   Error   - Always output
   Notice  - Always output, core things
   Warning - Things that could be an error but might not be
   Info    - Information above the individual connection level, e.g. player or channel
   Debug   - Inner process information on an individual connection level, often spammy
)
$def debugLevelWarning 1
$def debugLevelInfo 2
$def debugLevelTrivial 3
$def debugLevelAll 4
 
(Rest of the logs are optional depending on if they're turned on and thus behind gates to save processing times)
(For readibility the code between them should be indented)
$def _startLogWarning debugLevel @ debugLevelWarning >= if
$def _stopLogWarning " Warn" getLogPrefix swap strcat logstatus then
 
$def _startLogInfo debugLevel @ debugLevelInfo >= if
$def _stopLogInfo " Info" getLogPrefix swap strcat logstatus then
 
$def _startLogDebug debugLevel @ debugLevelAll >= if
$def _stopLogDebug "Debug" getLogPrefix swap strcat logstatus then
$def _stopLogDebugMultiple foreach nip "Debug" getLogPrefix swap strcat logstatus repeat then

svar connections (Main collection of connections, indexed by descr)
svar cacheByChannel ( {channel:[descr..]} )
svar cacheByPlayer ( {playerAsInt:[descr..]} )
svar cacheByAccount ( {accountAsInt:[descr..]} )
svar serverProcess (PID of the server daemon)
svar bandwidthCounts
svar debugLevel (Loaded from disk on initialization but otherwise in memory to stop constant proprefs)

: getLogPrefix (s -- s) (Outputs the log prefix for the given type)
    "[MWI-WS " swap 5 right strcat " " strcat pid serverProcess @ over = if pop "" else intostr then 8 right strcat "] " strcat
;
 
: logError (s -- ) (Output definite problems)
    "ERROR" getLogPrefix swap strcat logstatus
;
 
: logNotice (s -- ) (Output important notices)
    "-----" getLogPrefix swap strcat logstatus
;

: getConnections ( -- arr) (Return the connection collection)
    connections @
; archcall getConnections
 
: getCaches ( -- arr arr arr ) (Return the caches)
    cacheByChannel @ 
    cacheByPlayer @
    cacheByAccount @
; archcall getCaches 
 
: getDescrs ( -- arr) (Returns descrs the program is using, so other programs know they're reserved)
    { }list
    connections @ foreach pop swap array_appenditem repeat
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
 
  (Produces a string with the items in ConnectionDetails for logging and debugging)
: connectionDetailsToString[ arr:details -- str:result ]
    details @ not if "[Invalid/Disconnected Connection]" exit then
        "[Descr " details @ "descr" array_getitem intostr strcat
        ", PID:" details @ "pid" array_getitem intostr strcat strcat
        ", Account:" details @ "account" array_getitem ?dup not if "-UNSET-" else intostr then strcat strcat        
        ", Player:" details @ "player" array_getitem ?dup not if "-UNSET-" else dup ok? if name else pop "-INVALID-" then then strcat strcat
    "]" strcat
;
 
  (Utility function - ideally call connectiondetailsToString directly if already in possession of them)
: DescrToString[ str:who -- str:result ]
    connections @ who @ array_getitem connectionDetailsToString
;

: ensureInit
    (Ensures variables are configured and server daemon is running)
    connections @ dictionary? not if
        { }dict connections !
        { }dict cacheByChannel !
        { }dict cacheByPlayer !
        { }dict cacheByAccount !
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

: websocketIssueAuthenticationToken[ aid:account dbref?:character -- str:token ]
    systime_precise intostr "-" "." subst "-" strcat random 1000 % intostr base64encode strcat var! token
    prog "@tokens/" token @ strcat "/issued" strcat systime setprop
    prog "@tokens/" token @ strcat "/account" strcat account @ setprop
    character @ if 
        prog "@tokens/" token @ strcat "/character" strcat character @ setprop
    then
    token @
; wizcall websocketIssueAuthenticationToken

  (Quicker way to check to see if a player is using the connection framework)
: connectionsFromPlayer[ dbref:player -- int:connections ]
    player @ player? not if "Invalid Arguments" abort then
    cacheByPlayer @ player @ int array_getitem ?dup if array_count else 0 then
; PUBLIC connectionsFromPlayer 
 
  (Quicker function to verify if a player is on the given channel)
: playerUsingChannel?[ dbref:player str:channel -- int:bool ]
    cacheByPlayer @ player @ int array_getitem ?dup not if 0 exit then
    cacheByChannel @ channel @ array_getitem ?dup not if pop 0 exit then
    array_intersect array_count
; PUBLIC playerUsingChannel? 

  (Quicker function to verify if a player is on the given channel)
: accountUsingChannel?[ dbref:player int:account -- int:bool ]
    cacheByAccount @ account @ int array_getitem ?dup not if 0 exit then
    cacheByChannel @ channel @ array_getitem ?dup not if pop 0 exit then
    array_intersect array_count
; PUBLIC accountUsingChannel? 
 
  (Returns a list of players on the given channel.)
: playersOnChannel[ str:channel -- list:players ]
   { }list
   cacheByChannel @ channel @ array_getitem ?dup if
      foreach pop connections @ array_getitem
        "player" array_getitem dup player? if swap array_appenditem else pop then
      repeat
      1 array_union
   then
; PUBLIC playersOnChannel 
 
  (Returns a list of everyone connected)
: playersOnWeb[ -- list:players ]
    { }list
    cacheByPlayer @ foreach pop
        dbref dup player? if swap array_appenditem else pop then
    repeat
; PUBLIC playersOnWeb 

: setConnectionProperty[ int:who str:property any:data -- ]
    who @ int? property @ string? AND not if "setConnectionProperty: Invalid arguments" abort then
    connections @ who @ array_getitem ?dup not if exit then
    dup "properties" array_getitem data @ swap property @ array_setitem
    swap "properties" array_setitem connections @ who @ array_setitem connections !
; PUBLIC setConnectionProperty 
 
: getConnectionProperty[ int:who str:property -- any:data ]
    who @ int? property @ string? AND not if "getConnectionProperty: Invalid arguments" abort then
    connections @ who @ array_getitem ?dup not if 0 exit then
    "properties" array_getitem property @ array_getitem
; PUBLIC getConnectionProperty 
 
: delConnectionProperty[ int:who str:property -- ]
    who @ int? property @ string? AND not if "delConnectionProperty: Invalid arguments" abort then
    connections @ who @ array_getitem ?dup not if exit then
    dup "properties" array_getitem property @ array_delitem
    swap "properties" array_setitem connections @ who @ array_setitem connections !
; PUBLIC delConnectionProperty 

: dispatchStringToDescrs[ arr:descrs str:string -- ]
    string @ ensureValidUTF8 string !
    { }list var! descrs
    $ifdef trackbandwidth
        descrs @ array_count string @ strlen array_count 2 + * "websocket_out" trackBandwidthCounts
    $endif
    descrs @ string @ webSocketSendTextFrameToDescrs
;

: prepareSystemMessage[ str:message ?:data -- str:encoded ]
    "SYS" message @ strcat "," strcat data @ encodeJson strcat
;

: prepareChannelMessage[ str:channel str:message ?:data -- str:encoded ]
    "MSG" channel @ strcat "," strcat message @ strcat "," strcat data @ encodeJson strcat
;

(Utility to continue a system message through and ensure it's logged)
: sendSystemMessageToDescrs[ arr:descrs str:message ?:data -- ]
    message @ data @ prepareSystemMessage
    $ifdef trackBandwidth
        descrs @ array_count over strlen * 2 + "system_out" trackBandwidthCounts
    $endif
    _startLogDebug
        { }list var! debugOutput
        descrs @ foreach nip
            "[>>] " message @ strcat " " strcat swap strcat ": " strcat over dup "," instr strcut nip strcat
            debugOutput @ array_appenditem debugOutput !
        repeat
        debugOutput @
    _stopLogDebugMultiple
    descrs @ swap dispatchStringToDescrs
;

(This is the root function for sending - all sendTo functions break down their requirements to call this one)
(It assumes argument checking has been performed already)
: sendChannelMessageToDescrs[ arr:descrs str:channel str:message any:data -- ]
    channel @ message @ data @ prepareMessage
    $ifdef trackBandwidth
        message @ strlen descrs @ array_count * "channel_" channel @ strcat "_out" strcat trackBandwidthCounts
    $endif
    _startLogDebug
        { }list var! debugOutput
        descrs @ foreach nip
            "[>>][" channel @ strcat "." strcat message @ strcat "] " strcat swap strcat ": " strcat
            (Trim down to data part of outgoing string rather than processing it again)
            over dup "," instr strcut nip dup "," instr strcut nip strcat
            debugOutput @ array_appenditem debugOutput !
        repeat
        debugOutput @
    _stopLogDebugMultiple
    descrs @ swap dispatchStringToDescrs
;

: sendToDescrs[ arr:descrs str:channel str:message any:data -- ]
    descrs @ array? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    descrs @ channel @ message @ data @ sendChannelMessageToDescrs
; PUBLIC sendToDescrs 

: sendToDescr[ str:who str:channel str:message any:data -- ]
    who @ int? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    who @ "" stringcmp not if "Who can't be blank" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    { who @ }list channel @ message @ data @ sendChannelMessageToDescrs
; PUBLIC sendToDescr 

: sendToChannel[ str:channel str:message any:data -- ]
    channel @ string? message @ string? AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    cacheByChannel @ channel @ array_getitem ?dup if channel @ message @ data @ sendChannelMessageToDescrs then
; PUBLIC sendToChannel 

: sendToPlayer[ dbref:player str:channel str:message any:data -- ]
    player @ dbref? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    player @ ok? not if "Player must be valid" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    cacheByPlayer @ player @ int array_getitem ?dup not if 0 exit then
    cacheByChannel @ channel @ array_getitem ?dup not if pop 0 exit then
    array_intersect
    ?dup if
        channel @ message @ data @ sendChannelMessageToDescrs
    then
; PUBLIC sendToPlayer 

: sendToPlayers[ arr:players str:channel str:message any:data -- ]
    players @ array? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    { }list (Combined list) var player
    players @ foreach nip player !
        cacheByPlayer @ player @ int array_getitem ?dup not if 0 exit then
        cacheByChannel @ channel @ array_getitem ?dup not if pop 0 exit then
        array_intersect
        ?dup if
            array_union
        then
    repeat
    channel @ message @ data @ sendChannelMessageToDescrs
; PUBLIC sendToPlayers 

: sendToAccount[ aid:account str:channel str:message any:data -- ]
    account @ int? channel @ string? message @ string? AND AND not if "Invalid arguments" abort then
    account @ not if "Account can't be blank" abort then
    message @ "" stringcmp not if "Message can't be blank" abort then
    channel @ "" stringcmp not if "Channel can't be blank" abort then
    cacheByAccount @ account @ int array_getitem ?dup not if 0 exit then
    cacheByChannel @ channel @ array_getitem ?dup not if pop 0 exit then
    array_intersect
    ?dup if
        channel @ message @ data @ sendChannelMessageToDescrs
    then
; PUBLIC sendToAccount 

(Separate so that it can be called by internal processes)
: handleChannelCallbacks[ int:triggeringDescr dbref:triggeringPlayer str:channel str:message any:data -- ]
    _startLogDebug
        "Handling message from " triggeringDescr @ int strcat "/" strcat triggeringPlayer @ unparseobj strcat " on MUCK: " strcat channel @ strcat ":" strcat message @ strcat
    _stopLogDebug
    depth var! startDepth
    "on" message @ strcat var! functionToCall var programToCall
    prog "@channels/" channel @ strcat "/" strcat array_get_propvals foreach (ProgramAsInt CreationDate)
        dup int? not if pop pop continue then
        swap atoi dbref dup program? not if pop pop continue then
        swap over timestamps 3 popn = not if pop pop continue then
        programToCall !
        programToCall @ functionToCall @ cancall? if
            channel @ message @ triggeringDescr @ triggeringPlayer @ data @ programToCall @ functionToCall @
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
            _startLogDebug
                "Couldn't find or call " programToCall @ unparseobj strcat ":" strcat functionToCall @ strcat " to handle an incoming packet (maybe intentional)" strcat
            _stopLogDebug
        then
    repeat
;

: sendChannelConnectionAnnouncements[ str:channel int:who dbref:player int:account sendDescrNotifications sendPlayerNotifications sendAccountNotifications -- ]
    (Do announcements to client first, since callbacks may cause messages to send out of order)
    sendDescrNotifications @ if
        who @ channel @ "descrConnected" systime sendToDescr
    then
    sendPlayerNotifications @ if
        who @ channel @ "playerConnected" systime sendToDescr
    then
    sendAccountNotifications @ if
        who @ channel @ "accountConnected" systime sendToDescr
    then
    (And then process callbacks)
    sendDescrNotifications @ if
        who @ player @ channel @ "descrEnteredChannel" who @ handleChannelCallbacks
    then
    sendPlayerNotifications @ if
        who @ player @ channel @ "playerEnteredChannel" player @ handleChannelCallbacks
    then
    sendAccountNotifications @ if
        who @ player @ channel @ "accountEnteredChannel" account @ handleChannelCallbacks
    then
;

: addConnectionToChannel[ int:who str:channel -- ]
    0 var! announceDescr 0 var! announcePlayer 0 var! announceAccount
    connections @ who @ array_getitem
    ?dup not if
        _startLogWarning
            "Attempt at unknown descr " who @ strcat " trying to join channel: " strcat channel @ strcat "(Possibly okay if disconnected whilst joining)" strcat
        _stopLogWarning
        exit
    then
    dup var! connectionDetails
    dup "player" array_getitem ?dup not if #-1 then var! player
    "account" array_getitem var! account
    connectionDetails @ "channels" array_getitem
    dup channel @ array_findval not if
        channel @ swap array_appenditem
        connectionDetails @ "channels" array_setitem dup connectionDetails !
        connections @ who @ array_setitem connections !
        _startLogDebug
            "Descr " who @ strcat " joining channel " strcat channel @ strcat
        _stopLogDebug
        (Cache - byChannel)
        cacheByChannel @ channel @ array_getitem
        ?dup not if
            _startLogInfo
                "Channel now active: " channel @ strcat
            _stopLogInfo
            { }list
        then
        (Check if we need to do announcements about player / account joining channel if they weren't on it previously)
        player @ ok? if
            player @ channel @ playerUsingChannel? not announcePlayer !
        then
        account @ if
            account @ channel @ accountUsingChannel? not announceAccount !
        then
        (Cache - ByChannel)
        dup who @ array_findval not if
            who @ swap array_appenditem
            cacheByChannel @ channel @ array_setitem cacheByChannel !
        else
            pop
            "Descr " who @ strcat " joined channel '" strcat channel @ strcat "' but was already in channel cache." strcat logerror
        then
    else pop then
    (Send announcements as required)
    channel @ who @ player @ account @
    announceDescr @ announcePlayer @ announceAccount @ sendChannelConnectionAnnouncements
    
;

(Utility function to call addToChannel multiple times)
: addConnectionToChannels[ str:session arr:channels -- ]
    channels @ foreach nip session @ swap handleJoinChannel repeat
;

(Removes from channel, updates appropriate caches and does player/account announcements if required)
(Should probably only be called from removePlayerAndAccountFromSession?)
(Used retroactively - should NOT actually refer to sessionDetails as the reference may be out of date or gone.)
(Player may be a non-valid object reference from it being deleted)
: removeSessionsPlayerAndAccountFromChannel[ str:session dbref:player int:account str:channel  -- ]
    0 var! announcePlayer
    0 var! announceAccount
    player @ #-1 dbcmp not if ( Player could have been deleted so can't use ok? here)
        _startLogDebug
            "Removing Player:Session " player @ unparseobj strcat ":" strcat session @ strcat " from channel " strcat channel @ strcat
        _stopLogDebug
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
    then
    _startLogDebug
        "Removing Account:Session " account @ intostr strcat ":" strcat session @ strcat " from channel " strcat channel @ strcat
    _stopLogDebug
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

    announcePlayer @ if
        session @ player @ channel @ "playerExitedChannel" player @ handleChannelCallbacks
    then
    announceAccount @ if
        session @ player @ channel @ "accountExitedChannel" account @ handleChannelCallbacks
    then
;

(Used retroactively - should NOT actually refer to sessionDetails as the reference may be out of date or gone.)
(Player may be a non-valid object reference from it being deleted)
: unsetPlayerAndAccountonConnection[ str:session dbref:player int:account array:channels -- ]
    _startLogDebug
        "Removing Player " player @ unparseobj strcat " from " strcat " session " strcat session @ strcat
    _stopLogDebug
    channels @ foreach nip session @ player @ account @ 4 rotate removeSessionsPlayerAndAccountFromChannel repeat
    sessionsByPlayer @ player @ int array_getitem
    ?dup if
        dup session @ array_findval ?dup if
            foreach nip array_delitem repeat
            ?dup if
                sessionsByPlayer @ player @ int array_setitem sessionsByPlayer !
            else
                sessionsByPlayer @ player @ int array_delitem sessionsByPlayer !
                (Last player session gone)
                _startLogDebug
                "Doing _disconnect notification for " player @ unparseobj strcat
                _stopLogDebug
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
(Doesn't handle player:session and account:session so should be called after removePlayerAndAccountFromSession.)
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
        _startLogDebug
            "Deleting session " session @ strcat
        _stopLogDebug
        dup "channels" array_getitem var! channels
        dup "descr" array_getitem var! sessionDescr
        dup "player" array_getitem ?dup not if #-1 else then var! player
        "account" array_getitem var! account
        session @ player @ account @ channels @ removePlayerAndAccountFromSession
        channels @ ?dup if
            foreach nip session @ player @ rot removeSessionFromChannel repeat
        then
        (Previously cleared session details first, trying to hold onto them until here now in case a callback tries to refer to them)
        connectionsBySession @ session @ array_delitem connectionsBySession !
        (Cleanly disconnect descr, though this will trigger pidwatch for full clearing up.)
        sessionDescr @ descr? if
            _startLogDebug
                "Disconnecting still connected descr " sessionDescr @ intostr strcat " associated with " strcat session @ strcat
            _stopLogDebug
            { sessionDescr @ }list systime_precise intostr webSocketSendCloseFrameToDescrs
            sessionDescr @ descrboot
        then
    else
      "Attempt to delete a non-existing session: " session @ strcat logError
    then
;

: handleSetPlayer[ str:session dbref:player -- ]
    connectionsBySession @ session @ array_getitem
    ?dup if
        dup "channels" array_getitem var! channels
        dup "player" array_getitem ?dup not if #-1 then var! oldPlayer
        "account" array_getitem var! oldAccount
        oldPlayer @ #-1 dbcmp not if (Could possibly split this out as this will remove the account:session reference then reset it and potentially trigger disconnect/connect message)
            oldplayer @ player @ dbcmp if exit then
            session @ oldPlayer @ oldAccount @ channels @ removePlayerAndAccountFromSession
        then
        _startLogDebug
            "Setting player of session " session @ strcat " to " strcat player @ unparseobj strcat
            oldplayer @ #-1 dbcmp not if " (Previously " strcat oldPlayer @ unparseobj strcat ")" strcat then
        _stopLogDebug
        player @ connectionsBySession @ session @ array_getitem "player" array_setitem
        (Setting acount here since they're handled from the muck through the player reference)
        (Presently not unsetting an account though, since such shouldn't change)
        player @ dup ok? if acct_any2aid else pop 0 then ?dup if
            swap "account" array_setitem
        then
        connectionsBySession @ session @ array_setitem connectionsBySession !
        player @ ok? if
            (Ensure channels deal with the change)
            channels @ ?dup if session @ swap handleJoinChannels then
            (Cache - sessions by player)
            sessionsByPlayer @ player @ int array_getitem
            ?dup not if
                { }list (First session, treat as new connect)
                _startLogDebug
                "Doing _connect notification for " player @ unparseobj strcat
                _stopLogDebug
                prog "_connect" array_get_propvals foreach swap var! propQueueEntry (S: prog)
                dup string? if dup "$" instring if match else atoi then then dup dbref? not if dbref then
                dup program? if
                    player @ 0 rot "wwwConnect" 4 try enqueue pop catch "Failed to enqueue _connect event '" propQueueEntry @ strcat "'." strcat logError endcatch
                then
                repeat
            then
            dup session @ array_findval if pop else session @ swap array_appenditem sessionsByPlayer @ player @ int array_setitem sessionsByPlayer ! then
        then
    else
        "Attempt to set/clear player from invalid session: " session @ strcat logerror
    then
;
 
: handlePingResponse[ str:session float:pingResponse -- ]
    connectionsBySession @ session @ array_getitem
    ?dup if (Occasionally sessions witnessed being deleted before a ping response is dealt with)
        var! sessionDetails
        systime_precise sessionDetails @ "lastPingIn" array_setitem sessionDetails !
        systime_precise sessionDetails @ "lastPingOut" array_getitem - sessionDetails @ "ping" array_setitem sessionDetails !
        sessionDetails @ connectionsBySession @ session @ array_setitem connectionsBySession !
    then
;
 
: handleIncomingSystemMessage[ str:session str:message str:dataAsJson ] (Session should already be confirmed to be valid.)
    session @ not message @ not OR if "handleIncomingSystemMessageFrom called with either session or message blank." logError exit then
    _startLogDebug
        "[<<] " message @ strcat " " strcat session @ strcat ": " strcat dataAsJson @ strcat
    _stopLogDebug
    $ifdef trackBandwidth
        message @ strlen "system_in" trackBandwidthCounts
    $endif
    dataAsJson @ if
        0 try
            dataAsJson @ decodeJson
        catch
            "Failed to decode JSON whilst handling System Message '" message @ strcat "':" strcat dataAsJson @ strcat logError
            exit
        endcatch
    else "" then var! data
    message @ case
        "joinChannels" stringcmp not when
            session @ data @ dup string? if addConnectionToChannel else addConnectionToChannels then
        end
        default
            "ERROR: Unknown system message: " message @ strcat logError
        end
    endcase
;
 
: handleIncomingMessage[ str:session str:channel str:message str:dataAsJson ] (Session should already be confirmed to be valid.)
    session @ not channel @ not message @ not OR OR if "handleIncomingMessageFrom called with either session, channel or message blank." logError exit then
    _startLogDebug
        "[<<][" channel @ strcat "." strcat message @ strcat "] " strcat session @ strcat ": " strcat dataAsJson @ strcat
    _stopLogDebug
    $ifdef trackBandwidth
        message @ strlen "channel_" channel @ strcat "_in" strcat trackBandwidthCounts
    $endif
    dataAsJson @ if
        0 try
            dataAsJson @ decodeJson
        catch
            "Failed to decode JSON whilst handling Message '" message @ strcat "':" strcat dataAsJson @ strcat logError
            exit
        endcatch
    else "" then var! data
    session @ connectionsBySession @ { session @ "player" }list array_nested_get ?dup not if #-1 then channel @ message @ data @ handleChannelCallbacks
;
 
: handleIncomingTextFrame[ str:session str:payload ]
    connectionsBySession @ session @ array_getitem ?dup if (Because it may have dropped elsewhere)
        var! connectionDetails
        connectionDetails @ "pid" array_getitem pid = if
            connectionDetails @ "acceptedAt" array_getitem if (Are we still in the handshake?)
                payload @ dup string? not if pop "" then dup strlen 3 > not if "Malformed (or non-string) payload from session " session @ strcat ": " strcat swap strcat logError then
                3 strcut var! data
                case
                    "MSG" stringcmp not when (Expected format is Channel, Message, Data)
                        session @ data @ dup "," instr strcut swap dup strlen ?dup if 1 - strcut pop then swap dup "," instr strcut swap dup strlen ?dup if 1 - strcut pop then swap handleIncomingMessage
                    end
                    "SYS" stringcmp not when (Expected format is Message,Data)
                        session @ data @ dup "," instr strcut swap dup strlen ?dup if 1 - strcut pop then swap handleIncomingSystemMessage
                    end
                    default
                        "ERROR: Unrecognized text frame from descr " descr intostr strcat ": " strcat swap strcat logError
                    end
                endcase
            else (Still in handshake - only thing we're expecting is 'auth <token>')
                payload @ "auth " instring 1 = if
                    payload @ 5 strcut nip var! token
                    _startLogDebug
                        "Received auth token '" token @ strcat "' for descr " strcat descr intostr strcat
                    _stopLogDebug                      
                    prog "@tokens/" token @ strcat propdir? if
                        systime_precise connectionDetails @ "acceptedAt" array_setitem connectionDetails !                    
                        _startLogDebug
                            "Accepted auth token '" token @ strcat "' for descr " strcat descr intostr strcat
                        _stopLogDebug                      
                        
                        prog "@tokens/" token @ strcat "/account" strcat getprop
                        ?dup if connectionDetails @ "account" array_setitem connectionDetails ! then
                        
                        prog "@tokens/" token @ strcat "/character" strcat getprop dup dbref? not if pop #-1 then
                        (Don't set player manually as we have a dedicated function for it - but make sure we save the present session first)
                        connectionDetails @ connectionsBySession @ session @ array_setitem connectionsBySession !
                        session @ swap handleSetPlayer
                        
                        _startLogDebug
                            "Completed handshake for descr " descr intostr strcat " as: " strcat session @ sessionToString strcat
                        _stopLogDebug

                        (Notify connection)
                        { descr }list "session " session @ strcat
                        $ifdef trackBandwidth
                            dup strlen 2 + (For \r\n) "websocket_out" trackBandwidthCounts
                        $endif
                        _startLogDebug
                            "Informing descr " descr intostr strcat " of session: " strcat session @ strcat
                        _stopLogDebug
                        webSocketSendTextFrameToDescrs
                    
                        (TODO: Re-enable token clearup)
                        (prog "@tokens/" token @ strcat "/" strcat removepropdir)
                    else
                        _startLogWarning
                            "Websocket for descr " descr intostr strcat " gave an auth token that wasn't valid: " strcat payload @ 5 strcut nip strcat
                        _stopLogWarning
                        _startLogDebug
                            "Informing descr " descr intostr strcat " of token rejection." strcat
                        _stopLogDebug                        
                        { descr }list "invalidtoken" webSocketSendTextFrameToDescrs
                    then
                else
                    _startLogWarning
                        "Websocket for descr " descr intostr strcat " sent the following text instead of the expected auth request: " strcat payload @ strcat
                    _stopLogWarning
                then
            then        
        else
            _startLogWarning
                "Websocket for descr " descr intostr strcat " received a text frame from a PID that doesn't match the one in its connection details: " strcat payload @ strcat
            _stopLogWarning
        then
    else
        _startLogWarning
            "Received a text frame from descr " descr intostr strcat " but there's no connection details for them. Possibly okay if they were disconnecting at the time."
        _stopLogWarning
    then
;

: attemptToProcessWebsocketMessage[ session buffer -- bufferRemaining ]
    buffer @ array_count var! startingBufferLength
    buffer @ websocketGetFrameFromIncomingBuffer (Returns opCode payLoad remainingBuffer)
    buffer ! var! payLoad var! opCode
    opCode @ not if buffer @ exit then (Nothing found, persumably because the buffer doesn't have enough to get a message from yet)
    $ifdef trackBandwidth
        startingBufferLength @ buffer @ array_count -
        "websocket_in" trackBandwidthCounts
    $endif   
    opCode @ case
        136 = when
            _startLogDebug
                "Websocket Close request. Terminating pid."
            _stopLogDebug
            payload @ dup webSocketCreateCloseFrameHeader swap
            $ifdef trackBandwidth
                over array_count over strlen + 2 + "websocket_out" trackBandwidthCounts
            $endif
            descr rot rot webSocketSendFrame
            pid kill pop (Prevent further processing, pidwatch will react to the disconnect)
        end
        137 = when (Ping request, need to reply with pong)
            _startLogDebug
                "Websocket Ping request received."
            _stopLogDebug
            payload @ dup webSocketCreatePongFrameHeader swap
            $ifdef trackBandwidth
                over array_count over strlen + 2 + "websocket_out" trackBandwidthCounts
            $endif
            descr rot rot webSocketSendFrame
        end
        138 = when (Pong reply to a ping we sent - the packet should be the systime_precise we sent it at)
            payload @ strtof ?dup if
                _startLogDebug
                    "Websocket Poing response received."
                _stopLogDebug
                session @ swap handlePingResponse
            then
            { }list exit
        end
        129 = when (Text frame, an actual message!)
            session @ payload @ handleIncomingTextFrame (In separate function just for readibility)
        end
        default (This shouldn't happen as we previously check the opcode is one we support)
            "Websocket code didn't know what to do with an opcode: " opCode @ itoh strcat logError
        end
    endcase
    (In case there were multiple, we need to try to process another)
    buffer @ dup if session @ swap attemptToProcessWebsocketMessage then
;

: clientProcess[ clientSession -- ]
    _startLogDebug
        "Starting client process for " clientSession @ strcat " on descr " strcat descr intostr strcat
    _stopLogDebug
    var event var eventArguments
    1 var! keepGoing
    { }list var! buffer
    serverProcess @ "registerClientPID" { pid descr }list event_send (So daemon can handle disconnects)
    depth popn
    begin keepGoing @ descr descr? AND while
        background event_wait (debug_line) event ! eventArguments !
        event @ case
            "HTTP.disconnect." instring when
                _startLogDebug
                    "Client process received disconnect event."
                _stopLogDebug
                0 keepGoing !
            end
            "HTTP.input_raw" stringcmp not when (Possible websocket data!)
                buffer @
                dup array_count eventArguments @ array_insertrange
                clientSession @ swap attemptToProcessWebsocketMessage
                buffer !
            end
            "HTTP.input" stringcmp not when (Not used, just need to be aware of it)
            end
            default pop
            "ERROR: Unhandled client event - " event @ strcat logError
            end
        endcase
        depth if
            _startLogWarning
                debug_line_str depth 1 - "Client stack for " descr intostr strcat " had " strcat swap intostr strcat " item(s). Debug_line follows: " strcat swap strcat
            _stopLogWarning
        then
        depth popn
    repeat
    _startLogDebug
        "Ending client process for " clientSession @ strcat " on descr " strcat descr intostr strcat
    _stopLogDebug
;

: handleClientConnecting
	descr descr? not if exit then (Connections can be dropped immediately)
	prog "disabled" getpropstr "Y" instring if
		descr "HTTP/1.1 503 Service Unavailable\r\n" descrnotify 
        descr "\r\n" descrnotify (This should only send one \r\n)
        exit
	then
	systime var! connectedAt
	event_wait pop var! rawWebData
	
	(Ensure correct protocol version)
	rawWebData @ { "data" "CGIdata" "protocolVersion" 0 }list array_nested_get ?dup not if "" then
	protocolVersion stringcmp if
		_startLogWarning
			"Rejected new WebSocket connection from descr " descr intostr strcat " due to it being the wrong protocol version" strcat
		_stopLogWarning
		descr "HTTP/1.1 426 Upgrade Required\r\n" descrnotify
		descr "\r\n" descrnotify (This should only send one \r\n)
		exit
	then
	
	(At this point we're definitely trying to accept a websocket)
	_startLogDebug
		"New connection from descr " descr intostr strcat
	_stopLogDebug
	
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

    { descr }list "welcome" 
	$ifdef trackBandwidth
		dup strlen 2 + (For \r\n) "websocket_out" trackBandwidthCounts
	$endif
    webSocketSendTextFrameToDescrs    
    
	createNewSessionID var! session
	{
		"descr" descr
		"pid" pid
		"channels" { }list
		"properties" { }dict
		"connectedAt" connectedAt @
		"session" session @
	}dict
    $ifdef is_dev
        dup arrayDump
    $endif
    connectionsBySession @ session @ array_setitem connectionsBySession !    
    
    session @ clientProcess

	_startLogDebug
		"Client connection on " descr intostr strcat " ran for " strcat systime connectedAt @ - intostr strcat "s." strcat
	_stopLogDebug
;	
 
: serverDaemon
    var eventArguments
    var eventName
    var toPing
    var session 
    var sessionDetails    
    { }dict var! clientPIDs (In the form pid:descr)
    "Server Process started on PID " pid intostr strcat "." strcat logNotice
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
                        _startLogDebug
                            "Disconnecting " session @ sessionToString strcat " due to PID being dead." strcat
                        _stopLogDebug
                        session @ deleteSession continue
                    then
                    sessionDetails @ "descr" array_getitem descr? not if
                        _startLogDebug
                            "Disconnecting " session @ sessionToString strcat " due to descr being disconnected." strcat
                        _stopLogDebug
                        session @ deleteSession continue
                    then
                    sessionDetails @ "acceptedAt" array_getitem not if continue then (Not finished handshake, so we don't ping)
                    (Ping related)
                    sessionDetails @ "lastPingOut" array_getitem sessionDetails @ "lastPingIn" array_getitem
                    over over > if (If lastPingOut is higher we're expecting a response. On initial connect or reconnect both are 0)
                        pop systime_precise swap - maxPing > if
                            _startLogDebug
                                "Disconnecting " session @ sessionToString strcat " due to no response to ping." strcat
                            _stopLogDebug
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
                (TBC - Need something to drop pending connections that have taken too long)
                _startLogDebug
                    "Heartbeat. Connections: " connectionsBySession @ array_count intostr strcat
                    ". Caches - ByChannel: " strcat sessionsByChannel @ array_count intostr strcat
                    ", ByPlayer: " strcat sessionsByPlayer @ array_count intostr strcat
                    ", SessionsByPlayerByChannel: " strcat playersSessionsByChannel @ array_count intostr strcat
                    ", SessionsByAccountByChannel: " strcat accountsSessionsByChannel @ array_count intostr strcat
                    ". Outgoing Pings: " strcat toPing @ array_count intostr strcat
                _stopLogDebug
                toPing @ ?dup if
                    systime_precise intostr 
                    $ifdef trackBandwidth
                        over array_count over strlen 2 + * "websocket_out" trackBandwidthCounts
                    $endif
                    webSocketSendPingFrameToDescrs
                then
            end
            "USER.registerClientPID" stringcmp not when (Tells us to watch this PID - called with [pid, descr])
                eventArguments @ "data" array_getitem dup 1 array_getitem swap 0 array_getitem (Now S: descr PID)
                dup watchPID
                over clientPIDs @ 3 pick array_setitem clientPIDs !
                _startLogDebug
                    "Server process notified of PID " over intostr strcat " for descr " strcat 3 pick intostr strcat ", now monitoring " strcat clientPIDs @ array_count intostr strcat " PID(s)." strcat
                _stopLogDebug
                pop pop
            end
            "PROC.EXIT." instring when
                eventName @ 10 strcut nip atoi
                clientPIDs @ over array_getitem ?dup if (S: PID descr)
                clientPIDs @ 3 pick array_delitem clientPIDs !
                _startLogDebug
                    "Server process notified of disconnect on PID " 3 pick intostr strcat ", now monitoring " strcat clientPIDs @ array_count intostr strcat " PID(s)." strcat
                _stopLogDebug
                nip (S: descr) (Find sessions still associated with this descr )
                connectionsBySession @ foreach (Descr Session Details)
                    "descr" array_getitem 3 pick = if
                        deleteSession
                    else pop then
                repeat
                pop
                else
                _startLogWarning
                    "Server process notified of disconnect on an unmonitored PID - " over intostr strcat
                _stopLogWarning
                pop
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

    dup "#reset" stringcmp not if
        "[!] Reset triggered: " me @ unparseobj strcat logNotice
        (Need to kill old PIDs)
        prog getPids foreach nip pid over = if pop else kill pop then repeat
        0 serverProcess ! 0 connectionsBySession ! ensureInit
        "Server reset.." .tell
        exit
    then

    dup "#kill" instring 1 = if
        "[!] Kill signal received." logNotice
        "Service will shut down. This command is largely just here for testing - the system will start up again if something requests it." .tell
        0 serverProcess !
        exit
    then

    dup "#debug" instring 1 = if
		6 strcut nip strip
		dup "" stringcmp not if
			"Valid values are: off, warning, info, all" .tell
			exit
		then
		0 "" (Level String)
		3 pick "off"      stringcmp not if pop pop 0                 "Off (Core notices and errors only)" then
		3 pick "warning"  stringcmp not if pop pop debugLevelWarning "Warning" then
		3 pick "info"     stringcmp not if pop pop debugLevelInfo    "Info" then
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

!!@qmuf .debug-off "$www/mwi/websocket" match "getsessions" call $include $lib/kta/proto arrayDump
!!@qmuf .debug-off "$www/mwi/websocket" match "getcaches" call $include $lib/kta/proto "AccountsSessionsByChannel" .tell arrayDump "PlayersSessionsByChannel" .tell arrayDump "SessionsByPlayer" .tell arrayDump "SessionsByChannel" .tell arrayDump
!!@qmuf 3989 0 "$www/mwi/websocket" match "websocketIssueAuthenticationToken" call
