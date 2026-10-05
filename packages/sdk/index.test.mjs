import './check-locations.test.mjs';
import './effect-uncertainty.test.mjs';
import test, {mock} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {createServer} from 'node:http';
import {checkReasonSchemaCid} from '@actql/client-wire';
import {connect, ClientError, getCheckInput, getSubmissionInput, explainSubmission, resolveCheckLocation, explainCheckReason} from './index.mjs';

test('constraint explanations use owned families without choosing a failed numeric bound', () => {
  const hints = {
    numeric: 'Supply a number satisfying the declared integer, minimum and maximum constraints.',
    duration: 'Supply a string in the admitted duration format.',
    array_length: 'Supply an array with the declared exact length.',
    array_size: 'Supply an array within the declared maximum item count.',
  };
  for (const [constraint, hint] of Object.entries(hints)) {
    assert.deepEqual(explainCheckReason({code: 'supplied_value_constraint_violation',
      facts: {parameter: 'private-name', constraint}}),
    {kind: 'known', summary: 'A supplied value violates a declared constraint.', hint});
  }
  assert.equal(explainCheckReason({code: 'future_code', facts: {constraint: 'numeric'}}).kind, 'unknown');
  assert.equal(explainCheckReason({code: 'supplied_value_constraint_violation',
    facts: {constraint: 'private-provider-text'}}).hint,
  'Correct the value to satisfy the declared constraint family.');
});

test('Graph explanations require a known operation and owned issue', () => {
  assert.deepEqual(explainCheckReason({code: 'graph_operation_invalid',
    facts: {operation: 'components', issue: 'invalid_kind'}}),
  {kind: 'known', summary: 'The components kind is invalid.',
    hint: 'Choose weak or strong for components kind.'});
  assert.deepEqual(explainCheckReason({code: 'graph_operation_invalid',
    facts: {operation: 'components', issue: 'invalid_output_rows'}}),
  {kind: 'known', summary: 'The components output row limit is invalid.',
    hint: 'Supply a positive safe integer for components max_output_rows.'});
  for (const facts of [undefined, {}, {issue: 'invalid_kind'},
    {operation: 'future_operation', issue: 'invalid_kind'},
    {operation: 'components', issue: 'private_provider_text'}]) {
    assert.deepEqual(explainCheckReason({code: 'graph_operation_invalid', facts}),
      {kind: 'unknown', summary: 'No supported explanation is available for this reason.'});
  }
});

const ref = Object.freeze({namespaceId: 'namespace-a',
  authorityScopeCid: `sha256:${'a'.repeat(64)}`,
  runDefinitionCid: `sha256:${'b'.repeat(64)}`});
const profile = Object.freeze({version: 'actql-client-host/0.1',
  mode: 'remote', owner: 'remote', durability: 'durable',
  scopeRef: 'scope-a', capabilities: ['aql-document', 'result-jsonl'],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10,
    maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}});
const admission = Object.freeze({ref, durability: 'durable', revision: 4});
const state = Object.freeze({version: 'actql-run-state/0.1',
  run_id: 'run-a', status: 'succeeded',
  updated_at: '2026-09-24T00:00:00.000Z',
  next_action: {kind: 'refresh_availability', results: ['answer']},
  result_available: false,
  result_availability: {answer: {
    state: 'unknown', observed_at: '2026-09-24T00:00:00.000Z',
    reason: 'verification_pending'}}});
const options = {mode: 'remote', endpoint: 'https://host.example/',
  token: () => 'scoped-token'};
const oversizedControl = cancelled => new Response(new ReadableStream({
  start(controller) {
    controller.enqueue(new Uint8Array(1024 * 1024));
    controller.enqueue(new Uint8Array([123]));
  },
  cancel() { cancelled.push(true); },
}));

test('check refuses source coercion before serialization or transport', async t => {
  let sent = 0;
  mock.method(globalThis, 'fetch', async url => {
    assert.ok(url.pathname.endsWith('/connect'));
    sent++;
    return Response.json(profile);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.check({toJSON() { assert.fail('source coercion'); }},
    {format: 'sql'}), {code: 'InvalidCheckRequest'});
  assert.equal(sent, 1);
});

test('check rejects a location inside an original UTF-8 scalar', async t => {
  const revision = 'rev:' + '4'.repeat(64);
  let start = 9;
  mock.method(globalThis, 'fetch', async url => url.pathname.endsWith('/connect')
    ? Response.json(profile) : Response.json({version: 'actql-check-outcome/0.1',
      reason_schema_cid: checkReasonSchemaCid, outcome: 'completed', report: {
        context_ref: 'ctx:fixture', scope: {kind: 'bound_input'}, verdict: 'invalid',
        inputs: [{document_id: 'source', kind: 'text', revision, byte_length: 18}],
        reasons: [{code: 'query_syntax_invalid', location: {kind: 'text',
          document_id: 'source', revision, start_byte: start, end_byte: 12,
          precision: 'exact'}}], requirements: [], coverage: {limits: [], unresolved: []}}}));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.check("SELECT '😀' AS n", {format: 'sql'}),
    {code: 'InvalidHostCheckOutcome'});
  start = 8;
  const result = await client.check("SELECT '😀' AS n", {format: 'sql'});
  assert.equal(resolveCheckLocation(result, result.report.reasons[0].location).text, '😀');
  assert.equal(resolveCheckLocation(result,
    {...result.report.reasons[0].location, revision: undefined}), undefined);
  assert.equal(resolveCheckLocation(result,
    {...result.report.reasons[0].location, revision: 'rev:' + '5'.repeat(64)}), undefined);
});

test('review wire budget covers maximum base64 without relaxing body limits',
  async t => {
    const maximum = 1024 * 1024;
    let content = Buffer.alloc(maximum, 97);
    const checkpointCid = `sha256:${'c'.repeat(64)}`;
    mock.method(globalThis, 'fetch', async url => {
      if (url.pathname.endsWith('/connect')) return Response.json(profile);
      return Response.json({kind: 'review', checkpointCid,
        artifactCid: `sha256:${createHash('sha256').update(content).digest('hex')}`,
        byteLength: content.length, contentBase64: content.toString('base64')});
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    const result = await client.reviewCheckpoint(checkpointCid,
      {maxBytes: maximum});
    assert.deepEqual(Buffer.from(result.bytes), content);
    assert.ok(content.toString('base64').length > maximum);
    content = Buffer.alloc(maximum + 1, 97);
    await assert.rejects(client.reviewCheckpoint(checkpointCid,
      {maxBytes: maximum}), {code: 'InvalidHostCheckpointReview'});
  });

test('check refuses a Host verdict that contradicts its own evidence',
  async t => {
    const version = 'actql-check-outcome/0.1';
    const report = (verdict, reasons, limits, unresolved) => ({version, reason_schema_cid: checkReasonSchemaCid,
      outcome: 'completed', report: {context_ref: 'ctx:a', requirements: [], inputs: [{document_id: 'source', revision: 'rev:' + '1'.repeat(64), kind: 'text', byte_length: 13}],
        scope: {kind: 'bound_input'}, verdict, reasons,
        coverage: {limits, unresolved}}});
    const limit = [{code: 'analysis_budget_exhausted'}];
    const open = [{boundary: 'source_resolution',
      reason: 'unresolved_protected'}];
    const violation = [{code: 'supplied_value_invalid'}];
    let reply;
    mock.method(globalThis, 'fetch', async url =>
      url.pathname.endsWith('/connect') ? Response.json(profile)
        : Response.json(reply));
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    const check = () => client.check('SELECT 1 AS n', {format: 'sql'});
    for (const inconsistent of [
      report('verified', [], limit, open),
      report('verified', [], limit, []),
      report('verified', [], [], open),
      report('verified', violation, [], []),
      report('invalid', [], limit, []),
      report('undetermined', violation, limit, []),
      report('undetermined', [], [], []),
      {version, reason_schema_cid: checkReasonSchemaCid, outcome: 'failed', problem: {code: 'check_internal'},
        partial_report: report('invalid', [], [], open).report},
    ]) {
      reply = inconsistent;
      await assert.rejects(check(), {code: 'InvalidHostCheckOutcome'},
        JSON.stringify(inconsistent));
    }
    // Consistent outcomes are admitted, including codes this Client does not
    // know yet.
    for (const consistent of [
      report('verified', [], [], []),
      report('invalid', [{code: 'later_violation'}], limit, open),
      report('undetermined', [], [{code: 'later_limit'}], []),
    ]) {
      reply = consistent;
      assert.deepEqual(await check(), consistent);
    }
  });

test('peek bounds decoded JSON independently of escaped wire size', async t => {
  const maximum = 4 * 1024 * 1024;
  const prefix = JSON.stringify([{value: '\\"日本語'.repeat(120000)}]);
  let rowsJson = prefix.slice(0, -3) +
    'a'.repeat(maximum - Buffer.byteLength(prefix)) + prefix.slice(-3);
  assert.equal(Buffer.byteLength(rowsJson), maximum);
  assert.ok(Buffer.byteLength(JSON.stringify(rowsJson)) > maximum);
  mock.method(globalThis, 'fetch', async url =>
    url.pathname.endsWith('/connect') ? Response.json(profile) :
      Response.json({resourceConnection: 'connection', resource: 'resource',
        observationCid: `sha256:${'c'.repeat(64)}`, fields: ['value'],
        rowsJson, limited: false}));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.deepEqual((await client.peekResource('connection', 'resource',
    {fields: ['value'], maxBytes: maximum})).rows, JSON.parse(rowsJson));
  rowsJson = rowsJson.slice(0, -3) + 'a' + rowsJson.slice(-3);
  await assert.rejects(client.peekResource('connection', 'resource',
    {fields: ['value'], maxBytes: maximum}), {code: 'InvalidHostResourcePeek'});
});

test('review wire cap cancels an oversized stream despite a short length header',
  async t => {
    let cancelled = 0;
    mock.method(globalThis, 'fetch', async url => {
      if (url.pathname.endsWith('/connect')) return Response.json(profile);
      return new Response(new ReadableStream({
        start(controller) { controller.enqueue(new Uint8Array(4096)); },
        cancel() { cancelled++; },
      }), {headers: {'content-length': '1'}});
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    await assert.rejects(client.reviewCheckpoint(`sha256:${'c'.repeat(64)}`,
      {maxBytes: 1}), error => error.code === 'ReviewReadUnknown' &&
        error.cause.message === 'HostControlResponseLimit');
    assert.equal(cancelled, 1);
  });

test('control responses are bounded and uncertain submit keeps its ID',
  async t => {
    const cancelled = [];
    let reply = oversizedControl(cancelled);
    const requests = [];
    mock.method(globalThis, 'fetch', async url => {
      requests.push(url.pathname.split('/').at(-1));
      return requests.at(-1) === 'connect' && requests.length > 1
        ? Response.json(profile) : reply;
    });
    t.after(() => mock.restoreAll());
    await assert.rejects(connect(options), {code: 'InvalidHostProfile'});
    assert.equal(cancelled.length, 1);
    reply = oversizedControl(cancelled);
    const client = await connect(options);
    await assert.rejects(client.start({version: 'actql/0.1'},
      {requestId: 'saved-control-id'}), error =>
      error.code === 'SubmissionUnknown' &&
      error.requestId === 'saved-control-id');
    assert.equal(cancelled.length, 2);
    assert.deepEqual(requests, ['connect', 'connect', 'submit']);
  });

test('bounded control reads cover attach, status and error responses',
  async t => {
    const cancelled = [];
    let operationReply = Response.json(admission);
    mock.method(globalThis, 'fetch', async url => {
      const operation = url.pathname.split('/').at(-1);
      return operation === 'connect' ? Response.json(profile) : operationReply;
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    operationReply = oversizedControl(cancelled);
    await assert.rejects(client.attach(ref), {code: 'InvalidHostAdmission'});
    operationReply = Response.json(admission);
    const execution = await client.attach(ref);
    operationReply = oversizedControl(cancelled);
    await assert.rejects(execution.status(), {code: 'InvalidHostResponse'});
    operationReply = new Response(oversizedControl(cancelled).body,
      {status: 503});
    await assert.rejects(client.start({version: 'actql/0.1'},
      {requestId: 'saved-error-id'}), error =>
      error.code === 'SubmissionUnknown' &&
      error.requestId === 'saved-error-id');
    assert.equal(cancelled.length, 3);
  });

test('document submit, attach and reads use one reference without replay', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push({operation, body: JSON.parse(init.body), headers: init.headers});
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'submit' || operation === 'attach') {
      return Response.json(admission);
    }
    if (operation === 'status') return Response.json(state);
    if (operation === 'read') {
      return new Response('{"n":1}\n{"n":2}\n\x1e',
        {headers: {'content-type': 'application/x-ndjson'}});
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.equal(client.profile.durability, 'durable');
  const execution = await client.aql('{"version":"actql/0.1"}',
    {format: 'json', requestId: 'request-a'});
  assert.deepEqual(execution.ref, ref);
  assert.deepEqual(await execution.status(), state);
  const result = execution.result('answer');
  const reader = result.rows();
  assert.equal(reader.state(), 'not_started');
  assert.deepEqual(await Array.fromAsync(reader), [{n: 1}, {n: 2}]);
  assert.equal(reader.state(), 'complete');
  assert.deepEqual(await result.all(), [{n: 1}, {n: 2}]);
  const restored = await client.attach(ref);
  assert.deepEqual(await restored.status(), state);
  const reads = requests.filter(value => value.operation === 'read');
  assert.equal(requests.filter(value => value.operation === 'submit').length, 1);
  assert.equal(reads.length, 2);
  assert.notEqual(reads[0].body.attemptId, reads[1].body.attemptId);
  assert.equal(reads[0].headers.authorization, 'Bearer scoped-token');
  assert.deepEqual(requests.find(value => value.operation === 'submit').body,
    {connection: {mode: 'remote', owner: 'remote', consentRefs: [],
      runners: []}, requestId: 'request-a', kind: 'aql',
    input: {text: '{"version":"actql/0.1"}', format: 'json'},
    parameters: null});
});

test('query declarations travel with source without entering the SDK',
  async t => {
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      return Response.json(operation === 'connect' ? profile : admission);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    await client.aql('SELECT id FROM records WHERE id = @p', {
      format: 'sql', parameterDeclarations: {p: {type: 'number'}},
      parameters: {p: 1}, requestId: 'saved-query-id',
    });
    assert.deepEqual(requests[1].body, {
      connection: {mode: 'remote', owner: 'remote', consentRefs: [],
        runners: []}, requestId: 'saved-query-id', kind: 'aql',
      input: {text: 'SELECT id FROM records WHERE id = @p', format: 'sql',
        parameterDeclarations: {p: {type: 'number'}}},
      parameters: {p: 1},
    });
    await assert.rejects(client.aql('{}', {format: 'json',
      parameterDeclarations: {p: {type: 'number'}}}),
    {code: 'InvalidAqlDocument'});
    assert.equal(requests.length, 2);
  });

test('confirmed query input refusal stays typed after HTTP submit', async t => {
  const operations = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    operations.push(operation);
    return operation === 'connect' ? Response.json(profile) :
      Response.json({code: 'ClientProgramInvalidInput'}, {status: 400});
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.aql('SELECT @missing FROM records', {
    format: 'sql', requestId: 'saved-invalid-query',
  }), {code: 'ClientProgramInvalidInput'});
  assert.deepEqual(operations, ['connect', 'submit']);
});

test('status and wait reject malformed Host state replies', async t => {
  let reply = state;
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'status' || operation === 'wait') {
      return Response.json(reply);
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const execution = await (await connect(options)).attach(ref);
  assert.deepEqual(await execution.status(), state);
  assert.deepEqual(await execution.wait(), state);
  reply = {...state, status: 'not_an_engine_state'};
  await assert.rejects(execution.status(), {code: 'InvalidHostRunState'});
  await assert.rejects(execution.wait(), {code: 'InvalidHostRunState'});
});

test('Run reconciliation validates state without submitting computation', async t => {
  const requests = [];
  let reply = {...state, status: 'needs_reconciliation',
    next_action: {kind: 'reconcile_run', reason: 'execution_unknown'}};
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'reconcile') return Response.json(reply);
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const execution = await (await connect(options)).attach(ref);
  assert.deepEqual(await execution.reconcile(), reply);
  reply = {...reply, next_action: {kind: 'reconcile_run'}};
  await assert.rejects(execution.reconcile(), {code: 'InvalidHostRunState'});
  reply = {...state, status: 'needs_reconciliation',
    next_action: {kind: 'reconcile', effects: ['write']}};
  assert.deepEqual(await execution.reconcile(), reply);
  assert.deepEqual(requests, ['connect', 'attach', 'reconcile',
    'reconcile', 'reconcile']);
});

test('unknown submit carries one fixed request ID and lookup never submits', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push({operation, body: JSON.parse(init.body)});
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'submit') throw new Error('ACK lost');
    if (operation === 'lookup-request') {
      return Response.json({kind: 'unknown', reason: 'query_failed'});
    }
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  let requestId;
  await assert.rejects(client.start({version: 'actql/0.1'}), error => {
    assert.equal(error.code, 'SubmissionUnknown');
    assert.ok(error.requestId);
    assert.equal(error.lookupContext.scopeRef, 'scope-a');
    requestId = error.requestId;
    return true;
  });
  assert.equal(requests[1].body.requestId, requestId);
  assert.deepEqual(await client.lookupRequest(requestId),
    {kind: 'unknown', reason: 'query_failed'});
  assert.deepEqual(requests.map(value => value.operation),
    ['connect', 'submit', 'lookup-request']);
});

test('read limits reject complete collection without cancelling the Run', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async (url, init) => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n{"n":2}\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  const result = (await client.attach(ref)).result('answer');
  await assert.rejects(result.all({maxRows: 1}), error =>
    error.code === 'ResultRetainedLimit' && !!error.attemptId);
  assert.deepEqual(requests, ['connect', 'attach', 'read']);
});

test('stopping a row reader releases only its delivery stream', async t => {
  const requests = [];
  const cancelled = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new TextEncoder().encode('{"n":1}\n')); },
      cancel() { cancelled.push(true); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  for await (const row of reader) {
    assert.deepEqual(row, {n: 1});
    break;
  }
  assert.equal(reader.state(), 'prefix');
  assert.deepEqual(cancelled, [true]);
  assert.deepEqual(requests, ['connect', 'attach', 'read']);
});

test('a wire-limit failure releases the unfinished delivery stream', async t => {
  const cancelled = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new Uint8Array(32).fill(120)); },
      cancel() { cancelled.push(true); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxWireBytes: 16});
  await assert.rejects(Array.fromAsync(reader), error =>
    error.code === 'ResultWireLimit' &&
    error.attemptId === reader.attemptId);
  assert.equal(reader.state(), 'prefix');
  assert.deepEqual(cancelled, [true]);
});

test('a failed stream cancellation does not erase the read failure', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(new ReadableStream({
      start(controller) { controller.enqueue(
        new Uint8Array(32).fill(120)); },
      cancel() { throw new Error('physical cleanup failed'); },
    }));
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxWireBytes: 16});
  await assert.rejects(Array.fromAsync(reader), error =>
    error.code === 'ResultWireLimit' &&
    error.attemptId === reader.attemptId &&
    error.cleanupError?.message === 'physical cleanup failed');
});

test('row wire and retained-value limits are independent', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    requests.push(operation);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  await assert.rejects(result.all({maxRowWireBytes: 6}), error =>
    error.code === 'ResultRowWireLimit' && !!error.attemptId);
  await assert.rejects(result.all({maxRowRetainedValueBytes: 7}), error =>
    error.code === 'ResultRowRetainedLimit' && !!error.attemptId);
  assert.deepEqual(await result.all({maxRowWireBytes: 7,
    maxRowRetainedValueBytes: 1024}), [{n: 1}]);
  assert.deepEqual(requests, ['connect', 'attach', 'read', 'read', 'read']);
});

test('hybrid options are snapshotted and durable requests cannot downgrade', async t => {
  let sent;
  mock.method(globalThis, 'fetch', async (_url, init) => {
    sent = JSON.parse(init.body);
    return Response.json({...profile, mode: 'hybrid', owner: 'cloud',
      durability: 'volatile'});
  });
  t.after(() => mock.restoreAll());
  const selected = {mode: 'hybrid', owner: 'cloud',
    endpoint: 'https://host.example/', token: 'token',
    movementPolicyRef: 'policy-a', runners: ['runner-a'],
    consentRefs: ['grant-a'], durability: 'durable'};
  await assert.rejects(connect(selected), {code: 'InvalidHostProfile'});
  selected.runners.push('runner-b');
  assert.deepEqual(sent.connection.runners, ['runner-a']);
  assert.deepEqual(sent.connection.consentRefs, ['grant-a']);
});

test('local-owned Hybrid identifies Cloud assistance without changing owner',
  async t => {
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      requests.push({operation: url.pathname.split('/').at(-1),
        body: JSON.parse(init.body)});
      return Response.json({...profile, mode: 'hybrid', owner: 'local'});
    });
    t.after(() => mock.restoreAll());
    const selected = {mode: 'hybrid', owner: 'local',
      endpoint: 'https://local-host.example/', token: 'local-token',
      movementPolicyRef: 'movement-a',
      cloudConnectionRef: 'registered-cloud-a',
      consentRefs: ['grant-a']};
    const client = await connect(selected);
    assert.equal(client.profile.owner, 'local');
    assert.deepEqual(requests[0].body.connection, {
      mode: 'hybrid', owner: 'local', consentRefs: ['grant-a'],
      runners: [], movementPolicyRef: 'movement-a',
      cloudConnectionRef: 'registered-cloud-a',
    });
    await assert.rejects(connect({...selected,
      cloudConnectionRef: undefined}), {code: 'InvalidHybridConnection'});
    await assert.rejects(connect({...selected, mode: 'remote',
      owner: undefined}), {code: 'InvalidHybridConnection'});
    await assert.rejects(connect({...selected, owner: 'cloud'}),
      {code: 'InvalidHybridConnection'});
  });

test('one query and Result path serves each connected ownership profile',
  async t => {
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      const body = JSON.parse(init.body);
      requests.push({operation, body});
      if (operation === 'connect') return Response.json({...profile,
        mode: body.connection.mode, owner: body.connection.owner});
      if (operation === 'submit') return Response.json(admission);
      if (operation === 'read') return new Response('{"id":1}\n\x1e');
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const connected = [
      options,
      {mode: 'local', owner: 'local',
        endpoint: 'https://local.example/', token: 'token'},
      {mode: 'hybrid', owner: 'cloud',
        endpoint: 'https://cloud.example/', token: 'token',
        runners: ['runner-a'], movementPolicyRef: 'movement-a'},
      {mode: 'hybrid', owner: 'local',
        endpoint: 'https://local.example/', token: 'token',
        cloudConnectionRef: 'registered-cloud-a',
        movementPolicyRef: 'movement-a'},
    ];
    const query = async connection => {
      const client = await connect(connection);
      const execution = await client.aql('{"version":"actql/0.1"}',
        {format: 'json'});
      const values = await execution.result('answer').all();
      client.close();
      return values;
    };
    for (const connection of connected) {
      assert.deepEqual(await query(connection), [{id: 1}]);
    }
    assert.equal(requests.filter(item => item.operation === 'submit').length,
      connected.length);
    assert.equal(requests.filter(item => item.operation === 'read').length,
      connected.length);
  });

test('invalid refs and unsafe endpoints are rejected before transport', async t => {
  for (const endpoint of ['http://host.example/',
    'https://user:secret@host.example/',
    'https://host.example/?token=secret']) {
    await assert.rejects(connect({...options, endpoint}), ClientError);
  }
  mock.method(globalThis, 'fetch', async () => Response.json(profile));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.attach({...ref, authorityScopeCid: 'bad'}),
    {code: 'InvalidRunReference'});
});

test('attach rejects each foreign Run reference before status or read',
  async t => {
    let returned = ref;
    const operations = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      operations.push(operation);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json({
        ...admission, ref: returned});
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    for (const field of ['namespaceId', 'authorityScopeCid',
      'runDefinitionCid']) {
      returned = {...ref, [field]: field === 'namespaceId' ? 'namespace-b' :
        `sha256:${'c'.repeat(64)}`};
      await assert.rejects(client.attach(ref),
        {code: 'ForeignHostAdmission'});
    }
    returned = ref;
    assert.deepEqual((await client.attach(ref)).ref, ref);
    assert.deepEqual(operations,
      ['connect', 'attach', 'attach', 'attach', 'attach']);
  });

test('attach snapshots the requested reference before async credentials',
  async t => {
    let releaseCredential;
    let credentialCalls = 0;
    let sent;
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') {
        sent = JSON.parse(init.body).ref;
        return Response.json(admission);
      }
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const client = await connect({...options, token: () => {
      credentialCalls++;
      return credentialCalls === 1 ? 'scoped-token' :
        new Promise(resolve => { releaseCredential = resolve; });
    }});
    const mutable = {...ref};
    const attached = client.attach(mutable);
    mutable.runDefinitionCid = `sha256:${'c'.repeat(64)}`;
    releaseCredential('scoped-token');
    assert.deepEqual((await attached).ref, ref);
    assert.deepEqual(sent, ref);
  });

test('a complete row prefix without the end marker remains incomplete', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  const seen = [];
  await assert.rejects(async () => {
    for await (const row of reader) seen.push(row);
  }, error => error.code === 'IncompleteResultStream' &&
    error.attemptId === reader.attemptId);
  assert.deepEqual(seen, [{n: 1}]);
  assert.equal(reader.state(), 'prefix');
});

test('a blank JSONL record fails after the delivered prefix', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response('{"n":1}\n\n\x1e');
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows();
  const seen = [];
  await assert.rejects(async () => {
    for await (const row of reader) seen.push(row);
  }, error => error.code === 'InvalidResultStream' &&
    error.attemptId === reader.attemptId);
  assert.deepEqual(seen, [{n: 1}]);
  assert.equal(reader.state(), 'prefix');
});

test('one transport chunk can contain many bounded rows', async t => {
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile);
    if (operation === 'attach') return Response.json(admission);
    if (operation === 'read') return new Response(
      `${Array.from({length: 40}, (_, n) => JSON.stringify({n}))
        .join('\n')}\n\x1e`);
    throw new Error(`unexpected ${operation}`);
  });
  t.after(() => mock.restoreAll());
  const result = (await (await connect(options)).attach(ref)).result('answer');
  const reader = result.rows({maxRowWireBytes: 8});
  assert.deepEqual(await Array.fromAsync(reader),
    Array.from({length: 40}, (_, n) => ({n})));
  assert.equal(reader.state(), 'complete');
});

test('malformed acceptance is unknown and preserves the original ID', async t => {
  mock.method(globalThis, 'fetch', async url =>
    url.pathname.endsWith('/connect')
      ? Response.json(profile) : Response.json({bad: true}));
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  assert.equal(client.requestedDurability, null);
  await assert.rejects(client.start({version: 'actql/0.1'},
    {requestId: 'saved-id'}), error =>
    error.code === 'SubmissionUnknown' && error.requestId === 'saved-id');
});

test('an unserializable Program is rejected before submit', async t => {
  const requests = [];
  mock.method(globalThis, 'fetch', async url => {
    requests.push(url.pathname.split('/').at(-1));
    return Response.json(profile);
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  await assert.rejects(client.start({value: 1n}),
    {code: 'InvalidClientPayload'});
  assert.deepEqual(requests, ['connect']);
});

test('submit fixes Program and parameters before asynchronous token lookup',
  async t => {
    let releaseToken;
    const delayedToken = new Promise(resolve => { releaseToken = resolve; });
    let tokenCalls = 0;
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      return Response.json(operation === 'connect' ? profile : admission);
    });
    t.after(() => mock.restoreAll());
    const client = await connect({...options,
      token: () => ++tokenCalls === 1 ? 'token' : delayedToken});
    const program = {version: 'actql/0.1', marker: 'original'};
    const parameters = {value: 'original'};
    const submitted = client.start(program, {
      requestId: 'saved-id', parameters,
    });
    program.marker = 'changed';
    parameters.value = 'changed';
    releaseToken('token');
    const execution = await submitted;
    assert.deepEqual(requests[1].body, {
      connection: {mode: 'remote', owner: 'remote',
        consentRefs: [], runners: []},
      requestId: 'saved-id', kind: 'program',
      input: {version: 'actql/0.1', marker: 'original'},
      parameters: {value: 'original'},
    });
    const snapshot = getSubmissionInput(execution);
    assert.deepEqual(snapshot.input, {version: 'actql/0.1', marker: 'original'});
    assert.deepEqual(snapshot.parameters, {value: 'original'});
    assert.equal(Object.isFrozen(snapshot.input), true);
    assert.equal(Object.isFrozen(snapshot.parameters), true);
    assert.equal(snapshot.lookupContext.endpoint, 'https://host.example/');
    assert.equal(snapshot.lookupContext.scopeRef, 'scope-a');
    assert.equal('token' in snapshot, false);
  });

test('overlapping unknown submits keep their own exact text and declarations', async t => {
  const waiting = new Map();
  mock.method(globalThis, 'fetch', async (url, init) => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile);
    const body = JSON.parse(init.body);
    return new Promise(resolve => waiting.set(body.requestId, resolve));
  });
  t.after(() => mock.restoreAll());
  const client = await connect(options);
  const text = 'SELECT "e\u0301"\r\nFROM @x';
  const declarations = {p: {type: 'String'}};
  const parameters = {p: 'original'};
  const first = client.aql(text, {format: 'sql', requestId: 'first',
    parameterDeclarations: declarations, parameters}).catch(error => error);
  const second = client.start({version: 'actql/0.1', marker: 'second'},
    {requestId: 'second', parameters: {p: 'second'}}).catch(error => error);
  declarations.p.type = 'Int';
  parameters.p = 'edited';
  await new Promise(resolve => setImmediate(resolve));
  waiting.get('second')(Response.json({bad: true}));
  const secondError = await second;
  waiting.get('first')(Response.json({bad: true}));
  const firstError = await first;
  assert.equal(firstError.code, 'SubmissionUnknown');
  assert.equal(secondError.code, 'SubmissionUnknown');
  assert.deepEqual(getSubmissionInput(firstError).input,
    {text, format: 'sql', parameterDeclarations: {p: {type: 'String'}}},
    '[check-mutation:submission-input]');
  assert.deepEqual(getSubmissionInput(firstError).parameters, {p: 'original'});
  assert.deepEqual(getSubmissionInput(secondError).input,
    {version: 'actql/0.1', marker: 'second'});
  assert.equal(getSubmissionInput(firstError).requestId, 'first');
  const firstExplanation = explainSubmission(firstError);
  assert.deepEqual(firstExplanation, {
    observation: 'acceptance_unknown',
    summary: 'Submission acceptance is unknown. Work may already have started.',
    next: {operation: 'lookupRequest', requestId: 'first',
      lookupContext: {endpoint: 'https://host.example/', scopeRef: 'scope-a'}},
  });
  assert.equal(explainSubmission(secondError).next.requestId, 'second');
  firstError.code = 'Accepted';
  firstError.requestId = 'second';
  firstError.message = 'Execution succeeded';
  assert.equal(explainSubmission(firstError), firstExplanation);
  assert.equal(Object.isFrozen(firstExplanation.next.lookupContext), true);
  assert.equal(explainSubmission({...firstError}), undefined);
  assert.equal(explainSubmission(JSON.parse(JSON.stringify(firstError))), undefined);
  assert.equal(getSubmissionInput(secondError).requestId, 'second');
  assert.equal(Object.isFrozen(getSubmissionInput(firstError).input.parameterDeclarations.p), true);
  assert.equal(getSubmissionInput({...firstError}), undefined);
  assert.equal(getSubmissionInput(JSON.parse(JSON.stringify(firstError))), undefined);
});

test('local credential and payload failures do not acquire submission input', async t => {
  const foreign = new Error('CredentialUnavailable');
  const operations = [];
  mock.method(globalThis, 'fetch', async url => {
    operations.push(url.pathname.split('/').at(-1));
    return Response.json(profile);
  });
  t.after(() => mock.restoreAll());
  let calls = 0;
  const client = await connect({...options, token: () => {
    if (++calls === 1) return 'token';
    throw foreign;
  }});
  for (const marker of ['first', 'second']) {
    await assert.rejects(client.start({marker}), error => error === foreign);
    assert.equal(getSubmissionInput(foreign), undefined);
    assert.equal(explainSubmission(foreign), undefined);
  }
  await assert.rejects(client.start({value: 1n}), error => {
    assert.equal(error.code, 'InvalidClientPayload');
    assert.equal(getSubmissionInput(error), undefined);
    assert.equal(explainSubmission(error), undefined);
    return true;
  });
  for (const value of [undefined, null, 1, 'error', {}, new ClientError('SubmissionUnknown')]) {
    assert.equal(getSubmissionInput(value), undefined);
    assert.equal(explainSubmission(value), undefined);
  }
  assert.deepEqual(operations, ['connect']);
});

test('request lookup distinguishes retained Run, absence and malformed Host reply',
  async t => {
    let reply = {kind: 'found', requestId: 'saved-id', ref,
      durability: 'durable',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'};
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      return Response.json(operation === 'connect' ? profile : reply);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    assert.deepEqual(await client.lookupRequest('saved-id'), reply);
    reply = {kind: 'not_found'};
    assert.deepEqual(await client.lookupRequest('missing'), reply);
    reply = {kind: 'found', requestId: 'other-id', ref,
      durability: 'durable',
      lookupExpiresAt: '2026-09-24T00:00:00.000Z'};
    await assert.rejects(client.lookupRequest('saved-id'),
      {code: 'InvalidHostRequestLookup'});
    reply = {kind: 'found', ref: {...ref, runDefinitionCid: 'bad'},
      durability: 'durable', lookupExpiresAt: 'tomorrow'};
    await assert.rejects(client.lookupRequest('saved-id'),
      {code: 'InvalidHostRequestLookup'});
    assert.deepEqual(requests.map(item => item.operation),
      ['connect', 'lookup-request', 'lookup-request',
        'lookup-request', 'lookup-request']);
  });

test('delivery attempt lookup binds the existing Host evidence to the request',
  async t => {
    const found = JSON.parse(readFileSync(new URL(
      '../client-wire/fixtures/delivery-attempt.found.json', import.meta.url),
    'utf8'));
    let reply = found;
    const requests = [];
    mock.method(globalThis, 'fetch', async (url, init) => {
      const operation = url.pathname.split('/').at(-1);
      requests.push({operation, body: JSON.parse(init.body)});
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json(admission);
      return Response.json(reply);
    });
    t.after(() => mock.restoreAll());
    const client = await connect(options);
    const result = (await client.attach(ref)).result('answer');
    assert.deepEqual(await result.deliveryAttempt('read-a'), reply);
    reply = {kind: 'not_found'};
    assert.deepEqual(await result.deliveryAttempt('read-b'), reply);
    for (const update of [
      answer => { answer.attempt.attempt_id = 'OTHER'; },
      answer => { answer.attempt.run_definition_cid =
        `sha256:${'9'.repeat(64)}`; },
      answer => { answer.attempt.result_name = 'foreign'; },
      answer => { answer.hostReleaseReceipt = {}; },
      answer => { answer.record.state = 'failed'; },
      answer => { answer.hostReleaseReceipt.serialization_contract_cid =
        `sha256:${'9'.repeat(64)}`; },
    ]) {
      reply = structuredClone(found);
      update(reply);
      await assert.rejects(result.deliveryAttempt('read-a'),
        {code: 'InvalidHostAttemptLookup'});
    }
    assert.deepEqual(requests.slice(2).map(item => item.body.attemptId),
      ['read-a', 'read-b', ...Array(6).fill('read-a')]);
    assert(requests.slice(2).every(item =>
      item.body.resultName === 'answer'));
    assert(requests.every(item => item.operation !== 'read'));
  });


test('cancel validates the response and exact requested Run', async t => {
  let reply = {ref, kind: 'accepted', revision: 5};
  t.mock.method(globalThis, 'fetch', async url => Response.json(
    String(url).endsWith('/connect') ? profile :
      String(url).endsWith('/attach') ? admission : reply));
  const client = await connect(options);
  t.after(() => client.close());
  const execution = await client.attach(ref);
  assert.deepEqual(await execution.cancel(), reply);
  for (const invalid of [{}, {...reply, kind: 'stopped'},
    {...reply, revision: -1},
    ...['namespaceId', 'authorityScopeCid', 'runDefinitionCid'].map(key =>
      ({...reply, ref: {...ref, [key]: key === 'namespaceId' ? 'foreign' :
        `sha256:${'c'.repeat(64)}`}}))]) {
    reply = invalid;
    await assert.rejects(execution.cancel(), {code: 'InvalidHostCancellation'});
  }
});


for (const [count, stop] of [[1, 'abort'], [2, 'abort'],
  [1, 'return'], [2, 'return']]) {
  test(`${stop} stops real HTTP delivery after the first of ${count} rows`,
    async t => {
      const requests = [];
      const server = createServer(async (request, response) => {
        for await (const _ of request) { /* Consume the request body. */ }
        const operation = request.url.split('/').at(-1);
        requests.push(operation);
        const localProfile = {...profile, mode: 'local', owner: 'local'};
        response.writeHead(200, {'content-type': operation === 'read'
          ? 'application/x-ndjson' : 'application/json'});
        response.end(operation === 'connect' ? JSON.stringify(localProfile)
          : operation === 'attach' ? JSON.stringify(admission)
            : Array.from({length: count}, (_, n) =>
              JSON.stringify({n: n + 1}) + '\n').join('') + '\x1e');
      });
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      t.after(async () => {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      });
      const client = await connect({mode: 'local', owner: 'local',
        endpoint: `http://127.0.0.1:${server.address().port}/`,
        token: 'test-token'});
      t.after(() => client.close());
      const result = (await client.attach(ref)).result('answer');
      const controller = new AbortController();
      const reader = result.rows({signal: controller.signal});
      const iterator = reader[Symbol.asyncIterator]();
      assert.deepEqual(await iterator.next(), {done: false, value: {n: 1}});
      if (stop === 'abort') {
        controller.abort();
        await assert.rejects(iterator.next(), error =>
          error instanceof ClientError && error.code === 'ResultReadUnknown' &&
          error.attemptId === reader.attemptId &&
          error.cause?.name === 'AbortError');
      } else {
        assert.deepEqual(await iterator.return(),
          {done: true, value: undefined});
      }
      assert.equal(reader.state(), 'prefix');
      assert.deepEqual(requests, ['connect', 'attach', 'read']);
    });
}

for (const text of ['{"n":1}\n\x1e', '{"n":1}\n{"n":2}\n\x1e']) {
  test(`abort prevents buffered Response completion: ${JSON.stringify(text)}`,
    async t => {
      const requests = [];
      mock.method(globalThis, 'fetch', async url => {
        const operation = url.pathname.split('/').at(-1);
        requests.push(operation);
        if (operation === 'connect') return Response.json(profile);
        if (operation === 'attach') return Response.json(admission);
        if (operation === 'read') return new Response(text);
        throw new Error(`unexpected ${operation}`);
      });
      t.after(() => mock.restoreAll());
      const result = (await (await connect(options)).attach(ref)).result('answer');
      const controller = new AbortController();
      const reader = result.rows({signal: controller.signal});
      const iterator = reader[Symbol.asyncIterator]();
      assert.deepEqual(await iterator.next(), {done: false, value: {n: 1}});
      controller.abort();
      await assert.rejects(iterator.next(), error =>
        error.code === 'ResultReadUnknown' &&
        error.attemptId === reader.attemptId &&
        error.cause?.name === 'AbortError');
      assert.equal(reader.state(), 'prefix');
      assert.deepEqual(requests, ['connect', 'attach', 'read']);
    });
}

for (const stop of ['return', 'break']) {
  test(`early ${stop} reports a failed Result stream cleanup`, async t => {
    const requests = [];
    const cleanupError = new Error('physical cleanup failed');
    let cancellations = 0, body;
    mock.method(globalThis, 'fetch', async url => {
      const operation = url.pathname.split('/').at(-1);
      requests.push(operation);
      if (operation === 'connect') return Response.json(profile);
      if (operation === 'attach') return Response.json(admission);
      if (operation === 'read') {
        body = new ReadableStream({
          start(controller) {
            controller.enqueue(new TextEncoder().encode('{"n":1}\n'));
          },
          cancel() { cancellations++; throw cleanupError; },
        });
        return new Response(body);
      }
      throw new Error(`unexpected ${operation}`);
    });
    t.after(() => mock.restoreAll());
    const result = (await (await connect(options)).attach(ref)).result('answer');
    const reader = result.rows();
    await assert.rejects(async () => {
      if (stop === 'return') {
        const iterator = reader[Symbol.asyncIterator]();
        assert.deepEqual(await iterator.next(), {done: false, value: {n: 1}});
        await iterator.return();
      } else {
        for await (const row of reader) {
          assert.deepEqual(row, {n: 1});
          break;
        }
      }
    }, error => error.code === 'ResultReadCleanupUnknown' &&
      error.attemptId === reader.attemptId && error.cause === cleanupError);
    assert.equal(reader.state(), 'prefix');
    assert.equal(cancellations, 1);
    assert.equal(body.locked, false);
    assert.deepEqual(requests, ['connect', 'attach', 'read']);
  });
}


test('check retains detached submitted inputs while credentials are pending', async t => {
  let release;
  const credential = new Promise(resolve => {release = resolve;});
  let waitForCredentials = false;
  let sent;
  mock.method(globalThis, 'fetch', async (url, request) => {
    if (url.pathname.endsWith('/connect')) return Response.json(profile);
    sent = JSON.parse(request.body);
    return Response.json({version: 'actql-check-outcome/0.1',
      reason_schema_cid: checkReasonSchemaCid, outcome: 'completed', report: {
        context_ref: 'ctx:fixture', scope: {kind: 'bound_input'}, verdict: 'invalid',
        inputs: [
          {document_id: 'source', kind: 'text', revision: 'rev:' + '1'.repeat(64), byte_length: 13},
          {document_id: 'parameter_declarations', kind: 'structured', revision: 'rev:' + '2'.repeat(64), byte_length: 23},
          {document_id: 'parameters', kind: 'structured', revision: 'rev:' + '3'.repeat(64), byte_length: 11},
        ],
        reasons: [{code: 'supplied_value_type_mismatch',
          facts: {parameter: 'x', expected_type: 'number', actual_type: 'string'},
          location: {kind: 'structured', document_id: 'parameters',
            revision: 'rev:' + '3'.repeat(64), pointer: '/x'}}],
        requirements: [], coverage: {limits: [], unresolved: []},
      }});
  });
  t.after(() => mock.restoreAll());
  const client = await connect({...options, token: async () => {
    if (waitForCredentials) await credential;
    return 'scoped-token';
  }});
  waitForCredentials = true;
  const parameterDeclarations = {x: {type: 'number'}};
  const parameters = {x: 'bad'};
  const pending = client.check('SELECT 1 AS n', {format: 'sql', parameterDeclarations, parameters});
  parameterDeclarations.x.type = 'string';
  parameters.x = 'new';
  release();
  const outcome = await pending;
  assert.deepEqual(sent.input.parameterDeclarations, {x: {type: 'number'}});
  assert.deepEqual(sent.parameters, {x: 'bad'});
  assert.deepEqual(getCheckInput(outcome, 'parameters').value, {x: 'bad'});
  assert.equal(Object.isFrozen(getCheckInput(outcome, 'parameters').value), true);
  assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location).input.value.x, 'bad');
  assert.equal(resolveCheckLocation(outcome, outcome.report.reasons[0].location,
    {...getCheckInput(outcome, 'parameters'), value: parameters}), undefined);
  assert.equal(explainCheckReason({code: 'future_problem'}).kind, 'unknown');
});

// Compile an independent public consumer, including invalid reference/write uses.
test('typed submission explanations preserve reference roles and read-only targets', () => {
  execFileSync(process.execPath, [fileURLToPath(new URL(
    '../../node_modules/typescript/bin/tsc', import.meta.url)),
  '--noEmit', '--strict', '--module', 'NodeNext', '--moduleResolution', 'NodeNext',
  '--target', 'ES2022', fileURLToPath(new URL(
    './submission-explanation.typecheck.mts', import.meta.url))],
  {cwd: fileURLToPath(new URL('../../', import.meta.url)), timeout: 30000});
});
