import Channel from "./channel.js";
import ConnectionWebSocket from "./connection-websocket.js";
import ConnectionFaker from "./connection-faker.js";

export default class Core {


    /**
     * Message in the form MSG<Channel>,<Message>,<Data>
     * @type {RegExp}
     * @readonly
     */
    static msgRegExp = /MSG(\w*),(\w*),(.*)/;

    /**
     * System message in the form SYS<Message>,<Data>
     * @type {RegExp}
     * @readonly
     */
    static sysRegExp = /SYS(\w*),(.*)/;

    /**
     * @enum {string}
     * @readonly
     */
    static connectionStates = {
        connecting: 'connecting',
        login: 'login',
        connected: 'connected',
        failed: 'failed' // For when no more attempts will happen
    }

    /**
     * @type {boolean}
     */
    localStorageAvailable = false; // We'll set this properly in the constructor

    /**
     * @type {(connectionStates)}
     */
    connectionStatus;

    /**
     * @type {string}
     */
    session = "";

    /**
     * @type {number}
     */
    playerDbref = -1;

    /**
     * @type {string}
     */
    playerName = "";

    /**
     * @type {function[]}
     */
    playerChangedHandlers = [];

    /**
     * @type {function[]}
     */
    statusChangedHandlers = [];

    /**
     * @type {function[]}
     */
    errorHandlers = [];

    /**
     * @type {boolean}
     */
    debug = false;

    /**
     * The presently active connection
     * @type {Connection}
     */
    connection = null;

    /**
     * Presently active channels, indexed by channel name
     * @type {Object.<string, Channel>}
     */
    channels = {};

    constructor() {
        // Previously this was a test to find something in order of self, window, global
        let context = globalThis;
        let environment = "production";
        if (typeof process !== 'undefined' && process?.env?.NODE_ENV) environment = process.env.NODE_ENV;

        // Figure out whether we have local storage.
        this.localStorageAvailable = 'localStorage' in context;
        if (this.localStorageAvailable && localStorage.getItem('mwiWebsocket-debug') === 'y') this.debug = true;

        // Work out which connection we're using
        if (environment === 'test') this.connection = new ConnectionFaker(context, this);
        if (!this.connection) {
            if ("WebSocket" in context) this.connection = new ConnectionWebSocket(context, this);
        }
        if (!this.connection) throw "Failed to find any usable connection method";

        // And start the connection up
        this.startConnection();
    }

    /**
     * Enables or disables printing debug information in the console
     * @param {boolean} trueOrFalse
     */
    setDebug(trueOrFalse) {
        if (!this.localStorageAvailable) {
            console.log("Can't set debug preference - local storage is not available.");
            return;
        }
        if (trueOrFalse) {
            this.debug = true;
            console.log("Console logging enabled.");
            localStorage.setItem('mwiWebsocket-debug', 'y');
        } else {
            this.debug = false;
            console.log("Console logging disabled.");
            localStorage.removeItem('mwiWebsocket-debug');
        }
    }

    /**
     * Send a message over the specified channel. Data will be parsed to JSON.
     * @param {string} channel
     * @param {string} message
     * @param {any} data
     */
    sendMessage(channel, message, data) {
        if (this.debug) console.log("[ >> " + channel + "." + message + "] ", data);
        let parsedData = (typeof data !== 'undefined' ? JSON.stringify(data) : '');
        let parsedMessage = ["MSG", channel, ',', message, ',', parsedData].join('');
        this.connection.sendString(parsedMessage);
    };

    /**
     * Send a message without a channel. Data will be parsed to JSON.
     * @param {string} message
     * @param {any} data
     */
    sendSystemMessage(message, data) {
        if (this.debug) console.log("[ >> " + message + "] ", data);
        let parsedData = (typeof data !== 'undefined' ? JSON.stringify(data) : '');
        let parsedMessage = ["SYS", message, ',', parsedData].join('');
        this.connection.sendString(parsedMessage);
    };

    /**
     * Returns a channel interface to talk to a channel, joining it if required.
     * @param {string} channelName
     * @returns {ChannelInterface}
     */
    channel(channelName) {
        if (channelName in this.channels) return this.channels[channelName].interface;
        if (this.debug) console.log('New Channel - ' + channelName);
        let newChannel = new Channel(channelName, this);
        this.channels[channelName] = newChannel;
        //Only send join request if we have a connection, otherwise we'll join multiple as part of the initial connection
        if (this.session) this.sendSystemMessage('joinChannels', channelName);
        return newChannel.interface;
    };

    //region Event Processing

    /**
     *
     * @param {function} callback
     */
    onPlayerChanged(callback) {
        this.playerChangedHandlers.push(callback);
    }

    /**
     *
     * @param {function} callback
     */
    onError(callback) {
        this.errorHandlers.push(callback);
    }

    /**
     *
     * @param {function} callback
     */
    onStatusChanged(callback) {
        this.statusChangedHandlers.push(callback);
        //Trigger a one-off in case this handler is being attached after the initial connection
        setTimeout(function () {
            try {
                callback(this.connectionStatus);
                if (this.debug) console.log('Registered new statusChangedHandler and sent present status of: ' + this.connectionStatus);
            } catch (e) {
                if (this.debug) console.log('Registered new statusChangedHandler but failed to use its callback.');
            }
        }.bind(this));
    }

    //endregion Event Handlers

    /**
     * Called by present connection
     * @param {string} newSession The New session
     */
    updateAndDispatchSession(newSession) {
        if (this.debug) console.log("Session changed to " + newSession);
        if (this.session) { //Maybe send join requests?
            let channelsToJoin = [];
            for (let channel in this.channels) {
                if (this.channels.hasOwnProperty(channel) && !this.channels[channel].joined) {
                    channelsToJoin.push(channel);
                }
            }
            if (channelsToJoin.length > 0) this.sendSystemMessage('joinChannels', channelsToJoin);
        }
    }

    /**
     * Called by present connection
     * @param {string} newDbref New Dbref for player
     * @param {string} newName New name for the player
     */
    updateAndDispatchPlayerChanged(newDbref, newName) {
        if (this.debug) console.log("Player changed: " + newName + '(' + newDbref + ')');
        for (let i = 0, maxi = this.playerChangedHandlers.length; i < maxi; i++) {
            try {
                this.playerChangedHandlers[i](newDbref, newName);
            } catch (e) {
            }
        }
    }

    /**
     *
     * @param {string} error
     */
    dispatchError(error) {
        console.log("Mwi-Websocket Error reported: " + error);
        for (let i = 0, maxi = this.errorHandlers.length; i < maxi; i++) {
            try {
                this.errorHandlers[i](error);
            } catch (e) {
            }
        }
    }

    /**
     * Called by present connection
     * @param {connectionStates} newStatus The New status
     */
    updateAndDispatchStatus(newStatus) {
        if (this.connectionStatus === newStatus) return;
        if (this.debug) console.log('Connection status changed to ' + newStatus + ' (from ' + this.connectionStatus + ')');
        this.connectionStatus = newStatus;
        for (let i = 0, maxi = this.statusChangedHandlers.length; i < maxi; i++) {
            try {
                this.statusChangedHandlers[i](newStatus);
            } catch (e) {
            }
        }
    };

    /**
     * Handles any incoming string, whether it's a regular message or system message
     * @param {string} incoming
     */
    receivedString(incoming) {
        //console.log("Raw incoming string: " + incoming);
        if (incoming.indexOf('MSG') === 0) {
            let channel, message, data;
            try {
                let dataAsJson;
                [, channel, message, dataAsJson] = incoming.match(Core.msgRegExp);
                data = (dataAsJson === '' ? null : JSON.parse(dataAsJson));
            } catch (e) {
                console.log("Mwi-Websocket ERROR: Failed to parse string as incoming message: " + incoming);
                console.log("Mwi-Websocket Copy of actual error: ", e);
                return;
            }
            if (message === '') {
                console.log("Mwi-Websocket ERROR: Incoming message had an empty message: " + incoming);
                return;
            }
            if (this.debug) console.log("[ << " + channel + "." + message + "] ", data);
            this.receivedMessage(channel, message, data);
            return;
        }
        if (incoming.indexOf('SYS') === 0) {
            let message, data;
            try {
                let dataAsJson;
                [, message, dataAsJson] = incoming.match(Core.sysRegExp);
                data = (dataAsJson === '' ? null : JSON.parse(dataAsJson));
            } catch (e) {
                console.log("Mwi-Websocket ERROR: Failed to parse string as incoming system message: " + incoming);
                return;
            }
            if (message === '') {
                console.log("Mwi-Websocket ERROR: Incoming system message had an empty message: " + incoming);
                return;
            }
            if (this.debug) console.log("[ << " + message + "] ", data);
            this.receivedSystemMessage(message, data);
            return;
        }
        if (incoming === 'upgraded') {
            if (this.debug) console.log("Mwi-Websocket received notification on HttpStream that upgrade has occured.");
            //We don't actually do anything here, the websocket will also receive this notification and react.
            return;
        }
        console.log("Mwi-Websocket ERROR: Don't know what to do with the string: " + incoming);
    };

    /**
     *
     * @param {string} message
     * @param {any} data
     */
    receivedSystemMessage(message, data) {
        switch (message) {
            case 'channel':
                if (data in this.channels) this.channels[data].joined = true;
                else console.log("Mwi-Websocket ERROR: Muck acknowledged joining a channel we weren't aware of! Channel: " + data);
                break;
            case 'test':
                console.log("Mwi-Websocket Test message received. Data=", data);
                break;
            case 'ping': //This is actually http only, websockets do it at a lower level
                this.sendSystemMessage('pong', data);
                break;
            default:
                console.log("Mwi-Websocket ERROR: Unrecognized system message received: " + message);
        }
    };

    /**
     *
     * @param {string} channelName
     * @param {string} message
     * @param data
     */
    receivedMessage(channelName, message, data) {
        let channel = this.channels[channelName];
        if (!(channel instanceof Channel)) {
            if (this.debug) console.log("Received message on channel we're not aware of! Channel = " + channelName);
            return;
        }
        channel.receiveMessage.bind(channel)(message, data);
    };

    /**
     * Name of the present player. Empty string if no player.
     * @returns {string}
     */
    getPlayerName() {
        return this.playerName;
    };

    /**
     * Dbref of player represented as a number. -1 if no player.
     * @returns {number}
     */
    getPlayerDbref() {
        return this.playerDbref;
    };

    /**
     * Utility function to return whether a player exists
     * @returns {boolean}
     */
    getPlayerIsSet() {
        return this.playerDbref !== -1;
    };

    /**
     * Returns the present connection state.
     * One of: connecting, login, connected, failed
     * @returns {connectionStates}
     */
    getConnectionState() {
        return this.connectionStatus;
    };

    /**
     * Starts the attempts to connect.
     */
    startConnection() {
        if (this.debug) console.log("Starting connection.");
        this.updateAndDispatchStatus(Core.connectionStates.connecting);
        this.session = "";
        for (let channel in this.channels) {
            if (this.channels.hasOwnProperty(channel)) {
                //Channels will be re-joined but we need to let them know to buffer until the muck acknowledges them.
                this.channels[channel].joined = false;
            }
        }
        this.connection.connect();
    };

}