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
  let shrinkCount = 0;
  for (const polyfiller of polyfillers) {
    await polyfiller.polyfillGameMsg(msgTitle, buffer);
    if (polyfiller.shrinkCount > 0) {
      if (polyfiller.shrinkCount === 0x3f3f3f3f) {
        return 0x3f3f3f3f; // special case for cancel message
      }
      shrinkCount += polyfiller.shrinkCount;
    }
  }
  return shrinkCount;
}

export async function polyfillResponse(version: number, msgTitle: string, buffer: Buffer) {
  const polyfillers = getPolyfillers(version);
  for (const polyfiller of polyfillers) {
    await polyfiller.polyfillResponse(msgTitle, buffer);
  }
}
