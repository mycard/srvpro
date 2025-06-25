"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.polyfillGameMsg = polyfillGameMsg;
exports.polyfillResponse = polyfillResponse;
const registry_1 = require("./registry");
const getPolyfillers = (version) => {
    const polyfillers = [];
    for (const [pVersion, polyfillerCls] of registry_1.polyfillRegistry.entries()) {
        if (version <= pVersion) {
            polyfillers.push({ version: pVersion, polyfiller: new polyfillerCls() });
        }
    }
    polyfillers.sort((a, b) => a.version - b.version);
    return polyfillers.map(p => p.polyfiller);
};
async function polyfillGameMsg(version, msgTitle, buffer) {
    const polyfillers = getPolyfillers(version);
    let mutated = false;
    for (const polyfiller of polyfillers) {
        const newBuf = await polyfiller.polyfillGameMsg(msgTitle, buffer);
        if (newBuf) {
            mutated = true;
            buffer = newBuf;
        }
    }
    return mutated ? buffer : undefined;
}
async function polyfillResponse(version, msgTitle, buffer) {
    const polyfillers = getPolyfillers(version);
    for (const polyfiller of polyfillers) {
        await polyfiller.polyfillResponse(msgTitle, buffer);
    }
}
