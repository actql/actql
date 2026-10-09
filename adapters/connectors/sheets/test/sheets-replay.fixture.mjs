import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';

// Runs in a fresh process through the same public Local entry as initial use.
// It has no saved internal Owner handles and reconstructs only from Host files.
export async function replaySavedAppend(connectLocal, configPath) {
  const {ref, expectedStatus, installation} = JSON.parse(await readFile(configPath, 'utf8'));
  const client = await connectLocal({mode: 'local', owner: 'local', durability: 'durable',
    installation: {...installation, resolveEffectSecret: async () => 'fixture-only-secret'}});
  try {
    const execution = await client.attach(ref);
    assert.equal((await execution.status()).status, expectedStatus);
    if (expectedStatus === 'succeeded') {
      assert.deepEqual(await execution.result('answer').all(),
        [{text: '=literal e\u0301\r\n', number: 0, flag: false}]);
    } else {
      assert.equal((await execution.status()).result_available, false);
      await execution.reconcile();
      assert.equal((await execution.status()).status, 'needs_reconciliation');
    }
    console.log('SHEETS_REPLAY_VERIFIED');
  } finally { await client.close(); }
}
