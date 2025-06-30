export class BasePolyfiller {

  async polyfillGameMsg(msgTitle: string, buffer: Buffer): Promise<Buffer | undefined> {
    return;
  }

  async polyfillResponse(msgTitle: string, buffer: Buffer): Promise<Buffer | undefined> {
    return;
  }

  splice(buf: Buffer, offset: number, deleteCount = 1): Buffer {
    if (offset < 0 || offset >= buf.length) return Buffer.alloc(0);
  
    deleteCount = Math.min(deleteCount, buf.length - offset);
    const end = offset + deleteCount;
  
    const newBuf = Buffer.concat([
      buf.slice(0, offset),
      buf.slice(end)
    ]);
  
    return newBuf;
  }

  insert(buf: Buffer, offset: number, insertBuf: Buffer): Buffer {
    if (offset < 0) offset = 0;
    if (offset > buf.length) offset = buf.length;
  
    const newBuf = Buffer.concat([
      buf.slice(0, offset),
      insertBuf,
      buf.slice(offset)
    ]);
  
    return newBuf;
  }
}
