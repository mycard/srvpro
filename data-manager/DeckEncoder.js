"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.decodeDeck = exports.encodeDeck = void 0;
const assert_1 = __importDefault(require("assert"));
function encodeDeck(deck) {
    let pointer = 0;
    const bufferSize = (2 + deck.main.length + deck.side.length) * 4;
    const buffer = Buffer.allocUnsafe(bufferSize);
    buffer.writeInt32LE(deck.main.length, pointer);
    pointer += 4;
    buffer.writeInt32LE(deck.side.length, pointer);
    pointer += 4;
    for (let cardCode of deck.main.concat(deck.side)) {
        buffer.writeInt32LE(cardCode, pointer);
        pointer += 4;
    }
    assert_1.default(pointer === bufferSize, `Invalid buffer size. Expected: ${bufferSize}. Got: ${pointer}`);
    return buffer;
}
exports.encodeDeck = encodeDeck;
function decodeDeck(buffer) {
    let pointer = 0;
    const mainLength = buffer.readInt32LE(pointer);
    pointer += 4;
    const sideLength = buffer.readInt32LE(pointer);
    pointer += 4;
    const correctBufferLength = (2 + mainLength + sideLength) * 4;
    assert_1.default(buffer.length >= (2 + mainLength + sideLength) * 4, `Invalid buffer size. Expected: ${correctBufferLength}. Got: ${buffer.length}`);
    const main = [];
    const side = [];
    for (let i = 0; i < mainLength; ++i) {
        main.push(buffer.readInt32LE(pointer));
        pointer += 4;
    }
    for (let i = 0; i < sideLength; ++i) {
        side.push(buffer.readInt32LE(pointer));
        pointer += 4;
    }
    return { main, side };
}
exports.decodeDeck = decodeDeck;
//# sourceMappingURL=DeckEncoder.js.map