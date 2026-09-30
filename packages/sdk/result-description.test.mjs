import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import test, {mock} from 'node:test';
import {connect, ClientError} from './index.mjs';
import {connectInProcess} from './host-port.mjs';
import {resultDescriptionLimits, validResultDescription,
  withinResultDescriptionLimits} from '../client-wire/index.mjs';

const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;
const ref = {namespaceId: 'description', authorityScopeCid: cid('authority'),
  runDefinitionCid: cid('run')};
const admission = {ref, durability: 'durable', revision: 1};
const profile = mode => ({version: 'actql-client-host/0.1', mode,
  owner: mode, durability: 'durable', scopeRef: 'description',
  capabilities: ['result-jsonl'], limits: {maxReadWireBytes: 4096,
    maxRowWireBytes: 1024, maxRowRetainedValueBytes: 1024,
    maxRetainedValueBytes: 4096, maxRows: 10, maxBatchRows: 3,
    maxBatchRetainedValueBytes: 1024}});
const schema = {z: {type: 'object', nullable: true,
  additional_properties: false,
  fields: {nested: {type: 'array', nullable: false, max_items: 2,
    items: {type: 'decimal', nullable: true, precision: 12, scale: 3}}}},
  a: {type: 'vector', nullable: false, element_type: 'f32', dimensions: 4}};
const description = () => ({ref: {...ref}, resultName: 'answer',
  programDefinitionCid: cid('program'),
  resultDefinitionCid: cid({version: 'actql-result-definition/0.1',
    program_definition_cid: cid('program'), result_name: 'answer'}),
  resultArtifactCid: cid('artifact'), resultSchemaCid: cid(schema),
  columns: ['z', 'a'].map(name => ({name, contract: structuredClone(schema[name])})),
  serialization: {format: 'jsonl', version: 'actql-jsonl/0.1',
    contractCid: cid({version: 'actql-jsonl/0.1'})}});
const expected = {ref, resultName: 'answer', format: 'jsonl'};

test('generated contracts validate full recursive types and exact bindings', () => {
  assert.equal(validResultDescription(description(), expected), true);
  const changes = [
    value => { value.ref.namespaceId = 'foreign'; },
    value => { value.ref.authorityScopeCid = cid('foreign'); },
    value => { value.ref.runDefinitionCid = cid('foreign'); },
    value => { value.resultName = 'other'; },
    value => { value.serialization.version = 'actql-csv/0.1'; },
    value => { value.columns[1].name = 'z'; },
    value => { value.columns = []; },
    value => { value.columns[0].contract.fields.nested.items.precision = 0; },
    value => { value.columns[0].contract.fields.nested.items.scale = 13; },
    value => { delete value.columns[0].contract.fields.nested.items.nullable; },
    value => { value.columns[1].contract.dimensions = 0; },
    value => { value.columns[1].contract.storageCodec = 'secret'; },
  ];
  for (const change of changes) {
    const value = description(); change(value);
    assert.equal(validResultDescription(value, expected), false);
  }
});

test('wire bounds cover UTF-8 bytes, complete structure and cycles', () => {
  const value = description(); value.ref.namespaceId = '日本語';
  const bytes = Buffer.byteLength(JSON.stringify(value), 'utf8');
  assert.equal(withinResultDescriptionLimits(value,
    {...resultDescriptionLimits, maxWireBytes: bytes}), true);
  assert.equal(withinResultDescriptionLimits(value,
    {...resultDescriptionLimits, maxWireBytes: bytes - 1}), false);
  for (const limits of [{maxNodes: 1}, {maxDepth: 3}]) {
    assert.equal(withinResultDescriptionLimits(value,
      {...resultDescriptionLimits, ...limits}), false);
  }
  value.columns[0].contract.fields.cycle = value;
  assert.equal(validResultDescription(value, expected), false);
  assert.equal(withinResultDescriptionLimits(Array(10001).fill(null)), false);
});

for (const mode of ['local', 'remote']) {
  test(`${mode} describe verifies identities without reading or replaying`, async t => {
    let answer = description();
    const calls = [];
    const perform = async operation => {
      calls.push(operation);
      if (operation === 'connect') return profile(mode);
      if (operation === 'attach') return admission;
      if (operation === 'result-describe') return answer;
      throw new Error(`Unexpected:${operation}`);
    };
    mock.method(globalThis, 'fetch', async url => {
      if (mode === 'local') throw new Error('UnexpectedNetwork');
      return Response.json(await perform(url.pathname.split('/').at(-1)));
    });
    t.after(() => mock.restoreAll());
    const client = mode === 'local'
      ? await connectInProcess({mode, owner: 'local'}, {perform})
      : await connect({mode, endpoint: 'https://host.example/', token: 'test'});
    t.after(() => client.close());
    const result = (await client.attach(ref)).result('answer');
    assert.deepEqual(await result.describe(), description());
    for (const field of ['resultSchemaCid', 'resultDefinitionCid',
      'programDefinitionCid']) {
      answer = description(); answer[field] = cid('foreign');
      await assert.rejects(result.describe(),
        {code: 'InvalidHostResultDescription'});
    }
    answer = description(); answer.serialization.contractCid = cid('wrong');
    await assert.rejects(result.describe(), {code: 'InvalidHostResultDescription'});
    answer = description(); answer.ref.runDefinitionCid = cid('wrong');
    await assert.rejects(result.describe(), {code: 'InvalidHostResultDescription'});
    answer = description(); answer.columns.reverse();
    assert.deepEqual((await result.describe()).columns, answer.columns);
    const before = calls.length;
    for (const options of [{format: 'parquet'}, {maxWireBytes: 0},
      {maxNodes: 10001}, {maxDepth: 65}, {other: true}]) {
      await assert.rejects(result.describe(options), ClientError);
    }
    assert.equal(calls.length, before);
    assert.equal(calls.filter(value => value === 'attach').length, 1);
    assert.ok(calls.every(value =>
      ['connect', 'attach', 'result-describe'].includes(value)));
  });
}

test('an oversized HTTP description cancels the body with a typed error', async t => {
  let cancelled = false;
  mock.method(globalThis, 'fetch', async url => {
    const operation = url.pathname.split('/').at(-1);
    if (operation === 'connect') return Response.json(profile('remote'));
    if (operation === 'attach') return Response.json(admission);
    return new Response(new ReadableStream({
      start(controller) { controller.enqueue(new Uint8Array(4096)); },
      cancel() { cancelled = true; },
    }), {headers: {'content-length': '1'}});
  });
  t.after(() => mock.restoreAll());
  const client = await connect({mode: 'remote', endpoint: 'https://host.example/',
    token: 'test'});
  t.after(() => client.close());
  await assert.rejects((await client.attach(ref)).result('answer')
    .describe({maxWireBytes: 100}), {code: 'InvalidHostResultDescription'});
  assert.equal(cancelled, true);
});
