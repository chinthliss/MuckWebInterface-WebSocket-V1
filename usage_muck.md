From the muck side, programs register to monitor a channel.
* On each message the program looks for functions on registered programs in the form 'on<messsage>' and passes them the message.
* These functions are called with the arguments 'channel, message, descr, player, data'; Player may be #-1.

The #addChannel and #rmmChannel commands can be used to register/unregister programs, their usage is documented in the main help file.

# Channel, Player, Account or Descr?
Each connection can be talked to via one of several levels:
* Descr - Only a single connection is sent a message
* Player - All connections for the given player are sent a message
* Account - All players on a given account are sent a message
* Channel - All connections on a given channel are sent a message

The actual level to use will depend on the intent of the program in question. Whilst it's tempting to talk to a single descr, it's worth noting:

* Refreshing the browser window will cause a new descr.
* If a player has a bad connection they may timeout and reconnect.
* Handheld devices may drop the connection whilst the window isn't in focus.
* A player may be connected more than once (multiple tabs, devices, etc.) and may have multiple descrs on a channel.

Individual programs will need to decide how they'll deal with this based upon their purpose.

## Functions for outgoing messages
sendToDescr    [ str:descr str:channel str:message any:data -- ]  
sendToDescrs   [ arr:descrs str:channel str:message any:data -- ]  
sendtoPlayer   [ dbref:player str:channel str:message any:data -- ]   
sendtoPlayers  [ arr:players str:channel str:message any:data -- ]  
sendToAccount  [ aid:account str:channel str:message any:data -- ]  
sendToChannel  [ str:channel str:message any:data -- ]  

# Temporary Variables

Though they're temporary in nature there's a couple of functions to save data on a descr. This data is wiped after a descr drops and intended more to avoid programs saving lookup tables - for example saving that a given descr is accessing item Y.

As discussed above, descrs might be regenerated randomly so a using page will need to keep a local copy and re-set variables on descr change.

The functions are:

setConnectionProperty [ int:descr str:propertyName any:value -- ]  
getConnectionProperty [ int:descr str:propertyName -- any:value ]  
delConnectionProperty [ int:descr str:propertyName -- ]  

If the given property doesn't exist the get function will return '0'.

# Incoming messages

On receiving a message the muck will look for a function in the form 'on<message>' on programs registered to listen to a channel and call it if it finds such.

It will pass the arguments (str:channel str:message int:descr dbref:player any:data). Player may be #-1 if the player hasn't logged in.

# Events

There are messages that are automatically sent to all interested programs (And thus try to call the relevant on<message> function). They are:

| Message                  | When it occurs                                                                                                          |
|--------------------------|-------------------------------------------------------------------------------------------------------------------------|
| connectionEnteredChannel | First time a descr uses a channel                                                                                       |  
| connectionExitedChannel  | When the descr leaves                                                                                                   |
| playerEnteredChannel     | After the first descr of a player enters a channel. Does not occur if a descr of that player is already on the channel. |  
| playerExitedChannel      | After the last descr of a player has left.                                                                              |    
| accountEnteredChannel    | After the first descr of a player enters a channel.  Does not occur if a descr of that player remains on the channel.   |    
| accountExitedChannel     | After the last descr has left.                                                                                          |  

These are only sent to muck programs. It is up to the programs in question to decide whether to forward these onto other connections.

# Global Connection Hooks
The program has a @player propqueue upon itself. Programs registered in such will receive either a wsConnect or wsDisconnect call similar to other muck hooks.