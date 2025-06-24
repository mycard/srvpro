"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.polyfillGameMsg = polyfillGameMsg;
exports.polyfillResponse = polyfillResponse;
const registry_1 = require("./registry");
const getPolyfillers = (version) => {
    const polyfillers = [];
    for (const [pVersion, instance] of registry_1.polyfillRegistry.entries()) {
        if (version <= pVersion) {
            polyfillers.push({ version: pVersion, polyfiller: instance });
        }
    }
    polyfillers.sort((a, b) => a.version - b.version);
    return polyfillers.map(p => p.polyfiller);
};
async function polyfillGameMsg(version, msgTitle, buffer) {
    const polyfillers = getPolyfillers(version);
    for (const polyfiller of polyfillers) {
        if (await polyfiller.polyfillGameMsg(msgTitle, buffer)) {
            return true;
        }
    }
    return false;
}
async function polyfillResponse(version, msgTitle, buffer) {
    const polyfillers = getPolyfillers(version);
    for (const polyfiller of polyfillers) {
        if (await polyfiller.polyfillResponse(msgTitle, buffer)) {
            return true;
        }
    }
    return false;
}
