!!@program wwwChannel-Loopback.muf
!!q
!!@reg wwwChannel-Loopback.muf=www/mwi/websocket/loopback
!!@set $www/mwi/websocket/loopback=L
websocket #addChannel loopback=$www/mwi/websocket/loopback

@edit $www/mwi/websocket/loopback
1 99999 d
i

$include $www/mwi/websocket
$include $lib/account

(
    Simple program that does little more than loopback things. It will: 
    Return any message of 'test' on the channel.
    Send events to the entire channel
)
: onTest[ str:channel str:message int:who dbref:player any:data -- ] (Data: [anything])
    who @ channel @ "test" data @ sendToDescr
; PUBLIC onTest

: onPlayerEnteredChannel[ str:channel str:message int:who dbref:player any:data -- ]
    "loopback" "+player" player @ name sendToChannel
; PUBLIC onPlayerEnteredChannel

: onPlayerExitedChannel[ str:channel str:message int:who dbref:player any:data -- ]
    "loopback" "-player" player @ name sendToChannel
; PUBLIC onPlayerExitedChannel

: onAccountEnteredChannel[ str:channel str:message int:who dbref:player any:data -- ]
    "loopback" "+account" player @ acct_any2aid sendToChannel
; PUBLIC onAccountEnteredChannel

: onAccountExitedChannel[ str:channel str:message int:who dbref:player any:data -- ]
    "loopback" "-account" player @ acct_any2aid sendToChannel
; PUBLIC onAccountExitedChannel

.
c
q