/**
 * Created by zh99998 on 2016/12/23.
 */
// export declare var types: {
//     void: Type; int64: Type; ushort: Type;
//     int: Type; uint64: Type; float: Type;
//     uint: Type; long: Type; double: Type;
//     int8: Type; ulong: Type; Object: Type;
//     uint8: Type; longlong: Type; CString: Type;
//     int16: Type; ulonglong: Type; bool: Type;
//     uint16: Type; char: Type; byte: Type;
//     int32: Type; uchar: Type; size_t: Type;
//     uint32: Type; short: Type;
// };
import {types} from "ref";
import StructType = require('ref-struct');
import ArrayType = require('ref-array');

// 这玩意儿名字跟内置的Array重了，需要用数组的地方，类型写 number[], 而不要写Array<number>。如果因为这个引发了问题，可以把这个Array改个名，例如改叫ArrayRef
export interface Array<T> {
    [i: number]: T; length: number; toArray(): T[];
    toJSON(): T[]; inspect(): string; buffer: Buffer; ref(): Buffer;
}

export const HostInfo = StructType({
    lflist: types.uint,
    rule: types.uchar,
    mode: types.uchar,
    enable_priority: types.bool,
    no_check_deck: types.bool,
    no_shuffle_deck: types.bool,
    start_lp: types.uint,
    start_hand: types.uchar,
    draw_count: types.uchar,
    time_limit: types.ushort,
});

export interface HostInfo {
    lflist: number
    rule: number
    mode: number
    enable_priority: boolean
    no_check_deck: boolean
    no_shuffle_deck: boolean
    start_lp: number
    start_hand: number
    draw_count: number
    time_limit: number
}

export const ERROR_MSG = StructType({
    msg: types.uchar,
    code: types.int
});

export interface ERROR_MSG {
    msg: ERRMSG
    code: number
}

export const PLAYER_INFO = StructType({
    name: ArrayType(types.ushort, 20)
});

export interface PLAYER_INFO {
    name: Array<number>
}

export const JOIN_GAME = StructType({
    version: types.ushort,
    gameid: types.uint,
    pass: ArrayType(types.ushort, 20)
});

export interface JOIN_GAME {
    version: number,
    gameid: number,
    pass: Array<number>
}

export const STOC_CHAT = StructType({
    player: types.ushort,
    msg: ArrayType(types.ushort, 255) // 这里有个迷之bug，客户端定义的长度是256 https://github.com/Fluorohydride/ygopro/blob/master/gframe/network.h#L85 但是发送长度256的数组，客户端会崩，不知道为什么
});

export interface STOC_CHAT {
    player: number,
    msg: Array<number>
}

export type Struct = HostInfo | ERROR_MSG | PLAYER_INFO | JOIN_GAME | STOC_CHAT

export enum ERRMSG {
    JOINERROR = 1,
    DECKERROR = 2,
    SIDEERROR = 3,
    VERERROR = 4
}

export enum COLORS {
    LIGHTBLUE = 8,
    RED = 11,
    GREEN = 12,
    BLUE = 13,
    BABYBLUE = 14,
    PINK = 15,
    YELLOW = 16,
    WHITE = 17,
    GRAY = 18,
    DARKGRAY = 19
}

export const STOC = new Map(Object.entries({
    2: ERROR_MSG,
    25: STOC_CHAT
}).map(([key, value]) => <[number, StructType]>[parseInt(key), value]));

export const CTOS = new Map(Object.entries({
    16: PLAYER_INFO,
    18: JOIN_GAME
}).map(([key, value]) => <[number, StructType]>[parseInt(key), value]));