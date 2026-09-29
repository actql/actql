import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {checkpointLimits, clientHostOperations, isClientSubmitRejection,
  validCheckpointPage,
  validCheckpointReview, validClientAdmission, validClientBody,
  validClientConnection, validClientProfile, validDeliveryAttemptLookup,
  validHeldRequest, validRequestCancellation, validRequestLookup, validResolveResults, validRunRef,
  resourceLimits, validResourceInspection, validResourceListing,
  validResourcePeek,
  validRunState, validSubmitPreparationError,
  validSubmitReply} from './index.mjs';

const connection = Object.freeze({mode: 'remote', owner: 'remote',
  consentRefs: [], runners: []});
const ref = Object.freeze({namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});

test('public wire accepts the exact connected request shapes', () => {
  // The Run, request, Checkpoint and three Resource discovery operations.
  assert.equal(clientHostOperations.length, 17);
  assert.equal(validClientConnection(connection), true);
  assert.equal(validRunRef(ref), true);
  assert.equal(validClientBody('connect', {connection}), true);
  assert.equal(validClientBody('submit', {connection, requestId: 'saved-a',
    kind: 'aql', input: {text: 'version: actql/0.1\n', format: 'yaml'},
    parameters: null}), true);
  assert.equal(validClientBody('read', {connection, ref,
    resultName: 'answer', format: 'jsonl', attemptId: 'read-a'}), true);
});

test('submit preparation errors follow the public Host contract', () => {
  for (const code of ['ClientProgramInvalidInput',
    'ClientParametersInvalid', 'ClientParametersTooLarge',
    'ClientProgramUnsupported', 'ClientProgramNeedsInputs',
    'ClientProgramRejected']) {
    assert.equal(validSubmitPreparationError({code}), true);
  }
  assert.equal(validSubmitPreparationError({code: 'ClientHostFailure'}),
    false);
  assert.equal(validSubmitPreparationError({code: 'ClientProgramRejected',
    diagnostics: []}), false);
});

test('technical delegation failure before Run creation is known non-admission',
  () => {
    assert.equal(isClientSubmitRejection('ACTQL_E_DELEGATION_UNAVAILABLE'),
      true);
    assert.equal(isClientSubmitRejection('ClientAdmissionJournalUnavailable'),
      false);
    assert.equal(isClientSubmitRejection('ClientHostFailure'), false);
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
  for (const operation of ['constructor', 'toString', '__proto__']) {
    assert.equal(validClientBody(operation, {connection}), false);
  }
  assert.equal(validRunRef({...ref, namespaceId: '😀'.repeat(130)}), false);
  assert.equal(validRunRef({tenantId: ref.namespaceId,
    authorityScopeCid: ref.authorityScopeCid,
    runDefinitionCid: ref.runDefinitionCid}), false);
  assert.equal(validRunRef({...ref, tenantId: ref.namespaceId}), false);
  assert.equal(validClientConnection({...connection, consentRefs: ['grant-a',
    'grant-a']}), false);
  assert.equal(validClientConnection({...connection, durability: undefined}),
    false);
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
    ref: {...ref, namespaceId: ''}}, selected), false);
  assert.equal(validClientAdmission({...admission, revision: -1},
    selected), false);
});

test('request lookup retains found, absent and observation-unknown replies',
  () => {
    assert.equal(validRequestLookup({kind: 'found', requestId: 'request-a', ref,
      durability: 'volatile',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'}, 'request-a'), true);
    assert.equal(validRequestLookup({kind: 'not_found'}, 'request-a'), true);
    assert.equal(validRequestLookup({kind: 'unknown',
      reason: 'query_failed'}, 'request-a'), true);
    assert.equal(validRequestLookup({kind: 'found', requestId: 'request-b',
      ref, durability: 'volatile',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'}, 'request-a'), false);
    assert.equal(validRequestLookup({kind: 'found', ref,
      durability: 'volatile',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'}, 'request-a'), false);
    assert.equal(validRequestLookup({kind: 'found', requestId: 'request-a',
      ref: {...ref,
      runDefinitionCid: 'foreign'}, durability: 'durable',
    lookupExpiresAt: 'tomorrow'}, 'request-a'), false);
    assert.equal(validRequestLookup({kind: 'not_found', ref},
      'request-a'), false);
    assert.equal(validRequestLookup({kind: 'unknown', reason: ''},
      'request-a'), false);
  });

test('Run reconciliation is distinct from the unchanged Effect action', () => {
  const state = {version: 'actql-run-state/0.1', run_id: 'run-a',
    status: 'needs_reconciliation', updated_at: '2026-09-27T00:00:00.000Z',
    result_available: false, result_availability: {answer: {
      state: 'unavailable', reason: 'not_published',
      observed_at: '2026-09-27T00:00:00.000Z'}},
    next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}};
  assert.equal(validRunState(state), true);
  assert.equal(validRunState({...state,
    next_action: {kind: 'reconcile', effects: ['write']}}), true);
  for (const action of [
    {kind: 'reconcile', effects: []},
    {kind: 'reconcile_run'},
    {kind: 'reconcile_run', reason: 'execution_unknown', effects: []},
    {kind: 'reconcile_run', reason: 'failed'},
  ]) assert.equal(validRunState({...state, next_action: action}), false);
  for (const status of ['succeeded', 'failed', 'cancelled', 'running']) {
    assert.equal(validRunState({...state, status}), false);
  }
});

test('registered Run state guard checks nested availability and action wire',
  () => {
    const at = '2026-09-24T00:30:00.000Z';
    const state = {version: 'actql-run-state/0.1', run_id: 'run-a',
      status: 'succeeded', updated_at: at,
      next_action: {kind: 'read_result', results: ['answer']},
      result_available: true,
      result_availability: {answer: {state: 'available',
        reason: 'confirmed_present', observed_at: at}}};
    assert.equal(validRunState(state), true);
    for (const changed of [
      {...state, status: 'other'},
      {...state, result_available: 'true'},
      {...state, next_action: {kind: 'read_result', results: []}},
      {...state, next_action: {kind: 'none', results: ['answer']}},
      {...state, result_availability: {}},
      {...state, result_availability: {answer: {...state.result_availability.answer,
        reason: 'store_query_failed'}}},
      {...state, checkpoint: {checkpoint_id: 'paused',
        checkpoint_cid: `sha256:${'c'.repeat(64)}`, kind: 'run_scope'}},
      {...state, result_availability: {'': state.result_availability.answer}},
      {...state, revision: 1},
    ]) assert.equal(validRunState(changed), false);
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

const checkpointCid = `sha256:${'c'.repeat(64)}`;
const held = Object.freeze({kind: 'held', requestId: 'saved-a',
  prepareAttemptId: 'prepare-a', state: 'waiting_checkpoint',
  durability: 'durable', lookupExpiresAt: '2026-10-03T00:00:00.000Z',
  checkpoint: {checkpointId: 'prepare-a-preparation', checkpointCid,
    kind: 'run_scope', expiresAt: '2026-09-27T00:00:00.000Z'}});
const summary = Object.freeze({checkpointId: 'prepare-a-preparation',
  checkpointCid, kind: 'run_scope', phase: 'preflight',
  subject: {kind: 'prepare_attempt', prepareAttemptId: 'prepare-a',
    requestId: 'saved-a'},
  requiredArtifact: {type: 'prepared_invocation',
    cid: `sha256:${'d'.repeat(64)}`},
  reviewProjectionCid: `sha256:${'e'.repeat(64)}`,
  requirements: ['invocation_scope_approved'],
  createdAt: '2026-09-26T00:00:00.000Z',
  expiresAt: '2026-09-27T00:00:00.000Z', humanSummary: 'Run on site-a'});

test('a held request is a typed reply, distinct from a Run admission', () => {
  assert.equal(validHeldRequest(held, 'saved-a'), true);
  assert.equal(validHeldRequest(held, 'saved-b'), false);
  assert.equal(validSubmitReply(held, connection, 'saved-a'), true);
  assert.equal(validRequestLookup(held, 'saved-a'), true);
  // Waiting always names its Checkpoint; an ended request says why and
  // names no fictitious Run.
  const {checkpoint, ...unnamed} = held;
  assert.equal(validHeldRequest(unnamed, 'saved-a'), false);
  assert.equal(validHeldRequest({...unnamed, state: 'resuming'}, 'saved-a'),
    true);
  assert.equal(validHeldRequest({...unnamed, state: 'ended'}, 'saved-a'),
    false);
  assert.equal(validHeldRequest({...unnamed, state: 'ended',
    endReason: 'rejected'}, 'saved-a'), true);
  assert.equal(validHeldRequest({...held, ref}, 'saved-a'), false);
  assert.equal(validHeldRequest({...held, durability: 'volatile'},
    'saved-a'), false);
});

test('Checkpoint operations carry bounded, exact request shapes', () => {
  assert.equal(validClientBody('checkpoints', {connection, after: '',
    limit: 10}), true);
  assert.equal(validClientBody('checkpoints', {connection, after: 'x|y',
    limit: checkpointLimits.maxPageItems + 1}), false);
  assert.equal(validClientBody('checkpoints', {connection, limit: 10}),
    false);
  assert.equal(validClientBody('checkpoint-review', {connection,
    checkpointCid, maxBytes: 4096}), true);
  assert.equal(validClientBody('checkpoint-review', {connection,
    checkpointCid: 'cp-1', maxBytes: 4096}), false);
  assert.equal(validClientBody('checkpoint-review', {connection,
    checkpointCid, maxBytes: checkpointLimits.maxReviewBytes + 1}), false);
  const item = {checkpointCid, resolutionWire: '{}',
    approvalEvidenceWire: ''};
  assert.equal(validClientBody('resolve', {connection, items: [item]}),
    true);
  assert.equal(validClientBody('resolve', {connection, items: []}), false);
  assert.equal(validClientBody('resolve', {connection,
    items: [item, item]}), false);
  // A signing key or credential has no place in an answer item.
  assert.equal(validClientBody('resolve', {connection,
    items: [{...item, privateKey: 'x'}]}), false);
  assert.equal(validClientBody('resolve', {connection, items: Array.from(
    {length: checkpointLimits.maxResolveItems + 1}, (_, index) => ({...item,
      checkpointCid: `sha256:${index.toString(16).padStart(64, '0')}`}))}),
  false);
});

test('Checkpoint replies bind page bounds, exact review bytes and each item',
  () => {
    assert.equal(validCheckpointPage({items: [summary]}, 1), true);
    assert.equal(validCheckpointPage({items: [summary], next: 'a|b'}, 1),
      true);
    assert.equal(validCheckpointPage({items: [summary, summary]}, 2), false);
    assert.equal(validCheckpointPage({items: [summary]}, 0), false);
    assert.equal(validCheckpointPage({items: [{...summary,
      review: 'private'}]}, 1), false);
    const review = {kind: 'review', checkpointCid,
      artifactCid: `sha256:${'e'.repeat(64)}`, byteLength: 5,
      contentBase64: Buffer.from('hello').toString('base64')};
    assert.equal(validCheckpointReview(review, {checkpointCid,
      maxBytes: 5}), true);
    assert.equal(validCheckpointReview(review, {checkpointCid,
      maxBytes: 4}), false);
    assert.equal(validCheckpointReview({...review, byteLength: 6},
      {checkpointCid, maxBytes: 8}), false);
    assert.equal(validCheckpointReview(review, {checkpointCid:
      `sha256:${'f'.repeat(64)}`, maxBytes: 8}), false);
    const items = [{checkpointCid}, {checkpointCid:
      `sha256:${'f'.repeat(64)}`}];
    assert.equal(validResolveResults({results: [
      {checkpointCid, status: 'committed', decision: 'approved',
        resolutionCid: `sha256:${'1'.repeat(64)}`},
      {checkpointCid: items[1].checkpointCid, status: 'conflicting',
        reason: 'CheckpointResolutionConflict'},
    ]}, items), true);
    assert.equal(validResolveResults({results: [
      {checkpointCid, status: 'committed', decision: 'approved'},
      {checkpointCid: items[1].checkpointCid, status: 'invalid',
        reason: 'x'}]}, items), false);
    assert.equal(validResolveResults({results: [
      {checkpointCid: items[1].checkpointCid, status: 'invalid', reason: 'x'},
      {checkpointCid, status: 'invalid', reason: 'x'}]}, items), false);
    assert.equal(validResolveResults({results: []}, items), false);
  });

test('a request cancellation names its request and, with a Run, that Run', () => {
  assert.equal(validClientBody('cancel-request', {connection,
    requestId: 'saved-a'}), true);
  assert.equal(validClientBody('cancel-request', {connection,
    requestId: 'saved-a', ref}), false);
  assert.equal(validRequestCancellation({requestId: 'saved-a',
    kind: 'accepted'}, 'saved-a'), true);
  assert.equal(validRequestCancellation({requestId: 'saved-a',
    kind: 'accepted', ref, revision: 2}, 'saved-a'), true);
  assert.equal(validRequestCancellation({requestId: 'saved-b',
    kind: 'accepted'}, 'saved-a'), false);
  // A Run reference comes with its revision, and only known kinds.
  assert.equal(validRequestCancellation({requestId: 'saved-a',
    kind: 'accepted', ref}, 'saved-a'), false);
  assert.equal(validRequestCancellation({requestId: 'saved-a',
    kind: 'not_found'}, 'saved-a'), false);
});

test('Resource discovery requests and replies stay within their bounds', () => {
  const at = {resourceConnection: 'salesforce:00D000000000001EAA'};
  assert.equal(validClientBody('resources', {connection, ...at, query: '',
    limit: 10}), true);
  assert.equal(validClientBody('resources', {connection, ...at, query: 'a',
    limit: resourceLimits.maxListItems + 1}), false);
  assert.equal(validClientBody('resources', {connection, ...at,
    query: 'a\u0000', limit: 1}), false);
  assert.equal(validClientBody('resource-inspect', {connection, ...at,
    resource: 'Account', maxBytes: 1024}), true);
  const peek = {connection, ...at, resource: 'Account', fields: ['Id', 'Name'],
    maxRows: 2, maxBytes: 4096};
  assert.equal(validClientBody('resource-peek', peek), true);
  for (const change of [{fields: []}, {fields: ['Id', 'Id']},
    {maxRows: resourceLimits.maxPeekRows + 1}, {maxBytes: 0}]) {
    assert.equal(validClientBody('resource-peek', {...peek, ...change}), false);
  }
  const cid = `sha256:${'c'.repeat(64)}`;
  const listing = {...at, observationCid: cid,
    resources: [{name: 'Account', outcome: 'described'}],
    snapshotComplete: true, snapshotTruncated: false, resultTruncated: false};
  assert.equal(validResourceListing(listing, {...at, limit: 1}), true);
  assert.equal(validResourceListing({...listing, resources: [
    listing.resources[0], listing.resources[0]]}, {...at, limit: 5}), false);
  assert.equal(validResourceListing(listing, {resourceConnection: 'other',
    limit: 1}), false);
  const expected = {...at, resource: 'Account', maxBytes: 64};
  assert.equal(validResourceInspection({...at, resource: 'Account',
    observationCid: cid, status: 'ready', summaryJson: '{"fields":[]}'},
  expected), true);
  assert.equal(validResourceInspection({...at, resource: 'Account',
    observationCid: cid, status: 'catalog_required', reason: 'not_visible'},
  expected), true);
  assert.equal(validResourceInspection({...at, resource: 'Account',
    observationCid: cid, status: 'ready', reason: 'not_visible',
    summaryJson: '{}'}, expected), false);
  assert.equal(validResourceInspection({...at, resource: 'Account',
    observationCid: cid, status: 'ready',
    summaryJson: JSON.stringify({x: 'y'.repeat(64)})}, expected), false);
  const peekExpected = {...at, resource: 'Account', fields: ['Id', 'Name'],
    maxRows: 2, maxBytes: 4096};
  const reply = {...at, resource: 'Account', observationCid: cid,
    fields: ['Id', 'Name'], limited: true,
    rowsJson: JSON.stringify([{Id: '1', Name: 'a'}, {Id: '2', Name: null}])};
  assert.equal(validResourcePeek(reply, peekExpected), true);
  for (const change of [
    {limited: false},
    {rowsJson: JSON.stringify([{Id: '1'}])},
    {rowsJson: JSON.stringify([{Id: '1', Name: {nested: true}}])},
    {rowsJson: JSON.stringify([{Id: '1', Name: 'a'}, {Id: '2', Name: 'b'},
      {Id: '3', Name: 'c'}])},
    {fields: ['Name', 'Id']},
  ]) {
    assert.equal(validResourcePeek({...reply, ...change}, peekExpected),
      false, JSON.stringify(change));
  }
});
