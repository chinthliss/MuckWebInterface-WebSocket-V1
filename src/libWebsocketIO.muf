!!@program libWebsocketIO.muf
!!q
!!@reg libWebsocketIO.muf=lib/websocketIO
!!@set $lib/websocketIO=W
!!@set $lib/websocketIO=L

@edit $lib/websocketIO
1 999999 d
i
(
This library contains all the parts of a codebase that deal with the actual talking to a websocket.
It's intended to separate out parts dealing with the connection out of the programs using it, both to make them more readible and to separate out debugging requirements
Also to allow room to potentially identify improvements to it.

Present understanding of descrnotify: will append a \r\n AND strip additional trailing ones. Will always trigger a descrflush.
)

$version 1.2

$include $lib/kta/proto
$include $lib/kta/strings

$pubdef : (Clear present _defs)

$def debugWebsocketIO 0
(
$ifdef is_dev
   $def debugWebsocketIO 1
$endif
)

$libdef webSocketCreateAcceptKey
$libdef webSocketCreateFrameHeader
$libdef webSocketCreateTextFrameHeader
$libdef webSocketCreateCloseFrameHeader
$libdef webSocketCreatePingFrameHeader
$libdef webSocketCreatePongFrameHeader
$libdef webSocketGetFrameFromIncomingBuffer
$libdef webSocketSendFrame
$libdef webSocketSendTextFrameToDescrs
$libdef webSocketSendCloseFrameToDescrs
$libdef webSocketSendPingFrameToDescrs
$libdef webSocketSendPongFrameToDescrs

$def _startDebug debugWebsocketIO if
$def _stopDebugSingleLine getLogPrefix swap strcat logstatus then
$def _stopDebugMultipleLines foreach nip getLogPrefix swap strcat logstatus repeat then

: getLogPrefix ( -- s) (Outputs the log prefix for the given type)
    "[WebsocketIO " pid intostr 8 right strcat "] " strcat
;

: logError (s -- ) (Output definite problems)
    getLogPrefix " ERROR: " strcat swap strcat logstatus
;

: logWarning (s -- ) (Output important notices)
  getLogPrefix " WARNING: " strcat swap strcat logstatus
;

: webSocketOpCodeToString[ int:opCode -- str:Text ]
    opCode @ case
        128 = when "Continuation" end (Not supported)
        129 = when "Text" end
        130 = when "Binary" end (Not supported)
        (131 - 135 are reserved for future use)
        136 = when "Close" end
        137 = when "Ping" end
        138 = when "Pong" end
        (139 - 143 are reserved for future use)
        default "Unrecogized OpCode(" swap intostr strcat ")" strcat end
    endcase
; PUBLIC webSocketOpCodeToString

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
; PUBLIC webSocketCreateAcceptKey

(Returns a frame header of the given type. Because of issues converting text from the muck to UTF-8 it returns it as an array of ints)
(In the case of a close frame, isFinal becomes the status code sent out )
: webSocketCreateFrameHeader[ int:opCode int:isFinal int:payloadSize -- arr:header ]
    (First byte contains type and whether this is the final frame)
    { opCode @ isFinal @ if 128 bitor then }list
    (Following byte uses first bit to specify if we're masked, which is always 0, then 7 bits of length.)
    (Depending on the size we'll either use 0, 2 or 8 additional bytes)
    payloadSize @ 2 + (Two additional bytes for the /r/n the muck will append)
    opCode @ 8 = if 2 + then (Two additional bytes for the status code)
    dup 126 < if (Fits in one byte)
        swap array_appenditem
    else swap
        over 65536 < if (Start with 126, then use two bytes to represent length)
            126 swap array_appenditem
            over -8 bitshift swap array_appenditem
            swap 255 bitand swap array_appenditem
        else (Start with 127 then use eight bytes to represent length)
            127 swap array_appenditem
            over -56 bitshift 255 bitand swap array_appenditem
            over -48 bitshift 255 bitand swap array_appenditem
            over -40 bitshift 255 bitand swap array_appenditem
            over -32 bitshift 255 bitand swap array_appenditem
            over -24 bitshift 255 bitand swap array_appenditem
            over -16 bitshift 255 bitand swap array_appenditem
            over  -8 bitshift 255 bitand swap array_appenditem
            swap              255 bitand swap array_appenditem
        then
    then
    opCode @ 8 = if
        isFinal @ -8 bitshift 255 bitand swap array_appenditem
        isFinal @ 255 bitand swap array_appenditem
    then
; PUBLIC webSocketCreateFrameHeader

: webSocketCreateTextFrameHeader[ str:text -- arr:frameHeader ]
    1 1 text @ strlen webSocketCreateFrameHeader
; PUBLIC webSocketCreateTextFrameHeader

: webSocketCreateCloseFrameHeader[ str:content -- arr:frameHeader ] (Takes content since the spec says to reflect any provided content in acknowledgements)
    8 1000 content @ strlen webSocketCreateFrameHeader (TODO: Allow actually setting the status code rather than using the default)
; PUBLIC webSocketCreateCloseFrameHeader

: webSocketCreatePingFrameHeader[ str:content -- arr:frameHeader ]
    9 1 content @ strlen webSocketCreateFrameHeader
; PUBLIC webSocketCreatePingFrameHeader

: webSocketCreatePongFrameHeader[ str:response -- arr:frameHeader ]
    10 1 response @ strlen webSocketCreateFrameHeader
; PUBLIC webSocketCreatePongFrameHeader

: webSocketSendFrame (d:descr a:frameHeader ?:framepayload -- ) (Actually only works with strings but leaving some room for extension)
    dup string? not if "WebSocketSendFrame was called with a payload that isn't a string!" logError pop pop pop exit then
    _startDebug
        "WebSocket Out. Descr " 4 pick intostr strcat ": " strcat 3 pick foreach nip itoh strcat " " strcat repeat "| " strcat over strcat
    _stopDebugSingleLine
    rot rot foreach nip (? d c)
        over swap notify_descriptor_char
    repeat
    swap descrnotify
; PUBLIC webSocketSendFrame

: webSocketSendTextFrameToDescrs[ arr:descrs str:text -- ]
    text @ webSocketCreateTextFrameHeader var! frameHeader
    descrs @ foreach nip
        frameHeader @ text @ webSocketSendFrame
    repeat
; PUBLIC webSocketSendTextFrameToDescrs

: webSocketSendCloseFrameToDescrs[ arr:descrs str:response -- ]
    response @ webSocketCreateCloseFrameHeader var! frameHeader
    descrs @ foreach nip
        frameHeader @ response @ webSocketSendFrame
    repeat
; PUBLIC webSocketSendCloseFrameToDescrs

: webSocketSendPingFrameToDescrs[ arr:descrs str:content -- ]
    content @ webSocketCreatePingFrameHeader var! frameHeader
    descrs @ foreach nip
        frameHeader @ content @ webSocketSendFrame
    repeat
; PUBLIC webSocketSendPingFrameToDescrs

: webSocketSendPongFrameToDescrs[ arr:descrs str:response -- ]
    response @ webSocketCreatePongFrameHeader var! frameHeader
    descrs @ foreach nip
        frameHeader @ response @ webSocketSendFrame
    repeat
; PUBLIC webSocketSendPongFrameToDescrs

: webSocketGetFrameFromIncomingBuffer[ arr:buffer -- int:opCode str:payload arr:remainingBuffer ]
   (Quick break down on possible stucture in bytes:)
   (  Frame information)
   (  Masked? bit and length. Length is 7-bits and client will not allow masking to be off for client->server)
   (  Extended Length if second byte was 254 or 255) ( <- If WebSocket ever allows no masking these could be 126 and 127 too)
   (  Extended Length if second byte was 254 or 255)
   (  Extended Length if second byte was 255)
   (  Extended Length if second byte was 255)
   (  Extended Length if second byte was 255)
   (  Extended Length if second byte was 255)
   (  Extended Length if second byte was 255)
   (  Extended Length if second byte was 255)
   (  Mask 1/4)
   (  Mask 2/4)
   (  Mask 3/4)
   (  Mask 4/4)

    _startDebug
        "Investigating incoming websocket data: " buffer @ foreach nip itoh strcat " " strcat repeat
    _stopDebugSingleLine
   
   (Check we support this)
   buffer @ 0 array_getitem var! opCode
   opCode @ dup 129 = (Text frame) over 136 = OR (Close frame) over 137 = OR (Ping frame) swap 138 = OR (Pong frame) not if
      "First byte of a webSocket frame was 0x" buffer @ 0 array_getitem itoh strcat ". This code can only accept 0x81 (single text frame), 0x89 (ping), 0x8A (pong) and 0x88 (close frame). Abandoning further decoding and flushing the buffer." strcat logWarning
      0 "" { }list 
      exit
   then
   _startDebug
      "Checking buffer. OpCode= 0x" opCode @ itoh strcat ", Present length= " strcat buffer @ array_count intostr strcat
   _stopDebugSingleLine
   buffer @ array_count 1 = if 0 "" buffer @ exit then (First byte just contains type and flags we don't care about)
   6 (Header length without the extended length bytes)
   buffer @ 1 array_getitem
   dup 254 = if pop 2 + else 255 = if 8 + then then
   (S: HeaderSize) (Will now either be 6, 8 or 14)
   buffer @ array_count over < if pop 0 "" buffer @ exit then (Haven't received the frame header)
   0 (payloadSize)
   over 6 = if (Last 7 bits of second byte is length) buffer @ 1 array_getitem 127 bitand nip then
   over 8 = if (Bytes 3 to 4 are length)
      2 + (Two more bytes for length)
      buffer @ dup 2 array_getitem 8 bitshift swap 3 array_getitem + nip
   then
   over 14 = if (Bytes 3 to 10 are length)
      8 + (Eight more bytes for length)
      buffer @
      dup 2 array_getitem 56 bitshift
      over 3 array_getitem 48 bitshift +
      over 4 array_getitem 40 bitshift +
      over 5 array_getitem 32 bitshift +
      over 6 array_getitem 24 bitshift +
      over 7 array_getitem 16 bitshift +
      over 8 array_getitem 8 bitshift +
      swap 9 array_getitem + (And done!) nip
   then
   (S: headerSize payloadSize)
   _startDebug
      "  Header Size=" 3 pick intostr strcat ", payload size=" strcat over intostr strcat ", present buffer size=" strcat buffer @ array_count intostr strcat
   _stopDebugSingleLine
   buffer @ array_count 3 pick 3 pick + < if (Still need more)
      pop pop 0 "" buffer @ exit
   then
   over over + 1 - (Total then converted to last index value)
   buffer @ 0 3 pick array_getrange buffer @ 0 4 rotate array_delrange buffer !
   nip ( -payloadSize )
   (S: HeaderSize Frame)
   _startDebug
      "  Captured frame: " over foreach nip itoh strcat " " strcat repeat
   _stopDebugSingleLine
   dup 3 pick 4 - dup 3 + array_getrange (Get mask)
   swap 3 rotate over array_count array_getrange (Payload)
   _startDebug
      {
         "  Captured payload: " 3 pick foreach nip itoh strcat " " strcat repeat
         "  Captured mask: " 5 pick foreach nip itoh strcat " " strcat repeat
      }list
   _stopDebugMultipleLines
   swap var! frameMask
   "" (Result - seemed quicker to repeatedly strcat on the muck rather than throw into an array and join)
   swap foreach
      frameMask @ rot 4 % array_getitem (Which byte to xor with) bitxor itoc strcat
   repeat
   strip (Last two characters are sometimes newlines)
   ensureValidUTF8
   _startDebug
      "Unmasked Payload" buffer @ array_count ?dup if "(buffer still has " swap intostr strcat ")" strcat strcat then ": " strcat over strcat
   _stopDebugSingleLine
   opCode @ swap buffer @
; PUBLIC webSocketGetFrameFromIncomingBuffer

: main
    "This is a library and doesn't provide any direct functionality." .tell
;

.
c
q