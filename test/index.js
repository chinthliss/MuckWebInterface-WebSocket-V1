const chai = require('chai');
const expect = chai.expect;

const websocket = require('../src/index.js');

describe('Library', function () {
    describe('Core', function () {
        it('Should provide a channel object', function () {
            expect(websocket).to.haveOwnProperty('channel');
        });
    });
});