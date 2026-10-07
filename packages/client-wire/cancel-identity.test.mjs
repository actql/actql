import assert from 'node:assert/strict';
import test from 'node:test';
import * as wire from './index.mjs';
const cid = value => `sha256:${value.repeat(64)}`;
const ref = {namespaceId: 'namespace-a', authorityScopeCid: cid('a'), runDefinitionCid: cid('b')};
const cancelRef = {...ref, cancelId: 'original-cancel', expectedRevision: 19};
const cancellation = {ref, cancelRef, kind: 'accepted', revision: 20};
const connection = {mode: 'local', owner: 'local', consentRefs: [], runners: []};

test('public cancellation admission requires its immutable operation reference', () => {
  assert.equal(wire.validCancellation(cancellation, cancelRef), true);
  assert.equal(wire.validCancellation({ref, kind: 'accepted', revision: 20}), false);
  for (const change of [{cancelId: 'changed'}, {expectedRevision: 20},
    {namespaceId: 'foreign'}, {runDefinitionCid: cid('f')}]) {
    assert.equal(wire.validCancellation({...cancellation, cancelRef: {...cancelRef, ...change}}, cancelRef), false);
  }
});

test('exact cancellation lookup admits only its original found or unknown observation', () => {
  assert.equal(wire.validCancellationLookup({kind: 'found', cancellation}, cancelRef), true);
  assert.equal(wire.validCancellationLookup({kind: 'unknown', cancelRef}, cancelRef), true);
  assert.equal(wire.validCancellationLookup({kind: 'not_accepted', cancelRef}, cancelRef), false);
  assert.equal(wire.validCancellationLookup({kind: 'found', cancellation: {...cancellation,
    cancelRef: {...cancelRef, expectedRevision: 20}}}, cancelRef), false);
});

test('cancel and lookup requests bind the target and original expected revision', () => {
  const body = {connection, ref, cancelId: 'original-cancel', expectedRevision: 19};
  for (const operation of ['cancel', 'lookup-cancellation']) {
    assert.equal(wire.validClientBody(operation, body), true);
    for (const change of [{cancelId: ''}, {cancelId: 'bad\r\n'}, {cancelId: '\ud800'},
      {expectedRevision: -1}, {expectedRevision: 2147483648}, {extra: true}]) {
      assert.equal(wire.validClientBody(operation, {...body, ...change}), false);
    }
    assert.equal(wire.validClientBody(operation, {connection, ref}), false);
  }
});
