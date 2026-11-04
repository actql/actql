import assert from 'node:assert/strict';
import test, {mock} from 'node:test';
import {connect} from './index.mjs';
import {connectInProcess} from './host-port.mjs';
import {submissionEpoch} from './submission-fixture.mjs';

const cid = digit => `sha256:${digit.repeat(64)}`;
const ref = {namespaceId: 'typed-result-capture', authorityScopeCid: cid('a'),
  runDefinitionCid: cid('b')};
const admission = {ref, durability: 'volatile', revision: 1};
const profile = {version: 'actql-client-host/0.1', mode: 'local', owner: 'local',
  durability: 'volatile', scopeRef: 'typed-result-capture',
  capabilities: ['aql-document'], submissionEpoch,
  limits: {maxReadWireBytes: 256, maxRowWireBytes: 128,
    maxRowRetainedValueBytes: 512, maxRetainedValueBytes: 1024,
    maxRows: 10, maxBatchRows: 10, maxBatchRetainedValueBytes: 1024}};

async function fixture(t, frame) {
  const calls = []; let returns = 0, closes = 0;
  const port = {async perform(operation) {
    calls.push(operation);
    if (operation === 'connect') return profile;
    if (operation === 'attach') return admission;
    assert.equal(operation, 'read');
    return {kind: 'rows', close() {closes++;}, frames: (async function* () {
      try {yield frame;} finally {returns++;}
    })()};
  }};
  const client = await connectInProcess({mode: 'local', owner: 'local'}, port);
  t.after(() => client.close());
  return {result: (await client.attach(ref)).result('answer'), calls,
    cleanup: () => ({returns, closes})};
}

test('one typed Result frame captures borrowed fields and its row once', async t => {
  let values = 0, lengths = 0, cells = 0;
  const original = {get id() {cells++; return cells;}};
  const frame = {get value() {values++; return original;},
    get byteLength() {lengths++; return 8;}};
  const f = await fixture(t, frame);
  assert.deepEqual(await f.result.all(), [{id: 1}]);
  assert.deepEqual({values, lengths, cells}, {values: 1, lengths: 1, cells: 1});
  assert.deepEqual(f.calls, ['connect', 'attach', 'read']);
  assert.deepEqual(f.cleanup(), {returns: 1, closes: 1});
});

test('retained limits apply to the captured original before a shrinking validator', async t => {
  let cells = 0, validations = 0;
  const original = {get text() {cells++; return 'x'.repeat(1024);}};
  const f = await fixture(t, {value: original, byteLength: 8});
  const schema = {'~standard': {version: 1, vendor: 'typed-result-capture',
    validate() {validations++; return {value: {text: ''}};}}};
  await assert.rejects(f.result.all(schema),
    error => error.code === 'ResultRowRetainedLimit' && typeof error.attemptId === 'string');
  assert.equal(cells, 1); assert.equal(validations, 0);
  assert.deepEqual(f.cleanup(), {returns: 1, closes: 1});
});

test('typed frame wire refusal precedes row capture and retains cleanup', async t => {
  let cells = 0;
  const f = await fixture(t, {value: {get text() {cells++; assert.fail('RowBeforeWireAdmission');}}, byteLength: 129});
  await assert.rejects(f.result.all(), {code: 'ResultRowWireLimit'});
  assert.equal(cells, 0); assert.deepEqual(f.cleanup(), {returns: 1, closes: 1});
});

test('typed Result values reject noncanonical scalars before application validation', async t => {
  for (const value of [Infinity, -Infinity, NaN, -0, '\ud800']) {
    let validations = 0;
    const f = await fixture(t, {value: {nested: [value]}, byteLength: 32});
    const schema = {'~standard': {version: 1, vendor: 'typed-result-capture',
      validate(row) {validations++; return {value: row};}}};
    await assert.rejects(f.result.all(schema), {code: 'InvalidResultFrame'});
    assert.equal(validations, 0);
    assert.deepEqual(f.cleanup(), {returns: 1, closes: 1});
  }
});

test('HTTP Result rows reject invalid values and decoded duplicate keys', async t => {
  let wire, reads = 0, validations = 0;
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json({...profile, mode: 'remote', owner: 'remote'});
    if (operation === 'attach') return Response.json(admission);
    assert.equal(operation, 'read'); reads++;
    return new Response(wire + '\n\x1e');
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://example.invalid/', token: 'token'});
  t.after(() => client.close());
  const result = (await client.attach(ref)).result('answer');
  const schema = {'~standard': {version: 1, vendor: 'typed-result-capture',
    validate(row) {validations++; return {value: row};}}};
  const invalid = ['{"n":1e400}', '{"n":-0}', '{"n":"\\ud800"}',
    '{"n":1,"n":2}', '{"n":1,"\\u006e":2}', '{"nested":[{"x":1,"x":2}]}'];
  for (wire of invalid) {
    await assert.rejects(result.all(schema), {code: 'InvalidResultFrame'});
  }
  assert.equal(validations, 0);
  assert.equal(reads, invalid.length);
  // Repeated keys in different objects and punctuation inside strings are valid.
  wire = '{"nested":[{"x":1},{"x":2}],"text":"\\\"x\\\":{},[]","exact":"é\\r\\n"}';
  assert.deepEqual(await result.all(), [JSON.parse(wire)]);
});
