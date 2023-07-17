import Channel from "./channel.js";
import ConnectionWebSocket from "./connection-websocket.js";
import ConnectionFaker from "./connection-faker.js";

export default class Core {

    /**
     * Message in the form MSG<Channel>,<Message>,<Data>
     * @type {RegExp}
     * @readonly
     */
    static msgRegExp = /MSG(.*?),(.*?),(.*)/;

    /**
     * System message in the form SYS<Message>,<Data>
     * @type {RegExp}
     * @readonly
     */
    static sysRegExp = /SYS(.*?),(.*?),(.*)/;

    /**
     * @enum {string}
     * @readonly
     */
    static connectionStates = {
        disconnected: 'disconnected', // Only likely to be this at startup or if turned off
        connecting: 'connecting',
        login: 'login',
        connected: 'connected',
        failed: 'failed' // For when no more attempts will happen
    }

    /**
     * Not the best way to do this but couldn't find another way
     * @type {string}
     */
    environment = "production";

    /**
     * @type {boolean}
     */
    localStorageAvailable = false; // We'll set this properly in the constructor

    /**
     * @type {(connectionStates)}
     */
    connectionStatus = Core.connectionStates.disconnected;

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
     * Timeout handler for trying to reconnect if things weren't fatal
     * @type {number}
     */
    connectionRetry = -1;

    /**
     * Presently active channels, indexed by channel name
     * @type {Object.<string, Channel>}
     */
    channels = {};

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
     * Utility function to format errors
     * @param {string} message
     */
    logError(message) {
        console.log("Mwi-Websocket ERROR: " + message);
    }

    /**
     * Utility function to format debug lines and omit if disabled
     * @param {string} message
     */
    logDebug(message) {
        if (this.debug) console.log("Mwi-Websocket DEBUG: " + message);
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
        if (this.connectionStatus === Core.connectionStates.connected) this.sendSystemMessage('joinChannels', channelName);
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
    }

    /**
     * Called by present connection
     * @param {number} newDbref New Dbref for player
     * @param {string} newName New name for the player
     */
    updateAndDispatchPlayer(newDbref, newName) {
        if (this.playerDbref === newDbref && this.playerName === newName) return;
        this.playerDbref = newDbref;
        this.playerName = newName;
        this.logDebug("Player changed: " + newName + '(' + newDbref + ')');
        for (let i = 0, maxi = this.playerChangedHandlers.length; i < maxi; i++) {
            try {
                this.playerChangedHandlers[i](newDbref, newName);
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
        this.logDebug('Connection status changed to ' + newStatus + ' (from ' + this.connectionStatus + ')');
        this.connectionStatus = newStatus;

        // Maybe need to send channel join requests?
        if (newStatus === Core.connectionStates.connected) {
            let channelsToJoin = [];
            for (let channel in this.channels) {
                if (this.channels.hasOwnProperty(channel) && !this.channels[channel].joined) {
                    channelsToJoin.push(channel);
                }
            }
            if (channelsToJoin.length > 0) this.sendSystemMessage('joinChannels', channelsToJoin);
        }

        //Callbacks
        for (let i = 0, maxi = this.statusChangedHandlers.length; i < maxi; i++) {
            try {
                this.statusChangedHandlers[i](newStatus);
            } catch (e) {
            }
        }
    };

    /**
     * @param {string} error
     */
    dispatchCriticalError(error) {
        console.log("Mwi-Websocket Critical Error reported: " + error);
        for (let i = 0, maxi = this.errorHandlers.length; i < maxi; i++) {
            try {
                this.errorHandlers[i](error);
            } catch (e) {
            }
        }
    }

    //endregion Event Processing

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
                this.logError("Failed to parse string as incoming message: " + incoming);
                console.log(e);
                return;
            }
            if (message === '') {
                this.logError("Incoming message had an empty message: " + incoming);
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
                this.logError("Failed to parse string as incoming system message: " + incoming);
                return;
            }
            if (message === '') {
                this.logError("Incoming system message had an empty message: " + incoming);
                return;
            }
            if (this.debug) console.log("[ << " + message + "] ", data);
            this.receivedSystemMessage(message, data);
            return;
        }
        this.logError("Don't know what to do with the string: " + incoming);
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
                else this.logError("Muck acknowledged joining a channel we weren't aware of! Channel: " + data);
                break;
            case 'test':
                console.log("Mwi-Websocket Test message received. Data=", data);
                break;
            case 'ping': //This is actually http only, websockets do it at a lower level
                this.sendSystemMessage('pong', data);
                break;
            default:
                this.logError("Unrecognized system message received: " + message);
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
            this.logError("Received message on channel we're not aware of! Channel = " + channelName);
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
    IsPlayerSet() {
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
     * @param {string} reason
     * @param {boolean} fatal Whether to prevent trying again
     */
    connectionFailed(reason, fatal = false) {
        this.updateAndDispatchStatus(Core.connectionStates.failed);
        // Start again unless the problem was fatal
        if (fatal) {
            this.dispatchCriticalError(reason);
            console.log("Fatal Error, cancelling any further attempt to connect.");
        } else {
            if (this.connectionRetry === -1) {
                this.connectionRetry = setTimeout(this.startConnection.bind(this), 1000);
                this.logDebug("Connection retry queued.");
            }
        }
    }

    /**
     * Boots the library. Following options are presently supported
     * environment - Defaults to production. Code will check process.env.NODE_ENV first but this can override such.
     * websocketUrl - The url the websocket connection should use
     * authenticationUrl - The url that should be used to get an authentication token for the websocket connection
     * @param {object} options
     */
    init(options = {}) {

        if (this.connection) {
            this.logError("Attempt to run init() when initialisation has already taken place.");
            return;
        }
        // Previously this was a test to find something in order of self, window, global
        let context = globalThis;

        // Change/override environment if required
        if (typeof process !== 'undefined' && process?.env?.NODE_ENV) this.environment = process.env.NODE_ENV.toString();
        if (options.environment) this.environment = options.environment;

        // Figure out whether we have local storage (And load debug option if so)
        this.localStorageAvailable = 'localStorage' in context;
        if (this.localStorageAvailable && localStorage.getItem('mwiWebsocket-debug') === 'y') this.debug = true;
        if (this.environment === 'localdevelopment') this.debug = true; // No local storage in localdev

        // Work out which connection we're using
        if (this.environment === 'test') this.connection = new ConnectionFaker(this, options);
        if (!this.connection) {
            if ("WebSocket" in context) {
                // Calculate where we're connecting to
                if (context.location) {
                    if (!options.websocketUrl) options.websocketUrl =
                        (location.protocol === 'https:' ? 'wss://' : 'ws://') // Ensure same level of security as page
                        + location.hostname + "/mwi/ws";
                    if (!options.authenticationUrl) options.authenticationUrl = location.origin + '/getWebsocketToken';
                }
                this.connection = new ConnectionWebSocket(this, options);
            }
        }
        if (!this.connection) throw "Failed to find any usable connection method";

        // And start the connection up
        this.startConnection();
    }

    /**
     * Starts the attempts to connect.
     */
    startConnection() {
        this.logDebug("Starting connection.");
        this.connectionRetry = -1;
        this.updateAndDispatchStatus(Core.connectionStates.connecting);
        this.updateAndDispatchPlayer(-1, '');
        for (let channel in this.channels) {
            if (this.channels.hasOwnProperty(channel)) {
                //Channels will be re-joined if required, but we need to let them know to buffer until the muck acknowledges them.
                this.channels[channel].joined = false;
            }
        }
        this.connection.connect();
    };

}