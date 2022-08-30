The underlying code will handle the actual connection.

# Channels

A page using it needs to join channels they intend to use on that particular page.
```
const myChannel = mwiWebsocket.channel('channelname');
```

The object returned by such is the interface for receiving/sending on that channel.

Handlers for incoming messages are registered via the .on() function for each message wanted. When a message is received, they'll be called directly with (data).
```
myChannel.on('hello', (data) => {
    console.log("I received a greeting from the muck with the following data:", data);
});
```

Sending a message is done via the send(message, data) method on the Channel object. To complete the example above so that the page responds to the muck instead of logging to the console:
```
myChannel.on('hello', (data) => {
    myChannel.send('returnMessage', 'I received your greeting!');
});

```

The following additional methods are available on the channel object:  
name()        -- Returns the present channel's name.  
any(callback) -- Registers a callback to receive an event on any message.  
The any callback will receive the arguments (message, data, direction) with direction being a boolean that's true if it's outgoing and false otherwise.  

# Additional functions
The mwiWebsocket object provides a few additional functions:

| Function                          | Description                                                                  |
|-----------------------------------|------------------------------------------------------------------------------|
| onError(function)                 | Register a callback that's passed any errors that occur with the connection. |  
| onConnectionStateChange(function) | Register a callback to receive events when the system connects/disconnects.  |  
| onPlayerChanged(function)         | Register a callback to receive events when the active player changes.        |  
| playerName()                      | Returns the name of the presently active player or an empty string.          |
| playerDbref()                     | Returns the dbref, as an int, of the presently active player or -1.          |
| isPlayerSet()                     | Returns true if an active player exists.                                     |
| getConnectionState()              | Returns the present connection status.                                       |
| setDebug()                        | Toggles whether to log additional details to the console                     |

# Events
After connection the framework may automatically send the following messages to the connecting client:

| Message          | When it occurs                                                                      |
|------------------|-------------------------------------------------------------------------------------|
| connected        | For any time a connection to the given channel is formed. This includes reconnects. |
| playerConnected  | For the first time a player joins a channel.                                        |
| accountConnected | For the first time a player's account joins a channel.                              |
