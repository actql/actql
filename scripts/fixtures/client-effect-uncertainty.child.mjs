// Observe an actual installed Local Host in a separate process. The parent
// owns the provider and existing installation; process exit closes this Host.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as sdk from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from '../../adapters/host-node/embedded-local.mjs';

const [path] = process.argv.slice(2);
const installation = JSON.parse(readFileSync(path, 'utf8'));
const ref = JSON.parse(readFileSync(`${path}.ref.json`, 'utf8'));
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: installation.directory,
    sourceProfilePath: installation.sourceProfilePath,
    resolveSourceSecret: async () => 'test-only-secret',
    effectProfilePath: installation.effectProfilePath,
    resolveEffectSecret: async () => 'test-only-secret',
    authorization: installation.authorization}});
try {
  const execution = await client.attach(ref);
  let state;
  for (let attempt = 0; attempt < 400; attempt++) {
    state = await execution.status();
    if (state.status === 'needs_reconciliation' && state.control?.physical_stop === 'confirmed') break;
    assert.ok(!['succeeded', 'failed', 'cancelled'].includes(state.status));
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.equal(state.status, 'needs_reconciliation');
  let reconcileError;
  try { await execution.reconcile(); }
  catch (error) { reconcileError = error.code; }
  console.log(JSON.stringify({ref, state, reconcileError,
    explanation: sdk.explainEffectUncertainty?.(state),
    japaneseExplanation: sdk.explainEffectUncertainty?.(state, {locale: 'ja'}),
    copiedExplanation: sdk.explainEffectUncertainty?.({...state}),
    formats: ['text', 'html', 'json'].map(format => sdk.formatEffectUncertainty(state, {format}))}));
} finally {
  await client.close();
}
process.exit(0);
