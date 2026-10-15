import assert from 'node:assert/strict';
import test from 'node:test';
import {bindLocalJsHost} from '../host-common/local-js-host.mjs';
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

test('retired Workers invocation import is refused without a fallback', async () => {
  const retired = new URL('./invocation.mjs', import.meta.url);
  await assert.rejects(import(retired.href), {
    code: 'ERR_MODULE_NOT_FOUND', url: retired.href,
  });
});

test('shared JS scope preserves failed cleanup ownership and original causes', async () => {
  for (const kind of ['error', 'undefined', 'null']) {
    assert.deepEqual(await finalizerCase(kind, true), {
      failed: true, firstPreserved: true, pending: true, cleanup: false,
      finished: 2, closed: 1, consumed: 0,
    });
  }
});
