import { BasePolyfiller } from "./base-polyfiller";
import { polyfillRegistry } from "./registry";

const getPolyfillers = (version: number) => {
  const polyfillers: {version: number, polyfiller: BasePolyfiller}[] = [];
  for (const [pVersion, polyfillerCls] of polyfillRegistry.entries()) {
    if (version <= pVersion) { 
      polyfillers.push({ version: pVersion, polyfiller: new polyfillerCls() });
    }
  }
  polyfillers.sort((a, b) => a.version - b.version);
  return polyfillers.map(p => p.polyfiller);
}


export async function polyfillGameMsg(version: number, msgTitle: string, buffer: Buffer) {
  const polyfillers = getPolyfillers(version);
  let pbuf = buffer;
  for (const polyfiller of polyfillers) {
    const newBuf = await polyfiller.polyfillGameMsg(msgTitle, pbuf);
    if (newBuf) {
      pbuf = newBuf;
    }
  }
  if (pbuf === buffer) {
    return undefined;
  } else if (pbuf.length <= buffer.length) {
    pbuf.copy(buffer, 0, 0, pbuf.length);
    return pbuf.length === buffer.length
      ? undefined
      : buffer.slice(0, pbuf.length);
  } else {
    return pbuf;
  }
}

export async function polyfillResponse(version: number, msgTitle: string, buffer: Buffer) {
  const polyfillers = getPolyfillers(version);
  for (const polyfiller of polyfillers) {
    await polyfiller.polyfillResponse(msgTitle, buffer);
  }
}
