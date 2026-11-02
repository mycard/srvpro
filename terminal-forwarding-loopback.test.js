'use strict';
const fs = require('fs');
const vm = require('vm');
const net = require('net');
const crypto = require('crypto');
const path = require('path');
const PQueue = require('p-queue').default;
const sourceArgument = process.argv.indexOf('--source');
const sourcePath = sourceArgument >= 0 ? process.argv[sourceArgument + 1] : path.join(__dirname, 'ygopro-server.js');
const source = fs.readFileSync(sourcePath, 'utf8');
const a = source.indexOf('  netRequestHandler = function(client) {');
const b = source.indexOf('  deck_name_match = global.deck_name_match', a);
if (a < 0 || b < 0) throw Error('Source boundary changed');
const network = source.slice(a, b);
const wait = ms => new Promise(resolve => setTimeout(resolve, ms));
function deferred() { let resolve; const promise = new Promise(done => { resolve = done; }); return {promise, resolve}; }
function chat(text) {
  const body = Buffer.from(text + '\0', 'utf16le'), frame = Buffer.alloc(body.length + 5);
  frame.writeUInt16LE(body.length + 3); frame[2] = 0x19; frame.writeUInt16LE(8, 3); body.copy(frame, 5); return frame;
}
const terminal = Buffer.from([4, 0, 1, 5, 1, 0, 1, 0, 0x16]);
async function run(buffered) {
  const sockets = new Set(), servers = [], timers = new Set(), errors = [];
  const parseGate = deferred(), upstreamClosed = deferred(), connected = deferred(), peerClosed = deferred();
  const chunks = [];
  let client, native, peer, kicked = 0, writes = 0, callbacks = 0, backpressure = 0, cleared = 0;
  const prefix = buffered ? Buffer.concat(Array.from({length: 4096}, () => chat('fixture '.repeat(100)))) : Buffer.alloc(0);
  const expected = Buffer.concat([prefix, terminal]);
  const room = {disconnect() {}};
  const helper = {
    handleBuffer: async buffer => { await parseGate.promise; return {datas: [buffer]}; },
    send: (target, buffer) => new Promise(resolve => {
      writes++;
      const accepted = target.write(buffer, error => { callbacks++; resolve(error); });
      if (!accepted) backpressure++;
    })
  };
  const context = {
    global: {}, net, PQueue,
    settings: {modules: {reconnect: {enabled: false}, heartbeat_detection: {enabled: false}, cloud_replay: {enabled: false}}},
    ROOM_all: [room], ROOM_connected_ip: {}, ROOM_bad_ip: {},
    CLIENT_set_ip: () => false, CLIENT_reconnect_register: () => false,
    CLIENT_kick(target) { kicked++; target.system_kicked = true; target.destroy(); },
    SERVER_kick(target) { target.destroy(); }, SERVER_clear_disconnect() { cleared++; },
    log: {warn(...args) { errors.push(args.join(' ')); }},
    setTimeout(callback, ms) { const timer = setTimeout(() => { timers.delete(timer); callback(); }, ms); timers.add(timer); return timer; },
    clearTimeout(timer) { clearTimeout(timer); timers.delete(timer); },
    ygopro: {helper, constants: {COLORS: {RED: 1}},
      stoc_send_chat(target) { return helper.send(target, chat('fixture server closed')); }}
  };
  vm.createContext(context); vm.runInContext(network, context);
  const ownSocket = socket => { sockets.add(socket); socket.on('error', error => errors.push(error.code || error.message)); return socket; };
  async function listen(server) {
    servers.push(server);
    await new Promise((resolve, reject) => { server.once('error', reject); server.listen(0, '127.0.0.1', resolve); });
    return server.address().port;
  }
  let deadline;
  try {
    const work = (async () => {
      const upstream = net.createServer(socket => { ownSocket(socket); socket.end(expected); });
      const upstreamPort = await listen(upstream);
      const front = net.createServer(socket => {
        client = ownSocket(socket); Object.assign(client, {rid: 0, ip: '127.0.0.1', name: 'Fixture'});
        context.netRequestHandler(client); native = ownSocket(client.server);
        native.on('close', () => upstreamClosed.resolve());
        native.connect(upstreamPort, '127.0.0.1', () => connected.resolve());
      });
      const frontPort = await listen(front);
      peer = ownSocket(net.connect(frontPort, '127.0.0.1'));
      peer.pause(); peer.on('data', chunk => chunks.push(Buffer.from(chunk))); peer.on('close', () => peerClosed.resolve());
      await connected.promise; await upstreamClosed.promise;
      const stayedOpenDuringParse = !client.destroyed;
      parseGate.resolve();
      await wait(buffered ? 200 : 25);
      const pendingWriteObserved = writes > callbacks;
      peer.resume();
      await peerClosed.promise;
      const received = Buffer.concat(chunks);
      const exactTerminal = received.length >= expected.length && received.subarray(0, expected.length).equals(expected);
      return {buffered, expectedBytes: expected.length, receivedBytes: received.length, stayedOpenDuringParse,
        pendingWriteObserved, backpressure, writes, callbacks, kicked, cleared, timers: timers.size,
        exactTerminal, expectedSha256: crypto.createHash('sha256').update(expected).digest('hex'),
        receivedPrefixSha256: crypto.createHash('sha256').update(received.subarray(0, expected.length)).digest('hex'), errors};
    })();
    const timeout = new Promise((_, reject) => { deadline = setTimeout(() => reject(Error('Loopback exceeded 8-second bound')), 8000); });
    return await Promise.race([work, timeout]);
  } finally {
    clearTimeout(deadline); parseGate.resolve();
    for (const timer of timers) clearTimeout(timer);
    timers.clear();
    for (const socket of sockets) socket.destroy();
    await Promise.all(servers.map(server => new Promise(resolve => server.close(() => resolve()))));
  }
}
(async () => {
  const results = [];
  for (const buffered of [false, true]) results.push(await run(buffered));
  const passed = results.every(r => r.exactTerminal && r.stayedOpenDuringParse && r.kicked === 1 && r.cleared === 1 && r.timers === 0)
    && results[1].pendingWriteObserved && results[1].backpressure > 0;
  const receipt = {status: passed ? 'Passed real TCP terminal drain' : 'Reproduced terminal forwarding loss',
    queueVersion: require('p-queue/package.json').version, sourcePath, results,
    nativeCoreDuel: false, remoteCauseEstablished: false};
  if (process.env.TERMINAL_FORWARDING_RECEIPT)
    fs.writeFileSync(process.env.TERMINAL_FORWARDING_RECEIPT, JSON.stringify(receipt, null, 2));
  console.log(JSON.stringify(receipt, null, 2)); process.exitCode = passed ? 0 : 1;
})().catch(error => { console.error(error); process.exitCode = 1; });
