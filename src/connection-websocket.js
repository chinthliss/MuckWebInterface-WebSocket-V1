import Connection from "./connection";

/**
 * Handles the underlying websocket connection
 */
export default class ConnectionWebSocket extends Connection {

    /**
     * In case we're outdated and need a refresh.
     * @type {number}
     */
    static protocolVersion = 1;

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
            this.url = (location.protocol === 'https:' ? 'wss://' : 'ws://') // Ensure same level of security as page
                + location.hostname + "/liveconnect/ws";
        } else {
            // As of writing, the only context without a location should be testing which should be us
            throw "No location in provided context!"
        }
        // Overrides for local testing
        if (environment === 'development') {
            this.url = "ws://test.flexiblesurvival.com/liveconnect/ws";
        }

        // Add parameters to Url
        this.url += '?protocolVersion=' + this.protocolVersion;

    }

    connect() {
        this.connection = new WebSocket(this.url + "&session=" + this.core.session, 'mwi');

        this.connection.onopen = () => {
            if (this.core.debug) console.log("WebSocket opened.");
            this.receivedWelcome = false;
            this.handshakeCompleted = false;
            this.ensureConnectionTimeout = setTimeout(function () {
                console.log("MwiLive Error - WebSocket took too long to complete handshake, assuming failure.");
                this.core.websocketFailed();
            }.bind(this), 10000);
        };

        this.connection.onclose = () => {
            if (this.core.debug) console.log("WebSocket closed - passing back to host.");
            this.core.websocketFailed();
        };

        this.connection.onerror = (e) => {
            console.log("MwiLive Error - WebSocket error: ", e);
            this.core.websocketFailed();
        };

        this.connection.onmessage = (e) => {
            let message = e.data.slice(0, -2); //Remove \r\n
            if (!this.receivedWelcome) {
                if (message === 'welcome') {
                    this.connection.send('welcome');
                    this.receivedWelcome = true;
                    if (this.core.debug) console.log("WebSocket received initial welcome message.");
                } else console.log("MwiLive Error - WebSocket got an unexpected message whilst expecting welcome: " + message);
                return;
            }
            if (!this.handshakeCompleted) {
                if (message === 'upgraded') {
                    if (this.core.debug) console.log("WebSocket received handshake.");
                    this.handshakeCompleted = true;
                    this.core.completeWebSocketUpgrade();
                    clearTimeout(this.ensureConnectionTimeout);
                } else console.log("MwiLive Error - WebSocket got an unexpected message whilst expecting handshake completion: " + message);
                return;
            }
            this.core.receivedString(message);
        }
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