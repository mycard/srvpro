import { BasePolyfiller } from "./base-polyfiller";
import { polyfillRegistry } from "./registry";

const getPolyfillers = (version: number) => {
  const polyfillers: {version: number, polyfiller: BasePolyfiller}[] = [];
  for (const [pVersion, instance] of polyfillRegistry.entries()) {
    if (version <= pVersion) { 
      polyfillers.push({version: pVersion, polyfiller: instance});
    }
  }
  polyfillers.sort((a, b) => a.version - b.version);
  return polyfillers.map(p => p.polyfiller);
}


export async function polyfillGameMsg(version: number, msgTitle: string, buffer: Buffer) {
  const polyfillers = getPolyfillers(version);
  for (const polyfiller of polyfillers) {
    if (await polyfiller.polyfillGameMsg(msgTitle, buffer)) {
      return true;
    }
  }
  return false;
}

export async function polyfillResponse(version: number, msgTitle: string, buffer: Buffer) {
  const polyfillers = getPolyfillers(version);
  for (const polyfiller of polyfillers) {
    if (await polyfiller.polyfillResponse(msgTitle, buffer)) {
      return true;
    }
  }
  return false;
}
