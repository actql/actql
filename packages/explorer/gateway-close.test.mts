import assert from 'node:assert/strict';
import {setImmediate as nextTurn} from 'node:timers/promises';
import test from 'node:test';
import {createExplorerGateway, gatewayLimits, startExplorerGateway} from './gateway.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((yes, no) => {resolve = yes; reject = no;});
  return {promise, resolve, reject};
}

async function session(gateway, origin) {
  const response = await gateway.fetch(new Request(`${origin}/api/session`, {
    method: 'POST', headers: {Host: new URL(origin).host, Origin: origin,
      'Content-Type': 'application/json'},
    body: JSON.stringify({bootstrap: gateway.issueBootstrap().bootstrap}),
  }));
  assert.equal(response.status, 200);
  const body = await response.json();
  return {Host: new URL(origin).host, Origin: origin, 'Content-Type': 'application/json',
    Cookie: response.headers.get('set-cookie').split(';')[0], 'X-Actql-CSRF': body.csrf};
}

for (const rejects of [false, true]) {
  test(`Gateway close retains the original outstanding SDK read through ${rejects ? 'rejection' : 'success'}`, async () => {
    const original = deferred(), entered = deferred();
    let calls = 0, settled = false;
    const origin = 'http://127.0.0.1:43210';
    const gateway = createExplorerGateway({origin, client: {
      attach() {assert.fail('No Run operation');},
      checkpoints() {calls++; entered.resolve(); return original.promise;},
      close() {assert.fail('The Client is borrowed');},
    }});
    const headers = await session(gateway, origin);
    const response = gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
      method: 'POST', headers, body: '{}',
    }));
    try {
      await entered.promise;
      const closing = gateway.close();
      assert.equal(gateway.close(), closing, 'Repeated close retains the same settlement');
      Promise.resolve(closing).then(() => {settled = true;});
      await nextTurn();
      assert.equal(settled, false, 'Closing presentation must not acknowledge an outstanding SDK call');
      const refused = await gateway.fetch(new Request(origin, {headers: {Host: new URL(origin).host}}));
      assert.equal(refused.status, 503);
      if (rejects) original.reject(new Error('private original read failure'));
      else original.resolve({items: []});
      await closing;
      const late = await response;
      assert.notEqual(late.status, 200);
      assert(!(await late.text()).includes('private original read failure'));
      assert.equal(settled, true);
      assert.equal(calls, 1);
    } finally {
      original.resolve({items: []});
      await response;
      await gateway.close();
    }
  });
}

test('a reentrant close from the original SDK callback retains that same invocation', async () => {
  const original = deferred(), entered = deferred();
  const origin = 'http://127.0.0.1:43210';
  let closing, settled = false;
  const gateway = createExplorerGateway({origin, client: {
    attach() {assert.fail('No Run operation');},
    checkpoints() {
      closing = gateway.close();
      Promise.resolve(closing).then(() => {settled = true;});
      entered.resolve();
      return original.promise;
    },
  }});
  const headers = await session(gateway, origin);
  const response = gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
    method: 'POST', headers, body: '{}',
  }));
  try {
    await entered.promise;
    await nextTurn();
    assert.equal(settled, false, 'The original call must be retained before invoking its SDK callback');
    original.resolve({items: []});
    await closing;
    assert.notEqual((await response).status, 200);
    assert.equal(settled, true);
  } finally {
    original.resolve({items: []});
    await response;
    await gateway.close();
  }
});

test('a presentation timeout leaves the same SDK call pending until close observes its settlement', async t => {
  t.mock.timers.enable({apis: ['setTimeout']});
  const original = deferred(), entered = deferred();
  const origin = 'http://127.0.0.1:43210';
  let calls = 0, closed = false;
  const gateway = createExplorerGateway({origin, client: {
    attach() {assert.fail('No Run operation');},
    checkpoints() {calls++; entered.resolve(); return original.promise;},
  }});
  const headers = await session(gateway, origin);
  const response = gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
    method: 'POST', headers, body: '{}',
  }));
  try {
    await entered.promise;
    t.mock.timers.tick(gatewayLimits.requestMs);
    assert.equal((await response).status, 504);
    const closing = gateway.close();
    Promise.resolve(closing).then(() => {closed = true;});
    await nextTurn();
    assert.equal(closed, false, 'A timed-out HTTP response does not settle the original SDK call');
    original.resolve({items: []});
    await closing;
    assert.equal(closed, true);
    assert.equal(calls, 1, 'No read retry or replacement');
  } finally {
    original.resolve({items: []});
    await gateway.close();
    t.mock.timers.reset();
  }
});

test('the actual loopback server close waits for its original SDK call without closing the borrowed Client', async () => {
  const original = deferred(), entered = deferred();
  let calls = 0, closed = false;
  const server = await startExplorerGateway({client: {
    attach() {assert.fail('No Run operation');},
    checkpoints() {calls++; entered.resolve(); return original.promise;},
    close() {assert.fail('The Client is borrowed');},
  }});
  const bootstrap = await fetch(`${server.origin}/api/session`, {
    method: 'POST', headers: {Origin: server.origin, 'Content-Type': 'application/json'},
    body: JSON.stringify({bootstrap: server.issueBootstrap().bootstrap}),
  });
  const body = await bootstrap.json();
  const response = fetch(`${server.origin}/api/read/checkpoints`, {
    method: 'POST', headers: {Origin: server.origin, 'Content-Type': 'application/json',
      Cookie: bootstrap.headers.get('set-cookie').split(';')[0], 'X-Actql-CSRF': body.csrf},
    body: '{}',
  }).catch(() => null);
  try {
    await entered.promise;
    const closing = server.close();
    assert.equal(server.close(), closing);
    closing.then(() => {closed = true;});
    await nextTurn();
    assert.equal(closed, false, 'HTTP socket retirement is separate from original SDK settlement');
    original.resolve({items: []});
    await closing;
    await response;
    assert.equal(calls, 1);
    assert.equal(closed, true);
    await assert.rejects(fetch(server.origin));
  } finally {
    original.resolve({items: []});
    await response;
    await server.close();
  }
});

test('closing before a request body is admitted prevents SDK entry', async () => {
  const origin = 'http://127.0.0.1:43210';
  let calls = 0;
  const gateway = createExplorerGateway({origin, client: {
    attach() {assert.fail('No Run operation');},
    checkpoints() {calls++; return {items: []};},
  }});
  const headers = await session(gateway, origin);
  const response = gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
    method: 'POST', headers, body: '{}',
  }));
  await gateway.close();
  assert.notEqual((await response).status, 200);
  assert.equal(calls, 0);
});

test('settlement removes the original read before admitting its replacement into the four-call bound', async () => {
  // Observe the real collection without changing its ordinary add/delete
  // behavior. Reenter admission at the old read's removal boundary.
  const OriginalSet = globalThis.Set;
  const originals = Array.from({length: 4}, deferred), entered = deferred(), probed = deferred();
  const origin = 'http://127.0.0.1:43210';
  let gateway, headers, replacement, calls = 0, maximum = 0, didProbe = false;
  class ObservedSet extends OriginalSet {
    add(value) {
      const result = super.add(value);
      if (value instanceof Promise) maximum = Math.max(maximum, this.size);
      return result;
    }
    delete(value) {
      if (value instanceof Promise && !didProbe) {
        didProbe = true;
        replacement = gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
          method: 'POST', headers, body: '{}',
        }));
        probed.resolve();
      }
      return super.delete(value);
    }
  }
  globalThis.Set = ObservedSet;
  try {
    gateway = createExplorerGateway({origin, client: {
      attach() {assert.fail('No Run operation');},
      checkpoints() {
        const index = calls++;
        if (calls === 4) entered.resolve();
        return index < 4 ? originals[index].promise : {items: []};
      },
    }});
  } finally {globalThis.Set = OriginalSet;}
  headers = await session(gateway, origin);
  const responses = Array.from({length: 4}, () => gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
    method: 'POST', headers, body: '{}',
  })));
  try {
    await entered.promise;
    assert.equal(maximum, 4);
    originals[0].resolve({items: []});
    await probed.promise;
    const overlap = await replacement;
    assert.equal(maximum, 4, 'Retained original reads and newly admitted reads share the same four-call bound');
    assert.equal(overlap.status, 429, 'The old invocation still owns its slot until collection removal');
    assert.equal(calls, 4);
    const following = await gateway.fetch(new Request(`${origin}/api/read/checkpoints`, {
      method: 'POST', headers, body: '{}',
    }));
    assert.equal(following.status, 200, 'The same slot is available after original removal');
    assert.equal(calls, 5);
    assert.equal(maximum, 4);
  } finally {
    for (const original of originals) original.resolve({items: []});
    await Promise.all(responses);
    await replacement;
    await gateway.close();
  }
});
