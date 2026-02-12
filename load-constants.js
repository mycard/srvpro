"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.loadConstants = void 0;
const ygopro_msg_encode_1 = require("ygopro-msg-encode");
const fs_1 = __importDefault(require("fs"));
const path_1 = __importDefault(require("path"));
const loadConstantsJson = () => {
    const filePath = path_1.default.join(__dirname, "data", "constants.json");
    const raw = fs_1.default.readFileSync(filePath, "utf8");
    return JSON.parse(raw);
};
const addMissingNumberEntries = (target, source, prefix) => {
    for (const [key, value] of Object.entries(source)) {
        if (!key.startsWith(prefix)) {
            continue;
        }
        if (target[key] === undefined) {
            target[key] = value;
        }
    }
};
const addMissingStringEntries = (target, source, prefix) => {
    for (const [key, value] of Object.entries(source)) {
        if (!key.startsWith(prefix)) {
            continue;
        }
        const codeKey = String(value);
        if (target[codeKey] === undefined) {
            target[codeKey] = key.slice(prefix.length);
        }
    }
};
const legacyMsgFallback = {
    "3": "WAITING",
    "4": "START",
    "6": "UPDATE_DATA",
    "8": "REQUEST_DECK",
    "21": "SORT_CHAIN",
    "34": "REFRESH_DECK",
    "39": "MSG_SHUFFLE_EXTRA",
    "80": "CARD_SELECTED",
    "95": "UNEQUIP",
    "121": "BE_CHAIN_TARGET",
    "122": "CREATE_RELATION",
    "123": "RELEASE_RELATION",
};
const toConstantName = (name) => name
    .replace(/^_+|_+$/g, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .toUpperCase();
const normalizeProtoName = (name) => name
    .replace("TO_OBSERVER", "TOOBSERVER")
    .replace("TO_DUELIST", "TODUELIST")
    .replace("HS_NOT_READY", "HS_NOTREADY")
    .replace("KICK", "HS_KICK");
const buildProtoMap = (registry, classPrefix) => {
    const out = {};
    for (const [id, cls] of registry.protos.entries()) {
        const className = cls.name.replace(/^_+/, "");
        const rawName = className.startsWith(classPrefix)
            ? className.slice(classPrefix.length)
            : className;
        const name = normalizeProtoName(toConstantName(rawName));
        out[String(id)] = name;
    }
    return out;
};
const loadConstants = () => {
    const result = loadConstantsJson();
    if (!result.TYPES)
        result.TYPES = {};
    if (!result.RACES)
        result.RACES = {};
    if (!result.ATTRIBUTES)
        result.ATTRIBUTES = {};
    if (!result.LINK_MARKERS)
        result.LINK_MARKERS = {};
    if (!result.MSG)
        result.MSG = {};
    if (!result.TIMING)
        result.TIMING = {};
    if (!result.CTOS)
        result.CTOS = {};
    if (!result.STOC)
        result.STOC = {};
    if (!result.NETWORK)
        result.NETWORK = {};
    if (!result.NETPLAYER)
        result.NETPLAYER = {};
    if (!result.PLAYERCHANGE)
        result.PLAYERCHANGE = {};
    if (!result.ERRMSG)
        result.ERRMSG = {};
    if (!result.MODE)
        result.MODE = {};
    if (!result.DUEL_STAGE)
        result.DUEL_STAGE = {};
    if (!result.COLORS)
        result.COLORS = {};
    addMissingNumberEntries(result.TYPES, ygopro_msg_encode_1.OcgcoreCommonConstants, "TYPE_");
    addMissingNumberEntries(result.RACES, ygopro_msg_encode_1.OcgcoreCommonConstants, "RACE_");
    addMissingNumberEntries(result.ATTRIBUTES, ygopro_msg_encode_1.OcgcoreCommonConstants, "ATTRIBUTE_");
    addMissingNumberEntries(result.ATTRIBUTES, ygopro_msg_encode_1.OcgcoreScriptConstants, "ATTRIBUTE_");
    addMissingNumberEntries(result.LINK_MARKERS, ygopro_msg_encode_1.OcgcoreCommonConstants, "LINK_MARKER_");
    addMissingStringEntries(result.MSG, ygopro_msg_encode_1.OcgcoreCommonConstants, "MSG_");
    addMissingStringEntries(result.TIMING, ygopro_msg_encode_1.OcgcoreScriptConstants, "TIMING_");
    for (const [code, name] of Object.entries(legacyMsgFallback)) {
        result.MSG[code] = name;
    }
    const ctosMap = buildProtoMap(ygopro_msg_encode_1.YGOProCtos, "YGOProCtos");
    const stocMap = buildProtoMap(ygopro_msg_encode_1.YGOProStoc, "YGOProStoc");
    const mismatches = [];
    for (const [code, name] of Object.entries(ctosMap)) {
        if (result.CTOS[code] !== undefined && result.CTOS[code] !== name) {
            mismatches.push(`CTOS ${code}: ${result.CTOS[code]} != ${name}`);
        }
        result.CTOS[code] = name;
    }
    for (const [code, name] of Object.entries(stocMap)) {
        if (result.STOC[code] !== undefined && result.STOC[code] !== name) {
            mismatches.push(`STOC ${code}: ${result.STOC[code]} != ${name}`);
        }
        result.STOC[code] = name;
    }
    if (mismatches.length) {
        throw new Error(`CTOS/STOC name mismatch between constants.json and registry:\\n${mismatches.join("\\n")}`);
    }
    if (result.RACES.RACE_CYBERS === undefined &&
        result.RACES.RACE_CYBERSE !== undefined) {
        result.RACES.RACE_CYBERS = result.RACES.RACE_CYBERSE;
    }
    return result;
};
exports.loadConstants = loadConstants;
exports.default = exports.loadConstants;
if (typeof require !== "undefined" && require.main === module) {
    console.log(JSON.stringify((0, exports.loadConstants)(), null, 2));
}
