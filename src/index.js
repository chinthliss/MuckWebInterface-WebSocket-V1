const protocolVersion = 1;

let url;
// This would have been easier as 'window || global' but that didn't work under Mocha
let context = typeof(window) !== 'undefined' ? window : typeof(global) !== 'undefined' ? global : {};

if (context.location) {
    url = (location.protocol === 'https:'?'wss://':'ws://') // Ensure same level of security as page
    + location.hostname + "/liveconnect/ws";
} else {
    //No context.location means we're running under a test environment. Hopefully!
    url = "http://local.test";
}

// Overrides for local testing
if (process.env.NODE_ENV === 'development') {
    url = "ws://test.flexiblesurvival.com/liveconnect/ws";
}

url += '?protocolVersion=' + protocolVersion;

/*
let host = new Host(url);
export const channel = host.channel.bind(host);
export const onError = host.onError.bind(host);
export const onConnectionStateChange = host.onStatusChanged.bind(host);
export const onPlayerChange = host.onPlayerChanged.bind(host);
export const setDebug = host.setDebug.bind(host);
export const playerName = host.getPlayerName.bind(host);
export const playerDbref = host.getPlayerDbref.bind(host);
export const playerIsSet = host.getPlayerIsSet.bind(host);
export const connectionState = host.getConnectionState.bind(host);
*/