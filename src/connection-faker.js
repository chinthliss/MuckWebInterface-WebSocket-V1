import Connection from "./connection";

/**
 * A fake connection for testing purposes
 */
export default class ConnectionFaker extends Connection {

    constructor(context, core) {
        super(context, core);
        this.url = "http://local.test";
    }

    connect() {
    }

    disconnect() {
    }

    sendString(stringToSend) {
    }

}