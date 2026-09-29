import assert from 'node:assert/strict';
import test from 'node:test';
import {bindLocalJsHost} from '../host-common/local-js-host.mjs';
import {withScopedStrategy} from '../host-common/scoped-strategy.mjs';
import {withScopedStrategy as compatibilityEntry} from './invocation.mjs';
import {finalizerCase} from '../host-node/finalizer-fixture.mjs';

test('JS Host binding snapshots its runtime without installing contributions', () => {
  const setup = {};
  const usage = {};
  const runtime = {strategyHostUsage: value => {
    assert.equal(value, setup);
    return usage;
  }};
  const host = bindLocalJsHost(runtime, () => {
    assert.fail('contributions must not be installed by binding or usage');
  });
  runtime.strategyHostUsage = () => assert.fail('caller mutated runtime');
  assert.equal(host.usage(setup), usage);
  assert.ok(Object.isFrozen(host));
});

test('Workers compatibility entry is the same scoped owner, not another engine', () => {
  assert.equal(compatibilityEntry, withScopedStrategy);
});

test('shared JS scope preserves failed cleanup ownership and original causes', async () => {
  for (const kind of ['error', 'undefined', 'null']) {
    assert.deepEqual(await finalizerCase(kind, true), {
      failed: true, firstPreserved: true, pending: true, cleanup: false,
      finished: 2, closed: 1, consumed: 0,
    });
  }
});
