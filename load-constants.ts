import {
  OcgcoreCommonConstants,
  OcgcoreScriptConstants,
  YGOProCtos,
  YGOProStoc,
} from "ygopro-msg-encode";
import fs from "fs";
import path from "path";

export interface ConstantsShape {
  TYPES: Record<string, number>;
  RACES: Record<string, number>;
  ATTRIBUTES: Record<string, number>;
  LINK_MARKERS: Record<string, number>;
  DUEL_STAGE: Record<string, number>;
  COLORS: Record<string, number>;
  TIMING: Record<string, string>;
  NETWORK: Record<string, string>;
  NETPLAYER: Record<string, string>;
  CTOS: Record<string, string>;
  STOC: Record<string, string>;
  PLAYERCHANGE: Record<string, string>;
  ERRMSG: Record<string, string>;
  MODE: Record<string, string>;
  MSG: Record<string, string>;
}

type StringMap = Record<string, string>;
type NumberMap = Record<string, number>;

const loadConstantsJson = (): Partial<ConstantsShape> => {
  const filePath = path.join(__dirname, "data", "constants.json");
  const raw = fs.readFileSync(filePath, "utf8");
  return JSON.parse(raw) as Partial<ConstantsShape>;
};

const addMissingNumberEntries = (
  target: NumberMap,
  source: Record<string, number>,
  prefix: string
) => {
  for (const [key, value] of Object.entries(source)) {
    if (!key.startsWith(prefix)) {
      continue;
    }
    if (target[key] === undefined) {
      target[key] = value;
    }
  }
};

const addMissingStringEntries = (
  target: StringMap,
  source: Record<string, number>,
  prefix: string
) => {
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

const legacyMsgFallback: Record<string, string> = {
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

const toConstantName = (name: string) =>
  name
    .replace(/^_+|_+$/g, "")
    .replace(/([a-z0-9])([A-Z])/g, "$1_$2")
    .replace(/([A-Z]+)([A-Z][a-z])/g, "$1_$2")
    .toUpperCase();

const normalizeProtoName = (name: string) =>
  name
    .replace("TO_OBSERVER", "TOOBSERVER")
    .replace("TO_DUELIST", "TODUELIST")
    .replace("HS_NOT_READY", "HS_NOTREADY")
    .replace("KICK", "HS_KICK");

const buildProtoMap = (
  registry: { protos: Map<number, { name: string }> },
  classPrefix: string
) => {
  const out: Record<string, string> = {};
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

export const loadConstants = () => {
  const result = loadConstantsJson();

  if (!result.TYPES) result.TYPES = {};
  if (!result.RACES) result.RACES = {};
  if (!result.ATTRIBUTES) result.ATTRIBUTES = {};
  if (!result.LINK_MARKERS) result.LINK_MARKERS = {};
  if (!result.MSG) result.MSG = {};
  if (!result.TIMING) result.TIMING = {};
  if (!result.CTOS) result.CTOS = {};
  if (!result.STOC) result.STOC = {};
  if (!result.NETWORK) result.NETWORK = {};
  if (!result.NETPLAYER) result.NETPLAYER = {};
  if (!result.PLAYERCHANGE) result.PLAYERCHANGE = {};
  if (!result.ERRMSG) result.ERRMSG = {};
  if (!result.MODE) result.MODE = {};
  if (!result.DUEL_STAGE) result.DUEL_STAGE = {};
  if (!result.COLORS) result.COLORS = {};

  addMissingNumberEntries(result.TYPES, OcgcoreCommonConstants, "TYPE_");
  addMissingNumberEntries(result.RACES, OcgcoreCommonConstants, "RACE_");
  addMissingNumberEntries(result.ATTRIBUTES, OcgcoreCommonConstants, "ATTRIBUTE_");
  addMissingNumberEntries(result.ATTRIBUTES, OcgcoreScriptConstants, "ATTRIBUTE_");
  addMissingNumberEntries(result.LINK_MARKERS, OcgcoreCommonConstants, "LINK_MARKER_");

  addMissingStringEntries(result.MSG, OcgcoreCommonConstants, "MSG_");
  addMissingStringEntries(result.TIMING, OcgcoreScriptConstants, "TIMING_");
  for (const [code, name] of Object.entries(legacyMsgFallback)) {
    result.MSG[code] = name;
  }
  const ctosMap = buildProtoMap(YGOProCtos, "YGOProCtos");
  const stocMap = buildProtoMap(YGOProStoc, "YGOProStoc");
  const mismatches: string[] = [];
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
    throw new Error(
      `CTOS/STOC name mismatch between constants.json and registry:\\n${mismatches.join("\\n")}`
    );
  }

  if (
    result.RACES.RACE_CYBERS === undefined &&
    result.RACES.RACE_CYBERSE !== undefined
  ) {
    result.RACES.RACE_CYBERS = result.RACES.RACE_CYBERSE;
  }

  return result as ConstantsShape;
};

export default loadConstants;

if (typeof require !== "undefined" && require.main === module) {
  console.log(JSON.stringify(loadConstants(), null, 2));
}
