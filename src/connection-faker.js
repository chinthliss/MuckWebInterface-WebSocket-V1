import Connection from "./connection.js";

/**
 * A fake connection for testing purposes
 */
export default class ConnectionFaker extends Connection {

    constructor(context, core) {
        super(context, core);
    }

    connect() {
    }

    disconnect() {
    }

    sendString(stringToSend) {
    }

}