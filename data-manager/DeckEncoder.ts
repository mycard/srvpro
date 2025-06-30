import YGOProDeck from "ygopro-deck-encode";

export interface Deck {
    main: number[];
    side: number[];
}

// deprecated. Use YGOProDeck instead

export function encodeDeck(deck: Deck) {
    const pdeck = new YGOProDeck();
    pdeck.main = deck.main;
    pdeck.extra = [];
    pdeck.side = deck.side;
    return Buffer.from(pdeck.toUpdateDeckPayload());
}

export function decodeDeck(buffer: Buffer): Deck {
    return YGOProDeck.fromUpdateDeckPayload(buffer);
}
