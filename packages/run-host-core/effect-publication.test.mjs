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
export const clientValuesHostIssueEffectfulFinalRunReceipt = (...args) =>
  result('receipt', args, {cid: 'fixture:final', wire: 'fixture final receipt'});
export const clientValuesHostValidateEffectfulPublicationCommit = (...args) =>
  result('commit', args, undefined);
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

test('Preview admission forwards the independent original tuple and exact limits once', () => {
  const f = originals();
  assert.deepEqual(f.previewOriginal.args, ['original preview wire',
    'independent original Run identity', 'independent original context', 65536, 4096, 32]);
  assert.equal(control.calls.filter(call => call.name === 'preview').length, 1);
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
