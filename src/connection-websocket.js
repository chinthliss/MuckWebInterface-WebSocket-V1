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

    constructor(context, core) {
        super(context, core);

        // Calculate where we're connecting to
        if (context.location) {
            this.websocketUrl = (location.protocol === 'https:' ? 'wss://' : 'ws://') // Ensure same level of security as page
                + location.hostname + "/mwi/ws";
            this.authenticationUrl = location.origin + '/getWebsocketToken';
        } else {
            // As of writing, the only context without a location should be testing which should be us
            throw "No location in provided context!"
        }
        // Overrides for local testing
        if (this.core.environment === 'development') {
            this.websocketUrl = "wss://beta.flexiblesurvival.com/mwi/ws";
            this.websocketUrl = "https://beta.flexiblesurvival.com/getWebsocketToken";
        }

        // Add parameters to Url
        this.websocketUrl += '?protocolVersion=' + this.protocolVersion;

    }

    openWebsocket(websocketToken) {
        this.connection = new WebSocket(this.websocketUrl, 'mwi');

        this.connection.onopen = () => {
            if (this.core.debug) console.log("WebSocket opened.");
            this.core.updateAndDispatchStatus(Core.connectionStates.login);
            this.receivedWelcome = false;
            this.handshakeCompleted = false;
            this.ensureConnectionTimeout = setTimeout(function () {
                console.log("Mwi-Websocket Error - WebSocket took too long to complete handshake, assuming failure.");
                this.core.connectionFailed("Websocket took too long to connect.");
            }.bind(this), 10000);
        };

        this.connection.onclose = () => {
            if (this.core.debug) console.log("WebSocket closed.");
            this.core.connectionFailed("Websocket closed unexpectedly.")
        };

        this.connection.onerror = (e) => {
            console.log("Mwi-Websocket Error - WebSocket error: ", e);
            this.core.connectionFailed("Websocket return error: " + e);
        };

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
                    this.handshakeCompleted = true;
                    let session = message.slice(8);
                    this.core.updateAndDispatchSession(session);
                    this.core.updateAndDispatchStatus(Core.connectionStates.connected);
                    clearTimeout(this.ensureConnectionTimeout);
                } else console.log("Mwi-Websocket Error - WebSocket got an unexpected message whilst expecting session: " + message);
                return;
            }
            this.core.receivedString(message);
        }
    }

    connect() {
        //Step 1 - we need to get an authentication token from the webpage
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
        this.connection.send(stringToSend);
    }

}