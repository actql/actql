import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import test from 'node:test';
import * as moon from
  '../../_build/js/release/build/connectors_builtin_node_rela/connectors_builtin_node_rela.js';
import {runCapturedStrategy} from './entry-rela.mjs';

test('RelA-only Node bundle executes a checked Local Program', async () => {
  const fixture = new URL('../../packages/sdk/fixtures/', import.meta.url);
  const [document, environmentBody, registry, contract] = await Promise.all([
    readFile(new URL('values.json', fixture), 'utf8'),
    readFile(new URL('values.environment.json', fixture), 'utf8'),
    readFile(new URL('../../spec/dependencies/aoa-pipeline-registry.json',
      import.meta.url), 'utf8'),
    readFile(new URL('../../spec/contracts/actql-aoa.json', import.meta.url),
      'utf8'),
  ]);
  const environment = moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, false, false, false, false,
  );
  assert.ok(environment);
  assert.equal(moon.clientProgramCheckEnvironment(
    environmentBody.trimEnd(),
    'sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904',
    false, false, true, true, false, false, false,
  ), undefined);
  const prepared = moon.clientProgramPrepareEffectFree(
    document, 'json', environment);
  assert.ok(prepared);
  const values = JSON.stringify(
    JSON.parse(contract).execution_contracts['REL.values']);
  const setup = moon.clientProgramOpenSourceFreeLocalHost(
    prepared, registry, values, 1n, 0n, 0n, 0n);
  assert.ok(setup);
  const execution = await runCapturedStrategy(setup);
  try {
    assert.equal(execution.status, 'host-tasks-completed');
    assert.deepEqual(execution.resultInventory.map(result => result.name),
      ['answer']);
    assert.equal(execution.completed[0].outputRows, 2);
  } finally {
    await execution.close();
    assert.equal(execution.cleanupPending(), false);
  }
});
