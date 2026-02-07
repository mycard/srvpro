"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.overwriteBuffer = void 0;
exports.retry = retry;
async function retry(fn, count, delayFn = (attempt) => Math.pow(2, attempt) * 100) {
    let lastError;
    for (let attempt = 0; attempt < count; attempt++) {
        try {
            return await fn();
        }
        catch (error) {
            lastError = error;
            if (attempt < count - 1) {
                const delay = delayFn(attempt);
                await new Promise((resolve) => setTimeout(resolve, delay));
            }
        }
    }
    // 如果全部尝试失败，抛出最后一个错误
    throw lastError;
}
const overwriteBuffer = (buf, _input) => {
    const input = Buffer.isBuffer(_input) ? _input : Buffer.from(_input);
    if (input.length >= buf.length) {
        input.copy(buf, 0, 0, buf.length);
    }
    else {
        input.copy(buf, 0, 0, input.length);
    }
};
exports.overwriteBuffer = overwriteBuffer;
