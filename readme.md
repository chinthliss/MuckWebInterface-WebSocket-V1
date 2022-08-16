# MuckWeb Interface (MWI) - Websockets
A framework to provide standardised, live, channel-based, bi-directional, event-driven communication between a muck and a web client.

Based upon previous works (LiveConnect). This variant works on top of the MuckWebInterface and is greatly simplified from the previous one since it doesn't support a HTTP stream anymore since websockets are in common usage. 

## Overview

Message are sent via channels.

From the muck side, programs register to monitor a channel. 
* On each message the program looks for functions on registered programs in the form 'on<messsage>' and passes them the message.
* These functions are called with the arguments 'channel, message, descr, player, data'; Player may be #-1. 

From the web side, a client registers to channels they intend to use on that particular page.
* Handlers are registered via the .on() function for each message wanted. When a message is received, they'll be called directly with (data).
* The present player can be obtained via the library.

## Details

### Connection / Handshake
* Client connects to the webpage to get a token. This request is dealt with under the webpage's regular authentication.
* The website forwards the token to the muck where it's stored in a temporary buffer. The token contains the account / character details.
* The websocket to the muck is opened.
* The muck sends the word 'welcome'.
* The client responds with 'auth <token> <page being requested for>'.
* The muck verifies the token and, if accepted, responds with 'accepted <descr>'

### Messages
Communication is sent in the form of a short code prefixing the line. Message formats used:

|Message|Content|
|-------|-------|
| MSGChannel,Message,Data|Standard message sent over a channel. Data is JSON encoded |
| SYSMessage,Data|System messages without a channel. |
| Ping / Pong|Handled at the transport level |

