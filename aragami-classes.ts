import { CacheKey, CacheTTL } from "aragami";

@CacheTTL(60000)
export class ClientVersionBlocker {
  @CacheKey()
  clientKey: string;
}
