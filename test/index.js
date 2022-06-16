const chai = require('chai');
const expect = chai.expect;

process.env.NODE_ENV = 'test'
const websocket = require('../src/index.js');

describe('Library', function () {
    describe('Core', function () {

        it('Should provide a channel function', function () {
            expect(websocket).to.haveOwnProperty('channel');
            expect(websocket.channel).to.be.a('function');
        });

        it('Should allow registering a callback for errors', function () {
            expect(websocket).to.haveOwnProperty('onError');
            expect(websocket.onError).to.be.a('function');
            expect(() => websocket.onError(() => {})).to.not.throw();
        });

        it('Should allow registering a callback for connection state changes', function () {
            expect(websocket).to.haveOwnProperty('onConnectionStateChange');
            expect(websocket.onConnectionStateChange).to.be.a('function');
            expect(() => websocket.onConnectionStateChange(() => {})).to.not.throw();
        });

        it('Should allow registering a callback for player changes', function () {
            expect(websocket).to.haveOwnProperty('onPlayerChange');
            expect(websocket.onPlayerChange).to.be.a('function');
            expect(() => websocket.onPlayerChange(() => {})).to.not.throw();
        });

    });
});