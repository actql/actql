// Observe an actual installed Local Host in a separate process. The parent
// owns the provider and existing installation; process exit closes this Host.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import * as sdk from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal} from '../../adapters/host-node/embedded-local.mjs';

const [path] = process.argv.slice(2);
const installation = JSON.parse(readFileSync(path, 'utf8'));
const ref = JSON.parse(readFileSync(`${path}.ref.json`, 'utf8'));
const progress = (stage, facts = {}) => console.error('ACTQL_EFFECT_OBSERVATION_PROGRESS ' +
  JSON.stringify({stage, ...facts}));
progress('connecting');
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: installation.directory,
    sourceProfilePath: installation.sourceProfilePath,
    resolveSourceSecret: async () => 'test-only-secret',
    effectProfilePath: installation.effectProfilePath,
    resolveEffectSecret: async () => 'test-only-secret',
    authorization: installation.authorization}});
progress('connected');
try {
  const execution = await client.attach(ref);
  progress('attached');
  let state;
  for (let attempt = 0; attempt < 400; attempt++) {
    state = await execution.status();
    if (attempt === 0 || attempt % 40 === 0) progress('observing', {
      attempt, status: state.status, physicalStop: state.control?.physical_stop});
    if (state.status === 'needs_reconciliation' && state.control?.physical_stop === 'confirmed') break;
    assert.ok(!['succeeded', 'failed', 'cancelled'].includes(state.status));
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.equal(state.status, 'needs_reconciliation');
  progress('observed');
  let reconcileError;
  try { await execution.reconcile(); }
  catch (error) { reconcileError = error.code; }
  progress('reconcile_observed');
  console.log(JSON.stringify({ref, state, reconcileError,
    explanation: sdk.explainEffectUncertainty?.(state),
    japaneseExplanation: sdk.explainEffectUncertainty?.(state, {locale: 'ja'}),
    copiedExplanation: sdk.explainEffectUncertainty?.({...state}),
    formats: ['text', 'html', 'json'].map(format => sdk.formatEffectUncertainty(state, {format}))}));
  progress('presented');
} finally {
  progress('closing');
  await client.close();
  progress('closed');
}
process.exit(0);
