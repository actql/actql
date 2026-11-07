// Replay immutable, actually captured local campaigns. No Actions provenance or
// complete three-target admission can be derived from this local finite scope.
import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import {fileURLToPath} from 'node:url';
import {join} from 'node:path';
import {hash, gitTree} from './inputs.mjs';
import {checkLocalImageDefinition, localIsolatedRunArguments, isolatedCoreBuildMetadata} from './isolation.mjs';
import {checkIsolatedInputs} from './isolated-runtime.mjs';
import {checkIsolatedExecutionResult} from './isolated-execution.mjs';
import {fixedJsScientificObservation, fixedJsExecutions} from '../relation-pipeline/fixed-js-replay.mjs';
import {inspectMutationPart} from '../relation-pipeline/mutation-parts.mjs';
import {eraseFixedJsDetection} from './local-isolated-acceptance.mjs';
import {encode} from '../bounded-session/action-inputs.mjs';
import {historicalPipelineFixture} from './historical-pipeline-fixture.mjs';
import {payload as inputPayload} from '../relation-pipeline/fixture.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const revision = 'b7a6926588b03251d95df2f2f049dc7901355163';
function readOriginal(name, digest, limit) {
  const bytes = gunzipSync(readFileSync(new URL(`../../docs/reviews/evidence/${name}`, import.meta.url)), {maxOutputLength:limit});
  assert.equal(hash(bytes), digest, 'Changed captured original bytes');
  return JSON.parse(bytes);
}
const original = readOriginal('2026-10-08-local-isolated-pipeline-fixed-js-b7a692658.json.gz', '4c1fa01de96ea6379f0177d1a619dce68ac368611edf6e929d7ca76a064b528b', 16*1024*1024);
const normal = readOriginal('2026-10-08-pipeline-fixed-js-normal-b7a692658.json.gz', '002b8069785baeb3b2c2ccce69adbc555205485cc18cbe4bd9dd8c542488c232', 8*1024*1024);
const tree = gitTree(root, revision);
const consumer = await historicalPipelineFixture(root, revision);
tree.prefetch(consumer.pipelineFixedJsSourcePaths(tree));
const source = consumer.snapshotFromGit(tree, 'pipeline-fixed-js');
const context = {source, revision, readSource: path => tree.read(path)};
function consume(record) {
  assert.equal(record.authority, 'local-physical-acceptance'); assert.equal(record.reuseAuthorized,false);
  assert.equal(record.revision,revision); assert.equal(record.profile,'pipeline-fixed-js');
  const {prepared, answer} = record;
  assert.equal(record.manifestDigest,hash(JSON.stringify(prepared.manifest)));
  assert.equal(answer.owner,prepared.owner);
  consumer.checkIsolatedInputs({runtime:prepared.runtime,manifest:prepared.manifest,tree,local:true,profile:record.profile});
  checkLocalImageDefinition({image:answer.imageDefinition,imageId:answer.imageId,owner:answer.owner,profile:record.profile});
  assert.equal(encode(answer.arguments),encode(localIsolatedRunArguments({imageId:answer.imageId,owner:answer.owner,
    cidFile:join(prepared.context,'container.id'),profile:record.profile})));
  return consumer.checkPipelineFixedJsResult({payload:answer.payload,manifest:prepared.manifest,before:source,tree});
}
test('the actual immutable fixed campaign admits all twelve raw originals with four anchored detections and both healthy phases',()=>{
  assert(consume(original));
  assert.equal(fixedJsExecutions(original.answer.payload.report).length,12);
  assert.deepEqual(original.answer.payload.report.closure,{mutable:true,pristine:true,restoration:true,sourceRestored:true});
  const paths=new Set(original.answer.payload.root.entries.map(entry=>entry.path));
  for(const path of isolatedCoreBuildMetadata)assert(!paths.has(`runtime/moonbit/${path}`));
});
test('historical fixed acceptance stays separate from the current executor and rejects tampering',async()=>{
  const inputs={profile:'pipeline-fixed-js',payload:original.answer.payload,manifest:original.prepared.manifest,before:source,tree};
  assert(consumer.checkPipelineFixedJsResult(inputs));
  await assert.rejects(checkIsolatedExecutionResult(inputs), /strictly deep-equal|Wrong mutation part/u);
  const payload=structuredClone(inputs.payload);payload.sourcePreserved=false;
  assert.throws(()=>consumer.checkPipelineFixedJsResult({...inputs,payload}));
  await assert.rejects(checkIsolatedExecutionResult({...inputs,profile:'pipeline-pristine'}));
});
test('actual normal and image campaigns agree without discarding values, types, ordering, NULL, work or detected faults',()=>{
  assert(consumer.validateFixedJsReport({report:normal.report,files:normal.files,...context}));
  const scientific=fixedJsScientificObservation(original.answer.payload.report);
  assert.deepEqual(scientific,fixedJsScientificObservation(normal.report));
  assert.equal(hash(JSON.stringify(scientific)),original.comparison.scientificDigest);
  assert.equal(original.comparison.matched,true);
});
test('the final consumer rejects all thirteen altered actual originals and leaves its immutable original unchanged',()=>{
  const copy=structuredClone(original.answer.payload);
  assert.deepEqual(consumer.verifyFixedJsTamperRefusals(copy,context),original.comparison.rejected);
  assert.equal(original.comparison.rejected.length,13);
  assert.deepEqual(copy,original.answer.payload);
});
test('an actually captured mutant relabeled with re-sealed healthy observations is refused by the anchored defect check',()=>{
  const copy=structuredClone(original.answer.payload);eraseFixedJsDetection(copy);
  assert.equal(copy.report.results[0].killed,true);
  assert.throws(()=>consumer.validateFixedJsReport({report:copy.report,files:copy.files,...context}),/Declared detection differs/u);
});
test('a re-sealed requested Program is refused even when raw receipt/log/input digests remain consistent',()=>{
  const copy=structuredClone(original.answer.payload), execution=copy.report.results[0].executions[0],run=execution.receipt;
  run.cases[0].program.source='[]';
  copy.files[run.inputPath]=inputPayload(run.cases,run.correspondence);
  run.inputDigest=hash(copy.files[run.inputPath]);
  execution.digest=hash(JSON.stringify(run));copy.files[execution.path]=`${JSON.stringify(run,null,2)}\n`;
  assert.throws(()=>consumer.validateFixedJsReport({report:copy.report,files:copy.files,...context}),/Requested pipeline Program/u);
});
test('local fixed evidence cannot replace a full three-target part or Session/Actions admission',()=>{
  assert.throws(()=>inspectMutationPart(original.answer.payload.report));
  const {prepared}=original;
  assert.throws(()=>checkIsolatedInputs({runtime:prepared.runtime,manifest:prepared.manifest,tree,local:true}));
  assert.throws(()=>checkIsolatedInputs({runtime:prepared.runtime,manifest:prepared.manifest,tree,profile:'pipeline-fixed-js'}));
  const copy=structuredClone(original);copy.reuseAuthorized=true;assert.throws(()=>consume(copy));
});
for(const path of isolatedCoreBuildMetadata)test(`actual fixed runtime rejects reintroduced installed-core build metadata ${path}`,()=>{
  const copy=structuredClone(original);
  copy.prepared.manifest.root.entries.push({path:`runtime/moonbit/${path}`,kind:'file',mode:0o644,bytes:1,digest:'a'.repeat(64)});
  copy.prepared.runtime=consumer.imageRuntime(copy.prepared.manifest,{local:true,profile:'pipeline-fixed-js'});
  assert.throws(()=>consumer.checkIsolatedInputs({runtime:copy.prepared.runtime,manifest:copy.prepared.manifest,
    tree,local:true,profile:'pipeline-fixed-js'}),/core build metadata must be absent/u);
});
