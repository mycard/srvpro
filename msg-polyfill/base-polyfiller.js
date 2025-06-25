"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BasePolyfiller = void 0;
class BasePolyfiller {
    async polyfillGameMsg(msgTitle, buffer) {
        return;
    }
    async polyfillResponse(msgTitle, buffer) {
        return;
    }
    splice(buf, offset, deleteCount = 1) {
        if (offset < 0 || offset >= buf.length)
            return Buffer.alloc(0);
        deleteCount = Math.min(deleteCount, buf.length - offset);
        const end = offset + deleteCount;
        const newBuf = Buffer.concat([
            buf.slice(0, offset),
            buf.slice(end)
        ]);
        return newBuf;
    }
    insert(buf, offset, insertBuf) {
        if (offset < 0)
            offset = 0;
        if (offset > buf.length)
            offset = buf.length;
        const newBuf = Buffer.concat([
            buf.slice(0, offset),
            insertBuf,
            buf.slice(offset)
        ]);
        return newBuf;
    }
}
exports.BasePolyfiller = BasePolyfiller;
