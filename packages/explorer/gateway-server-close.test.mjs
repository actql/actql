import assert from 'node:assert/strict';
import {Server} from 'node:http';
import {setImmediate as nextTurn} from 'node:timers/promises';
import test from 'node:test';
import {startExplorerGateway} from './gateway.mjs';

test('a refused server close retries only the same original listener', async () => {
  const close = Server.prototype.close;
  const originalFailure = new Error('original listener close refused');
  let original, calls = 0;
  const attempted = [];
  Server.prototype.close = function(callback) {
    original ??= this;
    assert.equal(this, original);
    attempted.push(this);
    calls++;
    if (calls === 1) {
      queueMicrotask(() => callback(originalFailure));
      return this;
    }
    return Reflect.apply(close, this, [callback]);
  };
  let gateway;
  try {
    gateway = await startExplorerGateway({client: {
      attach() {assert.fail('No Run is opened');},
      close() {assert.fail('The borrowed Client is not the server cleanup');},
    }});
    const first = gateway.close();
    await assert.rejects(first, error => {
      assert.equal(error.message, 'ExplorerGatewayCleanupPending');
      assert.deepEqual(error.errors, [originalFailure]);
      return true;
    });
    assert.equal(original.listening, true, 'A refusal is not physical close acknowledgement');
    const retry = gateway.close();
    assert.notEqual(retry, first, 'A known failed cleanup must allow the same listener to retry');
    assert.equal(gateway.close(), retry, 'One original physical attempt stays in flight');
    await retry;
    assert.equal(calls, 2);
    assert.deepEqual(attempted, [original, original]);
    assert.equal(original.listening, false);
    assert.equal(gateway.close(), retry, 'Successful cleanup stays acknowledged');
  } finally {
    Server.prototype.close = close;
    if (original?.listening) {
      await new Promise((resolve, reject) => {
        Reflect.apply(close, original, [error => error ? reject(error) : resolve()]);
        original.closeAllConnections();
      });
    }
  }
});

test('a server close with an outstanding callback remains one pending attempt', async () => {
  const close = Server.prototype.close;
  let original, finish, calls = 0;
  Server.prototype.close = function(callback) {
    original ??= this;
    assert.equal(this, original);
    calls++;
    finish = () => Reflect.apply(close, this, [callback]);
    return this;
  };
  try {
    const gateway = await startExplorerGateway({client: {
      attach() {assert.fail('No Run is opened');},
      close() {assert.fail('The borrowed Client is not closed');},
    }});
    const pending = gateway.close();
    let settled = false;
    void pending.then(() => {settled = true;});
    await nextTurn();
    assert.equal(settled, false);
    assert.equal(gateway.close(), pending);
    assert.equal(calls, 1, 'A lost or pending callback does not permit a second close');
    assert.equal(original.listening, true);
    finish();
    await pending;
    assert.equal(original.listening, false);
  } finally {
    Server.prototype.close = close;
    if (original?.listening) {
      await new Promise((resolve, reject) => {
        Reflect.apply(close, original, [error => error ? reject(error) : resolve()]);
        original.closeAllConnections();
      });
    }
  }
});
