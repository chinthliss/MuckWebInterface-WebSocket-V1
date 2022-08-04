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

: onChat[ channel message who player data -- ]
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

: onPlayerEnteredChannel[ channel message who player data -- ]
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   "crappychat" swap "playerList" swap sendToChannel
; PUBLIC onPlayerEnteredChannel

: onPlayerExitedChannel[ channel message who player data -- ]
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   "crappychat" swap "playerList" swap sendToChannel
; PUBLIC onPlayerExitedChannel

: onDescrEnteredChannel[ channel message who player data -- ]
   "crappychat" "connectionCount" "crappychat" descrsOnChannel array_count sendToChannel
   who @ "crappychat" "playerList"
   { }list
   "crappychat" playersOnChannel foreach nip name swap array_appenditem repeat
   sendToDescr
; PUBLIC onDescrEnteredChannel

: onDescrExitedChannel[ channel message who player data -- ]
   "crappychat" "descrCount" "crappychat" descrsOnChannel array_count sendToChannel
; PUBLIC ondescrExitedChannel

: main
   "This doesn't do anything from the muck side." .tell
;
.
c
q
