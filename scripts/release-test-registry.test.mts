import assert from 'node:assert/strict';
import {test} from 'node:test';
import {openReleaseTestRegistry} from './release-test-registry.mjs';

test('release test registry closes its listening server successfully', async () => {
  const registry = await openReleaseTestRegistry([]);
  assert.equal(await registry.close(), undefined);
});

test('release test registry propagates the real server close callback error', async () => {
  const registry = await openReleaseTestRegistry([]);
  await registry.close();
  await assert.rejects(registry.close(), {code: 'ERR_SERVER_NOT_RUNNING'});
});
