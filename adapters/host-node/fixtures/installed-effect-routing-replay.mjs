// A fresh process has no old installation object, prepared request or Ledger
// handle. It attaches only the original Run through the public Local entry.
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {connectEmbeddedLocal} from '../embedded-local.mjs';

const {ref, expectedStatus, expectedRows, installation} = JSON.parse(
  await readFile(process.argv[2], 'utf8'));
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
  installation: {...installation, resolveEffectSecret: async () => 'synthetic-replay-secret'}});
try {
  const execution = await client.attach(ref);
  assert.equal((await execution.status()).status, expectedStatus);
  if (expectedStatus === 'succeeded') {
    assert.deepEqual(await execution.result('answer').all(), expectedRows);
  } else {
    assert.equal(expectedStatus, 'needs_reconciliation');
    assert.equal((await execution.status()).result_available, false);
    assert.deepEqual((await execution.status()).next_action, {kind: 'reconcile', effects: ['b_append']});
    await execution.reconcile();
    assert.equal((await execution.status()).status, 'needs_reconciliation');
  }
  console.log('INSTALLED_EFFECT_ROUTING_REPLAY_VERIFIED');
} finally { await client.close(); }
