"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BasePolyfiller = void 0;
class BasePolyfiller {
    async polyfillGameMsg(msgTitle, buffer) {
        return false;
    }
    async polyfillResponse(msgTitle, buffer) {
        return false;
    }
    splice(buf, offset, deleteCount = 1) {
        if (offset < 0 || offset >= buf.length)
            return Buffer.alloc(0);
        deleteCount = Math.min(deleteCount, buf.length - offset);
        const end = offset + deleteCount;
        const deleted = Buffer.allocUnsafe(deleteCount);
        buf.copy(deleted, 0, offset, end);
        const moveLength = buf.length - end;
        if (moveLength > 0) {
            buf.copy(buf, offset, end, buf.length);
        }
        buf.fill(0, buf.length - deleteCount);
        return deleted;
    }
    insert(buf, offset, insertBuf) {
        const availableSpace = buf.length - offset;
        const insertLength = Math.min(insertBuf.length, availableSpace);
        buf.copy(buf, offset + insertLength, offset, buf.length - insertLength);
        insertBuf.copy(buf, offset, 0, insertLength);
        return buf;
    }
}
exports.BasePolyfiller = BasePolyfiller;
