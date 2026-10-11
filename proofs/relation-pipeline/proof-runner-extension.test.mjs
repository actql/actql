import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import test from 'node:test';
import {checkBaseline} from './inventory.mjs';
import {checkProofRunnerExtension, custodyChecker} from './proof-runner-extension.mjs';
const root = fileURLToPath(new URL('../../', import.meta.url));
const baseline = JSON.parse(readFileSync(root + 'proofs/relation-pipeline/baseline.json'));
const read = path => readFileSync(root + path);
test('runner custody extension retains all original proof/claim inputs and current Git bindings', () => {
  assert(baseline.runnerExtension);
  checkBaseline(root);
});
for (const [name, alter] of [
  ['missing proof input', e => { delete e.preserved['proofs/relation-chain/StopClaims.lean']; }],
  ['resealed model input', e => { e.preserved['proofs/relation-chain/Chain.lean'] = 'a'.repeat(64); }],
  ['different source parent', e => { e.parent = 'a'.repeat(40); }],
  ['missing runner', e => { delete e.files['proofs/bounded-session/proof-command.mjs']; }],
  ['unrelated helper digest', e => { e.files['proofs/bounded-session/proof-command.mjs'] = 'a'.repeat(64); }],
]) test(`runner custody extension rejects ${name}`, () => {
  const changed = structuredClone(baseline.runnerExtension); alter(changed);
  assert.throws(() => checkProofRunnerExtension(root, changed, read));
});
test('checker mechanical extension cannot hide a weakened claim or changed audit', () => {
  const current = read('proofs/relation-chain/check.mjs').toString();
  for (const from of ['maxBuffer: 4 * 1024 * 1024', "['propext', 'Quot.sound']", '14]', '22]', '18]']) {
    assert(current.includes(from));
  }
  assert.throws(() => custodyChecker(current), /Missing unique original checker boundary/);
  assert.throws(() => checkProofRunnerExtension(root, baseline.runnerExtension,
    path => path === 'proofs/relation-chain/check.mjs'
      ? Buffer.from(current.replace('if (result.status !== 0', 'if (false && result.status !== 0')) : read(path)),
    /Changed reviewed runner extension/);
});
