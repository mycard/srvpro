import assert from "assert";

export interface Deck {
    main: number[];
    side: number[];
}

export function encodeDeck(deck: Deck) {
    let pointer = 0;
    const bufferSize = (2 + deck.main.length + deck.side.length) * 4;
    const buffer = Buffer.allocUnsafe(bufferSize);
    buffer.writeInt32LE(deck.main.length, pointer);
    pointer += 4;
    buffer.writeInt32LE(deck.side.length, pointer);
    pointer += 4;
    for(let cardCode of deck.main.concat(deck.side)) {
        buffer.writeInt32LE(cardCode, pointer);
        pointer += 4;
    }
    assert(pointer === bufferSize, `Invalid buffer size. Expected: ${bufferSize}. Got: ${pointer}`);
    return buffer;
}

export function decodeDeck(buffer: Buffer): Deck {
    let pointer = 0;
    const mainLength = buffer.readInt32LE(pointer);
    pointer += 4;
    const sideLength = buffer.readInt32LE(pointer);
    pointer += 4;
    const correctBufferLength = (2 + mainLength + sideLength) * 4;
    assert(buffer.length >= (2 + mainLength + sideLength) * 4, `Invalid buffer size. Expected: ${correctBufferLength}. Got: ${buffer.length}`);
    const main: number[] = [];
    const side: number[] = [];
    for(let i = 0; i < mainLength; ++i) {
        main.push(buffer.readInt32LE(pointer));
        pointer += 4;
    }
    for(let i = 0; i < sideLength; ++i) {
        side.push(buffer.readInt32LE(pointer));
        pointer += 4;
    }
    return {main, side};
}