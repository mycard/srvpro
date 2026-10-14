"use strict";
const assert = require("assert");
const fs = require("fs");
const vm = require("vm");
const path = require("path");
const invites = require("./lobby-invites");
const source = fs.readFileSync(path.join(__dirname, "ygopro-server.js"), "utf8");
let passed = 0;
async function test(name, run) { await run(); ++passed; console.log("PASS " + name); }
function settings(mycard = false) {
  return { version: 4945, alternative_versions: [], modules: {
    http: { public_roomlist: true }, stop: false,
    tournament_mode: { enabled: false }, challonge: { enabled: false },
    mycard: { enabled: mycard, auth_base_url: "https://auth.invalid", auth_key: "fixture" },
    random_duel: { enabled: true }, windbot: { enabled: false }, mysql: { enabled: false },
    cloud_replay: { enabled: false }, arena_mode: {}
  }};
}
function room(extra = {}) {
  return { name: "public", inviteId: invites.createKey(), established: true, duel_stage: 0,
    players: [{ pos: 0 }], hostinfo: { mode: 0 }, ...extra };
}
function packet(pass, gameid = invites.INVITATION_GAME_ID) {
  const buffer = Buffer.alloc(48);
  buffer.writeUInt16LE(4945, 0);
  buffer.writeUInt32LE(gameid, 4);
  buffer.write(pass, 8, 40, "utf16le");
  return { buffer, info: { version: 4945, gameid, pass }};
}
function mycardPassword(key, action = 6, secret = 123) {
  const data = Buffer.alloc(6);
  data[1] = action << 4;
  data[0] = (256 - data[1]) & 255;
  for (const offset of [0, 2, 4]) data.writeUInt16LE(data.readUInt16LE(offset) ^ (secret % 65535 + 1), offset);
  return data.toString("base64") + key;
}
function fixture(config = settings(), existing = room()) {
  let join, typeChange;
  const events = { errors: [], joined: [], created: [], reconnect: 0, auth: 0, watched: 0 };
  const context = {
    Buffer, console, settings: config, lobbyInvites: invites, ROOM_all: [existing],
    ROOM_connected_ip: {}, ROOM_validate: () => true,
    ROOM_find_or_create_by_name: async name => { events.created.push(name); return existing; },
    ROOM_find_by_name: () => existing, ROOM_find_by_title: () => existing,
    CLIENT_get_authorize_key: c => c.name, CLIENT_kick: () => {},
    CLIENT_is_able_to_reconnect: () => false, CLIENT_is_able_to_kick_reconnect: () => false,
    CLIENT_pre_reconnect: () => { ++events.reconnect; },
    aragami: { del: async () => {} }, aragami_classes: { ClientVersionBlocker: function() {} },
    badwordR: { level1: /(?!)x/, level2: /(?!)x/, level3: /(?!)x/ },
    log: { warn() {} },
    _: { indexOf: (array, item) => array.indexOf(item) },
    axios: { get: async () => { ++events.auth; return { data: { user: { u16Secret: 123, u16SecretPrevious: 456 } } }; } },
    ygopro: {
      constants: { COLORS: {}, DUEL_STAGE: { BEGIN: 0 } },
      structs: { get: () => ({ _setBuff(b) { this.buffer = b; }, set(field, value) {
        if (field === "gameid") this.buffer.writeUInt32LE(value, 4);
        else if (field === "version") this.buffer.writeUInt16LE(value, 0);
      } }) },
      stoc_die: (client, message) => { events.errors.push(message); client.isClosed = true; },
      stoc_send_chat: () => {}, stoc_send: () => {},
      ctos_follow: (name, sync, handler) => { assert.equal(name, "JOIN_GAME"); join = handler; },
      stoc_follow: (name, sync, handler) => { assert.equal(name, "TYPE_CHANGE"); typeChange = handler; },
      helper: { prepareMessage: (name, data) => { assert.equal(name, "STOC_TYPE_CHANGE"); return Buffer.concat([Buffer.from([2, 0, 0x13]), data]); } }
    }
  };
  vm.createContext(context);
  const joinStart = source.indexOf("  ygopro.ctos_follow('JOIN_GAME',");
  const joinEnd = source.indexOf("  ygopro.stoc_follow('JOIN_GAME',", joinStart);
  assert(joinStart >= 0 && joinEnd > joinStart);
  vm.runInContext(source.slice(joinStart, joinEnd), context);
  const typeStart = source.indexOf("  ygopro.stoc_follow('TYPE_CHANGE',");
  const typeEnd = source.indexOf("  ygopro.stoc_follow('HS_PLAYER_ENTER',", typeStart);
  vm.runInContext(source.slice(typeStart, typeEnd), context);
  const methodStart = source.indexOf("    join_player(client) {");
  const methodEnd = source.indexOf("    refreshLastActiveTime(", methodStart);
  const method = source.slice(methodStart, methodEnd).trim().replace(/^join_player\(/, "function(");
  const actualJoin = vm.runInContext("(" + method + ")", context);
  existing.join_player = function(client) { return actualJoin.call(this, client); };
  existing.connect = client => { events.joined.push(client); existing.players.push(client); };
  existing.join_post_watch = () => { ++events.watched; return true; };
  async function send(pass, gameid = invites.INVITATION_GAME_ID) {
    const p = packet(pass, gameid), client = { name: "Player", ip: "test", setTimeout() {} };
    await join(p.buffer, p.info, client, {}, []);
    return { client, ...p };
  }
  return { context, events, room: existing, send, typeChange };
}

(async () => {
  await test("room incarnation keys are opaque, distinct and exactly 12 ASCII units", () => {
    const keys = Array.from({ length: 100 }, () => invites.createKey());
    assert.equal(new Set(keys).size, 100); keys.forEach(k => assert(/^[A-Za-z0-9_-]{12}$/.test(k)));
  });
  await test("old clients do not opt in and gameid is preserved", () => {
    for (const id of [0, 1, 999]) { const info = { gameid: id }, c = {}; assert.equal(invites.negotiate(info,c), false); assert.equal(info.gameid,id); }
  });
  await test("both negotiated gameids are consumed before core forwarding", () => {
    for (const id of [invites.METADATA_GAME_ID, invites.INVITATION_GAME_ID]) { const info = { gameid: id }, c = {}; assert(invites.negotiate(info,c)); assert.equal(info.gameid,0); assert(c.supportsLobbyMetadata); assert.equal(c.invitationRequest,id===invites.INVITATION_GAME_ID); }
  });
  await test("listing carries only public instance identity and seat counts", () => {
    const r = room(); assert.deepStrictEqual(invites.listing([r],settings()), { version:1, backend:"srvpro", enabled:true, rooms:[{inviteId:r.inviteId,players:1,maxPlayers:2}] });
  });
  for (const [name, mutation] of Object.entries({
    private: {private:true}, password: {name:"public$secret"}, started: {duel_stage:1},
    deleted: {deleted:true}, finished: {finished:true}, error: {error:"failed"},
    random: {random_type:"M"}, arena: {arena:"athletic"}, bot: {windbot:true},
    tournament: {challonge_info:{}}, recovered: {recover_duel_log_id:1},
    pending: {established:false}, empty: {players:[]}, full: {players:[{pos:0},{pos:1}]}
  })) await test(name + " rooms are neither listed nor admitted", () => {
    const r=room(mutation), c={invitationRequest:true}; assert.equal(invites.listing([r],settings()).rooms.length,0); assert.equal(invites.findForInvitation([r],r.inviteId,c,settings()),null);
  });
  await test("pending and not-yet-retired closed players reserve slots; spectators do not", () => {
    for(const p of [{},{pos:1,isClosed:true}]) assert.equal(invites.joinable(room({players:[{pos:0},p]}),settings()),false);
    assert(invites.joinable(room({players:[{pos:0},{pos:7}]}),settings()));
    assert.equal(invites.capacity(room({hostinfo:{mode:2}})),4);
  });
  await test("disabled public listing and tournament settings fail closed", () => {
    for (const field of ["http","tournament_mode","challonge"]) { const s=settings(); if(field==="http") s.modules.http={}; else s.modules[field].enabled=true; assert.equal(invites.listing([room()],s).enabled,false); }
  });
  await test("recreated same-name rooms never accept an old invitation", () => {
    const old=room(), replacement=room(); old.deleted=true;
    assert.equal(invites.findForInvitation([old,replacement],old.inviteId,{invitationRequest:true},settings()),null);
  });
  await test("metadata is negotiated, seated, current-room only and native TYPE_CHANGE stays first", async () => {
    const f=fixture(); const c=f.room.players[0]; c.rid=0; const native=Buffer.from([0x10]);
    const datas=[]; assert.equal(await f.typeChange(native,{type:0x10},c,{},datas),false); assert.equal(datas.length,0);
    c.supportsLobbyMetadata=true;
    assert.equal(await f.typeChange(native,{type:0x10},c,{},datas),true);
    assert.deepStrictEqual(datas[0],Buffer.from([2,0,0x13,0x10]));
    assert.equal(datas[1].length,17); assert.equal(datas[1].readUInt16LE(0),15); assert.deepStrictEqual(Array.from(datas[1].slice(2,5)),[0xf2,2,1]); assert.equal(datas[1].toString("ascii",5),f.room.inviteId);
    c.pos=7; assert.equal(invites.metadata(f.room,c,settings()),null);
  });
  await test("strict generic join reaches the existing room without find-or-create or reconnect", async () => {
    const f=fixture(); f.context.CLIENT_is_able_to_reconnect=()=>true;
    const p=await f.send("I#"+f.room.inviteId);
    assert.equal(p.buffer.readUInt32LE(4),0); assert.equal(f.events.joined.length,1); assert.equal(f.events.reconnect,0); assert.equal(f.events.created.length,0); assert.equal(f.events.errors.length,0);
  });
  for(const pass of ["I#short", "i#abcdefghijkl", "I#abcdefghijkl#password", "ordinary", "I#!!!!!!!!!!!!"])
    await test("malformed/reserved generic invitation rejects: " + pass, async () => {
      const f=fixture(); await f.send(pass); assert.equal(f.events.errors.length,1); assert.equal(f.events.created.length,0); assert.equal(f.events.joined.length,0);
    });
  await test("missing negotiation cannot admit an invitation", async () => {
    const f=fixture(); f.context.CLIENT_is_able_to_reconnect=()=>true; await f.send("I#"+f.room.inviteId,0); assert.equal(f.events.errors.length,1); assert.equal(f.events.reconnect,0); assert.equal(f.events.created.length,0);
  });
  await test("ordinary unnegotiated reconnect behavior is preserved", async () => {
    const f=fixture(); f.context.CLIENT_is_able_to_reconnect=()=>true; await f.send("ordinary",0); assert.equal(f.events.reconnect,1);
  });
  await test("ordinary room join remains find-or-create and has no invitation guard", async () => {
    const f=fixture(); await f.send("ordinary",0); assert.deepStrictEqual(f.events.created,["ordinary"]); assert.equal(f.events.joined.length,1);
  });
  await test("last-slot reservations and state change recheck never fall back to spectator", async () => {
    const f=fixture(); await f.send("I#"+f.room.inviteId); await f.send("I#"+f.room.inviteId);
    assert.equal(f.events.joined.length,1); assert.equal(f.events.errors.length,1); assert.equal(f.events.watched,0);
    const r=room(), g=fixture(settings(),r), c={invitationRequest:true,setTimeout(){}};
    invites.findForInvitation([r],r.inviteId,c,settings()); r.duel_stage=1; r.join_player(c); assert.equal(g.events.watched,0); assert.equal(g.events.errors.length,1);
  });
  await test("authenticated MyCard action 6 admits the exact key with all 20 code units", async () => {
    const f=fixture(settings(true)); f.context.CLIENT_is_able_to_reconnect=()=>true;
    const pass=mycardPassword(f.room.inviteId); assert.equal(pass.length,20);
    const p=await f.send(pass); assert.equal(p.buffer.toString("utf16le",8),pass);
    assert.equal(f.events.auth,1); assert.equal(f.events.joined.length,1); assert.equal(f.events.reconnect,0); assert.equal(f.events.created.length,0);
  });
  await test("MyCard previous-secret rotation still authenticates action 6", async () => {
    const f=fixture(settings(true)); await f.send(mycardPassword(f.room.inviteId,6,456)); assert.equal(f.events.joined.length,1);
  });
  for (const [name, pass] of [["short", "abc"], ["invalid base64", "!!!!!!!!abcdefghijkl"], ["bad checksum/auth", "AAAAAAAAabcdefghijkl"]])
    await test("MyCard malformed auth fails closed: " + name, async () => { const f=fixture(settings(true)); await f.send(pass); assert.equal(f.events.joined.length,0); assert.equal(f.events.created.length,0); assert.equal(f.events.errors.length,1); });
  await test("MyCard auth unavailable does not fall back or create a room", async () => {
    const f=fixture(settings(true)); f.context.axios.get=async()=>{throw new Error("offline");}; await f.send(mycardPassword(f.room.inviteId)); assert.equal(f.events.errors.length,1); assert.equal(f.events.joined.length,0);
  });
  await test("MyCard rechecks the room after asynchronous authentication", async () => {
    for (const mutate of [r => { r.deleted=true; }, r => { r.duel_stage=1; }, r => { r.players.push({}); }]) {
      const f=fixture(settings(true)); f.context.axios.get=async()=>{ mutate(f.room); return {data:{user:{u16Secret:123}}}; };
      await f.send(mycardPassword(f.room.inviteId)); assert.equal(f.events.errors.length,1); assert.equal(f.events.joined.length,0); assert.equal(f.events.watched,0);
    }
  });
  await test("MyCard action 6 requires invitation negotiation", async () => {
    const f=fixture(settings(true)); await f.send(mycardPassword(f.room.inviteId),invites.METADATA_GAME_ID); assert.equal(f.events.errors.length,1); assert.equal(f.events.joined.length,0);
  });
  await test("invitation negotiation cannot execute MyCard create/match/watch actions", async () => {
    for(const action of [1,2,3,4,5]) { const f=fixture(settings(true)); await f.send(mycardPassword(f.room.inviteId,action)); assert.equal(f.events.errors.length,1); assert.equal(f.events.joined.length,0); assert.equal(f.events.created.length,0); }
  });
  await test("private/full/started MyCard action 6 never creates or watches", async () => {
    for(const options of [{private:true},{duel_stage:1},{players:[{pos:0},{pos:1}]}]) { const f=fixture(settings(true),room(options)); await f.send(mycardPassword(f.room.inviteId)); assert.equal(f.events.errors.length,1); assert.equal(f.events.joined.length,0); assert.equal(f.events.watched,0); }
  });
  await test("disabled deployment rejects invitation before any special room creation", async () => {
    const s=settings(); s.modules.challonge.enabled=true; const f=fixture(s); await f.send("I#"+f.room.inviteId); assert.equal(f.events.errors.length,1); assert.equal(f.events.created.length,0);
  });
  console.log("PASS " + passed + " invitation checks using production helper, JOIN handler and Room admission method");
})().catch(error => { console.error(error); process.exitCode=1; });
