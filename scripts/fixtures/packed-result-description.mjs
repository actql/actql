// This app runs unchanged outside the checkout against installed packages.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createServer} from 'node:https';
import {mkdir, readFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {userInfo} from 'node:os';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';

// Advance the installed Host's trusted wall clock, rather than altering its
// persisted publication or retention evidence. No payload is synthesized.
const RealDate = Date;
let offset = 0;
globalThis.Date = class extends RealDate {
  constructor(...args) { super(...(args.length ? args : [RealDate.now() + offset])); }
  static now() { return RealDate.now() + offset; }
};
const canonical = value => Array.isArray(value)
  ? `[${value.map(canonical).join(',')}]`
  : value !== null && typeof value === 'object'
    ? `{${Object.keys(value).sort().map(key =>
      `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`
    : JSON.stringify(value);
const cid = value => `sha256:${createHash('sha256')
  .update(canonical(value)).digest('hex')}`;
const scalarSchema = {a: {type: 'number', nullable: false},
  z: {type: 'string', nullable: true}};
const complexSchema = {
  arr: {type: 'array', nullable: true, max_items: 3,
    items: {type: 'string', nullable: false}},
  obj: {type: 'object', nullable: false, additional_properties: false,
    fields: {n: {type: 'decimal', nullable: true, precision: 12, scale: 3}}},
  vec: {type: 'vector', nullable: true, element_type: 'f32', dimensions: 2},
};
const inputContract = contract => Object.fromEntries(Object.entries(contract)
  .filter(([key]) => !['additional_properties', 'element_type'].includes(key))
  .map(([key, value]) => [key, key === 'items' ? inputContract(value)
    : key === 'fields' ? Object.fromEntries(Object.entries(value)
      .map(([name, nested]) => [name, inputContract(nested)])) : value]));
const program = (schema, fields, rows) => ({version: 'actql/0.1',
  id: 'result-description',
  stages: [{id: 's', inputs: {}, steps: [{as: 'v', values: {
    schema: Object.fromEntries(Object.entries(schema).map(([name, type]) =>
      [name, inputContract(type)])), rows}}],
    results: {out: {from: 'v', fields}}}],
  results: {answer: {from: {stage: 's', result: 'out'}}}});
const documents = [
  {input: program(scalarSchema, ['z', 'a'], [{a: 2, z: null}, {a: 1, z: 'é'}]),
    schema: scalarSchema, fields: ['z', 'a'], rows: [{z: null, a: 2}, {z: 'é', a: 1}]},
  {input: program(complexSchema, ['vec', 'obj', 'arr'], []),
    schema: complexSchema, fields: ['vec', 'obj', 'arr'], rows: []},
];
const code = expected => error => error?.code === expected;
const observations = [];
for (const mode of ['local', 'remote']) {
  offset = 0;
  const fetch = globalThis.fetch;
  if (mode === 'local') globalThis.fetch = () => {
    throw new Error('LocalDescriptionUnexpectedNetwork');
  };
  let host, server, release;
  const directory = resolve(`description-${mode}`);
  await mkdir(directory, {recursive: true});
  let options;
  let dispatches = 0;
  if (mode === 'local') {
    options = {mode, owner: 'local', installation: {directory}};
  } else {
    host = await openInstalledRemoteHttpHost({directory,
      authenticate: token => token === 'Bearer description-token'
        ? userInfo().username : undefined,
      beforeDispatch: async () => {
        dispatches++;
        if (release !== undefined) await release.promise;
      }});
    server = createServer({key: await readFile('remote.key'),
      cert: await readFile('remote.crt')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    options = {mode, endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'description-token'};
  }
  const client = await connect(options);
  try {
    const completed = [];
    for (const fixture of documents) {
      const execution = await client.start(fixture.input);
      await execution.wait();
      const result = execution.result('answer');
      const description = await result.describe();
      assert.deepEqual(description.ref, execution.ref);
      assert.equal(description.resultName, 'answer');
      assert.deepEqual(description.columns, fixture.fields.map(name =>
        ({name, contract: fixture.schema[name]})));
      assert.equal(description.resultSchemaCid, cid(fixture.schema));
      assert.equal(description.resultDefinitionCid, cid({
        version: 'actql-result-definition/0.1',
        program_definition_cid: description.programDefinitionCid,
        result_name: 'answer'}));
      assert.deepEqual(description.serialization, {format: 'jsonl',
        version: 'actql-jsonl/0.1',
        contractCid: cid({version: 'actql-jsonl/0.1'})});
      assert.deepEqual(await result.all(), fixture.rows);
      assert.deepEqual(await (await client.attach(execution.ref))
        .result('answer').describe(), description);
      for (const format of ['json', 'csv']) {
        const other = await result.describe({format});
        assert.deepEqual(other.columns, description.columns);
        assert.deepEqual(other.serialization, {format,
          version: `actql-${format}/0.1`,
          contractCid: cid({version: `actql-${format}/0.1`})});
      }
      await assert.rejects(result.describe({format: 'parquet'}),
        code('UnsupportedResultDescriptionFormat'));
      const bytes = Buffer.byteLength(JSON.stringify(description), 'utf8');
      assert.deepEqual(await result.describe({maxWireBytes: bytes}), description);
      await assert.rejects(result.describe({maxWireBytes: bytes - 1}),
        code('ResultDescriptionTooLarge'));
      await assert.rejects(result.describe({maxNodes: 1}),
        code('ResultDescriptionTooLarge'));
      await assert.rejects(result.describe({maxDepth: 2}),
        code('ResultDescriptionTooLarge'));
      completed.push({execution, result, description});
      observations.push({mode, empty: fixture.rows.length === 0,
        logical: {columns: description.columns,
          programDefinitionCid: description.programDefinitionCid,
          resultDefinitionCid: description.resultDefinitionCid,
          resultSchemaCid: description.resultSchemaCid,
          serialization: description.serialization}});
    }
    offset = 70 * 60 * 1000;
    for (const {result, description} of completed) {
      assert.deepEqual(await result.describe(), description);
      await assert.rejects(result.all(), code('ResultUnavailable'));
    }
    offset = 8 * 24 * 60 * 60 * 1000;
    for (const {execution, result} of completed) {
      await assert.rejects(result.describe(), code('ResultDescriptionUnavailable'));
      assert.equal((await execution.status()).status, 'succeeded');
    }
    if (mode === 'remote') {
      offset = 9 * 24 * 60 * 60 * 1000;
      const promise = new Promise(resolve => { release = {resolve}; });
      release.promise = promise;
      const execution = await client.start(documents[0].input);
      await assert.rejects(execution.result('answer').describe(),
        code('ResultAccessDenied'));
      const unauthorized = await fetch(new URL(
        'actql/client/0.1/result-describe', options.endpoint), {method: 'POST',
        headers: {'content-type': 'application/json', authorization: 'Bearer wrong'},
        body: '{}'});
      assert.equal(unauthorized.status, 403);
      release.resolve(); release = undefined;
      await execution.wait();
      await execution.result('answer').describe();
      assert.equal(dispatches, 3, 'describe and attach never dispatch Compute');
    }
  } finally {
    release?.resolve();
    client.close();
    globalThis.fetch = fetch;
    if (server) await new Promise(resolve => server.close(resolve));
    await host?.close();
  }
}
assert.deepEqual(observations.filter(v => v.mode === 'local').map(v => v.logical),
  observations.filter(v => v.mode === 'remote').map(v => v.logical));
console.log('Packed Result.describe: Local/HTTP, ordered/composite/empty types, ' +
  'attach, formats, bounds, retention, authorization and unpublished refusal passed');
