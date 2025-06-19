import * as fs from 'fs';
import * as lzma from 'lzma';

/** A minimal deck representation */
export interface DeckObject {
  main: number[];
  ex: number[];
}

export const SEED_COUNT = 8;
export const REPLAY_ID_YRP1 = 0x31707279;
export const REPLAY_ID_YRP2 = 0x32707279;

/**
 * Metadata stored at the beginning of every replay file.
 */
export class ReplayHeader {
  static readonly REPLAY_COMPRESSED_FLAG = 0x1;
  static readonly REPLAY_TAG_FLAG = 0x2;
  static readonly REPLAY_DECODED_FLAG = 0x4;
  static readonly REPLAY_SINGLE_MODE = 0x8;
  static readonly REPLAY_UNIFORM = 0x10;

  id = 0;
  version = 0;
  flag = 0;
  seed = 0;
  dataSizeRaw: number[] = [];
  hash = 0;
  props: number[] = [];
  seedSequence: number[] = [];
  headerVersion = 0;
  value1 = 0;
  value2 = 0;
  value3 = 0;


  /** Decompressed size as little‑endian 32‑bit */
  get dataSize(): number {
    return Buffer.from(this.dataSizeRaw).readUInt32LE(0);
  }

  get isTag(): boolean {
    return (this.flag & ReplayHeader.REPLAY_TAG_FLAG) !== 0;
  }

  get isCompressed(): boolean {
    return (this.flag & ReplayHeader.REPLAY_COMPRESSED_FLAG) !== 0;
  }

  /** Compose a valid 13‑byte LZMA header for this replay */
  getLzmaHeader(): Buffer {
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

/** Utility for reading little‑endian primitives from a Buffer */
class ReplayReader {
  private pointer = 0;
  constructor(private readonly buffer: Buffer) {}

  private advance<T>(size: number, read: () => T): T {
    const value = read();
    this.pointer += size;
    return value;
  }

  readByte(): number {
    return this.advance(1, () => this.buffer.readUInt8(this.pointer));
  }

  readByteArray(length: number): number[] {
    const out: number[] = [];
    for (let i = 0; i < length; i++) out.push(this.readByte());
    return out;
  }

  readInt8(): number {
    return this.advance(1, () => this.buffer.readInt8(this.pointer));
  }

  readUInt8(): number {
    return this.advance(1, () => this.buffer.readUInt8(this.pointer));
  }

  readInt16(): number {
    return this.advance(2, () => this.buffer.readInt16LE(this.pointer));
  }

  readInt32(): number {
    return this.advance(4, () => this.buffer.readInt32LE(this.pointer));
  }

  readUInt16(): number {
    return this.advance(2, () => this.buffer.readUInt16LE(this.pointer));
  }

  readUInt32(): number {
    return this.advance(4, () => this.buffer.readUInt32LE(this.pointer));
  }

  readAll(): Buffer {
    return this.buffer.slice(this.pointer);
  }

  readString(length: number): string | null {
    if (this.pointer + length > this.buffer.length) return null;
    const raw = this.buffer
      .slice(this.pointer, this.pointer + length)
      .toString('utf16le');
    this.pointer += length;
    return raw.split('\u0000')[0];
  }

  readRaw(length: number): Buffer | null {
    if (this.pointer + length > this.buffer.length) return null;
    const buf = this.buffer.slice(this.pointer, this.pointer + length);
    this.pointer += length;
    return buf;
  }
}

/** Utility for writing little‑endian primitives into a Buffer */
class ReplayWriter {
  private pointer = 0;
  constructor(public buffer: Buffer) {}

  private advance(action: () => void, size: number): void {
    action();
    this.pointer += size;
  }

  writeByte(val: number): void {
    this.advance(() => this.buffer.writeUInt8(val, this.pointer), 1);
  }

  writeByteArray(values: Iterable<number>): void {
    for (const v of values) this.writeByte(v);
  }

  writeInt8(val: number): void {
    this.advance(() => this.buffer.writeInt8(val, this.pointer), 1);
  }

  writeUInt8(val: number): void {
    this.advance(() => this.buffer.writeUInt8(val, this.pointer), 1);
  }

  writeInt16(val: number): void {
    this.advance(() => this.buffer.writeInt16LE(val, this.pointer), 2);
  }

  writeInt32(val: number): void {
    this.advance(() => this.buffer.writeInt32LE(val, this.pointer), 4);
  }

  writeUInt16(val: number): void {
    this.advance(() => this.buffer.writeUInt16LE(val, this.pointer), 2);
  }

  writeUInt32(val: number): void {
    this.advance(() => this.buffer.writeUInt32LE(val, this.pointer), 4);
  }

  writeAll(buf: Buffer): void {
    this.buffer = Buffer.concat([this.buffer, buf]);
  }

  writeString(val: string | null, length?: number): void {
    const raw = Buffer.from(val ?? '', 'utf16le');
    const bytes = [...raw];
    if (length !== undefined) {
      const padding = new Array(Math.max(length - bytes.length, 0)).fill(0);
      this.writeByteArray([...bytes, ...padding]);
    } else {
      this.writeByteArray(bytes);
    }
  }
}

export class Replay {
  header: ReplayHeader | null = null;
  hostName = '';
  clientName = '';
  startLp = 0;
  startHand = 0;
  drawCount = 0;
  opt = 0;

  hostDeck: DeckObject | null = null;
  clientDeck: DeckObject | null = null;

  tagHostName: string | null = null;
  tagClientName: string | null = null;
  tagHostDeck: DeckObject | null = null;
  tagClientDeck: DeckObject | null = null;

  responses: Buffer[] = [];

  /** All deck objects in play order */
  get decks(): DeckObject[] {
    return this.isTag
      ? [
          this.hostDeck!,
          this.clientDeck!,
          this.tagHostDeck!,
          this.tagClientDeck!,
        ]
      : [this.hostDeck!, this.clientDeck!];
  }

  get isTag(): boolean {
    return this.header?.isTag ?? false;
  }

  /* ------------------ Static helpers ------------------ */

  static async fromFile(path: string): Promise<Replay> {
    return Replay.fromBuffer(await fs.promises.readFile(path));
  }

  static fromBuffer(buffer: Buffer): Replay {
    const headerReader = new ReplayReader(buffer);
    const header = Replay.readHeader(headerReader);
    const raw = headerReader.readAll();

    const body = header.isCompressed
      ? Replay.decompressBody(header, raw)
      : raw;

    const bodyReader = new ReplayReader(body);
    return Replay.readReplay(header, bodyReader);
  }

  private static decompressBody(header: ReplayHeader, raw: Buffer): Buffer {
    const lzmaBuffer = Buffer.concat([header.getLzmaHeader(), raw]);
    // lzma‑native provides synchronous helpers.
    return Buffer.from(lzma.decompress(lzmaBuffer));
  }

  private static readHeader(reader: ReplayReader): ReplayHeader {
    const h = new ReplayHeader();
    h.id = reader.readUInt32();
    h.version = reader.readUInt32();
    h.flag = reader.readUInt32();
    h.seed = reader.readUInt32();
    h.dataSizeRaw = reader.readByteArray(4);
    h.hash = reader.readUInt32();
    h.props = reader.readByteArray(8);
    if (h.id === REPLAY_ID_YRP2) {
      for(let i = 0; i < SEED_COUNT; i++) {
        h.seedSequence.push(reader.readUInt32());
      }
      h.headerVersion = reader.readUInt32();
      h.value1 = reader.readUInt32();
      h.value2 = reader.readUInt32();
      h.value3 = reader.readUInt32();
    }
    return h;
  }

  private static readReplay(header: ReplayHeader, reader: ReplayReader): Replay {
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

  private static readDeck(reader: ReplayReader): DeckObject {
    return {
      main: Replay.readDeckPack(reader),
      ex: Replay.readDeckPack(reader),
    };
  }

  private static readDeckPack(reader: ReplayReader): number[] {
    const length = reader.readInt32();
    const cards: number[] = [];
    for (let i = 0; i < length; i++) cards.push(reader.readInt32());
    return cards;
  }

  /* ------------------ Response helpers ------------------ */

  private static readResponses(reader: ReplayReader): Buffer[] {
    const out: Buffer[] = [];
    while (true) {
      try {
        let length = reader.readUInt8();
        if (length > 64) length = 64;
        const segment = reader.readRaw(length);
        if (!segment) break;
        out.push(segment);
      } catch {
        break;
      }
    }
    return out;
  }

  /* ------------------ Writing ------------------ */

  toBuffer(): Buffer {
    if (!this.header) throw new Error('Header not initialised');

    const headerWriter = new ReplayWriter(Buffer.alloc(32));
    this.writeHeader(headerWriter);

    const deckSize = (d: DeckObject | null) =>
      ((d?.main.length ?? 0) + (d?.ex.length ?? 0)) * 4 + 8;

    const responseSize = this.responses.reduce((s, b) => s + b.length + 1, 0);

    let contentSize =
      96 + deckSize(this.hostDeck) + deckSize(this.clientDeck) + responseSize;

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

  async writeToFile(path: string): Promise<void> {
    await fs.promises.writeFile(path, this.toBuffer());
  }

  private writeHeader(w: ReplayWriter): void {
    w.writeUInt32(this.header!.id);
    w.writeUInt32(this.header!.version);
    w.writeUInt32(this.header!.flag);
    w.writeUInt32(this.header!.seed);
    w.writeByteArray(this.header!.dataSizeRaw);
    w.writeUInt32(this.header!.hash);
    w.writeByteArray(this.header!.props);
    if (this.header!.id === REPLAY_ID_YRP2) {
      for (let i = 0; i < SEED_COUNT; i++) {
        w.writeUInt32(this.header!.seedSequence[i]);
      }
      w.writeUInt32(this.header!.headerVersion);
      w.writeUInt32(this.header!.value1);
      w.writeUInt32(this.header!.value2);
      w.writeUInt32(this.header!.value3);
    }
  }

  private writeContent(w: ReplayWriter): void {
    w.writeString(this.hostName, 40);
    if (this.header!.isTag) {
      w.writeString(this.tagHostName, 40);
      w.writeString(this.tagClientName, 40);
    }
    w.writeString(this.clientName, 40);

    w.writeInt32(this.startLp);
    w.writeInt32(this.startHand);
    w.writeInt32(this.drawCount);
    w.writeInt32(this.opt);

    Replay.writeDeck(w, this.hostDeck);
    if (this.header!.isTag) {
      Replay.writeDeck(w, this.tagHostDeck);
      Replay.writeDeck(w, this.tagClientDeck);
    }
    Replay.writeDeck(w, this.clientDeck);

    Replay.writeResponses(w, this.responses);
  }

  private static writeDeck(w: ReplayWriter, d: DeckObject | null): void {
    if (!d) {
      w.writeInt32(0);
      w.writeInt32(0);
      return;
    }
    Replay.writeDeckPack(w, d.main);
    Replay.writeDeckPack(w, d.ex);
  }

  private static writeDeckPack(w: ReplayWriter, pack: number[]): void {
    w.writeInt32(pack.length);
    for (const card of pack) w.writeInt32(card);
  }

  private static writeResponses(w: ReplayWriter, res: Buffer[]): void {
    for (const buf of res) {
      w.writeUInt8(buf.length);
      w.writeByteArray(buf);
    }
  }
}
