'use strict';

const assert = require('assert');
const fs = require('fs');
const vm = require('vm');
const coffee = require('coffeescript');
const { MycardSpectatorReplay } = require('./mycard-spectator-replay');
const policy = new MycardSpectatorReplay();
const client = (username, active = true) => {
  const value = {};
  policy.authenticate(value, { username, active });
  return value;
};
const a = client('alice'),
  b = client('alice'),
  same = client('alice');
policy.observe(a, 'one');
policy.observe(same, 'one');
assert.strictEqual(
  policy.blocked(a, true, true),
  false,
  'duplicate connections in one room count as one table',
);
policy.observe(b, 'two');
for (const value of [a, b, same])
  assert.strictEqual(policy.blocked(value, true, true), true);
assert.strictEqual(policy.blocked(a, true, false), true);
assert.strictEqual(policy.blocked(a, false, true), false);
policy.leave(b);
policy.leave(same);
assert.strictEqual(
  policy.blocked(a, true, true),
  true,
  'leaving a second room does not restore the first',
);
policy.unobserve(a);
policy.observe(a, 'one');
assert.strictEqual(
  policy.blocked(a, true, true),
  true,
  'changing roles does not reset the room session',
);
policy.leave(a);
policy.authenticate(a, { username: 'alice', active: true });
policy.observe(a, 'one');
assert.strictEqual(
  policy.blocked(a, true, true),
  false,
  'actual leave and rejoin resets the session',
);
const inactive = client('inactive', false);
policy.observe(inactive, 'one');
assert.strictEqual(policy.blocked(inactive, true, true), true);
assert.strictEqual(policy.blocked(inactive, true, false), false);
assert.strictEqual(policy.blocked(inactive, false, true), true);
assert.strictEqual(policy.blocked(inactive), false);
policy.clearRoom('one');
assert.strictEqual(policy.observers.size, 0);
assert.strictEqual(
  policy.blocked(inactive, true, true),
  true,
  'room cleanup must not erase a pending replay decision',
);

// Exercise the actual delayed replay entrypoint for both observer identities.
const source = fs.readFileSync(
  require.resolve('./ygopro-server.coffee'),
  'utf8',
);
const sender = source.slice(
  source.indexOf('CLIENT_send_replays ='),
  source.indexOf('CLIENT_send_replays_and_kick ='),
);
let sent = 0;
let hints = 0;
const context = {
  settings: {
    modules: {
      mycard: {
        enabled: true,
        restrict_multi_room_spectator_replay: true,
        restrict_unverified_spectator_replay: true,
      },
      replay_delay: true,
      tournament_mode: {},
    },
  },
  mycardSpectatorReplay: policy,
  ygopro: {
    constants: { COLORS: {} },
    stoc_send_chat: async () => {
      hints++;
    },
    stoc_send: async () => {
      sent++;
    },
  },
};
context.mycardSpectatorReplayEnabled = () => {
  const config = context.settings.modules.mycard;
  return (
    config.enabled &&
    (config.restrict_multi_room_spectator_replay ||
      config.restrict_unverified_spectator_replay)
  );
};
context.global = context;
vm.createContext(context);
vm.runInContext(coffee.compile(sender, { bare: true }), context);
const room = { replays: [Buffer.from('replay')], hostinfo: { mode: 1 } };
(async () => {
  for (const identity of [{ pos: 7 }, { is_post_watcher: true }]) {
    Object.assign(inactive, identity);
    delete inactive.replays_sent;
    assert.strictEqual(
      await context.CLIENT_send_replays(inactive, room),
      false,
    );
    assert.strictEqual(inactive.replays_sent, undefined);
    assert.strictEqual(hints, 0);
    delete inactive.pos;
    delete inactive.is_post_watcher;
  }
  inactive.pos = 0;
  assert.strictEqual(
    await context.CLIENT_send_replays(inactive, room),
    true,
    'duelists retain their replays',
  );
  assert.strictEqual(sent, 1);
  assert.strictEqual(hints, 1);
  inactive.pos = 7;
  delete inactive.replays_sent;
  context.settings.modules.mycard.restrict_multi_room_spectator_replay = false;
  context.settings.modules.mycard.restrict_unverified_spectator_replay = false;
  assert.strictEqual(await context.CLIENT_send_replays(inactive, room), true);
  assert.strictEqual(sent, 2);
  assert.strictEqual(hints, 2);
  console.log('Mycard spectator replay regression tests passed');
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
