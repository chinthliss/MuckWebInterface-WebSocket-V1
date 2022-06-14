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

    });
});