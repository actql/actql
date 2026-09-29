import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';

// Copy this script and the authored fixtures into a clean packed installation.
// Only the installed Client and Host handle source compilation and execution.
const [installation, fixtureDirectory, mode, requestedCase] =
  process.argv.slice(2);
if (!installation || !fixtureDirectory || !['local', 'remote'].includes(mode)) {
  throw new Error('Usage: node accept-sga-public-source.mjs ' +
    '<packed-installation> <fixture-directory> <local|remote> [case-name]');
}
if (mode === 'local' && !process.env.ACTQL_LOCAL_STATE_DIR) {
  throw new Error('Local acceptance requires ACTQL_LOCAL_STATE_DIR');
}
const requireInstalled = createRequire(join(resolve(installation), 'package.json'));
const {connect} = await import(pathToFileURL(requireInstalled.resolve('@actql/node')));
const options = mode === 'local'
  ? {mode: 'local', owner: 'local', durability: 'durable',
    installation: {directory: resolve(process.env.ACTQL_LOCAL_STATE_DIR),
      sourceProfilePath: process.env.ACTQL_TEST_LOCAL_SOURCE_PROFILE}}
  : {mode: 'remote', endpoint: process.env.ACTQL_TEST_REMOTE_ENDPOINT,
    token: process.env.ACTQL_TEST_REMOTE_TOKEN, durability: 'durable'};
if (mode === 'remote' && (!options.endpoint || !options.token)) {
  throw new Error('Remote acceptance requires endpoint and token');
}

const cases = ['components', 'reach-subgraph', 'diff-apply',
  'mean-graphs', 'graphs-equal', 'normalize-rows', 'degree-rows',
  'graph-bounds', 'traverse-paths', 'union-graphs'];
if (requestedCase && !cases.includes(requestedCase)) {
  throw new Error(`Unknown SGA acceptance case: ${requestedCase}`);
}
const readFixture = (name, suffix) => readFile(join(resolve(fixtureDirectory),
  `${name}.${suffix}`), 'utf8');

// The public Result API exposes rows but not the published Result schema.
// This checks row shape and values; it is not schema or column-order evidence.
function checkRowShapes(rows, expectedSchema) {
  const fields = Object.keys(expectedSchema).sort();
  for (const row of rows) {
    assert.deepEqual(Object.keys(row).sort(), fields);
    for (const [field, column] of Object.entries(expectedSchema)) {
      const value = row[field];
      if (value === null) {
        assert.equal(column.nullable, true, field);
      } else {
        assert.equal(typeof value, column.type, field);
      }
    }
  }
}

const client = await connect(options);
try {
  assert.equal(client.profile.mode, mode);
  for (const name of requestedCase ? [requestedCase] : cases) {
    const source = await readFixture(name, 'named.aql');
    const expected = JSON.parse(await readFixture(name,
      'expected-results.json'));
    const requestId = `sga-public-${name}-${randomUUID()}`;
    const execution = await client.aql(source, {format: 'aql-text', requestId});
    const state = await execution.wait({signal: AbortSignal.timeout(120000)});
    assert.equal(state.status, 'succeeded', `${name}: ${JSON.stringify(state)}`);
    assert.deepEqual((await client.lookupRequest(requestId)).ref,
      execution.ref, name);
    const attached = await client.attach(execution.ref);
    assert.deepEqual(attached.ref, execution.ref, name);
    assert.deepEqual((await client.aql(source, {format: 'aql-text',
      requestId})).ref, execution.ref, name);
    for (const [resultName, result] of Object.entries(expected)) {
      const rows = await attached.result(resultName).all();
      checkRowShapes(rows, result.schema);
      assert.deepEqual(rows, result.rows, `${name}.${resultName}`);
      const reader = execution.result(resultName).rows();
      const reread = [];
      for await (const row of reader) reread.push(row);
      assert.equal(reader.state(), 'complete', `${name}.${resultName}`);
      assert.deepEqual(reread, result.rows, `${name}.${resultName}`);
    }
    assert.equal((await execution.status()).status, 'succeeded', name);
    assert.equal((await execution.cancel()).kind, 'already_terminal', name);
  }
  console.log(`packed ${mode} named SGA source and Result acceptance passed`);
} finally {
  await client.close();
}
