import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parse} from 'acorn';

const operationSource = readFileSync(new URL('./infer-operation.mjs', import.meta.url), 'utf8');
const continuationSource = readFileSync(new URL('./installed-model-continuation.mjs', import.meta.url), 'utf8');
function select(source, predicate) {
  const selected = [];
  function visit(node) {
    if (node === null || typeof node !== 'object') return;
    if (predicate(node)) selected.push(source.slice(node.start, node.end));
    for (const child of Object.values(node)) {
      if (Array.isArray(child)) child.forEach(visit); else visit(child);
    }
  }
  visit(parse(source, {ecmaVersion: 'latest', sourceType: 'module'}));
  assert.equal(selected.length, 1);
  return selected[0];
}
const method = select(operationSource, node => node.type === 'Property' && node.key.name === 'restoreCall');
const call = select(continuationSource, node => node.type === 'CallExpression' &&
  node.callee.type === 'MemberExpression' && node.callee.object.name === 'operation' &&
  node.callee.property.name === 'restoreCall');

test('saved attachment admission reaches the same private Core restore call without another issuer', () => {
  for (const attachment of [undefined, Object.freeze({original: 'attachment'})]) {
    const prepared = {}, record = {}, proof = {}, bundle = {}, result = {};
    const moon = {clientProgramRestoreInferPreparedCall(...args) {
      assert.deepEqual(args, [prepared, 2, record, proof, bundle, attachment]);
      return result;
    }};
    const api = Function('moon', 'checked', `return ({${method}});`)(moon, value => value);
    assert.equal(api.restoreCall(prepared, 2, record, proof, bundle, attachment), result);
  }
});

test('the controller forwards only the Store-read original and preserves a missing inventory as absent', () => {
  for (const attachment of [undefined, Object.freeze({original: 'attachment'})]) {
    const originals = Object.fromEntries(['model_slot_capture', 'model_call_attempt',
      'model_attempt_accounting', 'model_attempt_outcome', 'model_dispatch_authority']
      .map(name => [name, Object.freeze({name})]));
    if (attachment !== undefined) originals.model_attachment_admission = attachment;
    const preparedCallSet = {}, bundle = {}, proof = {};
    const bodies = attachment === undefined ? {} : {model_attachment_admission: 'Store-owned wire'};
    let calls = 0;
    const operation = {restoreCall(...args) {
      calls++;
      assert.deepEqual(args, [preparedCallSet, 2, originals.model_slot_capture, proof, bundle, attachment]);
    }};
    const moon = {clientProgramInferAttemptRecords(...args) {
      assert.deepEqual(args, ['model_call_attempt', 'model_attempt_accounting',
        'model_attempt_outcome', 'model_dispatch_authority'].map(name => originals[name]));
      return proof;
    }};
    Function('operation', 'preparedCallSet', 'slot', 'leaf', 'moon', 'bundle', 'stored',
      `return ${call};`)(operation, preparedCallSet, {ordinal: 2}, name => {
      assert(Object.hasOwn(originals, name)); return originals[name];
    }, moon, bundle, {bodies});
    assert.equal(calls, 1);
  }
});
