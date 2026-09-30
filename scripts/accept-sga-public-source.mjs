import assert from 'node:assert/strict';
import {randomUUID} from 'node:crypto';
import {readFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join, resolve} from 'node:path';
import {pathToFileURL} from 'node:url';
import {reachSelectorChainSource} from './reach-selector-capacity-fixture.mjs';

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
  'shortest-path',
  'reach-selector', 'reach-selector-duplicates', 'reach-selector-empty',
  'reach-selector-nullable',
  'graph-bounds', 'traverse-paths', 'union-graphs', 'graft-graphs',
  'subtract-graphs', 'match-projections'];
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
    if (name === 'shortest-path') {
      const invalid = source.replace('max_hops: 3', 'max_hops: 0');
      assert.notEqual(invalid, source);
      await assert.rejects(client.aql(invalid, {format: 'aql-text',
        requestId: `sga-invalid-hop-${randomUUID()}`}),
      error => error.code === 'ClientProgramRejected');
    }
    if (name === 'reach-selector-nullable') {
      const invalid = source.replace(
        '"id":{"type":"string","nullable":true}},"rows":[{"id":"A"}]',
        '"id":{"type":"number","nullable":true}},"rows":[{"id":1}]');
      assert.notEqual(invalid, source);
      await assert.rejects(client.aql(invalid, {format: 'aql-text',
        requestId: `sga-invalid-selector-type-${randomUUID()}`}),
      error => error.code === 'ClientProgramRejected');
      // Both Programs are well typed. Membership and selected NULL admission
      // require the actual retained Graph and Relation, so fail at execution.
      for (const [label, rows] of [['missing', [{id: 'C'}]],
        ['null', [{id: null}]]]) {
        const seed = JSON.stringify({schema: {id: {type: 'string',
          nullable: true}}, rows});
        const badSource = source.replace(/^    DATA seeds = OP values .*;$/m,
          `    DATA seeds = OP values ${seed};`);
        assert.notEqual(badSource, source);
        const id = `sga-selector-${label}-${randomUUID()}`;
        const rejected = await client.aql(badSource, {format: 'aql-text',
          requestId: id});
        const failed = await rejected.wait({signal: AbortSignal.timeout(120000)});
        assert.equal(failed.status, 'failed', `${label}: ${JSON.stringify(failed)}`);
        assert.equal(failed.result_available, false, label);
        assert.deepEqual((await client.lookupRequest(id)).ref, rejected.ref);
        const restored = await client.attach(rejected.ref);
        assert.equal((await restored.status()).status, 'failed', label);
        await assert.rejects(restored.result('answer').all(),
          error => error.code === 'ResultAccessDenied');
        assert.deepEqual((await client.aql(badSource, {format: 'aql-text',
          requestId: id})).ref, rejected.ref);
      }
      console.log(`packed ${mode} selector membership and NULL failures passed`);
    }
    if (name === 'reach-selector') {
      // Host policy permits 1,000 rows, but the installed execution profile
      // also has a stricter 100-row sequence-output limit. Preserve both.
      // In a directed chain, all starts reach exactly n(n+1)/2 endpoint pairs.
      // This oracle comes from the Reach law, not compiler or kernel output.
      const bounded = reachSelectorChainSource(source, 13);
      assert.notEqual(bounded, source);
      const within = await client.aql(bounded, {format: 'aql-text',
        requestId: `sga-selector-capacity-within-${randomUUID()}`});
      const withinState = await within.wait({signal: AbortSignal.timeout(120000)});
      assert.equal(withinState.status, 'succeeded', JSON.stringify(withinState));
      const expectedRows = [];
      for (let start = 0; start < 13; start++) {
        for (let endpoint = start; endpoint < 13; endpoint++) {
          const startId = `N${String(start).padStart(2, '0')}`;
          const nodeId = `N${String(endpoint).padStart(2, '0')}`;
          expectedRows.push({start_id: startId, node_id: nodeId,
            depth: endpoint - start, id: nodeId});
        }
      }
      assert.equal(expectedRows.length, 91);
      assert.deepEqual(await within.result('answer').all(), expectedRows);
      const overflowing = reachSelectorChainSource(source, 14); // 105 pairs.
      const overflowId = `sga-selector-capacity-overflow-${randomUUID()}`;
      const over = await client.aql(overflowing, {format: 'aql-text',
        requestId: overflowId});
      const overState = await over.wait({signal: AbortSignal.timeout(120000)});
      assert.equal(overState.status, 'failed', JSON.stringify(overState));
      assert.equal(overState.result_available, false);
      assert.deepEqual((await client.lookupRequest(overflowId)).ref, over.ref);
      const restored = await client.attach(over.ref);
      assert.equal((await restored.status()).status, 'failed');
      await assert.rejects(restored.result('answer').all(),
        error => error.code === 'ResultAccessDenied');
      assert.deepEqual((await client.aql(overflowing, {format: 'aql-text',
        requestId: overflowId})).ref, over.ref);
      console.log(`packed ${mode} selector capacity boundary passed`);
    }
  }
  console.log(`packed ${mode} named SGA source and Result acceptance passed`);
} finally {
  await client.close();
}
