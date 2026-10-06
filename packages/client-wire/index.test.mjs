import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {snapshotCheckRequest, checkpointLimits, clientHostOperations, clientSourceFormats, isClientSubmitRejection,
  validCheckpointPage, validCheckOutcome,
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
  // The Run, request, check, Checkpoint and three Resource discovery
  // operations.
  assert.equal(clientHostOperations.length, 19);
  assert.equal(validClientConnection(connection), true);
  assert.equal(validRunRef(ref), true);
  assert.equal(validClientBody('connect', {connection}), true);
  assert.equal(validClientBody('submit', {connection, requestId: 'saved-a',
    kind: 'aql', input: {text: 'version: actql/0.1\n', format: 'yaml'},
    parameters: null}), true);
  assert.equal(validClientBody('read', {connection, ref,
    resultName: 'answer', format: 'jsonl', attemptId: 'read-a'}), true);
  const description = {connection, ref, resultName: 'answer', format: 'jsonl',
    attemptId: 'metadata-a', maxWireBytes: 1048576, maxNodes: 10000, maxDepth: 64};
  assert.equal(validClientBody('result-describe', description), true);
  for (const invalid of [{format: 'parquet'}, {maxWireBytes: 0},
    {maxNodes: 10001}, {maxDepth: 65}, {extra: true}]) {
    assert.equal(validClientBody('result-describe',
      {...description, ...invalid}), false);
  }
});

test('check requests carry authored source and bindings only', () => {
  const input = {text: 'SELECT id FROM records WHERE amount >= @p',
    format: 'sql', parameterDeclarations: {p: {type: 'number'}}};
  assert.equal(validClientBody('check', {connection, input,
    parameters: {p: 1}}), true);
  assert.equal(validClientBody('check', {connection,
    input: {text: 'SELECT id FROM records', format: 'aql-text'},
    parameters: null}), true);
  for (const invalid of [
    {input: {...input, format: 'json'}},
    {input: {...input, text: ''}},
    {input: {...input, parameterDeclarations: null}},
    {input: {...input, extra: true}},
    {parameters: []},
    {requestId: 'not-a-run'},
  ]) {
    assert.equal(validClientBody('check', {connection, input,
      parameters: null, ...invalid}), false, JSON.stringify(invalid));
  }
  assert.equal(validClientBody('check', {connection, input}), false);
});

test('source format selection is explicit and bounded', () => {
  for (const format of clientSourceFormats) {
    assert.equal(validClientBody('submit', {connection,
      requestId: 'saved-format', kind: 'aql',
      input: {text: 'SELECT id FROM records', format},
      parameters: null}), true, format);
  }
  for (const format of ['auto', 'pipe', 'sql-v2', '']) {
    assert.equal(validClientBody('submit', {connection,
      requestId: 'saved-format', kind: 'aql',
      input: {text: 'SELECT id FROM records', format},
      parameters: null}), false, format);
  }
  const declared = {p: {type: 'number'}};
  for (const format of ['aql-text', 'sql']) {
    assert.equal(validClientBody('submit', {connection,
      requestId: 'saved-declarations', kind: 'aql',
      input: {text: 'SELECT @p FROM records', format,
        parameterDeclarations: declared}, parameters: {p: 1}}), true);
  }
  for (const format of ['json', 'yaml', 'aql-json', 'aql-yaml']) {
    assert.equal(validClientBody('submit', {connection,
      requestId: 'saved-declarations', kind: 'aql',
      input: {text: '{}', format, parameterDeclarations: declared},
      parameters: null}), false);
  }
  for (const parameterDeclarations of [null, [], 'p']) {
    assert.equal(validClientBody('submit', {connection,
      requestId: 'saved-declarations', kind: 'aql',
      input: {text: 'SELECT @p', format: 'sql', parameterDeclarations},
      parameters: null}), false);
  }
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

test('independent default mismatch fixture binds closed facts to the declaration revision', () => {
  const original = JSON.parse(readFileSync(new URL(
    './fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
  assert.equal(validCheckOutcome(original), true);
  for (const update of [
    answer => { answer.report.reasons[0].location.document_id = 'parameters'; },
    answer => { answer.report.reasons[0].location.revision = `rev:${'6'.repeat(64)}`; },
    answer => { delete answer.report.reasons[0].facts.actual_type; },
    answer => { answer.report.reasons[0].facts.value = 'private-default'; },
    answer => { answer.report.verdict = 'verified'; },
    answer => { answer.reason_schema_cid = 'sha256:6c1c1eb6f5d8ac67e831f7c49ef8b2defe598c951ef542b12360e1356037ce76'; },
  ]) {
    const changed = structuredClone(original); update(changed);
    assert.equal(validCheckOutcome(changed), false);
  }
});


test('independent unused Parameter fixture requires closed facts and original declaration custody', () => {
  const original = JSON.parse(readFileSync(new URL(
    './fixtures/check-unused-parameter.invalid.json', import.meta.url), 'utf8'));
  assert.equal(validCheckOutcome(original), true);
  const unlocated = structuredClone(original); delete unlocated.report.reasons[0].location;
  assert.equal(validCheckOutcome(unlocated), true);
  for (const update of [
    answer => { delete answer.report.reasons[0].facts; },
    answer => { answer.report.reasons[0].facts.value = 'private-default'; },
    answer => { answer.report.reasons[0].facts.expected_type = 'number'; },
    answer => { answer.report.reasons[0].facts.constraint = 'numeric'; },
    answer => { answer.report.reasons[0].location.document_id = 'parameters'; },
    answer => { answer.report.reasons[0].location = {kind: 'text', document_id: 'source',
      revision: `rev:${'5'.repeat(64)}`, start_byte: 0, end_byte: 1, precision: 'exact'}; },
    answer => { answer.report.reasons[0].location.revision = `rev:${'5'.repeat(64)}`; },
    answer => { answer.report.verdict = 'verified'; },
    answer => { answer.reason_schema_cid = 'sha256:ceb2a05aa8eee7b8c62fc9e734d5488e1c3b9ddd4fc57bbbd1b419cb2bb88261'; },
  ]) {
    const changed = structuredClone(original); update(changed);
    assert.equal(validCheckOutcome(changed), false);
  }
});

test('independent known reasons retain their original input domains', () => {
  // Authored independently: SELECT; {minimum: {type: 'number'}};
  // {minimum: 'wrong'}. Revisions are literal opaque fixture identities.
  const fixture = JSON.parse(readFileSync(new URL(
    './fixtures/check-location-domains.json', import.meta.url), 'utf8'));
  for (const {reason, allowedDocuments} of fixture.cases) {
    const requirement = reason.code === 'parameter_value_required';
    const report = {context_ref: 'ctx:independent-location-domain',
      scope: {kind: 'bound_input'}, inputs: fixture.inputs,
      verdict: requirement ? 'undetermined' : 'invalid',
      reasons: requirement ? [] : [reason], requirements: requirement ? [reason] : [],
      coverage: {limits: requirement ? [{code: 'bound_values_missing'}] : [], unresolved: []}};
    const outcome = report => ({version: 'actql-check-outcome/0.1',
      reason_schema_cid: fixture.reason_schema_cid, outcome_schema_cid: fixture.outcome_schema_cid, outcome: 'completed', report});
    assert.equal(validCheckOutcome(outcome(report)), true, 'Unavailable positions remain optional.');
    for (const document of fixture.inputs) {
      const location = {kind: document.kind, document_id: document.document_id,
        revision: document.revision, ...(document.kind === 'text'
          ? {start_byte: 6, end_byte: 6, precision: 'exact'} : {pointer: '/minimum'})};
      const located = {...reason, location};
      const locatedReport = {...report, reasons: requirement ? [] : [located],
        requirements: requirement ? [located] : []};
      const expected = allowedDocuments.includes(document.document_id);
      const complete = outcome(locatedReport);
      const partial = {version: complete.version, reason_schema_cid: complete.reason_schema_cid, outcome_schema_cid: complete.outcome_schema_cid,
        outcome: 'failed', correlation_ref: 'corr:fixture', problem: {code: 'check_internal'}, partial_report: locatedReport};
      assert.equal(validCheckOutcome(complete), expected,
        `${reason.code}: ${document.document_id} completed`);
      assert.equal(validCheckOutcome(partial), expected,
        `${reason.code}: ${document.document_id} partial`);
    }
  }
});

test('independent frame reasons reject malformed facts and foreign locations', () => {
  const reason = JSON.parse(readFileSync(new URL('./fixtures/check-frame-reason.json', import.meta.url), 'utf8'));
  const original = JSON.parse(readFileSync(new URL('./fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const outcome = value => ({...original, report: {...original.report, verdict: 'invalid', reasons: [value]}});
  assert.equal(validCheckOutcome(outcome(reason)), true);
  for (const invalid of [
    {code: reason.code}, {...reason, facts: {}},
    {...reason, facts: {issue: 'reversed_preceding'}},
    {...reason, facts: {issue: 'invalid_bounds', requirement_index: 0}},
    {...reason, facts: {issue: 'expected_boolean'}},
    {...reason, location: {kind: 'structured', document_id: 'parameters',
      revision: original.report.inputs[0].revision, pointer: ''}},
    {code: 'future_frame_reason', facts: reason.facts},
  ]) assert.equal(validCheckOutcome(outcome(invalid)), false);
  assert.equal(validCheckOutcome(outcome({code: 'future_frame_reason'})), true);
});

test('independent check envelopes require outcome identity and safe Problem correlation', () => {
  for (const name of ['check-reporting-failure.json', 'check-outcome-pins.verified.json']) {
    const original = JSON.parse(readFileSync(new URL(`./fixtures/${name}`, import.meta.url), 'utf8'));
    assert.equal(validCheckOutcome(original), true);
    for (const change of [
      value => { delete value.outcome_schema_cid; },
      value => { value.outcome_schema_cid = 'sha256:' + '0'.repeat(64); },
      value => { value.outcome_schema_cid = value.reason_schema_cid; },
      value => { value.outcome_schema_cid = 'sha256:3022a1bfadaab076c2fb116ccdca5de59451dd349fb6df6cc3adcd7905675cb0'; },
    ]) {
      const changed = structuredClone(original); change(changed);
      assert.equal(validCheckOutcome(changed), false);
    }
    if (original.outcome === 'failed') {
      for (const correlation of [undefined, '', 'a'.repeat(129), 'private value\n']) {
        const changed = {...original, correlation_ref: correlation};
        if (correlation === undefined) delete changed.correlation_ref;
        assert.equal(validCheckOutcome(changed), false);
      }
      assert.equal(validCheckOutcome({...original, report: {verdict: 'verified'}}), false);
    } else {
      assert.equal(validCheckOutcome({...original, correlation_ref: 'corr:unrelated'}), false);
    }
  }
});

test('independent operation parameter reasons retain closed domains and input locations', () => {
  const reasons = JSON.parse(readFileSync(new URL('./fixtures/check-operation-parameter-reasons.json', import.meta.url), 'utf8'));
  const original = JSON.parse(readFileSync(new URL('./fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const outcome = reason => ({...original, report: {...original.report, verdict: 'invalid', reasons: [reason]}});
  for (const reason of reasons) {
    assert.equal(validCheckOutcome(outcome(reason)), true);
    for (const invalid of [{code: reason.code}, {...reason, facts: {}},
      {...reason, facts: {...reason.facts, domain: 'private_provider_domain'}},
      {...reason, facts: {...reason.facts, value: 0}},
      {...reason, facts: {...reason.facts, requirement_index: 0}},
      {code: 'parameter_undeclared', facts: reason.facts},
      {code: 'future_operation_parameter', facts: reason.facts},
      {...reason, location: {kind: 'text', document_id: 'source',
        revision: original.report.inputs[0].revision, start_byte: 0, end_byte: 1, precision: 'exact'}}]) {
      assert.equal(validCheckOutcome(outcome(invalid)), false);
    }
  }
  assert.equal(validCheckOutcome(outcome({code: 'future_operation_parameter'})), true);
  for (const prior of [
    {reason_schema_cid: 'sha256:15d4d9b93f6e22c50256271ba09d09ba5da6a2a7105e118af2ad224a0591feac'},
    {outcome_schema_cid: 'sha256:506730273187b8d1bb3b7a5bd1a446eaffe3007da615c637bd461743e4e0a1b6'},
  ]) assert.equal(validCheckOutcome({...outcome(reasons[0]), ...prior}), false);
});

test('independent expression type reasons reject values and foreign fact families', () => {
  const reasons = JSON.parse(readFileSync(new URL('./fixtures/check-expression-types.json', import.meta.url), 'utf8'));
  const original = JSON.parse(readFileSync(new URL('./fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const outcome = reason => ({...original, report: {...original.report, verdict: 'invalid', reasons: [reason]}});
  for (const reason of reasons) {
    assert.equal(validCheckOutcome(outcome(reason)), true);
    for (const facts of [undefined, {}, {expected_type: 'private_field'},
      {expected_type: 'array'}, {...reason.facts, parameter: 'private_parameter'},
      {...reason.facts, actual_value: 'private-value'}, {...reason.facts, actual_type: 'string'}]) {
      assert.equal(validCheckOutcome(outcome({...reason, facts})), false);
    }
    assert.equal(validCheckOutcome(outcome({code: 'parameter_value_required', facts: reason.facts})), false);
    assert.equal(validCheckOutcome(outcome({code: 'future_expression_type', facts: reason.facts})), false);
    assert.equal(validCheckOutcome(outcome({...reason, location: {kind: 'structured', document_id: 'source',
      revision: original.report.inputs[0].revision, pointer: '/stages/0/steps/0'}})), false);
    assert.equal(validCheckOutcome(outcome({...reason, location: {kind: 'text', document_id: 'parameters',
      revision: original.report.inputs[0].revision, start_byte: 0, end_byte: 1, precision: 'exact'}})), false);
  }
  assert.equal(validCheckOutcome(outcome({code: 'future_expression_type'})), true);
  for (const prior of [
    {reason_schema_cid: 'sha256:3204b8f2edb377120d3139f380fc3c49541ff34b7117430de4ed52e0f826025f'},
    {outcome_schema_cid: 'sha256:e82160288635a2047646ae956dbba116224b1c64b03231b6c4245d43a6cecc5c'},
  ]) assert.equal(validCheckOutcome({...outcome(reasons[0]), ...prior}), false);
});

test('check request snapshots refuse lossy numbers and detach without normalization', () => {
  for (const value of [NaN, Infinity, -Infinity, -0, new Number(NaN),
    new Number(-0), {toJSON: () => Infinity}, {toJSON: () => -0},
    Object.assign(new Number(1), {valueOf: () => NaN}),
    Object.assign(new Number(1), {[Symbol.toPrimitive]: () => -0})]) {
    assert.throws(() => snapshotCheckRequest({parameters: {x: {nested: [value]}}}), TypeError);
  }
  let coerced = 0;
  const number = Object.assign(new Number(1), {valueOf: () => {coerced++; return 3.5;}});
  assert.deepEqual(snapshotCheckRequest({parameters: {x: number}}), {parameters: {x: 3.5}});
  assert.equal(coerced, 1);
  const input = {input: {text: '/*😀*/\r\nSELECT @x AS n', format: 'sql'},
    parameters: {'e\u0301/~': [0, null, 1.25, -2, Number.MAX_VALUE, Number.MIN_VALUE]}};
  const copy = snapshotCheckRequest(input);
  assert.deepEqual(copy, input);
  input.parameters['e\u0301/~'][0] = 9;
  assert.equal(copy.parameters['e\u0301/~'][0], 0);
  let nested = 'leaf';
  for (let i = 0; i < 70; i++) nested = [nested];
  assert.deepEqual(snapshotCheckRequest({parameters: {x: nested}}), {parameters: {x: nested}});
});

test('independent binding JSON reasons require owned documents and closed parser facts', () => {
  const fixture = JSON.parse(readFileSync(new URL('./fixtures/check-binding-json-reasons.json', import.meta.url), 'utf8'));
  const source = {document_id: 'source', kind: 'text', revision: 'rev:' + '1'.repeat(64), byte_length: 8};
  const revision = 'rev:' + '2'.repeat(64);
  const outcome = (document, reason) => ({version: 'actql-check-outcome/0.1',
    reason_schema_cid: fixture.reason_schema_cid, outcome_schema_cid: fixture.outcome_schema_cid,
    outcome: 'completed', report: {context_ref: 'ctx:independent-json-reasons',
      scope: {kind: 'bound_input'}, verdict: 'invalid',
      inputs: [source, ...fixture.documents.map(document_id =>
        ({document_id, kind: 'structured', revision, byte_length: 2}))],
      reasons: [reason], requirements: [], coverage: {limits: [], unresolved: []}}});
  for (const document of fixture.documents) {
    for (const issue of fixture.issues) {
      const reason = {code: 'binding_json_invalid', facts: {document, issue},
        location: {kind: 'structured', document_id: document, revision, pointer: ''}};
      assert.equal(validCheckOutcome(outcome(document, reason)), true);
      for (const invalid of [
        {code: reason.code}, {...reason, facts: {issue}}, {...reason, facts: {document}},
        {...reason, facts: {document: 'source', issue}},
        {...reason, facts: {document, issue: 'depth_limit'}},
        {...reason, facts: {document, issue, key: 'private-key'}},
        {...reason, facts: {document, issue: 'future_json_issue'}},
        {...reason, location: {...reason.location, document_id: document === 'parameters' ? 'parameter_declarations' : 'parameters'}},
        {code: 'future_json_reason', facts: reason.facts},
      ]) assert.equal(validCheckOutcome(outcome(document, invalid)), false,
        '[check-mutation:json-facts-schema]');
      assert.equal(validCheckOutcome(outcome(document, {code: 'future_json_reason'})), true);
    }
  }
});

test('located implementation limits bind source revisions and reject malformed material', () => {
  const outcome = JSON.parse(readFileSync(new URL('./fixtures/check-outcome-pins.verified.json', import.meta.url), 'utf8'));
  const source = outcome.report.inputs[0];
  outcome.report.verdict = 'undetermined';
  outcome.report.coverage.limits = [{code: 'implementation_limit',
    facts: {issue: 'function_lowering_unresolved'}, location: {kind: 'text', document_id: 'source',
      revision: source.revision, precision: 'exact', start_byte: 0, end_byte: source.byte_length}}];
  assert.equal(validCheckOutcome(outcome), true);
  for (const mutate of [
    value => {value.facts.issue = 'unknown_reference';},
    value => {value.facts.issue = 42;},
    value => {value.facts.private_name = 'private-function-name';},
    value => {value.location.revision = 'rev:' + '0'.repeat(64);},
    value => {value.location.end_byte = source.byte_length + 1;},
  ]) {
    const corrupt = structuredClone(outcome); mutate(corrupt.report.coverage.limits[0]);
    assert.equal(validCheckOutcome(corrupt), false);
  }
});
