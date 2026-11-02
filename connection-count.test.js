'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const coffee = require('coffeescript');

// Exercise the actual admission and close handlers without starting the server.
const source = fs.readFileSync(
  require.resolve('./ygopro-server.coffee'),
  'utf8',
);
const admission = source.slice(
  source.indexOf('CLIENT_set_ip ='),
  source.indexOf('SOCKET_flush_data ='),
);
const closeStart = source.indexOf('  closeHandler = (error) ->');
const close = source.slice(
  closeStart,
  source.indexOf('\n  if client.isWs', closeStart),
);
const context = {
  ROOM_connected_ip: {},
  ROOM_bad_ip: {},
  ROOM_all: [],
  settings: { modules: { test_mode: {}, heartbeat_detection: {} } },
  getRealIp: (physical, forwarded) => forwarded || physical,
  isTrustedProxy: (ip) => ip === 'proxy',
  real_windbot_server_ip: 'bot',
  log: { info() {} },
  SERVER_kick() {},
  CLIENT_reconnect_register: () => false,
  mycardSpectatorReplay: { leave() {} },
};
context.global = context;
vm.createContext(context);
vm.runInContext(
  coffee.compile(
    admission +
      '\ncreateClose = (client) ->\n' +
      close +
      '\n  return closeHandler\n',
    { bare: true },
  ),
  context,
);

function connect(ip, ws = false) {
  const client = {
    physical_ip: ip,
    isWs: ws,
    destroy() {
      this.destroyed = true;
      if (this.close) this.close();
    },
  };
  if (!context.CLIENT_set_ip(client))
    client.close = context.createClose(client);
  return client;
}

for (const ws of [false, true]) {
  const ip = ws ? 'websocket' : 'tcp';
  const accepted = Array.from({ length: 10 }, () => connect(ip, ws));
  assert.strictEqual(context.ROOM_connected_ip[ip], 10);
  for (let i = 0; i < 30; i++) {
    assert.strictEqual(connect(ip, ws).destroyed, true);
    assert.strictEqual(context.ROOM_connected_ip[ip], 10);
  }
  accepted.forEach((client) => {
    client.close();
    client.close();
  });
  assert.strictEqual(context.ROOM_connected_ip[ip], undefined);
  const next = connect(ip, ws);
  assert.strictEqual(next.destroyed, undefined);
  next.close();
}

const full = Array.from({ length: 10 }, () => connect('forwarded'));
const migrating = connect('physical');
assert.strictEqual(context.CLIENT_set_ip(migrating, 'forwarded'), true);
assert.strictEqual(
  context.ROOM_connected_ip.forwarded,
  10,
  'close must not release an existing user slot',
);
assert.strictEqual(context.ROOM_connected_ip.physical, undefined);
migrating.close();
assert.strictEqual(context.ROOM_connected_ip.forwarded, 10);
full.forEach((client) => client.close());

context.ROOM_bad_ip.bad = 6;
assert.strictEqual(connect('bad').destroyed, true);
assert.strictEqual(context.ROOM_connected_ip.bad, undefined);
context.ROOM_bad_ip.proxy = 6;
assert.strictEqual(connect('proxy', true).destroyed, true);
assert.ok(!context.ROOM_connected_ip.proxy);
assert.ok(
  Object.values(context.ROOM_connected_ip).every((count) => count === 0),
);
console.log('connection count regression tests passed');
