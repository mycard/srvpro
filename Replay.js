"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.Replay = exports.ReplayHeader = exports.REPLAY_ID_YRP2 = exports.REPLAY_ID_YRP1 = exports.SEED_COUNT = void 0;
const fs = __importStar(require("fs"));
const lzma = __importStar(require("lzma"));
exports.SEED_COUNT = 8;
exports.REPLAY_ID_YRP1 = 0x31707279;
exports.REPLAY_ID_YRP2 = 0x32707279;
/**
 * Metadata stored at the beginning of every replay file.
 */
class ReplayHeader {
    constructor() {
        this.id = 0;
        this.version = 0;
        this.flag = 0;
        this.seed = 0;
        this.dataSizeRaw = [];
        this.hash = 0;
        this.props = [];
        this.seedSequence = [];
        this.headerVersion = 0;
        this.value1 = 0;
        this.value2 = 0;
        this.value3 = 0;
    }
    /** Decompressed size as little‑endian 32‑bit */
    get dataSize() {
        return Buffer.from(this.dataSizeRaw).readUInt32LE(0);
    }
    get isTag() {
        return (this.flag & ReplayHeader.REPLAY_TAG_FLAG) !== 0;
    }
    get isCompressed() {
        return (this.flag & ReplayHeader.REPLAY_COMPRESSED_FLAG) !== 0;
    }
    /** Compose a valid 13‑byte LZMA header for this replay */
    getLzmaHeader() {
        const bytes = [
            ...this.props.slice(0, 5),
            ...this.dataSizeRaw,
            0,
            0,
            0,
            0,
        ];
        return Buffer.from(bytes);
    }
}
exports.ReplayHeader = ReplayHeader;
ReplayHeader.REPLAY_COMPRESSED_FLAG = 0x1;
ReplayHeader.REPLAY_TAG_FLAG = 0x2;
ReplayHeader.REPLAY_DECODED_FLAG = 0x4;
ReplayHeader.REPLAY_SINGLE_MODE = 0x8;
ReplayHeader.REPLAY_UNIFORM = 0x10;
/** Utility for reading little‑endian primitives from a Buffer */
class ReplayReader {
    constructor(buffer) {
        this.buffer = buffer;
        this.pointer = 0;
    }
    advance(size, read) {
        const value = read();
        this.pointer += size;
        return value;
    }
    readByte() {
        return this.advance(1, () => this.buffer.readUInt8(this.pointer));
    }
    readByteArray(length) {
        const out = [];
        for (let i = 0; i < length; i++)
            out.push(this.readByte());
        return out;
    }
    readInt8() {
        return this.advance(1, () => this.buffer.readInt8(this.pointer));
    }
    readUInt8() {
        return this.advance(1, () => this.buffer.readUInt8(this.pointer));
    }
    readInt16() {
        return this.advance(2, () => this.buffer.readInt16LE(this.pointer));
    }
    readInt32() {
        return this.advance(4, () => this.buffer.readInt32LE(this.pointer));
    }
    readUInt16() {
        return this.advance(2, () => this.buffer.readUInt16LE(this.pointer));
    }
    readUInt32() {
        return this.advance(4, () => this.buffer.readUInt32LE(this.pointer));
    }
    readAll() {
        return this.buffer.slice(this.pointer);
    }
    readString(length) {
        if (this.pointer + length > this.buffer.length)
            return null;
        const raw = this.buffer
            .slice(this.pointer, this.pointer + length)
            .toString('utf16le');
        this.pointer += length;
        return raw.split('\u0000')[0];
    }
    readRaw(length) {
        if (this.pointer + length > this.buffer.length)
            return null;
        const buf = this.buffer.slice(this.pointer, this.pointer + length);
        this.pointer += length;
        return buf;
    }
}
/** Utility for writing little‑endian primitives into a Buffer */
class ReplayWriter {
    constructor(buffer) {
        this.buffer = buffer;
        this.pointer = 0;
    }
    advance(action, size) {
        action();
        this.pointer += size;
    }
    writeByte(val) {
        this.advance(() => this.buffer.writeUInt8(val, this.pointer), 1);
    }
    writeByteArray(values) {
        for (const v of values)
            this.writeByte(v);
    }
    writeInt8(val) {
        this.advance(() => this.buffer.writeInt8(val, this.pointer), 1);
    }
    writeUInt8(val) {
        this.advance(() => this.buffer.writeUInt8(val, this.pointer), 1);
    }
    writeInt16(val) {
        this.advance(() => this.buffer.writeInt16LE(val, this.pointer), 2);
    }
    writeInt32(val) {
        this.advance(() => this.buffer.writeInt32LE(val, this.pointer), 4);
    }
    writeUInt16(val) {
        this.advance(() => this.buffer.writeUInt16LE(val, this.pointer), 2);
    }
    writeUInt32(val) {
        this.advance(() => this.buffer.writeUInt32LE(val, this.pointer), 4);
    }
    writeAll(buf) {
        this.buffer = Buffer.concat([this.buffer, buf]);
    }
    writeString(val, length) {
        const raw = Buffer.from(val ?? '', 'utf16le');
        const bytes = [...raw];
        if (length !== undefined) {
            const padding = new Array(Math.max(length - bytes.length, 0)).fill(0);
            this.writeByteArray([...bytes, ...padding]);
        }
        else {
            this.writeByteArray(bytes);
        }
    }
}
class Replay {
    constructor() {
        this.header = null;
        this.hostName = '';
        this.clientName = '';
        this.startLp = 0;
        this.startHand = 0;
        this.drawCount = 0;
        this.opt = 0;
        this.hostDeck = null;
        this.clientDeck = null;
        this.tagHostName = null;
        this.tagClientName = null;
        this.tagHostDeck = null;
        this.tagClientDeck = null;
        this.responses = [];
    }
    /** All deck objects in play order */
    get decks() {
        return this.isTag
            ? [
                this.hostDeck,
                this.clientDeck,
                this.tagHostDeck,
                this.tagClientDeck,
            ]
            : [this.hostDeck, this.clientDeck];
    }
    get isTag() {
        return this.header?.isTag ?? false;
    }
    /* ------------------ Static helpers ------------------ */
    static async fromFile(path) {
        return Replay.fromBuffer(await fs.promises.readFile(path));
    }
    static fromBuffer(buffer) {
        const headerReader = new ReplayReader(buffer);
        const header = Replay.readHeader(headerReader);
        const raw = headerReader.readAll();
        const body = header.isCompressed
            ? Replay.decompressBody(header, raw)
            : raw;
        const bodyReader = new ReplayReader(body);
        return Replay.readReplay(header, bodyReader);
    }
    static decompressBody(header, raw) {
        const lzmaBuffer = Buffer.concat([header.getLzmaHeader(), raw]);
        // lzma‑native provides synchronous helpers.
        return Buffer.from(lzma.decompress(lzmaBuffer));
    }
    static readHeader(reader) {
        const h = new ReplayHeader();
        h.id = reader.readUInt32();
        h.version = reader.readUInt32();
        h.flag = reader.readUInt32();
        h.seed = reader.readUInt32();
        h.dataSizeRaw = reader.readByteArray(4);
        h.hash = reader.readUInt32();
        h.props = reader.readByteArray(8);
        if (h.id === exports.REPLAY_ID_YRP2) {
            for (let i = 0; i < exports.SEED_COUNT; i++) {
                h.seedSequence.push(reader.readUInt32());
            }
            h.headerVersion = reader.readUInt32();
            h.value1 = reader.readUInt32();
            h.value2 = reader.readUInt32();
            h.value3 = reader.readUInt32();
        }
        return h;
    }
    static readReplay(header, reader) {
        const r = new Replay();
        r.header = header;
        r.hostName = reader.readString(40) ?? '';
        if (header.isTag) {
            r.tagHostName = reader.readString(40);
            r.tagClientName = reader.readString(40);
        }
        r.clientName = reader.readString(40) ?? '';
        r.startLp = reader.readInt32();
        r.startHand = reader.readInt32();
        r.drawCount = reader.readInt32();
        r.opt = reader.readInt32();
        r.hostDeck = Replay.readDeck(reader);
        if (header.isTag) {
            r.tagHostDeck = Replay.readDeck(reader);
            r.tagClientDeck = Replay.readDeck(reader);
        }
        r.clientDeck = Replay.readDeck(reader);
        r.responses = Replay.readResponses(reader);
        return r;
    }
    /* ------------------ Deck helpers ------------------ */
    static readDeck(reader) {
        return {
            main: Replay.readDeckPack(reader),
            ex: Replay.readDeckPack(reader),
        };
    }
    static readDeckPack(reader) {
        const length = reader.readInt32();
        const cards = [];
        for (let i = 0; i < length; i++)
            cards.push(reader.readInt32());
        return cards;
    }
    /* ------------------ Response helpers ------------------ */
    static readResponses(reader) {
        const out = [];
        while (true) {
            try {
                let length = reader.readUInt8();
                if (length > 64)
                    length = 64;
                const segment = reader.readRaw(length);
                if (!segment)
                    break;
                out.push(segment);
            }
            catch {
                break;
            }
        }
        return out;
    }
    /* ------------------ Writing ------------------ */
    toBuffer() {
        if (!this.header)
            throw new Error('Header not initialised');
        const headerWriter = new ReplayWriter(Buffer.alloc(32));
        this.writeHeader(headerWriter);
        const deckSize = (d) => ((d?.main.length ?? 0) + (d?.ex.length ?? 0)) * 4 + 8;
        const responseSize = this.responses.reduce((s, b) => s + b.length + 1, 0);
        let contentSize = 96 + deckSize(this.hostDeck) + deckSize(this.clientDeck) + responseSize;
        if (this.header.isTag) {
            contentSize +=
                deckSize(this.tagHostDeck) + deckSize(this.tagClientDeck) + 80;
        }
        const contentWriter = new ReplayWriter(Buffer.alloc(contentSize));
        this.writeContent(contentWriter);
        let body = contentWriter.buffer;
        if (this.header.isCompressed) {
            body = Buffer.from(lzma.compress(body));
            body = body.slice(13); // strip header like original implementation
        }
        return Buffer.concat([headerWriter.buffer, body]);
    }
    async writeToFile(path) {
        await fs.promises.writeFile(path, this.toBuffer());
    }
    writeHeader(w) {
        w.writeUInt32(this.header.id);
        w.writeUInt32(this.header.version);
        w.writeUInt32(this.header.flag);
        w.writeUInt32(this.header.seed);
        w.writeByteArray(this.header.dataSizeRaw);
        w.writeUInt32(this.header.hash);
        w.writeByteArray(this.header.props);
        if (this.header.id === exports.REPLAY_ID_YRP2) {
            for (let i = 0; i < exports.SEED_COUNT; i++) {
                w.writeUInt32(this.header.seedSequence[i]);
            }
            w.writeUInt32(this.header.headerVersion);
            w.writeUInt32(this.header.value1);
            w.writeUInt32(this.header.value2);
            w.writeUInt32(this.header.value3);
        }
    }
    writeContent(w) {
        w.writeString(this.hostName, 40);
        if (this.header.isTag) {
            w.writeString(this.tagHostName, 40);
            w.writeString(this.tagClientName, 40);
        }
        w.writeString(this.clientName, 40);
        w.writeInt32(this.startLp);
        w.writeInt32(this.startHand);
        w.writeInt32(this.drawCount);
        w.writeInt32(this.opt);
        Replay.writeDeck(w, this.hostDeck);
        if (this.header.isTag) {
            Replay.writeDeck(w, this.tagHostDeck);
            Replay.writeDeck(w, this.tagClientDeck);
        }
        Replay.writeDeck(w, this.clientDeck);
        Replay.writeResponses(w, this.responses);
    }
    static writeDeck(w, d) {
        if (!d) {
            w.writeInt32(0);
            w.writeInt32(0);
            return;
        }
        Replay.writeDeckPack(w, d.main);
        Replay.writeDeckPack(w, d.ex);
    }
    static writeDeckPack(w, pack) {
        w.writeInt32(pack.length);
        for (const card of pack)
            w.writeInt32(card);
    }
    static writeResponses(w, res) {
        for (const buf of res) {
            w.writeUInt8(buf.length);
            w.writeByteArray(buf);
        }
    }
}
exports.Replay = Replay;
