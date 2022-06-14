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
     * @param {string} url URL to connect to
     * @param {Core} core Object to send notifications and share properties.
     */
    constructor(url, core) {
        if (typeof url !== 'string' || url === '') throw "Attempt to create connection with no url specified.";
        if (typeof core !== 'object') throw "Attempt to create connection with core dependency not passed.";
        this.url = url;
        this.core = core;
    }

    maybePropagateSessionChange(newSession) {
        if (this.core.session !== newSession) {
            this.core.session = newSession;
            this.core.SessionChanged(newSession);
        }
    }

    maybePropagatePlayerChange(newPlayerDbref, newPlayerName) {
        if (typeof newPlayerDbref !== 'number') newPlayerDbref = parseInt(newPlayerDbref);
        if (this.core.playerDbref !== newPlayerDbref || this.core.playerName !== newPlayerName) {
            this.core.playerDbref = newPlayerDbref;
            this.core.playerName = newPlayerName;
            this.core.PlayerChanged(newPlayerDbref, newPlayerName);
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