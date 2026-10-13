// Adapter membership/pass-through counters with explicit Common issuer doubles.
// These do not validate origins or prove Resource admission, funding or restore.
import test from 'node:test';
import assert from 'node:assert/strict';
import {runtimeCore} from './runtime-core.mjs';

const ok = value => ({$tag: 1, _0: value});
const limits = {maxWireBytes: 4096, maxNodes: 256, maxDepth: 16};
function fixture() {
  const definitionOriginal = Object.freeze({name: 'run_definition', wire: '{}', identity: 'definition'});
  const planOriginal = Object.freeze({name: 'compiled_plan', wire: '{}', identity: 'plan'});
  const evidenceOriginal = Object.freeze({name: 'evidence', wire: '{}', identity: 'evidence'});
  const compiledOriginal = Object.freeze({kind: 'explicit compiled issuer double'});
  const documentOriginal = Object.freeze({kind: 'explicit bounded reader double'});
  const graph = Object.freeze({kind: 'original checked graph double'});
  const calls = [];
  const moon = {
    strategyRemoteManagedOutputEvidenceKind: () => 'explicit fixture metadata',
    strategyPublicationAdmit: () => ok(definitionOriginal),
    strategyPublicationContractName: value => value.name,
    strategyPublicationContractIdentityField: () => 'cid',
    strategyPublicationContractIdentity: value => value.identity,
    strategyPublicationContractJson: value => value.wire,
    strategyRunEvidenceName: value => value.name,
    strategyRunEvidenceIdentity: value => value.identity,
    strategyRunEvidenceJson: value => value.wire,
    clientProgramCompileLocalInfer: () => ok({kind: 'compilation double'}),
    clientProgramIssueTaskCompiledRun: () => ok(compiledOriginal),
    clientProgramBindCompiledInferResultPolicy: value => ok(value),
    clientProgramCompiledRunTemplate: () => evidenceOriginal,
    clientProgramCompiledRunPlan: () => planOriginal,
    clientProgramCompiledRunPrepared: () => evidenceOriginal,
    clientProgramCompiledRunAuthorization: () => evidenceOriginal,
    clientProgramCompiledRunAdmission: () => ({}),
    clientProgramReadModelOriginalResourceDocument: () => ok(documentOriginal),
    clientProgramCheckInferOriginalPreRestoreOrigin(...args) {calls.push(args); return ok(undefined);},
  };
  const control = runtimeCore(moon).publicationControl;
  const definition = control.admit('run_definition', '{}', limits);
  const compiled = control.prepareCheckedClientCompiledRun({}, 'infer', {
    executionContextCid: 'context double', hostPolicyCid: 'policy double', expiresAt: 'time double',
    resultDataPolicy: {kind: 'data_policy', cid: 'policy double', wire: '{}'}}, graph);
  const document = control.readModelOriginalResourceDocument('{}', limits);
  const selected = Object.freeze({layout: Object.freeze({kind: 'original layout double'}),
    installation: Object.freeze({kind: 'original installation double'}),
    runtimeArtifactCid: 'runtime double', layoutArtifactCid: 'layout double', probability: undefined});
  return {moon, control, definition, compiled, document, graph, selected, calls,
    definitionOriginal, compiledOriginal, documentOriginal};
}

test('pre-restore control delegates the same originals without a Scope or Store grant', () => {
  const f = fixture();
  assert.equal(f.control.checkCheckedClientInferOriginalPreRestoreOrigin(
    f.compiled, f.definition, f.graph, f.document, f.selected), undefined);
  assert.equal(f.calls.length, 1);
  assert.deepEqual(f.calls[0], [f.compiledOriginal, f.definitionOriginal, f.graph,
    f.documentOriginal, f.selected.layout, f.selected.installation,
    f.selected.runtimeArtifactCid, f.selected.layoutArtifactCid, undefined]);
  assert.strictEqual(f.calls[0][0], f.compiledOriginal);
  assert.strictEqual(f.calls[0][1], f.definitionOriginal);
  assert.strictEqual(f.calls[0][3], f.documentOriginal);
});

test('copied compiled/document/definition refs fail before selected getters or Common calls', () => {
  const f = fixture();
  let reads = 0;
  const selected = {get layout() {reads++; throw Error('UnexpectedSelectionRead');}};
  for (const [compiled, definition, document] of [
    [{...f.compiled}, f.definition, f.document],
    [f.compiled, {...f.definition}, f.document],
    [f.compiled, f.definition, {...f.document}],
    [undefined, f.definition, f.document],
    [f.compiled, f.definition, undefined],
  ]) {
    assert.throws(() => f.control.checkCheckedClientInferOriginalPreRestoreOrigin(
      compiled, definition, f.graph, document, selected), TypeError);
  }
  assert.equal(reads, 0); assert.equal(f.calls.length, 0);
});

test('other installed control cannot adopt original nominal views by copying data', () => {
  const f = fixture(), other = fixture();
  for (const [compiled, definition, document] of [
    [other.compiled, f.definition, f.document],
    [f.compiled, other.definition, f.document],
    [f.compiled, f.definition, other.document],
  ]) {
    assert.throws(() => f.control.checkCheckedClientInferOriginalPreRestoreOrigin(
      compiled, definition, f.graph, document, f.selected), TypeError);
  }
  assert.equal(f.calls.length, 0); assert.equal(other.calls.length, 0);
});

test('missing physical consumer is typed unavailable without reading installation data', () => {
  const f = fixture();
  delete f.moon.clientProgramCheckInferOriginalPreRestoreOrigin;
  let reads = 0;
  const selected = {get layout() {reads++; throw Error('UnexpectedSelectionRead');}};
  assert.throws(() => f.control.checkCheckedClientInferOriginalPreRestoreOrigin(
    f.compiled, f.definition, f.graph, f.document, selected), {code: 'ClientOperationUnavailable'});
  assert.equal(reads, 0); assert.equal(f.calls.length, 0);
});

test('selected original fields are read once and passed by reference, without normalization', () => {
  const f = fixture(), counts = {};
  const selected = Object.fromEntries(Object.keys(f.selected).map(key => [key, undefined]));
  for (const [key, value] of Object.entries(f.selected)) {
    Object.defineProperty(selected, key, {get() {counts[key] = (counts[key] ?? 0) + 1; return value;}});
  }
  f.control.checkCheckedClientInferOriginalPreRestoreOrigin(f.compiled,
    f.definition, f.graph, f.document, selected);
  assert.deepEqual(counts, {layout: 1, installation: 1, runtimeArtifactCid: 1,
    layoutArtifactCid: 1, probability: 1});
  assert.strictEqual(f.calls[0][4], f.selected.layout);
  assert.strictEqual(f.calls[0][5], f.selected.installation);
  assert.equal(f.calls[0][8], undefined);
});

test('Common refusal is propagated unchanged, not converted to an allowed restore', () => {
  const f = fixture(), issue = Object.freeze({kind: 'explicit origin mismatch double'});
  f.moon.clientProgramCheckInferOriginalPreRestoreOrigin = () => ({$tag: 0, _0: issue});
  assert.throws(() => f.control.checkCheckedClientInferOriginalPreRestoreOrigin(
    f.compiled, f.definition, f.graph, f.document, f.selected),
  error => error.code === 'MoonBitHostFailure' && error.cause === issue);
  assert.equal('restore' in f.document || 'send' in f.document || 'scope' in f.document, false);
});
