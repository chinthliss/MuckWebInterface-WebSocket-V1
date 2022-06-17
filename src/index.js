import Core from "./core.js";

let core;
const publicInterface = {};

// This is pretty much a separate function just so it can be called during testing to reset things.
let setup = function () {
    core = new Core();
    publicInterface.init = core.init.bind(core);
    publicInterface.channel = core.channel.bind(core);
    publicInterface.onError = core.onError.bind(core);
    publicInterface.onConnectionStateChange = core.onStatusChanged.bind(core);
    publicInterface.onPlayerChange = core.onPlayerChanged.bind(core);
    publicInterface.getPlayerName = core.getPlayerName.bind(core);
    publicInterface.getPlayerDbref = core.getPlayerDbref.bind(core);
    publicInterface.isPlayerSet = core.IsPlayerSet.bind(core);
    publicInterface.getConnectionState = core.getConnectionState.bind(core);
    publicInterface.setDebug = core.setDebug.bind(core);
};
setup();

// Used for testing. May be worth adding something to only expose during such?
publicInterface.reset = () => {
    setup()
};

export default publicInterface;