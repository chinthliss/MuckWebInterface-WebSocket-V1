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
        if (this.core.debug) console.log("WebSocket closed: ", e);
        this.clearConnectionTimeoutIfSet();
        this.core.connectionFailed("Websocket closed with " + (e.reason ? "reason: " + e.reason : "no reason given."));
    };

    /**
     * @param {ErrorEvent} e
     */
    handleWebSocketError = (e) => {
        console.log("Mwi-Websocket Error - WebSocket error: ", e);
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
        this.connection = new WebSocket(this.websocketUrl, 'mwi');

        this.connection.onopen = () => {
            if (this.core.debug) console.log("WebSocket opened.");
            this.core.updateAndDispatchStatus(Core.connectionStates.login);
            this.receivedWelcome = false;
            this.handshakeCompleted = false;
            this.connectingOutgoingMessageBuffer = [];
            this.ensureConnectionTimeout = setTimeout(function () {
                console.log("Mwi-Websocket Error - WebSocket took too long to complete handshake, assuming failure.");
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
                    this.connection.send('auth ' + websocketToken);
                    this.receivedWelcome = true;
                    if (this.core.debug) console.log("WebSocket received initial welcome message, attempting to authenticate.");
                } else console.log("Mwi-Websocket Error - WebSocket got an unexpected message whilst expecting welcome: " + message);
                return;
            }

            if (!this.handshakeCompleted) {
                if (message.startsWith('session ')) {
                    if (this.core.debug) console.log("WebSocket received session.");
                    let session = message.slice(8);
                    this.clearConnectionTimeoutIfSet();
                    this.handshakeCompleted = true;
                    this.connection.onmessage = this.handleWebSocketMessage;
                    this.core.updateAndDispatchSession(session);
                    this.core.updateAndDispatchStatus(Core.connectionStates.connected);
                    //Resend anything that was buffered
                    for (let i = 0; i++; i < this.connectingOutgoingMessageBuffer.length) {
                        this.sendString(this.connectingOutgoingMessageBuffer[i]);
                    }
                    this.connectingOutgoingMessageBuffer = [];

                } else console.log("Mwi-Websocket Error - WebSocket got an unexpected message whilst expecting session: " + message);
                return;
            }
            console.log("Unexpected message during login: " + message);

        }
    }

    connect() {
        //Step 1 - we need to get an authentication token from the webpage
        if (this.core.environment === 'localdevelopment')
        {
            //Skip authentication for localdevelopment
            console.log("Skipping getting websocketToken for local development.");
            this.openWebsocket('localdevelopment');
            return;
        }
        let websocketToken;
        if (this.core.debug) console.log("Mwi-Websocket Requesting authentication token from webpage");
        axios.get(this.authenticationUrl)
            .then((response) => {
                websocketToken = response.data;
                //Step 2 - connect to the websocket and throw the token at it
                this.openWebsocket(websocketToken);
            })
            .catch((error) => {
                console.log("Mwi-Websocket ERROR: Failed to get an authentication token from the webpage. Error was:", error);
                this.core.connectionFailed("Couldn't authenticate");
            });
    }

    disconnect() {
        if (this.connection !== null) this.connection.close();
        this.connection = null;
    }

    sendString(stringToSend) {
        if (stringToSend.length > 30000) {
            console.log("Websocket connection - had to abort sending a strings because it's over 30,000 characters.");
            return;
        }
        // Buffer the string if we're still connecting
        if (!this.receivedWelcome || !this.handshakeCompleted) {
            if (this.core.debug) console.log("Buffering outgoing message: ", stringToSend);
            return;
        }
        this.connection.send(stringToSend);
    }

}