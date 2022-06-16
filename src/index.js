import Core from "./core";

let core = new Core();

export const channel = core.channel.bind(core);
export const onError = core.onError.bind(core);
export const onConnectionStateChange = core.onStatusChanged.bind(core);
export const onPlayerChange = core.onPlayerChanged.bind(core);
export const getPlayerName = core.getPlayerName.bind(core);
export const getPlayerDbref = core.getPlayerDbref.bind(core);
export const isPlayerSet = core.IsPlayerSet.bind(core);
export const getConnectionState = core.getConnectionState.bind(core);
export const setDebug = core.setDebug.bind(core);