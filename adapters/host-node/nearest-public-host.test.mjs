import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {mkdir, mkdtemp, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connectEmbeddedLocal} from './embedded-local.mjs';
import {installNearestSource} from '../../scripts/fixtures/nearest-installed-source.mjs';
import {canonical} from '../../scripts/fixtures/two-source-public-query.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const scratch = join(repository, '_build/nearest-public-host');
const {DuckDBInstance} = createRequire(join(repository,
  'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');

test('installed typed vector source executes a vector predicate', async t => {
  await mkdir(scratch, {recursive: true});
  const root = await mkdtemp(join(scratch, 'read-'));
  t.after(() => rm(root, {recursive: true, force: true}));
  const {profile, database, environment} = await installNearestSource({root,
    name: 'queries', duckdb: {DuckDBInstance}, templatePath: join(repository,
      'adapters/host-node/fixtures/two-source/left.environment.json')});
  const moon = await import(new URL('../../_build/js/release/build/' +
    'connectors_builtin_node/connectors_builtin_node.js', import.meta.url));
  assert.notEqual(moon.clientProgramCheckEnvironment(canonical(environment),
    environment.evidence_bundle_cid, false, false, true, false, false, false,
    false), undefined);
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run("INSERT INTO records VALUES ('q2', [0.0, 0.0], 'zero')");
  } finally {connection.closeSync(); instance.closeSync();}
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory: join(root, 'state'), sourceProfilePath: profile}});
  const program = {version: 'actql/0.1', id: 'nearest.typed-source-read',
    stages: [{id: 'read', inputs: {remote: {connector: 'nearest/queries',
      resource: 'r'}},
    steps: [{from: 'remote', filter:
      "vector_score(embedding, embedding, 'dot') = 1", as: 'filtered'},
      {from: 'filtered', select: ['request_id'], as: 'out'}],
    results: {rows: {from: 'out', fields: ['request_id']}}},
    {id: 'project', inputs: {rows: {result: {stage: 'read', result: 'rows'}}},
      steps: [{from: 'rows', filter: 'true', as: 'out'}],
      results: {rows: {from: 'out', fields: ['request_id']}}}],
    results: {answer: {from: {stage: 'project', result: 'rows'}}}};
  const execution = await client.aql(JSON.stringify(program), {format: 'json',
    requestId: 'nearest-typed-source-read'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = [];
  for await (const row of execution.result('answer').rows()) rows.push(row);
  assert.deepEqual(rows, [{request_id: 'q1'}]);
});
