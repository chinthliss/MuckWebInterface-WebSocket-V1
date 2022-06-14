import ChannelInterface from "./channel-interface.js";
import Core from "./channel-interface.js";

/**
 * Functionality for an individual channel
 */
export default class Channel {
    /**
     * @type {string};
     */
    name;

    /**
     * Collection of callbacks, indexed by the message they're receiving
     * @type {Object.<string, function[]>}
     */
    callbacks = {};

    /**
     * Callbacks that will receive any message
     * @type {function[]}
     */
    monitors = [];

    /**
     * Link back to the core object for transmitting
     * @type {Core}
     */
    core;

    /**
     * The public interface that will be passed back to the calling page
     * @type {ChannelInterface}
     */
    interface;

    /**
     * @param {string} channelName
     * @param {Core} core
     */
    constructor(channelName, core) {
        if (typeof channelName !== 'string' || channelName === '') throw "Attempt to create channel with no channelName specified.";
        if (typeof core !== 'object' || !(core instanceof Core)) throw "Attempt to create channel with core dependency not passed.";
        this.name = channelName;
        this.core = core;
        this.interface = new ChannelInterface(this);
    }

    receiveMessage(message, data) {
        let channel = this;
        for (let i = 0, maxi = this.monitors.length; i < maxi; i++) {
            setTimeout(function () {
                channel.monitors[i](message, data, false);
            });
        }
        if (Array.isArray(this.callbacks[message])) {
            for (let i = 0, maxi = this.callbacks[message].length; i < maxi; i++) {
                setTimeout(function () {
                    channel.callbacks[message][i](data);
                });
            }
        }
    }

    sendMessage(message, data) {
        let channel = this;
        for (let i = 0, maxi = this.monitors.length; i < maxi; i++) {
            setTimeout(function () {
                channel.monitors[i](message, data, true);
            }.bind(this));
        }
        this.core.sendMessage(this.name, message, data);
    }

}
