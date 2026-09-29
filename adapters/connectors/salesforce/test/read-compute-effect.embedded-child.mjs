// One step of the Embedded Read→Compute→Effect acceptance, in its own
// process: each process opens the Embedded Local Host afresh, so consecutive
// steps are Host restarts. Arguments: step, then the installation JSON path.
import assert from 'node:assert/strict';
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {connectEmbeddedLocal} from '../../../host-node/embedded-local.mjs';

const [step, installationPath] = process.argv.slice(2);
const installation = JSON.parse(readFileSync(installationPath, 'utf8'));
const secret = async () => 'test-only-secret';
const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
  durability: 'durable', installation: {
    directory: installation.directory,
    sourceProfilePath: installation.sourceProfilePath,
    resolveSourceSecret: secret,
    effectProfilePath: installation.effectProfilePath,
    resolveEffectSecret: secret,
    authorization: installation.authorization}});
async function waitFor(check) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await check();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  throw new Error('EmbeddedStepTimeout');
}
const refPath = `${installationPath}.ref.json`;
try {
  if (step === 'submit') {
    let execution;
    try {
      execution = await client.aql(installation.program, {format: 'json',
        requestId: installation.requestId});
    } catch (error) {
      if (error?.code === 'ClientProgramUnsupported') {
        console.log(JSON.stringify({notConnected: true}));
        process.exit(0);
      }
      throw error;
    }
    await waitFor(async () => (await execution.status()).status ===
      'waiting_checkpoint');
    writeFileSync(refPath, JSON.stringify(execution.ref));
    console.log(JSON.stringify({held: true}));
  } else if (step === 'answer') {
    const ref = JSON.parse(readFileSync(refPath, 'utf8'));
    const [checkpoint] = (await client.checkpoints()).items;
    assert.equal(checkpoint.kind, 'effect_set');
    const key = createPrivateKey(installation.reviewerPrivateKey);
    const answer = await client.resolveCheckpoints([
      {checkpoint, decision: 'approved'}], {signer: {keyId: 'reviewer-key',
      reviewerId: 'reviewer', authorityScopeCid: ref.authorityScopeCid,
      sign: bytes => sign(null, bytes, key)}});
    console.log(JSON.stringify({answered: answer.results.map(item =>
      item.status)}));
  } else if (step === 'resume') {
    const ref = JSON.parse(readFileSync(refPath, 'utf8'));
    const execution = await client.attach(ref);
    const state = await waitFor(async () => {
      const current = await execution.status();
      return ['succeeded', 'failed', 'needs_reconciliation', 'cancelled']
        .includes(current.status) ? current : undefined;
    });
    const rows = state.status === 'succeeded'
      ? await execution.result('updates').all() : undefined;
    console.log(JSON.stringify({status: state.status, rows}));
  } else {
    throw new Error('InvalidEmbeddedStep');
  }
} finally {
  await client.close();
}
// The Embedded Host stays open for this process; the step ends it.
process.exit(0);
