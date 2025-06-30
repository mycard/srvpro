"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Polyfiller1361 = exports.gcd = void 0;
const base_polyfiller_1 = require("../base-polyfiller");
const gcd = (nums) => {
    const gcdTwo = (a, b) => {
        if (b === 0)
            return a;
        return gcdTwo(b, a % b);
    };
    return nums.reduce((acc, num) => gcdTwo(acc, num));
};
exports.gcd = gcd;
class Polyfiller1361 extends base_polyfiller_1.BasePolyfiller {
    async polyfillGameMsg(msgTitle, buffer) {
        if (msgTitle === 'CONFIRM_CARDS') {
            // buf[0]: MSG_CONFIRM_CARDS
            // buf[1]: playerid
            // buf[2]: ADDED skip_panel
            return this.splice(buffer, 2, 1);
        }
        else if (msgTitle === 'SELECT_CHAIN') {
            // buf[0]: MSG_SELECT_CHAIN
            // buf[1]: playerid
            // buf[2]: size
            // buf[3]: spe_count
            // buf[REMOVED]: forced
            // buf[4-7]: hint_timing player
            // buf[8-11]: hint_timing 1-player
            // then it's 14 bytes for each item
            // item[0]: not related
            // item[1]: ADDED forced
            // item[2-13] not related
            const size = buffer[2];
            const itemStartOffset = 12; // after the header (up to hint timings)
            // 判断是否存在任何 item 的 forced = 1（在原始 buffer 中判断）
            let anyForced = false;
            for (let i = 0; i < size; i++) {
                const itemOffset = itemStartOffset + i * 14;
                const forced = buffer[itemOffset + 1];
                if (forced === 1) {
                    anyForced = true;
                    break;
                }
            }
            // 从后往前 splice 每个 item 的 forced 字段
            for (let i = size - 1; i >= 0; i--) {
                const itemOffset = itemStartOffset + i * 14;
                buffer = this.splice(buffer, itemOffset + 1, 1); // 删除每个 item 的 forced（第 1 字节）
            }
            // 最后再插入旧版所需的 forced 标志
            return this.insert(buffer, 4, Buffer.from([anyForced ? 1 : 0]));
        }
        else if (msgTitle === 'SELECT_SUM') {
            // buf[0]: MSG_SELECT_SUM
            // buf[1]: 0 => equal, 1 => greater
            // buf[2]: playerid
            // buf[3-6]: target_value
            // buf[7]: min
            // buf[8]: max
            // buf[9]: forced_count
            // then each item 11 bytes
            // item[0-3] code
            // item[4] controler
            // item[5] location
            // item[6] sequence
            // item[7-10] value
            // item[10 + forced_count * 11] card_count
            // same as above items
            const targetValue = buffer.readUInt32LE(3);
            const forcedCount = buffer[9];
            const cardCount = buffer[10 + forcedCount * 11];
            const valueOffsets = [];
            for (let i = 0; i < forcedCount; i++) {
                const itemOffset = 10 + i * 11;
                valueOffsets.push(itemOffset + 7);
            }
            for (let i = 0; i < cardCount; i++) {
                const itemOffset = 11 + forcedCount * 11 + i * 11;
                valueOffsets.push(itemOffset + 7);
            }
            const values = valueOffsets.map(offset => ({
                offset,
                value: buffer.readUInt32LE(offset),
            }));
            if (!values.some(v => v.value & 0x80000000)) {
                return;
            }
            const gcds = [targetValue];
            for (const { value } of values) {
                if (value & 0x80000000) {
                    gcds.push(value & 0x7FFFFFFF);
                }
                else {
                    const op1 = value & 0xffff;
                    const op2 = (value >>> 16) & 0xffff;
                    [op1, op2].filter(v => v > 0)
                        .forEach(v => gcds.push(v));
                }
            }
            const gcdValue = (0, exports.gcd)(gcds);
            buffer.writeUInt32LE(targetValue / gcdValue, 3);
            for (const trans of values) {
                let target = 0;
                const { value } = trans;
                if (value & 0x80000000) {
                    target = ((value & 0x7FFFFFFF) / gcdValue) & 0xffff;
                }
                else {
                    // shrink op1 and op2
                    const op1 = value & 0xffff;
                    const op2 = (value >>> 16) & 0xffff;
                    target = ((op1 / gcdValue) & 0xffff) | ((((op2 / gcdValue) & 0xffff) << 16) >>> 0);
                }
                buffer.writeUInt32LE(target, trans.offset);
            }
        }
        return;
    }
}
exports.Polyfiller1361 = Polyfiller1361;
