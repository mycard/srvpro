# Native terminal forwarding and socket retirement

The proxy previously destroyed the external client as soon as its native
YGOPro socket closed. Accepted `server_data_queue` work can still be waiting
for asynchronous message parsing, delayed replay capture, or a downstream write
callback. The resulting `client.isClosed`/destroyed socket prevents those accepted
messages from reaching the client. A Win or DUEL_END can therefore be lost at
the native EOF boundary.

The proxy now marks the native socket closed immediately, preventing admission
of new buffers or reconnect claims to that transport. It waits for the existing
PQueue to become idle before closing the captured external client. A ten-second
deadline bounds cleanup and exceeds the existing five-second delayed replay
capture wait. Expiration emits an operator warning without packet contents,
deck data, credentials or player identity; it does not manufacture a result.

Each accepted native buffer retains its external client and native socket
identity. Those identities are checked before/after parsing and before each
write. Parsing still runs for a disconnected client whose native transport
remains owned, preserving cached prompts and reconnect state; only delivery
requires an open external client. Reconnection cannot redirect already accepted
work to a replacement.
Error and close events share one retirement operation. Disconnect-registration
cleanup searches by the exact native socket even if its client is already gone,
without clearing a replacement socket's registration or grace timer.

Existing translated terminal notices and socket-kick policy are retained.
Authoritative game packets are not synthesized, and parser exceptions remain
observable. The terminal notice is still best-effort; authoritative queued
writes complete before retirement.

## Regression commands and evidence

After installing the repository dependencies:

```sh
npm run test:terminal-forwarding
```

`terminal-forwarding.test.js` extracts the complete current `netRequestHandler`,
reconnect admission and disconnect-cleanup functions. It uses real PQueue 6.6.2
(the package-lock version), controlled sockets, explicit parser/write gates and
a controlled clock. Twenty-one assertions cover accepted terminal order, pending
writes, error/close duplication, owner replacement, bounded timeout, absent or
already closed clients, exact disconnect cleanup, and unchanged exact-deck
admission for live native transports, including continued offline packet caching.

`terminal-forwarding-loopback.test.js` uses real Node TCP sockets on temporary
127.0.0.1 ports, with the same production handler and actual PQueue. It closes
the upstream connection while parsing is pending and pauses the downstream
peer to force backpressure. Both the nine-byte Win/DUEL_END stream and the same
terminal sequence following 6,582,272 bytes of valid chat framing arrive intact.
The captured prefix hashes are checked, every accepted write callback completes,
one retirement occurs, and owned sockets/listeners/deadline timers are cleaned.
Each loopback case has an eight-second bound and requires no native game binary.

Windows/Node 24.17.0 acceptance on 2026-10-14 passed all twenty-one assertions and
both real TCP cases with no socket errors or retained timers. The buffered case
observed pending writes and socket backpressure, with all 6,582,281 expected
bytes intact (SHA256
`b23c64d4e16fa43fc0f9c693eef9b6ba96239d1f9c0ed93a20efdd4c3d17a0e3`).
The pre-correction source at `de3ee4455a3bc6a9bc8181aa07786ace32d1fb4f`
passes eight and fails thirteen assertions; both loopback cases lose the
terminal stream. Tests accept `--source <saved-js-file>` for a before comparison.
Set `TERMINAL_FORWARDING_RECEIPT` to an explicit scratch JSON path if a saved
loopback receipt is needed. No test output is written into the repository by
default.

This proves a local source defect and its transport correction. It does not
establish that the deployed pre-release server uses this source or that this
race caused the particular named-room surrender report. That report still
needs deployed proxy/native versions and terminal-frame ordering. The tests
are transport checks, not a native-core duel or remote reconnect acceptance.

The correction requires an updated server deployment. It does not require a
player/resource patch, and this local change does not deploy or publish it.
