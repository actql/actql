import assert from 'node:assert/strict';
import test from 'node:test';
import {registerHooks} from 'node:module';
import {mkdtemp, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {verifyLocalSourceRuntime, assertSourceRuntimeReceiptCurrent}
  from '../../scripts/verify-local-source-runtime.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const prefix = pathToFileURL(root).href;
const coherence = await verifyLocalSourceRuntime(root);
// Test-only module loading fault at the actual selected Result admission.
// No product hook, changed resource grant, fabricated Run or cleanup ACK.
// Both handlers run concurrently; the third/new generation is unchanged.
let injected = false;
const hooks = registerHooks({load(url, context, next) {
  const result = next(url, context);
  if (url !== prefix + 'packages/local-node/adapters/host-node/ordinary-host-result.mjs') return result;
  const source = String(result.source);
  const seam = '  function admitSelectedRun(prepared, value, kind) {';
  assert.equal(source.split(seam).length, 2);
  injected = true;
  return {...result, source: 'let forcedInitialRefusals=2;\n' + source.replace(seam,
    seam + "\n    if(forcedInitialRefusals>0){forcedInitialRefusals--;throw new TypeError('TestOriginalResultAdmissionRefusal');}")};
}});
const {open} = await import(prefix + 'packages/node/index.mjs');
const {getSubmissionInput} = await import(prefix + 'packages/sdk/index.mjs');
const program = n => ({version:'actql/0.1',id:'initial-refusal',stages:[{id:'main',inputs:{},
  steps:[{as:'v',values:{schema:{x:{type:'number',nullable:false}},rows:[{x:n}]}}],
  results:{rows:{from:'v',fields:['x']}}}],results:{answer:{from:{stage:'main',result:'rows'}}}});

test('Ready initial preparations retire before Run adoption after Result refusal', {timeout:30000}, async () => {
  const stateDir = await mkdtemp(join(tmpdir(), 'actql-initial-retirement-'));
  let db, success = false;
  try {
    db = await open({stateDir});
    const outcomes = await Promise.allSettled([db.start(program(1)), db.start(program(2))]);
    assert.equal(injected, true);
    assert.deepEqual(outcomes.map(value => value.status), ['rejected', 'rejected']);
    const snapshots = outcomes.map(value => getSubmissionInput(value.reason));
    assert.deepEqual(snapshots.map(value => value.input.stages[0].steps[0].values.rows[0].x), [1,2]);
    assert.ok(snapshots.every(Object.isFrozen));
    await db.close(); db = undefined;
    db = await open({stateDir});
    const run = await db.start(program(9));
    assert.equal((await run.wait({signal:AbortSignal.timeout(10000)})).status, 'succeeded');
    assert.deepEqual(await run.result('answer').all(), [{x:9}]);
    await db.close(); db = undefined;
    outcomes.forEach((value, index) => assert.equal(getSubmissionInput(value.reason), snapshots[index]));
    success = true;
  } finally {
    hooks.deregister();
    if (db) await db.close().catch(error => console.error('original cleanup remains pending', error));
    assertSourceRuntimeReceiptCurrent(coherence);
    if (success) await rm(stateDir, {recursive:true, force:true});
    else console.error('preserved initial retirement failure state', stateDir);
  }
});
