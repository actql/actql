import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {clientHostOperations, validClientAdmission, validClientBody,
  validClientConnection, validClientProfile, validDeliveryAttemptLookup,
  validRequestLookup, validRunRef} from './index.mjs';

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

test('Host profile and admission replies bind the selected connection', () => {
  const selected = {...connection, durability: 'durable'};
  const profile = {version: 'actql-client-host/0.1', mode: 'remote',
    owner: 'remote', durability: 'durable', scopeRef: 'scope-a',
    capabilities: ['aql-document'],
    limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
      maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
      maxRows: 10, maxBatchRows: 3,
      maxBatchRetainedValueBytes: 1024}};
  const admission = {ref, durability: 'durable', revision: 4};
  assert.equal(validClientProfile(profile, selected), true);
  assert.equal(validClientAdmission(admission, selected), true);
  assert.equal(validClientProfile({...profile, durability: 'volatile'},
    selected), false);
  assert.equal(validClientAdmission({...admission, durability: 'volatile'},
    selected), false);
  assert.equal(validClientProfile({...profile, owner: 'cloud'},
    selected), false);
  assert.equal(validClientProfile({...profile,
    limits: {...profile.limits, maxRows: 1.5}}, selected), false);
  assert.equal(validClientAdmission({...admission,
    ref: {...ref, tenantId: ''}}, selected), false);
  assert.equal(validClientAdmission({...admission, revision: -1},
    selected), false);
});

test('request lookup retains found, absent and observation-unknown replies',
  () => {
    assert.equal(validRequestLookup({kind: 'found', ref,
      durability: 'volatile',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'}), true);
    assert.equal(validRequestLookup({kind: 'not_found'}), true);
    assert.equal(validRequestLookup({kind: 'unknown',
      reason: 'query_failed'}), true);
    assert.equal(validRequestLookup({kind: 'found', ref: {...ref,
      runDefinitionCid: 'foreign'}, durability: 'durable',
    lookupExpiresAt: 'tomorrow'}), false);
    assert.equal(validRequestLookup({kind: 'not_found', ref}), false);
    assert.equal(validRequestLookup({kind: 'unknown', reason: ''}), false);
  });

const delivery = JSON.parse(readFileSync(new URL(
  './fixtures/delivery-attempt.found.json', import.meta.url), 'utf8'));
const expectedDelivery = {attemptId: 'read-a',
  runDefinitionCid: ref.runDefinitionCid, resultName: 'answer'};

test('delivery lookup follows the published attempt, record and receipt shapes',
  () => {
    const protocol = JSON.parse(readFileSync(new URL(
      '../../spec/contracts/actql-protocol-schemas.json', import.meta.url),
    'utf8')).artifact_schemas;
    const publication = JSON.parse(readFileSync(new URL(
      '../../spec/contracts/actql-run-publication.json', import.meta.url),
    'utf8')).schemas;
    for (const [key, schema] of [
      ['attempt', publication.delivery_attempt],
      ['record', publication.delivery_record],
      ['hostReleaseReceipt', protocol.result_delivery_receipt],
    ]) {
      assert(schema.required.every(field =>
        Object.hasOwn(delivery[key], field)));
      assert(Object.keys(delivery[key]).every(field =>
        Object.hasOwn(schema.properties, field)));
    }
    assert.equal(validDeliveryAttemptLookup(delivery, expectedDelivery), true);
    assert.equal(validDeliveryAttemptLookup({kind: 'not_found'},
      expectedDelivery), true);
    assert.equal(validDeliveryAttemptLookup({kind: 'found',
      attempt: delivery.attempt, record: null, hostReleaseReceipt: null},
    expectedDelivery), true);
  });

test('delivery lookup rejects foreign identity and contradictory receipts', () => {
  const changed = update => {
    const answer = structuredClone(delivery);
    update(answer);
    return validDeliveryAttemptLookup(answer, expectedDelivery);
  };
  for (const update of [
    answer => { answer.attempt.attempt_id = 'OTHER'; },
    answer => { answer.attempt.run_definition_cid = `sha256:${'9'.repeat(64)}`; },
    answer => { answer.attempt.result_name = 'foreign'; },
    answer => { answer.record.delivery_attempt_cid = `sha256:${'9'.repeat(64)}`; },
    answer => { answer.hostReleaseReceipt.result_name = 'foreign'; },
    answer => { answer.hostReleaseReceipt.serialization_contract_cid =
      `sha256:${'9'.repeat(64)}`; },
    answer => { answer.hostReleaseReceipt.result_artifact_cid =
      `sha256:${'9'.repeat(64)}`; },
    answer => { answer.hostReleaseReceipt = {}; },
    answer => { answer.record = {}; },
    answer => { answer.hostReleaseReceipt = null; },
    answer => { answer.record = null; },
    answer => { answer.record.state = 'failed'; },
    answer => { answer.record.confirmed_byte_count++; },
    answer => { answer.record.exposure = 'unknown_additional'; },
    answer => { answer.record.sequence = 1; },
  ]) assert.equal(changed(update), false);
});
