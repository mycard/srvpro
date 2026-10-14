# Public lobby invitations

This gateway extension joins one existing public waiting room incarnation. It is
opt-in and does not change normal names, random pairing, MyCard match action 4,
reconnect admission or intentional spectator routes for existing clients.

## Discovery and deployment

`GET /api/lobby-invites` returns uncached JSON:

```json
{"version":1,"backend":"srvpro","enabled":true,"rooms":[{"inviteId":"abcdefghijkl","players":1,"maxPlayers":2}]}
```

The backend is `mycard` when that module is enabled. Discovery is enabled only
when `modules.http.public_roomlist` or `modules.http.websocket_roomlist` already
allows public room discovery, the server is not stopped, and tournament and
Challonge modes are disabled. No credentials, room commands, passwords, player
names, PIDs or account IDs are included. Private/password rooms, random pairing,
arenas, bots, recovered rooms and full/started/retired rooms are excluded.

Each Room generates a fresh cryptographic 12-character base64url `inviteId`
(72 bits). It identifies the instance, grants no authentication, and is not
derived from reusable room names or process IDs. Destroying and recreating the
same room name invalidates its old invitation. Pending connections reserve seats
before core admission; spectator position 7 does not consume a player seat.

Operators must deploy these gateway files and expose this endpoint through their
known HTTPS origin. The client must pin the provider/game endpoint to that origin
and perform a fresh successful capability + exact-key lookup before invitation
admission. Never accept an endpoint from Discord data. An old server has no
capability response and must remain presence-only. In particular, its ordinary
name route might CREATE a room for `I#...`; sending that command without verified
support is unsafe.

The bundled MyCard client's existing secure room-list connections prove these
HTTP listener origins: `https://tiramisu.moenext.com:7923` (entertainment) and
`https://tiramisu.moenext.com:8923` (athletic). This does not establish that the
extension is deployed there. No HTTPS metadata origin is documented for
`mygo.superpre.pro:888` or `mygo2.superpre.pro:888`; their client invitation support
must stay disabled until an operator supplies a trusted HTTPS mapping. Do not
infer an HTTP port from the game port.

## Negotiation and wire frames

Clients opt in via `CTOS_JOIN_GAME.gameid`: `0x4d445034` requests metadata during
ordinary admission; `0x4d445035` requests strict invitation admission. The gateway
consumes either value and forwards gameid 0 to the core. Other gameids are left
unchanged. Invitation intent bypasses the initial reconnect-by-identity branch,
so an invite cannot silently reconnect to the player's previous duel.

An opted-in seated player in an eligible public waiting room receives this frame
immediately AFTER the unchanged native `STOC_TYPE_CHANGE`:

```
0f 00 f2 02 <backend:1=srvpro,2=mycard> <inviteId:12 ASCII bytes>
```

Metadata may be sent while the room is full; clients must independently gate
sharing on their current authoritative player count and phase. Clear metadata
on duel start, spectator promotion, transport retirement and connection-version
change. Old clients never receive this extension.

## Strict admission

- SRVPro: send `I#<inviteId>` with invitation gameid. The prefix is reserved;
  malformed/missing/expired keys reject without find-or-create or spectating.
- MyCard: send existing encrypted 8-character authenticated header with action
  **6**, followed by the 12-character key, with invitation gameid. All **20**
  UTF-16 code units must be written; a writer reserving a terminator and sending
  only 19 is incompatible. Current/previous u16Secret lookup, checksum/decryption,
  normal version and existing account/IP bans are retained. The action executes
  only after authentication. Action 6 without invitation negotiation rejects;
  invitation negotiation with another action rejects. Matchmaking passwords and
  action 4 must never be shared or reused as invitation identity.

Admission rechecks instance identity, public/waiting state and available seats
immediately before the synchronous Room.connect reservation. Every failure uses
the existing error path and never changes into spectator admission. Lobby keys
are public identity; authentication remains the server's responsibility.

## Validation

Run `node lobby-invites.test.js`. It tests the production helper and extracts the
checked-in generated JOIN, TYPE_CHANGE and Room.join_player implementations into
a bounded dependency fixture. It does not start a server, core, listener or auth
request. Regenerate only `ygopro-server.js` with CoffeeScript 2.7.0 after editing
the CoffeeScript source. Live two-client admission and actual deployed HTTPS
capability/auth acceptance remain deployment acceptance requirements.
