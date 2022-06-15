import Core from "./channel-interface";

/**
 * Contract for a self-contained object for holding a connection open.
 * @abstract
 */
export default class Connection {

    /**
     * @type {string}
     */
    url;

    /**
     * @type {Core}
     */
    core;

    /**
     * @param {Object} context Either window, global or self. The object holding the environmental globals.
     * @param {Core} core Object to send notifications and share properties.
     */
    constructor(context, core) {
        if (typeof context !== 'object') throw "Missing or incorrect argument - context";
        if (typeof core !== 'object') throw "Missing or incorrect argument - core";
        this.core = core;
        // Context is intended to be used by connections overriding this one.
    }

    maybePropagateSessionChange(newSession) {
        if (this.core.session !== newSession) {
            this.core.session = newSession;
            this.core.updateAndDispatchSession(newSession);
        }
    }

    maybePropagatePlayerChange(newPlayerDbref, newPlayerName) {
        if (typeof newPlayerDbref !== 'number') newPlayerDbref = parseInt(newPlayerDbref);
        if (this.core.playerDbref !== newPlayerDbref || this.core.playerName !== newPlayerName) {
            this.core.playerDbref = newPlayerDbref;
            this.core.playerName = newPlayerName;
            this.core.updateAndDispatchPlayerChanged(newPlayerDbref, newPlayerName);
        }
    }

    /////////////////////////////////////
    //Functions that should be replaced
    /////////////////////////////////////

    /**
     * Drops any existing connection, intended to be used when a connection is being swapped out for another
     * @virtual
     */
    disconnect() {
        throw "Default function should have been overridden.";
    }

    /**
     * @virtual
     */
    connect() {
        throw "Default function should have been overridden.";
    }

    /**
     * @virtual
     */
    sendString() {
        throw "Default function should have been overridden.";
    }

}