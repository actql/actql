import assert from 'node:assert/strict';
import {registerHooks} from 'node:module';
import test from 'node:test';

// Synthetic ABI ports isolate facade forwarding and same-module originals.
// Their DATA is intentionally not a canonical receipt or an execution/Store
// acknowledgement. Real Common semantics and a matching runtime are separate.
const abi = `
export const control = {calls: [], fail: undefined, serial: 0};
const result = (name, args, value) => {
  control.calls.push({name, args});
  return control.fail === name ? {$tag: 0, _0: 'fixture-refusal'}
    : {$tag: 1, _0: value};
};
export const clientValuesHostAdmitPublicationContract = (kind, wire, ...limits) =>
  result('contract', [kind, wire, ...limits], {cid: 'fixture:' + (++control.serial), wire});
export const clientValuesHostPublicationContractIdentity = value => value.cid;
export const clientValuesHostPublicationContractWire = value => value.wire;
export const clientValuesHostAdmitEffectPreviewIdentity = (...args) =>
  result('preview', args, {fixturePreview: ++control.serial, memberCount: 2});
export const clientValuesHostEffectPreviewMemberCount = value => value.memberCount;
export const clientValuesHostEffectPreviewSemanticIdentity = value => 'fixture:preview-semantic:' + value.fixturePreview;
export const clientValuesHostAdmitEffectRunMaterials = (...args) =>
  result('materials', args, {prepared: {}, compilation: {}, allowed: {}, definition: {}});
export const clientValuesHostRestoredEffectPrepared = value => value.prepared;
export const clientValuesHostRestoredEffectCompilation = value => value.compilation;
export const clientValuesHostRestoredEffectAllowed = value => value.allowed;
export const clientValuesHostRestoredEffectDefinition = value => value.definition;
export const clientValuesHostRestoredEffectRequest = () => [];
export const clientValuesHostAdmitEffectCheckpointBinding = (...args) =>
  result('checkpoint-binding', args, {wire: args[2]});
export const clientValuesHostEffectCheckpointBindingFields = value =>
  result('checkpoint-fields', [value], ['sha256:' + 'a'.repeat(64), value.wire,
    'original Run', 'original unit', ...['b', 'c', 'd', 'e'].map(x => 'sha256:' + x.repeat(64))]);
export const clientValuesHostAdmitEffectCheckpointPreview = (...args) =>
  result('checkpoint-preview', args, {fixturePreview: ++control.serial, memberCount: 2});
export const clientValuesHostIssueEffectfulFinalRunReceipt = (...args) =>
  result('receipt', args, {cid: 'fixture:final', wire: 'fixture final receipt'});
export const clientValuesHostValidateEffectfulPublicationCommit = (...args) =>
  result('commit', args, undefined);
export const clientValuesHostAdmitEffectfulFinalRunEvidence = (...args) =>
  result('admit-full', args, {receipt: args[13], status: control.status || 'succeeded', allUnattempted: false});
export const clientValuesHostEffectfulFinalRunReceipt = value => value.receipt;
export const clientValuesHostEffectfulFinalRunStatus = value => {control.calls.push({name:'status'});return value.status;};
export const clientValuesHostEffectfulFinalRunAllUnattempted = value => value.allUnattempted;
export const clientValuesHostEffectfulFinalRunReconciliationState = (...args) =>
  args[0].status === 'needs_reconciliation' ? result('reconcile-retained', args, 'fixture reconciliation wire')
    : {$tag:0,_0:'not-an-unknown-partition'};
export const clientValuesHostValidateRetainedEffectfulPublicationCommit = (...args) =>
  result('commit-retained', args, args[4]);
export const clientValuesHostAdmitOriginalResultOccurrenceEvidence = (...args) =>
  result('original-occurrence', args, {derivation: args[2], ordering: args[3]});
export const clientValuesHostResultOccurrenceDerivation = value => value.derivation;
export const clientValuesHostResultOccurrenceOrdering = value => value.ordering;
export const clientValuesHostIssueEffectSucceededRunStateWire = (...args) => {
  control.calls.push({name:'effect-state',args});
  return args[3].status === 'succeeded' ? 'fixture succeeded state' : undefined;
};
`;
const abiUrl = 'data:text/javascript,' + encodeURIComponent(abi);
const source = new URL('./index.mjs', import.meta.url);
const hooks = registerHooks({resolve(specifier, context, next) {
  if (specifier === './dist/client_values_host_abi.js' &&
      context.parentURL !== undefined &&
      new URL(context.parentURL).pathname === source.pathname) {
    return {url: abiUrl, shortCircuit: true};
  }
  return next(specifier, context);
}});
const {control} = await import(abiUrl);
const owner = await import(source.href);
const foreign = await import(source.href + '?foreign-publication-namespace');
hooks.deregister();
const limits = Object.freeze({maxWireBytes: 65536, maxNodes: 4096, maxDepth: 32});
function originals() {
  control.fail = undefined;
  const contract = name => owner.admitPublicationContract(name, `fixture:${name}`, limits);
  const runDefinition = contract('run_definition'), invocation = contract('run_invocation');
  const definition = contract('result_definition'), artifact = contract('result_artifact');
  const derivation = contract('derivation_evidence'), ordering = contract('ordering_evidence');
  const retention = contract('result_retention_policy'), binding = contract('durable_result_binding');
  const manifest = contract('result_manifest'), computationReceipt = contract('run_receipt');
  const capturedRun = contract('captured_run'), request = contract('publication_request');
  const attempt = contract('publication_attempt'), index = contract('public_index_entry');
  control.calls.length = 0;
  const preview = owner.admitEffectPreviewIdentity('original preview wire',
    'independent original Run identity', 'independent original context', limits);
  const previewOriginal = control.calls[0];
  const setReceiptWire = 'original set receipt', memberReceiptWires = Object.freeze(['member one', 'member two']);
  const finalReceipt = owner.issueEffectfulFinalRunReceipt(runDefinition, computationReceipt,
    capturedRun, preview, setReceiptWire, memberReceiptWires, limits);
  const receiptOriginal = control.calls[1];
  const evidence = {runDefinition, invocation, definitions: [definition], artifacts: [artifact],
    derivations: [derivation], orderings: [ordering], retentions: [retention],
    durableBindings: [binding], manifest, computationReceipt, capturedRun,
    preview, setReceiptWire, memberReceiptWires, finalReceipt};
  return {evidence, request, attempt, index, previewOriginal, receiptOriginal};
}

test('original Checkpoint Preview forwards nominal roots and refuses copied or foreign tuples', () => {
  control.fail = undefined;
  const materials = api => api.admitEffectRunMaterials('saved material wire',
    'original Definition CID', {});
  const f = materials(owner), other = materials(foreign);
  const checkpointWire = 'original sealed Checkpoint wire';
  const binding = owner.effectReviewCheckpointBinding(f.allowed, f.definition, checkpointWire);
  const bindingCall = control.calls.findLast(call => call.name === 'checkpoint-binding');
  const original = control.calls.findLast(call => call.name === 'checkpoint-fields').args[0];
  const foreignBinding = foreign.effectReviewCheckpointBinding(other.allowed,
    other.definition, checkpointWire);
  control.calls.length = 0;
  const storedWire = 'exact stored Checkpoint bytes\n', previewWire = 'original Preview α';
  const preview = owner.effectReviewCheckpointPreview(binding, f.allowed,
    f.definition, storedWire, previewWire, limits);
  assert.deepEqual(control.calls.map(call => call.name), ['checkpoint-preview']);
  const args = control.calls[0].args;
  assert.strictEqual(args[0], original);
  assert.strictEqual(args[1], bindingCall.args[0]);
  assert.strictEqual(args[2], bindingCall.args[1]);
  assert.deepEqual(args.slice(3), [storedWire, previewWire, 65536, 4096, 32]);
  assert(Object.isFrozen(preview));
  const previewSerial = control.serial;
  assert.equal(owner.effectPreviewIdentityCid(preview), `fixture:preview-semantic:${previewSerial}`);

  const contract = kind => owner.admitPublicationContract(kind, 'fixture:' + kind, limits);
  const receiptArgs = [contract('run_definition'), contract('run_receipt'),
    contract('captured_run'), preview, 'set receipt'];
  control.calls.length = 0;
  assert.throws(() => owner.issueEffectfulFinalRunReceipt(...receiptArgs,
    ['one'], limits), /InvalidRunHostEffectReceipts/u);
  assert.equal(control.calls.length, 0, 'The returned Preview retains its two-member inventory');
  owner.issueEffectfulFinalRunReceipt(...receiptArgs, ['one', 'two'], limits);
  assert.strictEqual(control.calls[0].args[3].fixturePreview, previewSerial);

  control.calls.length = 0;
  for (const [selected, allowed, definition] of [
    [{...binding}, f.allowed, f.definition], [foreignBinding, f.allowed, f.definition],
    [binding, {...f.allowed}, f.definition], [binding, other.allowed, f.definition],
    [binding, f.allowed, {...f.definition}], [binding, f.allowed, other.definition],
  ]) {
    assert.throws(() => owner.effectReviewCheckpointPreview(selected, allowed,
      definition, storedWire, previewWire, limits), /ForeignRunHostCheckpointBinding/u);
  }
  assert.throws(() => owner.effectPreviewIdentityCid({...preview}), /ForeignRunHostHandle/u);
  assert.throws(() => foreign.effectPreviewIdentityCid(preview), /ForeignRunHostHandle/u);
  assert.equal(control.calls.length, 0, 'Copies and foreign tuples must refuse before the Common port');
});

test('Preview admission forwards the independent original tuple and exact limits once', () => {
  const f = originals();
  assert.deepEqual(f.previewOriginal.args, ['original preview wire',
    'independent original Run identity', 'independent original context', 65536, 4096, 32]);
  assert.equal(control.calls.filter(call => call.name === 'preview').length, 1);
});

test('Preview semantic identity observes the original without admission or scalar substitution', () => {
  const f = originals();
  const original = f.receiptOriginal.args[3];
  const before = control.calls.length;
  assert.equal(owner.effectPreviewIdentityCid(f.evidence.preview),
    `fixture:preview-semantic:${original.fixturePreview}`);
  assert.equal(control.calls.length, before, 'A pure identity getter must not re-admit evidence');
  assert.throws(() => owner.effectPreviewIdentityCid({...f.evidence.preview}), /ForeignRunHostHandle/u);
  assert.throws(() => owner.effectPreviewIdentityCid('fixture:preview-semantic'), /ForeignRunHostHandle/u);
  const other = foreign.admitEffectPreviewIdentity('foreign', 'run', 'context', limits);
  assert.throws(() => owner.effectPreviewIdentityCid(other), /ForeignRunHostHandle/u);
});

test('final receipt forwarding retains the complete original member inventory', () => {
  const f = originals(), args = f.receiptOriginal.args;
  assert.equal(args[0].wire, 'fixture:run_definition');
  assert.equal(args[1].wire, 'fixture:run_receipt');
  assert.equal(args[2].wire, 'fixture:captured_run');
  assert.equal(args[4], f.evidence.setReceiptWire);
  assert.deepEqual(args[5], ['member one', 'member two']);
  assert.deepEqual(args.slice(6), [65536, 4096, 32]);
  assert.equal(f.evidence.finalReceipt.wire, 'fixture final receipt');
});

test('publication forwarding includes every Result dependency and exact commit tuple', () => {
  const f = originals();
  owner.validateEffectfulPublicationCommit(f.evidence, f.request, f.attempt, f.index, limits);
  const args = control.calls.at(-1).args;
  assert.equal(args.length, 21);
  assert.deepEqual(args.slice(0, 2).map(value => value.wire),
    ['fixture:run_definition', 'fixture:run_invocation']);
  assert.deepEqual(args.slice(2, 8).map(values => values.map(value => value.wire)),
    [['fixture:result_definition'], ['fixture:result_artifact'], ['fixture:derivation_evidence'],
      ['fixture:ordering_evidence'], ['fixture:result_retention_policy'], ['fixture:durable_result_binding']]);
  assert.deepEqual(args.slice(8, 11).map(value => value.wire),
    ['fixture:result_manifest', 'fixture:run_receipt', 'fixture:captured_run']);
  assert.equal(args[11], f.receiptOriginal.args[3]);
  assert.equal(args[12], 'original set receipt');
  assert.deepEqual(args[13], ['member one', 'member two']);
  assert.deepEqual(args.slice(14, 18).map(value => value.wire),
    ['fixture final receipt', 'fixture:publication_request', 'fixture:publication_attempt', 'fixture:public_index_entry']);
  assert.deepEqual(args.slice(18), [65536, 4096, 32]);
  assert.equal(control.calls.filter(call => call.name === 'preview').length, 1,
    'The facade must retain its original Preview; Common internal work is not counted here');
});

test('copied Preview and foreign namespace originals refuse before publication ABI use', () => {
  const f = originals();
  const otherPreview = foreign.admitEffectPreviewIdentity('foreign', 'run', 'context', limits);
  const otherContract = foreign.admitPublicationContract('run_definition', 'foreign', limits);
  control.calls.length = 0;
  for (const preview of [{...f.evidence.preview}, otherPreview, 'scalar wire']) {
    assert.throws(() => owner.issueEffectfulFinalRunReceipt(f.evidence.runDefinition,
      f.evidence.computationReceipt, f.evidence.capturedRun, preview,
      f.evidence.setReceiptWire, f.evidence.memberReceiptWires, limits), /ForeignRunHostHandle/u);
  }
  assert.throws(() => owner.validateEffectfulPublicationCommit({...f.evidence,
    runDefinition: otherContract}, f.request, f.attempt, f.index, limits), /ForeignRunHostHandle/u);
  assert.equal(control.calls.length, 0);
});

test('visible contract fields cannot replace the retained nominal contract', () => {
  const f = originals();
  owner.validateEffectfulPublicationCommit({...f.evidence,
    finalReceipt: {...f.evidence.finalReceipt, cid: 'replacement', wire: 'replacement'}},
  f.request, f.attempt, f.index, limits);
  assert.equal(control.calls.at(-1).args[14].wire, 'fixture final receipt');
});

test('Common port refusal propagates without a successful receipt or commit fallback', () => {
  const f = originals();
  control.fail = 'preview';
  assert.throws(() => owner.admitEffectPreviewIdentity('wire', 'run', 'context', limits),
    /RunHostEffectPreviewRejected/u);
  control.fail = 'receipt';
  assert.throws(() => owner.issueEffectfulFinalRunReceipt(f.evidence.runDefinition,
    f.evidence.computationReceipt, f.evidence.capturedRun, f.evidence.preview,
    f.evidence.setReceiptWire, f.evidence.memberReceiptWires, limits), /RunHostEffectfulFinalReceiptRejected/u);
  control.fail = 'commit';
  assert.throws(() => owner.validateEffectfulPublicationCommit(f.evidence,
    f.request, f.attempt, f.index, limits), /RunHostEffectfulPublicationCommitRejected/u);
  control.fail = undefined;
});

test('invalid inventories and bounds do not reach the publication ABI', () => {
  const f = originals(); control.calls.length = 0;
  assert.throws(() => owner.admitEffectPreviewIdentity(1, 'run', 'context', limits), TypeError);
  assert.throws(() => owner.issueEffectfulFinalRunReceipt(f.evidence.runDefinition,
    f.evidence.computationReceipt, f.evidence.capturedRun, f.evidence.preview,
    'set', [undefined], limits), TypeError);
  const oversized = new Array(3);
  Object.defineProperty(oversized, 0, {get() { throw new Error('InventoryReadBeforeBound'); }});
  assert.throws(() => owner.issueEffectfulFinalRunReceipt(f.evidence.runDefinition,
    f.evidence.computationReceipt, f.evidence.capturedRun, f.evidence.preview,
    'set', oversized, limits), /InvalidRunHostEffectReceipts/u);
  assert.throws(() => owner.issueEffectfulFinalRunReceipt(f.evidence.runDefinition,
    f.evidence.computationReceipt, f.evidence.capturedRun, f.evidence.preview,
    'set', ['valid', undefined], limits), TypeError);
  assert.throws(() => owner.validateEffectfulPublicationCommit({...f.evidence, artifacts: undefined},
    f.request, f.attempt, f.index, limits), TypeError);
  assert.throws(() => owner.validateEffectfulPublicationCommit(f.evidence,
    f.request, f.attempt, f.index, {...limits, maxNodes: 0}), TypeError);
  assert.equal(control.calls.length, 0);
});


test('retained public full-chain evidence performs one full admission across pure getters and publication checks',()=>{
  control.status='succeeded';const f=originals();control.calls.length=0;
  const receipt=owner.admitEffectfulFinalRunEvidence(f.evidence,limits);
  const input={...f.evidence,finalReceipt:receipt};
  for(let index=0;index<20;index++)assert.deepEqual(owner.effectfulFinalRunOutcome(receipt),{status:'succeeded',allUnattempted:false});
  owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits);
  owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits);
  assert.equal(control.calls.filter(call=>call.name==='admit-full').length,1);
  assert.equal(control.calls.filter(call=>call.name==='commit-retained').length,2);
  assert.equal(control.calls.filter(call=>call.name==='commit').length,0);
  const full=control.calls.find(call=>call.name==='admit-full');
  assert.deepEqual(full.args.slice(-3),[65536,4096,32]);
  assert.equal(receipt.wire,f.evidence.finalReceipt.wire);assert.equal(receipt.cid,f.evidence.finalReceipt.cid);
});

test('retained public evidence refuses copied originals changed vectors and stale failed publication facts',()=>{
  control.status='succeeded';const f=originals();const receipt=owner.admitEffectfulFinalRunEvidence(f.evidence,limits);
  const input={...f.evidence,finalReceipt:receipt};
  owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits);
  control.calls.length=0;
  assert.throws(()=>owner.effectfulFinalRunOutcome({...receipt}),/ForeignRunHostEffectFinalEvidence/u);
  assert.throws(()=>foreign.effectfulFinalRunOutcome(receipt),/ForeignRunHostEffectFinalEvidence/u);
  const changed={...input,definitions:[f.evidence.artifacts[0]]};
  assert.throws(()=>owner.validateEffectfulPublicationCommit(changed,f.request,f.attempt,f.index,limits),/ForeignRunHostEffectFinalEvidence/u);
  assert.equal(control.calls.length,0);
  const materials=owner.admitEffectRunMaterials('saved material wire','original Definition CID',{});
  assert.throws(()=>owner.issueSucceededRunStateWire(materials.prepared,materials.compilation,materials.allowed,
    materials.definition,'2026-09-18T00:00:00.000Z',[],receipt),/RunHostEffectPublicationEvidenceRequired/u);
  owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits);
  control.fail='commit-retained';
  assert.throws(()=>owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits),{code:'RunHostEffectfulPublicationCommitRejected'});
  assert.throws(()=>owner.issueSucceededRunStateWire(materials.prepared,materials.compilation,materials.allowed,
    materials.definition,'2026-09-18T00:00:00.000Z',[],receipt),/RunHostEffectPublicationEvidenceRequired/u);
  control.fail=undefined;
  owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,limits);
  assert.throws(()=>owner.validateEffectfulPublicationCommit(input,f.request,f.attempt,f.index,{...limits,maxNodes:0}),
    /InvalidRunHostPublicationLimits/u);
  assert.throws(()=>owner.issueSucceededRunStateWire(materials.prepared,materials.compilation,materials.allowed,
    materials.definition,'2026-09-18T00:00:00.000Z',[],receipt),/RunHostEffectPublicationEvidenceRequired/u);
});

test('retained public original Result occurrence preserves derivation ordering and independently observed facts',()=>{
  const f=originals(),e=f.evidence;control.calls.length=0;
  const facts={logicalValueCid:'observed-value',resultSchemaCid:'observed-schema',effectiveDataPolicyCid:'observed-policy'};
  const result=owner.admitOriginalResultOccurrenceEvidence(e.definitions[0],e.artifacts[0],e.derivations[0],e.orderings[0],e.retentions[0],facts);
  assert.equal(result.derivation.cid,e.derivations[0].cid);assert.equal(result.derivation.wire,e.derivations[0].wire);
  assert.equal(result.ordering.cid,e.orderings[0].cid);assert.equal(result.ordering.wire,e.orderings[0].wire);
  assert.deepEqual(control.calls.map(call=>call.name),['original-occurrence']);
  assert.deepEqual(control.calls[0].args.slice(-3),['observed-value','observed-schema','observed-policy']);
  let calls=0;const accessor={...facts};Object.defineProperty(accessor,'logicalValueCid',{enumerable:true,get(){calls++;return'changed';}});
  assert.throws(()=>owner.admitOriginalResultOccurrenceEvidence(e.definitions[0],e.artifacts[0],e.derivations[0],e.orderings[0],e.retentions[0],accessor),/InvalidRunHostOriginalResultEvidence/u);
  assert.equal(calls,0);assert.equal(control.calls.length,1);
});

test('retained public Effect succeeded state requires original checked publication and actual admitted success',()=>{
  for(const status of ['succeeded','needs_reconciliation','failed']){
    control.status=status;const f=originals();const receipt=owner.admitEffectfulFinalRunEvidence(f.evidence,limits);
    const materials=owner.admitEffectRunMaterials('saved material wire','original Definition CID',{});
    const issue=()=>owner.issueSucceededRunStateWire(materials.prepared,materials.compilation,materials.allowed,
      materials.definition,'2026-09-18T00:00:00.000Z',[],receipt);
    assert.throws(issue,/RunHostEffectPublicationEvidenceRequired/u);
    owner.validateEffectfulPublicationCommit({...f.evidence,finalReceipt:receipt},f.request,f.attempt,f.index,limits);
    if(status==='succeeded')assert.equal(issue(),'fixture succeeded state');
    else assert.throws(issue,{code:'RunHostStateProjectionRejected'});
    if(status==='needs_reconciliation')assert.equal(owner.effectfulFinalRunReconciliationState(receipt,'2026-09-18T00:00:00.000Z',limits),'fixture reconciliation wire');
    else assert.throws(()=>owner.effectfulFinalRunReconciliationState(receipt,'2026-09-18T00:00:00.000Z',limits),{code:'RunHostEffectReconciliationStateRejected'});
    const other=owner.admitEffectRunMaterials('other saved material','other Definition CID',{});
    assert.throws(()=>owner.issueSucceededRunStateWire(other.prepared,materials.compilation,materials.allowed,
      materials.definition,'2026-09-18T00:00:00.000Z',[],receipt),/ForeignRunHostCompilation/u);
  }
  control.status='succeeded';
});
