import Connection from "./connection.js";
import axios from "axios";
import Core from "./core.js";

/**
 * Handles the underlying websocket connection
 */
export default class ConnectionWebSocket extends Connection {

    /**
     * In case we're outdated and need a refresh.
     * @type {number}
     */
    protocolVersion = 1;

    /**
     * @type {string}
     */
    authenticationUrl;

    /**
     * @type {string}
     */
    websocketUrl;

    /**
     * @type {WebSocket}
     */
    connection;

    /**
     * @type {boolean}
     */
    receivedWelcome = false;

    /**
     * @type {boolean}
     */
    handshakeCompleted = false;

    /**
     * @type {number}
     */
    ensureConnectionTimeout = -1;

    /**
     * Used to hold messages that try to send before the initial connection is complete
     * @type {string[]}
     */
    connectingOutgoingMessageBuffer;

    /**
     * @param {Core} core
     * @param {object} options
     */
    constructor(core, options = {}) {
        super(core, options);

        if (!options.websocketUrl || !options.authenticationUrl) throw "Missing mandatory options";

        // Calculate where we're connecting to
        this.websocketUrl = options.websocketUrl;
        this.authenticationUrl = options.authenticationUrl;

        // Add parameters to Url
        this.websocketUrl += '?protocolVersion=' + this.protocolVersion;

    }

    clearConnectionTimeoutIfSet = () => {
        if (this.ensureConnectionTimeout !== -1) {
            clearTimeout(this.ensureConnectionTimeout);
            this.ensureConnectionTimeout = -1;
        }
    };

    /**
     * @param {CloseEvent} e
     */
    handleWebSocketClose = (e) => {
        this.core.logDebug("WebSocket closed: " + (e.reason ? e.reason : 'No reason given.'));
        console.log(e);
        this.clearConnectionTimeoutIfSet();
        this.core.connectionFailed("Websocket closed with " + (e.reason ? "reason: " + e.reason : "no reason given."));
    };

    /**
     * @param {ErrorEvent} e
     */
    handleWebSocketError = (e) => {
        this.core.logError('An error occurred with the websocket: ' + e.message)
        console.log(e);
        this.clearConnectionTimeoutIfSet();
        this.core.connectionFailed("Websocket returned error: " + e.message);
    }

    /**
     * @param {MessageEvent} e
     */
    handleWebSocketMessage = (e) => {
        let message = e.data.slice(0, -2); //Remove \r\n
        this.core.receivedString(message);
    }

    openWebsocket(websocketToken) {
        this.core.logDebug("Opening websocket");
        this.connection = new WebSocket(this.websocketUrl, 'mwi');

        this.connection.onopen = () => {
            this.core.updateAndDispatchStatus(Core.connectionStates.login);
            this.receivedWelcome = false;
            this.handshakeCompleted = false;
            this.connectingOutgoingMessageBuffer = [];
            this.ensureConnectionTimeout = setTimeout(function () {
                this.core.logError('WebSocket took too long to complete handshake, assuming failure.');
                this.core.connectionFailed("Websocket took too long to connect.");
            }.bind(this), 10000);
        };

        this.connection.onclose = this.handleWebSocketClose;
        this.connection.onerror = this.handleWebSocketError;

        // During connection, we use a special onMessage handling to deal with the handshake
        this.connection.onmessage = (e) => {
            let message = e.data.slice(0, -2); //Remove \r\n

            if (!this.receivedWelcome) {
                if (message === 'welcome') {
                    this.connection.send('auth ' + websocketToken + ' ' + location.href);
                    this.receivedWelcome = true;
                    this.core.logDebug("WebSocket received initial welcome message, attempting to authenticate.");
                } else this.core.logError("WebSocket got an unexpected message whilst expecting welcome: " + message);
                return;
            }

            if (!this.handshakeCompleted) {
                if (message.startsWith('accepted ')) {
                    this.core.logDebug("WebSocket received descr.");
                    let descr = message.slice(9);
                    this.clearConnectionTimeoutIfSet();
                    this.handshakeCompleted = true;
                    this.connection.onmessage = this.handleWebSocketMessage;
                    this.core.updateAndDispatchDescr(descr);
                    this.core.updateAndDispatchStatus(Core.connectionStates.connected);
                    //Resend anything that was buffered
                    for (let i = 0; i++; i < this.connectingOutgoingMessageBuffer.length) {
                        this.sendString(this.connectingOutgoingMessageBuffer[i]);
                    }
                    this.connectingOutgoingMessageBuffer = [];
                    return;
                }
                if (message === 'invalidtoken') {
                    this.core.connectionFailed("Server refused authentication token.");
                    return;
                }
                this.core.logError("WebSocket got an unexpected message whilst expecting descr: " + message);
                return;
            }
            this.core.logError("Unexpected message during login: " + message);
        }
    }

    connect() {
        if (this.connection && this.connection.readyState < 2) {
            console.log(this.connection);
            this.core.logError("Attempt to connect whilst socket already connecting.");
            return;
        }
        //Step 1 - we need to get an authentication token from the webpage
        let websocketToken;
        this.core.logDebug("Requesting authentication token from webpage");
        axios.get(this.authenticationUrl)
            .then((response) => {
                websocketToken = response.data;
                //Step 2 - connect to the websocket and throw the token at it
                this.openWebsocket(websocketToken);
            })
            .catch((error) => {
                this.core.logError("Failed to get an authentication token from the webpage. Error was:" + error);
                this.core.connectionFailed("Couldn't authenticate");
            });
    }

    disconnect() {
        this.core.logDebug(this.connection !== null ? "Closing websocket." : "No websocket to close.");
        if (this.connection !== null) this.connection.close(1000, "Disconnected");
        this.connection = null;
    }

    sendString(stringToSend) {
        if (stringToSend.length > 30000) {
            this.core.logError("Websocket had to abort sending a strings because it's over 30,000 characters.");
            return;
        }
        // Buffer the string if we're still connecting
        if (!this.receivedWelcome || !this.handshakeCompleted) {
            this.core.logDebug("Buffering outgoing message: " + stringToSend);
            return;
        }
        this.connection.send(stringToSend);
    }

}