import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connectInProcess} from './host-port.mjs';
import {connect, ClientError, explainCheckFailure, getCheckFailureInput, getCheckInput,
  explainCheckOutcome, resolveCheckLocation} from './index.mjs';

const fixture = JSON.parse(readFileSync(new URL(
  '../client-wire/fixtures/check-default-type.invalid.json', import.meta.url), 'utf8'));
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'protocol-fixture', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096, maxRows: 10,
    maxBatchRows: 3, maxBatchRetainedValueBytes: 1024}};
const capture = async promise => {
  try { await promise; assert.fail('Expected protocol rejection'); }
  catch (error) { assert.equal(error.code, 'InvalidHostCheckOutcome'); return error; }
};
async function client(t, reply) {
  const calls = [];
  const value = await connectInProcess({mode: 'local', owner: 'local'}, {
    async perform(operation, body) {
      calls.push({operation, body});
      if (operation === 'connect') return profile;
      if (operation === 'check') return reply(body);
      if (operation !== 'close') assert.fail('Unexpected operation');
    },
  });
  t.after(() => value.close());
  return {value, calls};
}
const admittedHeader = () => ({version: fixture.version,
  reason_schema_cid: fixture.reason_schema_cid, outcome_schema_cid: fixture.outcome_schema_cid});

test('check protocol failures distinguish unknown outcomes from malformed known facts and pins', async t => {
  for (const [reply, kind, problem] of [
    [{...admittedHeader(), outcome: 'private-future-outcome', report: {verdict: 'verified'}},
      'uninterpretable', 'unknown_outcome'],
    [{...fixture, report: {...fixture.report, reasons: [{code: 'query_lexical_invalid', facts: {issue: 42}}]}},
      'protocol_failure', 'malformed_response'],
    [{...admittedHeader(), outcome: 'completed'}, 'protocol_failure', 'malformed_response'],
    [{...admittedHeader(), outcome: 'future', outcome_schema_cid: `sha256:${'0'.repeat(64)}`},
      'protocol_failure', 'contract_mismatch'],
    [{...admittedHeader(), outcome: 'future', reason_schema_cid: undefined},
      'protocol_failure', 'malformed_response'],
    [null, 'protocol_failure', 'malformed_response'],
  ]) {
    const {value, calls} = await client(t, () => reply);
    const error = await capture(value.check('SELECT 1 AS n', {format: 'sql'}));
    const view = explainCheckFailure(error);
    assert.deepEqual({kind: view.kind, problem: view.problem}, {kind, problem},
      '[check-mutation:protocol-failure-kind]');
    assert.equal(calls.filter(call => call.operation === 'check').length, 1);
    for (const field of ['verdict', 'report', 'scope', 'contextRef', 'correlationRef', 'next', 'ref']) {
      assert.equal(Object.hasOwn(view, field), false);
    }
    assert.equal(explainCheckOutcome(error), undefined);
    assert.equal(getCheckInput(error, 'source'), undefined);
    assert.equal(resolveCheckLocation(error, fixture.report.reasons[0].location), undefined);
  }
});

test('check protocol failures retain each original submitted snapshot only under its real error', async t => {
  let release;
  const barrier = new Promise(resolve => { release = resolve; });
  const reused = {...admittedHeader(), outcome: 'future'};
  const {value, calls} = await client(t, async () => { await barrier; return reused; });
  const declarations = {x: {type: 'string', default: 'e\u0301\r\n😀'}};
  const parameters = {x: 'private-submitted-value'};
  const text = '\ufeff/*e\u0301😀*/\r\nSELECT @x AS value';
  const first = value.check(text, {format: 'sql', parameterDeclarations: declarations, parameters});
  declarations.x.default = 'edited'; parameters.x = 'edited';
  const second = value.check('SELECT @x AS other', {format: 'aql-text', parameters});
  release();
  const errors = await Promise.all([capture(first), capture(second)]);
  assert.notEqual(errors[0], errors[1]);
  assert.deepEqual(getCheckFailureInput(errors[0]), {text, format: 'sql',
    parameterDeclarations: {x: {type: 'string', default: 'e\u0301\r\n😀'}},
    parameters: {x: 'private-submitted-value'}}, '[check-mutation:protocol-failure-input]');
  assert.deepEqual(getCheckFailureInput(errors[1]), {text: 'SELECT @x AS other', format: 'aql-text',
    parameters: {x: 'edited'}});
  assert.equal(Object.isFrozen(getCheckFailureInput(errors[0]).parameterDeclarations.x), true);
  assert.equal(Object.hasOwn(getCheckFailureInput(errors[0]), 'revision'), false);
  for (const error of errors) {
    const serialized = JSON.stringify(error);
    for (const secret of [text, 'private-submitted-value', 'parameterDeclarations', 'report', 'future']) {
      assert.equal(serialized.includes(secret), false, '[check-mutation:protocol-failure-disclosure]');
    }
    for (const copied of [structuredClone(error), {...error}, JSON.parse(serialized),
      new ClientError('InvalidHostCheckOutcome'), {kind: 'uninterpretable'}]) {
      assert.equal(getCheckFailureInput(copied), undefined, '[check-mutation:protocol-failure-custody]');
      assert.equal(explainCheckFailure(copied), undefined);
    }
  }
  assert.equal(calls.filter(call => call.operation === 'check').length, 2);
});

test('check protocol failure presentation is immutable across hostile display options and error edits', async t => {
  const {value, calls} = await client(t, () => ({...admittedHeader(), outcome: 'private-future-outcome'}));
  const error = await capture(value.check('SELECT 1 AS n', {format: 'sql'}));
  const en = explainCheckFailure(error);
  error.code = 'Success'; error.message = 'verified'; error.kind = 'verified'; error.severity = 'info';
  const ja = explainCheckFailure(error, {get locale() { error.problem = 'verified'; return 'ja'; }});
  assert.deepEqual({kind: ja.kind, problem: ja.problem}, {kind: 'uninterpretable', problem: 'unknown_outcome'},
    '[check-mutation:protocol-failure-presentation]');
  assert.equal(ja.summary, 'このSDKでは検査応答のoutcomeを解釈できません。');
  assert.deepEqual(explainCheckFailure(error, {get locale() { throw new Error('private locale'); }}), en);
  assert.equal(Object.isFrozen(ja), true);
  assert.equal(calls.filter(call => call.operation === 'check').length, 1);
});

test('check protocol failure classification does not evaluate rejected reply accessors again', async t => {
  let reads = 0;
  const reply = structuredClone(fixture);
  Object.defineProperty(reply, 'outcome', {enumerable: true, get() {
    reads++; throw new Error('private malformed wire');
  }});
  const {value} = await client(t, () => reply);
  const error = await capture(value.check('SELECT 1 AS n', {format: 'sql'}));
  assert.equal(reads, 1);
  assert.equal(explainCheckFailure(error).problem, 'malformed_response');
  assert.equal(JSON.stringify(error).includes('private malformed wire'), false);
  assert.equal(error.cause, undefined);
});

test('check protocol failures do not brand input or transport refusal as a diagnosed reply', async t => {
  const refusal = new ClientError('ClientHostFailure');
  const {value} = await client(t, () => { throw refusal; });
  await assert.rejects(value.check('\ud800', {format: 'sql'}), error => {
    assert.equal(error.code, 'InvalidCheckRequest');
    assert.equal(explainCheckFailure(error), undefined);
    assert.equal(getCheckFailureInput(error), undefined); return true;
  });
  await assert.rejects(value.check('SELECT 1 AS n', {format: 'sql'}), error => {
    assert.equal(error, refusal); assert.equal(explainCheckFailure(error), undefined); return true;
  });
});

for (const asynchronous of [false, true]) {
  test(`check does not brand ${asynchronous ? 'asynchronous' : 'synchronous'} credential failures as received replies`, async t => {
    const refusal = new Error('Synthetic credential provider refusal');
    const requests = [];
    let credentials = 0;
    t.mock.method(globalThis, 'fetch', async url => {
      requests.push(url.pathname);
      assert.equal(url.pathname, '/actql/client/0.1/connect');
      return Response.json({...profile, mode: 'remote', owner: 'remote'});
    });
    const value = await connect({mode: 'remote', endpoint: 'https://host.example/',
      token() {
        credentials++;
        if (credentials === 1) return 'synthetic-connect-token';
        if (asynchronous) return Promise.reject(refusal);
        throw refusal;
      }});
    let rejected;
    try { await value.check('SELECT 1 AS n', {format: 'sql'}); }
    catch (error) { rejected = error; }
    assert.ok(rejected);
    assert.equal(credentials, 2);
    assert.deepEqual(requests, ['/actql/client/0.1/connect']);
    assert.deepEqual({originalError: rejected === refusal,
      explanation: explainCheckFailure(rejected), input: getCheckFailureInput(rejected)},
    {originalError: true, explanation: undefined, input: undefined});
  });
}

test('check still brands malformed received JSON after successful credentials', async t => {
  const requests = [];
  let credentials = 0;
  t.mock.method(globalThis, 'fetch', async url => {
    requests.push(url.pathname);
    if (url.pathname === '/actql/client/0.1/connect') {
      return Response.json({...profile, mode: 'remote', owner: 'remote'});
    }
    assert.equal(url.pathname, '/actql/client/0.1/check');
    return new Response('{', {headers: {'content-type': 'application/json'}});
  });
  const value = await connect({mode: 'remote', endpoint: 'https://host.example/',
    token() { credentials++; return 'synthetic-check-token'; }});
  const error = await capture(value.check('SELECT 1 AS n', {format: 'sql'}));
  assert.equal(credentials, 2);
  assert.deepEqual(requests, ['/actql/client/0.1/connect', '/actql/client/0.1/check']);
  const view = explainCheckFailure(error);
  assert.deepEqual({kind: view.kind, problem: view.problem},
    {kind: 'protocol_failure', problem: 'malformed_response'});
  assert.deepEqual(getCheckFailureInput(error),
    {text: 'SELECT 1 AS n', format: 'sql', parameters: null});
});
