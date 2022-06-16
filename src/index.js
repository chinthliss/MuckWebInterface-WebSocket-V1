import Core from "./core.js";

let core = new Core();

export default {
    init: core.init.bind(core),
    channel: core.channel.bind(core),
    onError: core.onError.bind(core),
    onConnectionStateChange: core.onStatusChanged.bind(core),
    onPlayerChange: core.onPlayerChanged.bind(core),
    getPlayerName: core.getPlayerName.bind(core),
    getPlayerDbref: core.getPlayerDbref.bind(core),
    isPlayerSet: core.IsPlayerSet.bind(core),
    getConnectionState: core.getConnectionState.bind(core),
    setDebug: core.setDebug.bind(core)
}
