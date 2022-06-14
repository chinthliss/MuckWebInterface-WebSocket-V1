import Connection from "./connection";

/**
 * A fake connection for testing purposes
 */
export default class ConnectionFaker extends Connection {

    constructor(url, core) {
        super(url, core);
    }

    connect() {
    }

    disconnect() {
    }

    sendString(stringToSend) {
    }

}