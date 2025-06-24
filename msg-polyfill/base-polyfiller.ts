export class BasePolyfiller {
  async polyfillGameMsg(msgTitle: string, buffer: Buffer) {
    return false;
  }

  async polyfillResponse(msgTitle: string, buffer: Buffer) {
    return false;
  }

  splice(buf: Buffer, offset: number, deleteCount = 1): Buffer {
    if (offset < 0 || offset >= buf.length) return Buffer.alloc(0);
  
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

  insert(buf: Buffer, offset: number, insertBuf: Buffer) {
    const availableSpace = buf.length - offset;
    const insertLength = Math.min(insertBuf.length, availableSpace);
  
    buf.copy(buf, offset + insertLength, offset, buf.length - insertLength);

    insertBuf.copy(buf, offset, 0, insertLength);
  
    return buf;
  }
}
