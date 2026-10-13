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
