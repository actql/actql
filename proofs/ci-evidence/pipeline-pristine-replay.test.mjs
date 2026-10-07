// Replay captured real local execution without inventing an Actions original.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {hash, gitTree} from './inputs.mjs';
import {pipelinePristineSourcePaths} from './isolation.mjs';
import {snapshotFromGit} from './isolated-runtime.mjs';
import {validatePristineReport} from '../relation-pipeline/pristine-replay.mjs';
import {payload} from '../relation-pipeline/fixture.mjs';
import {validatePipelinePristineOriginal} from './isolated-execution.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bytes = gunzipSync(readFileSync(new URL('../../docs/reviews/evidence/2026-10-07-pipeline-pristine-normal-346f9274c.json.gz', import.meta.url)), {maxOutputLength: 4 * 1024 * 1024});
assert.equal(hash(bytes), '8623af4522c4e1d1394eb5511194404c2b668b9bce5d9919c36a2ad9b151e012');
const original = JSON.parse(bytes);
const tree = gitTree(root, '346f9274cccb5d617d48c99ad1efc4576cad29e2');
tree.prefetch(pipelinePristineSourcePaths(tree));
const source = snapshotFromGit(tree, 'pipeline-pristine');

test('four captured real pristine JS executions retain original source, compiled fixtures, inputs, logs and independent values', () => {
  assert(validatePipelinePristineOriginal(original.report, source, original.files));
  assert.equal(original.report.units, 4); assert.equal(original.report.reuseAuthorized, false);
});

test('re-sealed requested Program cannot replace the Program actually observed by the compiled fixture', () => {
  const {report, files} = structuredClone(original), execution = report.receipts[0], run = execution.receipt;
  run.cases[0].program.source = '[]';
  files[run.inputPath] = payload(run.cases, true); run.inputDigest = hash(files[run.inputPath]);
  execution.digest = hash(JSON.stringify(run)); files[execution.path] = `${JSON.stringify(run, null, 2)}\n`;
  // Demonstrate why semantic/log agreement alone is insufficient for input binding.
  assert(validatePristineReport(report, source, files));
  assert.throws(() => validatePipelinePristineOriginal(report, source, files), /Requested pipeline Program/u);
});

for (const [name, alter] of [
  ['missing receipt', r => r.report.receipts.pop()],
  ['wrong target', r => r.report.action.target = 'native'],
  ['changed raw log', r => r.files[r.report.receipts[0].receipt.logPath] += 'changed'],
  ['changed source', r => r.report.source.digest = '0'.repeat(64)],
  ['false reuse permit', r => r.report.reuseAuthorized = true],
]) test(`the real original rejects ${name}`, () => {
  const changed = structuredClone(original); alter(changed);
  assert.throws(() => validatePipelinePristineOriginal(changed.report, source, changed.files));
});
