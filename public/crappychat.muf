!!@program wwwCrappyChat.muf
!!q
!!@reg wwwCrappyChat=www/crappyChat
!!@set $www/crappyChat=L
!!@set $www/crappyChat=_type:noheader
!!@propset $www=dbref:_/www/crappyChat:$www/crappyChat

@program $www/crappyChat
1 99999 d
i
(
Simple program to test/demo the newer MWI program.
)

$include $www/liveconnect

: onChat[ channel message session player data -- ]
   player @ ok? not if exit then (Players only)
   (Sending out a data object in the form [playerDbref playerName message])
   (Because this is just a simple demo a player's name is sent out with each message)   
   "crappychat" "chat"
   {
      player @ int
      player @ name 
      data @
   }list
   sendToChannel
; PUBLIC onChat

: onPlayerEnteredChannel[ channel message session player data -- ]
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   "crappychat" swap "playerList" swap sendToChannel
; PUBLIC onPlayerEnteredChannel

: onPlayerExitedChannel[ channel message session player data -- ]
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   "crappychat" swap "playerList" swap sendToChannel
; PUBLIC onPlayerExitedChannel

: onSessionEnteredChannel[ channel message session player data -- ]
   "crappychat" "sessionCount" "crappychat" sessionsOnChannel array_count sendToChannel   
   session @ "crappychat" "playerList" 
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   sendToSession
; PUBLIC onSessionEnteredChannel

: onSessionExitedChannel[ channel message session player data -- ]
   "crappychat" "sessionCount" "crappychat" sessionsOnChannel array_count sendToChannel
; PUBLIC onSessionExitedChannel

: main
   "This doesn't do anything from the muck side." .tell
;
.
c
q
