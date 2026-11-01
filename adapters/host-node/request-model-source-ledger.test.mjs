// Execute the actual pre-acquisition dispatch branch with explicit native
// Resource/Source ports; no nominal grant or physical Source is issued here.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {parse} from 'acorn';
const source = readFileSync(new URL('./client-dispatch-owner.mjs', import.meta.url), 'utf8');
const ast = parse(source, {ecmaVersion: 'latest', sourceType: 'module'});
let branch, selection;
const walk = (node, parents = []) => {
  if (!node || typeof node !== 'object') return;
  if (node.type === 'CallExpression' && node.callee?.object?.name === 'runContent' &&
      node.callee.property?.name === 'prepareAcquiredLedger') {
    branch = parents.find(p => p.type === 'IfStatement');
  }
  if (node.type === 'VariableDeclaration' && node.declarations[0]?.id?.name === 'requestModelAcquired') selection = node;
  for (const value of Object.values(node)) {
    if (Array.isArray(value)) value.forEach(child => walk(child, [node, ...parents]));
    else if (value && typeof value === 'object') walk(value, [node, ...parents]);
  }
};
walk(ast); assert(branch);
const body = (selection ? source.slice(selection.start, selection.end) : '') + '\n' + source.slice(branch.start, branch.end);

test('plain Request Model dispatch borrows its same adopted Source Ledger before physical acquisition', async () => {
  const nativeParent = {}, prepared = {}, plan = {}, request = {}, access = {}, preparedSource = {},
    capacity = Object.freeze({managedRun: nativeParent}), ledger = {}, entry = {};
  const held = {managedRun: nativeParent, plan, preparedSource, preparedSourceAccess: access};
  const calls = [], installedSource = {sourceAccess: access, ledgerCapacity(actual) {
    assert.strictEqual(actual, preparedSource); calls.push('capacity'); return capacity;
  }};
  const ports = {held, entry, preparedProgram: prepared, requested: request, inferring: true,
    generatingContent: false, acquiring: true, multiple: false, keyedSelection: undefined,
    installedSource, checkpoints: undefined, submission: {requestId: 'fixture-request'},
    preparationLease: {}, moon: {},
    prepareAcquisition() {assert.fail('do not reconstruct the retained original Source');},
    retainDispatchPreparationHost(actualEntry, _moon, actualParent, actualPrepared, actualRequest, custody) {
      assert.strictEqual(actualEntry, entry); assert.strictEqual(actualParent, nativeParent);
      assert.strictEqual(actualPrepared, prepared); assert.strictEqual(actualRequest, request);
      assert.equal(custody, true); calls.push('same parent borrow');
    },
    runContent: {prepareAcquiredLedger() {assert.fail('plain Model has no Content prefix');}},
    runInfer: {prepareAcquiredLedger(actual) {
      assert.deepEqual(actual, {preparedProgram: prepared, plan, sourceCapacity: capacity});
      calls.push('same Model Ledger'); return ledger;
    }}};
  const run = Function(...Object.keys(ports), `return (async () => {let ledger;${body};return ledger;})();`);
  assert.strictEqual(await run(...Object.values(ports)), ledger);
  assert.deepEqual(calls, ['same parent borrow', 'capacity', 'same Model Ledger']);
  assert.strictEqual(entry.acquisitionLedger, ledger);
  assert.equal(entry.borrowedSources, true);
});
