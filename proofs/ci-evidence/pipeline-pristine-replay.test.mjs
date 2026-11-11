// Replay captured real local execution without inventing an Actions original.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {hash, gitTree} from './inputs.mjs';
import {checkLocalImageDefinition, localIsolatedRunArguments, isolatedCoreBuildMetadata} from './isolation.mjs';
import {checkIsolatedInputs} from './isolated-runtime.mjs';
import {pristineScientificObservation} from '../relation-pipeline/pristine-replay.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {join} from 'node:path';
import {payload} from '../relation-pipeline/fixture.mjs';
import {checkIsolatedExecutionResult} from './isolated-execution.mjs';
import {historicalPipelineFixture} from './historical-pipeline-fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const bytes = gunzipSync(readFileSync(new URL('../../docs/reviews/evidence/2026-10-07-pipeline-pristine-normal-346f9274c.json.gz', import.meta.url)), {maxOutputLength: 4 * 1024 * 1024});
assert.equal(hash(bytes), '8623af4522c4e1d1394eb5511194404c2b668b9bce5d9919c36a2ad9b151e012');
const original = JSON.parse(bytes);
const tree = gitTree(root, '346f9274cccb5d617d48c99ad1efc4576cad29e2');
const consumer = await historicalPipelineFixture(root, tree.revision);
tree.prefetch(consumer.pipelinePristineSourcePaths(tree));
const source = consumer.snapshotFromGit(tree, 'pipeline-pristine');

test('four captured real pristine JS executions retain original source, compiled fixtures, inputs, logs and independent values', () => {
  assert(consumer.validatePipelinePristineOriginal(original.report, source, original.files));
  assert.equal(original.report.units, 4); assert.equal(original.report.reuseAuthorized, false);
});

test('re-sealed requested Program cannot replace the Program actually observed by the compiled fixture', () => {
  const {report, files} = structuredClone(original), execution = report.receipts[0], run = execution.receipt;
  run.cases[0].program.source = '[]';
  files[run.inputPath] = payload(run.cases, true); run.inputDigest = hash(files[run.inputPath]);
  execution.digest = hash(JSON.stringify(run)); files[execution.path] = `${JSON.stringify(run, null, 2)}\n`;
  // Demonstrate why semantic/log agreement alone is insufficient for input binding.
  assert(consumer.validatePristineReport(report, source, files));
  assert.throws(() => consumer.validatePipelinePristineOriginal(report, source, files), /Requested pipeline Program/u);
});

for (const [name, alter] of [
  ['missing receipt', r => r.report.receipts.pop()],
  ['wrong target', r => r.report.action.target = 'native'],
  ['changed raw log', r => r.files[r.report.receipts[0].receipt.logPath] += 'changed'],
  ['changed source', r => r.report.source.digest = '0'.repeat(64)],
  ['false reuse permit', r => r.report.reuseAuthorized = true],
]) test(`the real original rejects ${name}`, () => {
  const changed = structuredClone(original); alter(changed);
  assert.throws(() => consumer.validatePipelinePristineOriginal(changed.report, source, changed.files));
});


test('captured real output tampering changes a value even when the first independent minimum is empty', () => {
  assert.deepEqual(original.report.observations[0].observed.wireRows, []);
  const pristine = structuredClone(original);
  assert.deepEqual(consumer.verifyPristineTamperRefusals(pristine), ['missing-receipt', 'wrong-target', 'changed-source',
    'changed-log', 'changed-input', 'changed-value', 'reuse-promotion']);
  assert.deepEqual(pristine, original, 'Refusal experiments must not rewrite their original');
});


const imageBytes = gunzipSync(readFileSync(new URL('../../docs/reviews/evidence/2026-10-08-local-isolated-pipeline-pristine-f2a191b51.json.gz', import.meta.url)), {maxOutputLength: 8 * 1024 * 1024});
assert.equal(hash(imageBytes), 'bd87e6234f3620945f04a1d7a2af5d595b92b319e8b547643d163aa61ccc468a');
const imageOriginal = JSON.parse(imageBytes), imageRevision = 'f2a191b51fd6ecd7b70486c6e8fa33204fa8964e';
const imageTree = gitTree(root, imageRevision);
const imageConsumer = await historicalPipelineFixture(root, imageRevision);
imageTree.prefetch(imageConsumer.pipelinePristineSourcePaths(imageTree));
const imageSource = imageConsumer.snapshotFromGit(imageTree, 'pipeline-pristine');
const normalImageBytes = gunzipSync(readFileSync(new URL('../../docs/reviews/evidence/2026-10-08-pipeline-pristine-normal-f2a191b51.json.gz', import.meta.url)), {maxOutputLength: 4 * 1024 * 1024});
assert.equal(hash(normalImageBytes), '0a81ea5af7e6c061696c486a3615262a512d67d8edd3c3d9d9c1e304bbbef68f');
const pairedNormal = JSON.parse(normalImageBytes);

function consumeImage(record) {
  assert.equal(record.authority, 'local-physical-acceptance'); assert.equal(record.reuseAuthorized, false);
  assert.equal(record.revision, imageRevision); assert.equal(record.profile, 'pipeline-pristine');
  const {prepared, answer} = record;
  assert.equal(record.manifestDigest, hash(JSON.stringify(prepared.manifest)));
  assert.equal(answer.owner, prepared.owner);
  imageConsumer.checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree: imageTree, local: true, profile: record.profile});
  checkLocalImageDefinition({image: answer.imageDefinition, imageId: answer.imageId, owner: answer.owner, profile: record.profile});
  assert.equal(encode(answer.arguments), encode(localIsolatedRunArguments({imageId: answer.imageId,
    owner: answer.owner, cidFile: join(prepared.context, 'container.id'), profile: record.profile})));
  return imageConsumer.checkPipelinePristineResult({payload: answer.payload, manifest: prepared.manifest, before: imageSource});
}

test('the actual immutable pipeline image original passes source, runtime, entrypoint and strong original receipt checks', () => {
  assert(consumeImage(imageOriginal));
  assert.equal(imageOriginal.answer.payload.report.units, 4);
  assert.equal(imageOriginal.answer.payload.sourcePreserved, true);
  const paths = new Set(imageOriginal.answer.payload.root.entries.map(entry => entry.path));
  for (const path of isolatedCoreBuildMetadata) assert(!paths.has(`runtime/moonbit/${path}`));
});
test('historical pristine acceptance stays separate from the current executor and rejects tampering', async () => {
  const inputs = {profile: 'pipeline-pristine', payload: imageOriginal.answer.payload,
    manifest: imageOriginal.prepared.manifest, before: imageSource};
  assert(imageConsumer.checkPipelinePristineResult(inputs));
  await assert.rejects(checkIsolatedExecutionResult(inputs), /Compiled|fixture|strictly equal/u);
  const payload = structuredClone(inputs.payload); payload.sourcePreserved = false;
  assert.throws(() => imageConsumer.checkPipelinePristineResult({...inputs, payload}));
  await assert.rejects(checkIsolatedExecutionResult({...inputs, profile: 'session'}));
});

test('the two real fresh phases agree without discarding schema, work, identity, NULL, rows or order', () => {
  assert(imageConsumer.validatePipelinePristineOriginal(pairedNormal.report, imageSource, pairedNormal.files));
  const science = pristineScientificObservation(imageOriginal.answer.payload.report);
  assert.deepEqual(science, pristineScientificObservation(pairedNormal.report));
  assert.equal(hash(JSON.stringify(science)), imageOriginal.comparison.scientificDigest);
  assert.equal(imageOriginal.comparison.matched, true);
  assert.deepEqual(imageConsumer.verifyPristineTamperRefusals(imageOriginal.answer.payload), imageOriginal.comparison.rejected);
});

test('a local pipeline image never enters Session or Actions admission and cannot promote reuse', () => {
  const {prepared} = imageOriginal;
  assert.throws(() => checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree: imageTree, local: true}));
  assert.throws(() => checkIsolatedInputs({runtime: prepared.runtime, manifest: prepared.manifest, tree: imageTree, profile: 'pipeline-pristine'}));
  const altered = structuredClone(imageOriginal); altered.reuseAuthorized = true; assert.throws(() => consumeImage(altered));
});

for (const path of isolatedCoreBuildMetadata) test(`the real pipeline cohort rejects reintroduced core build metadata ${path}`, () => {
  const altered = structuredClone(imageOriginal);
  altered.prepared.manifest.root.entries.push({path: `runtime/moonbit/${path}`, kind: 'file', mode: 0o644, bytes: 1, digest: 'a'.repeat(64)});
  // Keep the altered runtime identity internally consistent so this negative
  // copy reaches the explicit exclusion, beyond the root-digest check.
  altered.prepared.runtime = imageConsumer.imageRuntime(altered.prepared.manifest, {local: true, profile: 'pipeline-pristine'});
  assert.throws(() => imageConsumer.checkIsolatedInputs({runtime: altered.prepared.runtime, manifest: altered.prepared.manifest,
    tree: imageTree, local: true, profile: 'pipeline-pristine'}), /core build metadata must be absent/u);
});

test('historical replay refuses caller-selected revisions', async () => {
  await assert.rejects(historicalPipelineFixture(root, '0'.repeat(40)), /Unregistered historical pipeline revision/u);
});
