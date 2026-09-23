import test from 'node:test';
import assert from 'node:assert/strict';
import {clientHostOperations, validClientBody, validClientConnection,
  validRunRef} from './index.mjs';

const connection = Object.freeze({mode: 'remote', owner: 'remote',
  consentRefs: [], runners: []});
const ref = Object.freeze({tenantId: 'tenant-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});

test('public wire accepts the exact connected request shapes', () => {
  assert.equal(clientHostOperations.length, 10);
  assert.equal(validClientConnection(connection), true);
  assert.equal(validRunRef(ref), true);
  assert.equal(validClientBody('connect', {connection}), true);
  assert.equal(validClientBody('submit', {connection, requestId: 'saved-a',
    kind: 'aql', input: {text: 'version: actql/0.1\n', format: 'yaml'},
    parameters: null}), true);
  assert.equal(validClientBody('read', {connection, ref,
    resultName: 'answer', format: 'jsonl', attemptId: 'read-a'}), true);
});

test('public wire rejects extra fields and unscoped or implicit movement', () => {
  assert.equal(validClientBody('connect', {connection, token: 'secret'}), false);
  assert.equal(validClientBody('connect', {connection: {...connection,
    movementPolicyRef: 'policy-a'}}), false);
  assert.equal(validClientBody('connect', {connection: {mode: 'hybrid',
    owner: 'cloud', consentRefs: [], runners: ['runner-a']}}), false);
  assert.equal(validClientBody('attach', {connection,
    ref: {...ref, authorityScopeCid: 'bad'}}), false);
  assert.equal(validClientBody('lookup-request', {connection,
    requestId: 'saved-a', intent: {changed: true}}), false);
  assert.equal(validClientBody('unknown', {connection}), false);
});

test('Hybrid wire binds Cloud assistance to its selected Run owner', () => {
  const localOwned = {mode: 'hybrid', owner: 'local',
    consentRefs: ['grant-a'], runners: [],
    movementPolicyRef: 'movement-a',
    cloudConnectionRef: 'registered-cloud-a'};
  assert.equal(validClientBody('connect', {connection: localOwned}), true);
  assert.equal(validClientBody('connect', {connection: {...localOwned,
    cloudConnectionRef: undefined}}), false);
  assert.equal(validClientBody('connect', {connection: {...localOwned,
    cloudConnectionRef: 'new-cloud-b', consentRefs: []}}), true);
  const cloudOwned = {mode: 'hybrid', owner: 'cloud',
    consentRefs: ['runner-grant-a'], runners: ['runner-a'],
    movementPolicyRef: 'movement-a'};
  assert.equal(validClientBody('connect', {connection: cloudOwned}), true);
  assert.equal(validClientBody('connect', {connection: {...cloudOwned,
    cloudConnectionRef: 'registered-cloud-a'}}), false);
  assert.equal(validClientBody('connect', {connection: {...cloudOwned,
    runners: []}}), false);
  assert.equal(validClientBody('connect', {connection: {...connection,
    cloudConnectionRef: 'registered-cloud-a'}}), false);
});
