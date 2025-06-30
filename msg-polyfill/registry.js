"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.polyfillRegistry = void 0;
const _0x1361_1 = require("./polyfillers/0x1361");
exports.polyfillRegistry = new Map();
const addPolyfiller = (version, polyfiller) => {
    exports.polyfillRegistry.set(version, polyfiller);
};
addPolyfiller(0x1361, _0x1361_1.Polyfiller1361);
