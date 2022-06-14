import Channel from "./channel.js";

/**
 * The parts of a channel that will be exposed to a program using this library
 */
export default class ChannelInterface {
    /**
     * Channel object hosting this public interface
     * @type {Channel} channel
     */
    #channel;

    /**
     * @param {Channel} channel
     */
    constructor(channel) {
        if (!(channel instanceof Channel)) throw "Attempt to create a channel interface without a valid channel reference"
        this.#channel = channel;
    }

    name() {
        return this.#channel.name;
    }

    toString() {
        return "Channel[" + this.name() + "]"
    }

    /**
     * Used to register callbacks for when a given message arrives via this channel.
     * The given callback will receive whatever data the muck sends
     * @param {string} message
     * @param {function} callback
     */
    on(message, callback) {
        if (typeof message !== 'string' || message === "" || typeof callback !== 'function')
            throw "Invalid Arguments";
        if (!(message in this.#channel.callbacks)) this.#channel.callbacks[message] = [];
        this.#channel.callbacks[message].push(callback.bind(this));
    }

    /**
     * Called on ANY message, mostly intended to monitor a channel in development
     * The given callback will receive (message, data, outgoing?)
     * @param {function} callback
     */
    any(callback) {
        if (typeof callback !== 'function') throw "Invalid Arguments";
        this.#channel.monitors.push(callback.bind(this));
    }

    /**
     * Sends a message via this channel
     * @param {string} message
     * @param data
     */
    send(message, data) {
        if (typeof (message) !== 'string' || message === "") throw "Send called without a text message";
        this.#channel.sendMessage(message, data);
    }
}