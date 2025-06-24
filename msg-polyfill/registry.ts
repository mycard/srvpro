import { BasePolyfiller } from "./base-polyfiller";
import { Polyfiller1361 } from "./polyfillers/0x1361";

export const polyfillRegistry = new Map<number, typeof BasePolyfiller>();

const addPolyfiller = (version: number, polyfiller: typeof BasePolyfiller) => {
  polyfillRegistry.set(version, polyfiller);
}

addPolyfiller(0x1361, Polyfiller1361);
