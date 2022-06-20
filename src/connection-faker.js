import Connection from "./connection.js";
import Core from "./core.js";

/**
 * A fake connection for testing purposes
 */
export default class ConnectionFaker extends Connection {

    constructor(core, options = {}) {
        super(core, options);
    }

    connect() {
        this.core.updateAndDispatchSession('1234');
        this.core.updateAndDispatchStatus(Core.connectionStates.connected);
        this.core.updateAndDispatchPlayer(1, 'TestPlayer');
    }

    disconnect() {
    }

    sendString(stringToSend) {
        //Reflect anything that has 'reflect' as the message
        let [channel, message, data] = stringToSend.split(',', 3);
        if (message === 'reflect') {
            channel = channel.slice(3);
            this.core.receivedString('MSG' + channel + ',reflected,' + data);
        }
    }

}