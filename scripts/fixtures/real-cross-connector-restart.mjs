// Different-process public recovery. Original profiles, proof keys, Host state,
// Run and Checkpoint are retained; no second submission or Source replay.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {sign} from 'node:crypto';
import {dirname, join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';
import {observeInstalledGcsMetadata, observeInstalledDuckDbReads}
  from './real-cross-connector-observation.mjs';
import {realCrossConnectorControl as control} from './real-cross-connector-control.mjs';

const input = JSON.parse(await readFile(process.argv[2], 'utf8'));
const require = createRequire(join(input.application, 'package.json'));
const {connect} = await import(require.resolve('@actql/node'));
const duckdb = require('@duckdb/node-api');
const gcs = observeInstalledGcsMetadata(input.manifest, {forbidden: true});
const reads = observeInstalledDuckDbReads(duckdb, {forbidden: true});
let client, credentialResolutions = 0, completed = false;
try {
  client = await connect({...input.options, installation: {...input.options.installation,
    resolveSourceSecret() { credentialResolutions++; throw new Error('UnexpectedSourceCredentialOnRestore'); }}});
  const run = await client.attach(input.ref);
  assert.deepEqual(run.ref, input.ref);
  assert.equal((await run.status()).status, 'waiting_checkpoint');
  const checkpoints = (await client.checkpoints()).items;
  assert.equal(checkpoints.length, 1);
  assert.equal(checkpoints[0].checkpointCid, input.approval.checkpointCid);
  const preview = await client.reviewCheckpoint(checkpoints[0], {maxBytes: 1000000});
  const value = JSON.parse(Buffer.from(preview.bytes).toString('utf8'));
  assert.equal(value.effects.length, 1);
  assert.equal(value.effects[0].approval, 'required');
  const ref = checkpoints[0];
  const answer = await client.resolveCheckpoints([{checkpoint: ref, decision: 'approved'}], {signer: {
    keyId: input.approval.keyId, reviewerId: input.approval.reviewerId,
    authorityScopeCid: input.ref.authorityScopeCid,
    sign: bytes => sign(null, bytes, input.approval.privateKey),
  }});
  assert.deepEqual(answer.results.map(result => result.status), ['committed']);
  const signal = AbortSignal.timeout(30000);
  let state;
  for (;;) {
    signal.throwIfAborted(); state = await run.wait({signal});
    if (!['running', 'resuming'].includes(state.status)) break;
    await delay(20, undefined, {signal});
  }
  assert.equal(state.status, 'succeeded');
  assert.deepEqual(Object.keys(state.result_availability), ['joined']);
  const result = run.result('joined');
  const observed = {name: 'joined', rows: await result.all(), columns: (await result.describe()).columns};
  assert.deepEqual(observed, control.expected);
  assert.equal(credentialResolutions, 0);
  assert.deepEqual(gcs.observation(), {requests: 0, responses: 0, responseBytes: 0});
  assert.deepEqual(reads.observation(), {sourceReadSessions: 0, sourceReadStatements: 0});
  await client.close(); client = undefined;
  completed = true;
  await writeFile(join(dirname(process.argv[2]), 'restart-observation.json'), JSON.stringify({
    pid: process.pid, ref: run.ref, status: state.status, observedResult: observed,
    gcs: gcs.observation(), duckdb: reads.observation(), credentialResolutions,
    submissionCount: 0, approval: 'committed',
  }, null, 2)+'\n', {flag: 'wx', mode: 0o600});
} finally {
  try { if (client) await client.close(); }
  finally { try { reads.close(); } finally { gcs.close(); } }
}
assert(completed);
process.stdout.write(JSON.stringify({completed: true, pid: process.pid, sourceRequests: 0})+'\n');
