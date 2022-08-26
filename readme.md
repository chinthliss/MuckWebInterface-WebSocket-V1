# MuckWeb Interface (MWI) - Websockets
A framework to provide standardised, live, channel-based, bi-directional, event-driven communication between a muck and a web client.

Based upon previous works (LiveConnect). This variant works on top of the MuckWebInterface and is greatly simplified from the previous one since it doesn't support a HTTP stream anymore since websockets are in common usage. 

## Overview
* **Channel** - Everything is split into channels. The channel helps the underlying code know which programs to notify. It might be as simple as the name of the program 'hosting' a service/page though it should be noted multiple programs can listen to a channel. Some examples might be 'publicchat', 'combatsystem', 'notifications'
* **Message** - Individual commands sent to a channel. For instance the channel 'notifications' might have the message 'newmail' to notify a player of new mail. The channel 'chat' might have the message 'message' to notify everyone on the channel of a new message. Who gets the messages is up to the program sending them.
* **Data** - There are no restrictions on what data is. It might be a dictionary array to carry multiple items but could equally be a list array, a single integer, etc. There are two exceptions:
  * Javascript (client side) doesn't know what a dbref is and these will become integers by default.
  * The muck doesn't know what a boolean is and these will become integers.

From the muck side, programs register to monitor a channel. 
* On each message the program looks for functions on registered programs in the form 'on<messsage>' and passes them the message.
* These functions are called with the arguments 'channel, message, descr, player, data'; Player may be #-1. 

From the web side, a client registers to channels they intend to use on that particular page.
* Handlers are registered via the .on() function for each message wanted. When a message is received, they'll be called directly with (data).
* The present player can be obtained via the library.

### Important
Web browsers expose everything and, with very little knowledge, it's possible to change running scripts on the fly. EVERYTHING from a client should be validated and any changes to important values should be done on the muck and notified to the client.

Following on from such - for the intents of this documentation the underlying software is stateless and asynchronous. This means programs need to be provide their own context and be prepared to deal with messages that may be out of that context (Edit messages in an editor when nothing is selected, combat actions taken whilst not in a fight, etc).

## Details

### Connection / Handshake
* Client connects to the webpage to get a token. This request is dealt with under the webpage's regular authentication.
* The website forwards the token to the muck where it's stored in a temporary buffer. The token contains the account / character details.
* The websocket to the muck is opened.
* The muck sends the word 'welcome'.
* The client responds with 'auth <token> <page being requested for>'.
* The muck verifies the token and, if accepted, responds with 'accepted <descr>,<playerDbref>,<playerName>'. Player can be #-1 and playername can be blank.

### Messages
Communication is sent in the form of a short code prefixing the line. Message formats used:

|Message|Content|
|-------|-------|
| MSGChannel,Message,Data|Standard message sent over a channel. Data is JSON encoded |
| SYSMessage,Data|System messages without a channel. |
| Ping / Pong|Handled at the transport level |

