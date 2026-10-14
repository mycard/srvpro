'use strict';
// Full production netRequestHandler and reconnect admission bodies, controlled sockets.
const fs = require('fs');
const vm = require('vm');
const {EventEmitter} = require('events');
const path = require('path');
const PQueue = require('p-queue').default;
const sourceArgument = process.argv.indexOf('--source');
const sourcePath = sourceArgument >= 0 ? process.argv[sourceArgument + 1] : path.join(__dirname, 'ygopro-server.js');
const source = fs.readFileSync(sourcePath, 'utf8');
function slice(start, end) {
  const a = source.indexOf(start), b = source.indexOf(end, a);
  if (a < 0 || b < 0) throw Error('Source boundary changed: ' + start);
  return source.slice(a, b);
}
const network = slice('  netRequestHandler = function(client) {', '  deck_name_match = global.deck_name_match');
const admission = slice('  CLIENT_is_able_to_reconnect = global.CLIENT_is_able_to_reconnect', '  CLIENT_is_able_to_kick_reconnect = global.CLIENT_is_able_to_kick_reconnect');
const reconnectCleanup = slice('  release_disconnect = global.release_disconnect', '  CLIENT_get_authorize_key = global.CLIENT_get_authorize_key')
  + slice('  SERVER_clear_disconnect = global.SERVER_clear_disconnect', '  ROOM_clear_disconnect = global.ROOM_clear_disconnect');
function deferred() { let resolve, reject; const promise = new Promise((a, b) => { resolve = a; reject = b; }); return {promise, resolve, reject}; }
class Socket extends EventEmitter {
  constructor() { super(); this.isClosed = false; this.remoteAddress = '127.0.0.1'; }
  setTimeout() {}
  destroy() { this.destroyCount = (this.destroyCount || 0) + 1; this.emit('close', false); }
}
async function ticks() { for (let n = 0; n < 30; n++) await Promise.resolve(); }
const WIN = Buffer.from([4, 0, 1, 5, 1, 0]);
const END = Buffer.from([1, 0, 22]);
function fixture() {
  const client = new Socket(); Object.assign(client, {rid: 0, ip: '127.0.0.1', name: 'Fixture', pass: 'Fixture', pos: 0});
  const timers = new Map(), forwarded = [], notices = [], warnings = [], failures = [], cleanup = [];
  let timerId = 0;
  const room = {duel_stage: 3, players: [client], get_playing_player() { return this.players; }, disconnect() {}};
  const context = {
    global: {}, net: {Socket}, PQueue,
    settings: {modules: {reconnect: {enabled: true}, heartbeat_detection: {enabled: false},
      cloud_replay: {enabled: false}, challonge: {enabled: false}, mycard: {enabled: false}, tournament_mode: {enabled: false}}},
    ROOM_all: [room], ROOM_connected_ip: {}, ROOM_bad_ip: {}, disconnect_list: {},
    CLIENT_set_ip: () => false, CLIENT_reconnect_register: () => false,
    CLIENT_get_authorize_key: () => 'fixture', CLIENT_reconnect_unregister() {},
    CLIENT_kick(target) { target.system_kicked = true; target.destroy(); },
    SERVER_kick(target) { target.destroy(); }, SERVER_clear_disconnect(target) { cleanup.push(target); },
    log: {warn(...args) { warnings.push(args); }},
    setTimeout(callback, ms) { const id = ++timerId; timers.set(id, {callback, ms}); return id; },
    clearTimeout(id) { timers.delete(id); },
    ygopro: {constants: {COLORS: {RED: 1}, DUEL_STAGE: {BEGIN: 0}},
      stoc_send_chat(target, text) { notices.push({target, text}); },
      helper: {handleBuffer: async buffer => ({datas: [buffer]}),
        send: async (target, buffer) => { forwarded.push({target, bytes: buffer.toString('hex')}); }}}
  };
  vm.createContext(context);
  vm.runInContext(network + admission + reconnectCleanup, context);
  const clearDisconnect = context.SERVER_clear_disconnect;
  context.SERVER_clear_disconnect = target => { cleanup.push(target); return clearDisconnect(target); };
  context.netRequestHandler(client);
  const server = client.server;
  function fire(event, data) {
    for (const callback of server.listeners(event)) {
      const value = callback(data);
      if (value && typeof value.catch === 'function') value.catch(error => failures.push(error));
    }
  }
  return {context, client, server, room, timers, forwarded, notices, warnings, failures, cleanup, fire};
}
let passed = 0, failed = 0;
function check(ok, name) { console.log((ok ? 'PASS ' : 'FAIL ') + name); if (ok) passed++; else failed++; }
(async () => {
  {
    const f = fixture(), parse = deferred(); let count = 0;
    f.context.ygopro.helper.handleBuffer = async buffer => { if (++count === 1) await parse.promise; return {datas: [buffer]}; };
    f.fire('data', WIN); f.fire('data', END); await ticks(); f.fire('close', false);
    check(!f.client.isClosed, 'Native EOF waits for accepted parser work');
    f.fire('data', Buffer.from([99])); parse.resolve(); await ticks();
    check(f.forwarded.map(x => x.bytes).join(',') === [WIN, END].map(x => x.toString('hex')).join(','), 'WIN and DUEL_END reach original client in order; later data rejected');
    check(f.client.destroyCount === 1 && f.cleanup.length === 1 && f.timers.size === 0, 'Drained EOF retires once and clears deadline');
  }
  {
    const f = fixture(), write = deferred();
    f.context.ygopro.helper.send = async (target, buffer) => { await write.promise; f.forwarded.push({target, bytes: buffer.toString('hex')}); };
    f.fire('data', WIN); await ticks(); f.fire('close', false);
    check(!f.client.isClosed, 'Native EOF waits for accepted socket write callback');
    write.resolve(); await ticks(); check(f.forwarded.length === 1 && f.client.isClosed, 'Completed terminal write precedes retirement');
  }
  {
    const f = fixture(), parse = deferred();
    f.context.ygopro.helper.handleBuffer = async buffer => { await parse.promise; return {datas: [buffer]}; };
    f.fire('data', WIN); await ticks(); f.fire('error', new Error('fixture')); f.fire('close', true);
    parse.resolve(); await ticks();
    check(f.forwarded.length === 1 && f.client.destroyCount === 1 && f.cleanup.length === 1 && f.notices.length === 1, 'Error and close share one terminal drain');
  }
  {
    const f = fixture(), parse = deferred();
    f.context.ygopro.helper.handleBuffer = async buffer => { await parse.promise; return {datas: [buffer]}; };
    f.fire('data', WIN); await ticks(); f.fire('close', false);
    const replacement = new Socket(); replacement.server = f.server;
    f.server.client = replacement; f.client.server = new Socket(); parse.resolve(); await ticks();
    check(f.forwarded.length === 0 && !replacement.isClosed && !replacement.destroyCount && f.cleanup.length === 1,
      'Late parser and terminal callback cannot affect replacement ownership');
  }
  {
    const f = fixture(), parse = deferred();
    f.context.ygopro.helper.handleBuffer = async buffer => { await parse.promise; return {datas: [buffer]}; };
    f.fire('data', WIN); await ticks(); f.fire('close', false);
    const timer = Array.from(f.timers.values())[0];
    check(!!timer && timer.ms === 10000, 'Drain deadline allows existing five-second replay wait');
    if (timer) timer.callback();
    parse.resolve(); await ticks();
    check(f.client.destroyCount === 1 && f.warnings.length === 1 && f.forwarded.length === 0 && f.timers.size === 0,
      'Stalled parse retires bounded owner; late completion sends nothing');
  }
  {
    const f = fixture(); f.client.isClosed = true; f.fire('close', false); await ticks();
    check(!f.client.destroyCount && f.cleanup.length === 1, 'Already closed external client still clears dead native reconnect entry');
  }
  {
    const f = fixture(); let parsed = 0;
    f.client.isClosed = true;
    f.context.ygopro.helper.handleBuffer = async buffer => { parsed++; return {datas: [buffer]}; };
    f.fire('data', WIN); await ticks();
    check(parsed === 1 && f.forwarded.length === 0 && !f.server.isClosed,
      'Disconnected player still updates native packet cache while its native owner remains live');
  }
  {
    const f = fixture(); f.fire('close', false); await ticks();
    check(f.client.destroyCount === 1 && f.timers.size === 0, 'Empty queue retires immediately without leaked timer');
  }
  {
    const f = fixture(); f.server.client = null; f.fire('close', false); await ticks();
    check(!f.client.destroyCount && f.cleanup.length === 1 && f.timers.size === 0,
      'Initial closure with no bound client still retires its timer and exact socket cleanup');
  }
  {
    const f = fixture(), old = new Socket(), newer = new Socket(), newerNative = new Socket();
    old.isClosed = true; old.server = f.server; newer.server = newerNative;
    const oldTimeout = f.context.setTimeout(() => {}, 90000), newTimeout = f.context.setTimeout(() => {}, 90000);
    f.context.disconnect_list.old = {old_client: old, old_server: f.server, timeout: oldTimeout};
    f.context.disconnect_list.newer = {old_client: newer, old_server: newerNative, timeout: newTimeout};
    f.server.client = null; f.fire('close', false); await ticks();
    check(!f.context.disconnect_list.old && f.context.disconnect_list.newer
      && !f.timers.has(oldTimeout) && f.timers.has(newTimeout) && !newer.destroyCount && !newerNative.destroyCount,
      'Exact SERVER_clear_disconnect removes only dead native owner and its grace timer');
    f.context.clearTimeout(newTimeout);
    check(f.timers.size === 0, 'No terminal or fixture-owned grace timers remain');
  }
  {
    const f = fixture(), parse = deferred();
    f.context.ygopro.helper.handleBuffer = () => parse.promise;
    f.fire('data', WIN); await ticks(); f.fire('close', false); parse.reject(new Error('parse-failed')); await ticks();
    check(f.failures.length === 1 && f.client.destroyCount === 1, 'Parser exception remains observable and does not prevent terminal retirement');
  }
  {
    const f = fixture(), deck = Buffer.from([1, 2, 3]);
    f.context.disconnect_list.fixture = {room_id: 0, deckbuf: deck, old_server: f.server};
    check(f.context.CLIENT_is_able_to_reconnect(f.client, deck), 'Live native reconnect retains exact-deck admission');
    check(!f.context.CLIENT_is_able_to_reconnect(f.client, Buffer.from([3, 2, 1])), 'Live native reconnect still rejects different deck');
    f.server.isClosed = true;
    check(!f.context.CLIENT_is_able_to_reconnect(f.client, deck), 'Reconnect cannot claim native transport during terminal drain');
    f.server.isClosed = false;
    check(f.context.CLIENT_get_kick_reconnect_target(f.client) === f.client, 'Live kick reconnect target remains supported');
    f.server.isClosed = true;
    check(f.context.CLIENT_get_kick_reconnect_target(f.client) == null, 'Kick reconnect cannot claim closed native transport');
  }
  console.log(JSON.stringify({sourcePath, queueVersion: require('p-queue/package.json').version,
    passed, failed, controlledSockets: true, remoteCauseEstablished: false}));
  process.exitCode = failed ? 1 : 0;
})().catch(error => { console.error(error); process.exitCode = 1; });
