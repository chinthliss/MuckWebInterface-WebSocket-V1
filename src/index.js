import Core from "./core";

let core = new Core();

export const channel = core.channel.bind(core);
export const onError = core.onError.bind(core);
export const onConnectionStateChange = core.onStatusChanged.bind(core);
export const onPlayerChange = core.onPlayerChanged.bind(core);
export const setDebug = core.setDebug.bind(core);
export const playerName = core.getPlayerName.bind(core);
export const playerDbref = core.getPlayerDbref.bind(core);
export const playerIsSet = core.getPlayerIsSet.bind(core);
export const connectionState = core.getConnectionState.bind(core);