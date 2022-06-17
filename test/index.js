// const chai = require('chai');
import * as chai from 'chai';

const expect = chai.expect;

import websocket from '../src/index.js';

describe('MWI-Websocket', function () {

    before(() => {
        process.env.NODE_ENV = 'test';
    });

    afterEach(() => {
        websocket.reset();
    })

    describe('Core', function () {

        it('Should allow registering a callback for errors', function () {
            expect(websocket).to.haveOwnProperty('onError');
            expect(websocket.onError).to.be.a('function');
            expect(() => websocket.onError(() => {
            })).to.not.throw();
        });

        it('Should have an an init function and startup okay', function () {
            expect(websocket).to.haveOwnProperty('init');
            expect(websocket.init).to.be.a('function');
            expect(() => websocket.init(() => {
            })).to.not.throw();
        });
    });

    describe('ConnectionStatus', function () {

        it('Should be able to register a callback for connection state changes', function () {
            expect(websocket).to.haveOwnProperty('onConnectionStateChange');
            expect(websocket.onConnectionStateChange).to.be.a('function');
            expect(() => websocket.onConnectionStateChange(() => {
            })).to.not.throw();
        });

        it('Should change from disconnected to connected during startup', function () {
            expect(websocket.getConnectionState()).to.equal('disconnected');
            websocket.init();
            expect(websocket.getConnectionState()).to.equal('connected');
        })

        it('Should throw an event for change', function (done) {
            websocket.onConnectionStateChange((newStatus) => {
                expect(newStatus).to.equal('connected');
                done();
            });
            websocket.init();
        })
    });

    describe('Player Change', function () {

        it('Should be able to register a callback for player changes', function () {
            expect(websocket).to.haveOwnProperty('onPlayerChange');
            expect(websocket.onPlayerChange).to.be.a('function');
            expect(() => websocket.onPlayerChange(() => {
            })).to.not.throw();
        });

        it('Should change during startup', function () {
            expect(websocket.getPlayerDbref()).to.equal(-1);
            expect(websocket.getPlayerName()).to.equal('');
            expect(websocket.isPlayerSet()).to.equal(false);
            websocket.init();
            expect(websocket.getPlayerDbref()).to.equal(1);
            expect(websocket.getPlayerName()).to.equal('TestPlayer');
            expect(websocket.isPlayerSet()).to.equal(true);
        })

        it('Should throw an event for change', function (done) {
            websocket.onPlayerChange((newDbref, newName) => {
                expect(newDbref).to.equal(1);
                expect(newName).to.equal('TestPlayer');
                done();
            });
            websocket.init();
        })
    });

    describe('Channels', function () {

        it('Should be able to get a channel interface', function () {
            websocket.init();
            expect(websocket).to.haveOwnProperty('channel');
            expect(websocket.channel).to.be.a('function');
            const channel = websocket.channel('test');
            expect(channel).to.be.a('object');
            expect(channel.send).to.be.a('function');
            expect(channel.on).to.be.a('function');
        })

        it('Should be able to send a message', function () {
            websocket.init();
            const channel = websocket.channel('test');
            expect(() => {
                channel.send('out');
            }).to.not.throw();
        })

        it('Should be able to receive a message', function (done) {
            websocket.init();
            const channel = websocket.channel('test');
            channel.on('reflected', (data) => {
                expect(data).to.equal('data');
                done();
            });
            expect(() => {
                channel.send('reflect', 'data');
            }).to.not.throw();
        })

    });

});