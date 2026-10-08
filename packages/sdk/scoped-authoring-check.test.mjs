import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {connectInProcess, getCheckInput, resolveCheckLocation, getCheckFailureInput,
  createCheckSupplementationSession} from './index.mjs';

// Fixed received facts, independent of the checker and Host output.
const fixture = JSON.parse(readFileSync(new URL('../client-wire/fixtures/check-template.verified.json', import.meta.url)));
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'scoped-fixture', capabilities: [],
  limits: {maxReadWireBytes: 4096, maxRowWireBytes: 1024,
    maxRowRetainedValueBytes: 1024, maxRetainedValueBytes: 4096,
    maxRows: 10, maxBatchRows: 2, maxBatchRetainedValueBytes: 2048}};
async function client(t, reply) {
  const calls = [];
  const value = await connectInProcess({mode: 'local', owner: 'local'}, {async perform(operation, body) {
    calls.push({operation, body});
    if (operation === 'connect') return profile;
    if (operation === 'check') return reply(body);
    assert.equal(operation, 'close', 'No submission or execution operation');
  }});
  t.after(() => value.close());
  return {value, calls};
}
function received(body) {
  const reply = structuredClone(fixture);
  reply.report.scope.kind = body.scope;
  if (body.scope === 'bound_input') {
    reply.report.verdict = 'undetermined';
    reply.report.coverage.limits = [{code: 'bound_values_missing'}];
  }
  const document = reply.report.inputs[0];
  document.byte_length = new TextEncoder().encode(JSON.stringify(body.input)).length;
  return reply;
}

test('scoped SDK rejects missing kind or scope and every template bindings presence before I/O', async t => {
  const {value, calls} = await client(t, () => assert.fail('Invalid request reached transport'));
  for (const options of [undefined, {}, {kind: 'text', format: 'sql'},
    {scope: 'template_only', format: 'sql'},
    ...[undefined, null, {}, {x: 1}].map(parameters =>
      ({kind: 'text', scope: 'template_only', format: 'sql', parameters}))]) {
    await assert.rejects(value.check('SELECT @x AS n', options), {code: 'InvalidCheckRequest'});
  }
  for (const parameters of [undefined, null, {}, {x: 1}]) {
    await assert.rejects(value.check({params: {}}, {kind: 'program', scope: 'template_only', parameters}),
      {code: 'InvalidCheckRequest'});
  }
  assert.deepEqual(calls.map(call => call.operation), ['connect']);
  let reads = 0;
  await assert.rejects(value.check('SELECT @x AS n', {kind: 'text', format: 'sql', parameters: {},
    get scope() {return ++reads === 1 ? 'template_only' : 'bound_input';}}), {code: 'InvalidCheckRequest'});
  assert.equal(reads, 1, 'The selected scope cannot change during request capture');
  assert.deepEqual(calls.map(call => call.operation), ['connect']);
});

test('scoped template Requirements allow an explicit bound recheck without automatic submission or reset', async t => {
  const {value, calls} = await client(t, received);
  const session = createCheckSupplementationSession(value, {maxAttempts: 3});
  const program = {params: {x: {type: 'number'}}};
  const template = await session.check(program, {kind: 'program', scope: 'template_only'});
  assert.equal(template.outcome.report.verdict, 'verified');
  assert.deepEqual(template.decision, {kind: 'more_checks'});
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'check']);
  const bound = await session.check(program, {kind: 'program', scope: 'bound_input'});
  assert.equal(bound.outcome.report.verdict, 'undetermined');
  assert.equal(bound.attempts, 2);
  assert.deepEqual(bound.decision, {kind: 'more_checks'});
  const stopped = await session.check(program, {kind: 'program', scope: 'bound_input'});
  assert.equal(stopped.attempts, 3);
  assert.deepEqual(stopped.decision, {kind: 'stop', reason: 'unchanged_frontier'});
  await assert.rejects(session.check(program, {kind: 'program', scope: 'template_only'}),
    {code: 'CheckSupplementationStopped'});
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'check', 'check', 'check']);
});

test('scoped Program checks capture before I/O and retain immutable pointer custody across rechecks', async t => {
  let release;
  const barrier = new Promise(resolve => {release = resolve;});
  const {value, calls} = await client(t, async body => {await barrier; return received(body);});
  const program = {params: {x: {type: 'number'}, 'e\u0301/~': null}};
  const pending = value.check(program, {kind: 'program', scope: 'template_only'});
  program.params.x.type = 'string'; delete program.params['e\u0301/~'];
  release();
  const original = await pending;
  const snapshot = getCheckInput(original, 'program');
  assert.deepEqual(snapshot.value, {params: {x: {type: 'number'}, 'e\u0301/~': null}});
  assert.equal(Object.isFrozen(snapshot.value.params.x), true);
  const location = original.report.requirements[0].location;
  assert.ok(resolveCheckLocation(original, location));
  assert.equal(getCheckInput(structuredClone(original), 'program'), undefined);
  assert.equal(resolveCheckLocation(structuredClone(original), location), undefined);
  assert.equal(getCheckInput(original, 'program', 'rev:' + '2'.repeat(64)), undefined);
  const second = await value.check(program, {kind: 'program', scope: 'bound_input'});
  assert.equal(getCheckInput(second, 'program').value.params.x.type, 'string');
  assert.equal(snapshot.value.params.x.type, 'number');
  assert.deepEqual(calls.map(call => call.operation), ['connect', 'check', 'check']);
  assert.equal(Object.hasOwn(calls[1].body, 'parameters'), false);
  assert.equal(calls[2].body.parameters, null);
});

test('scoped SDK rejects a foreign scope and retains only the original failure snapshot', async t => {
  const {value} = await client(t, body => received({...body, scope: 'bound_input'}));
  const program = {params: {x: {type: 'number'}}};
  let error;
  try {await value.check(program, {kind: 'program', scope: 'template_only'});} catch (cause) {error = cause;}
  assert.equal(error.code, 'InvalidHostCheckOutcome');
  assert.deepEqual(getCheckFailureInput(error), {kind: 'program', scope: 'template_only', program});
  assert.equal(getCheckInput(error, 'program'), undefined);
  assert.equal(getCheckFailureInput(structuredClone(error)), undefined);
});
