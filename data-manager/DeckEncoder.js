"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.encodeDeck = encodeDeck;
exports.decodeDeck = decodeDeck;
const ygopro_deck_encode_1 = __importDefault(require("ygopro-deck-encode"));
// deprecated. Use YGOProDeck instead
function encodeDeck(deck) {
    const pdeck = new ygopro_deck_encode_1.default();
    pdeck.main = deck.main;
    pdeck.extra = [];
    pdeck.side = deck.side;
    return Buffer.from(pdeck.toUpdateDeckPayload());
}
function decodeDeck(buffer) {
    return ygopro_deck_encode_1.default.fromUpdateDeckPayload(buffer);
}
