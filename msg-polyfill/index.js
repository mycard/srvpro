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
    let shrinkCount = 0;
    for (const polyfiller of polyfillers) {
        await polyfiller.polyfillGameMsg(msgTitle, buffer);
        if (polyfiller.shrinkCount > 0) {
            if (polyfiller.shrinkCount === 0x3f3f3f3f) {
                return 0x3f3f3f3f; // special case for cancel message
            }
            shrinkCount += polyfiller.shrinkCount;
        }
    }
    return shrinkCount;
}
async function polyfillResponse(version, msgTitle, buffer) {
    const polyfillers = getPolyfillers(version);
    for (const polyfiller of polyfillers) {
        await polyfiller.polyfillResponse(msgTitle, buffer);
    }
}
