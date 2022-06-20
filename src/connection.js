/**
 * Contract for a self-contained object for holding a connection open.
 * @abstract
 */
export default class Connection {

    /**
     * @type {Core}
     */
    core;

    /**
     * @param {Core} core Reference to the core service, so we can communication with it
     * @param {object} options Intended more to be used by inheriting services
     */
    constructor(core, options = {}) {
        if (typeof core !== 'object') throw "Missing or incorrect argument - core";
        this.core = core;
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