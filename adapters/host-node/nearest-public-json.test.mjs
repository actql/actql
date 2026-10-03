import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {join} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {connectEmbeddedLocal} from './embedded-local.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const fixture = join(repository, 'spec/frontend/fixtures/nearest-keep');

test('installed Local Host executes the independent nearest JSON control', async t => {
  const directory = await mkdtemp(join(repository, '_build/nearest-json-'));
  t.after(() => rm(directory, {recursive: true, force: true}));
  const program = await readFile(join(fixture, 'common-minimal.program.json'),
    'utf8');
  const expectedRows = JSON.parse(await readFile(join(fixture,
    'expected-rows.json'), 'utf8'));
  const expectedSchema = JSON.parse(await readFile(join(fixture,
    'expected-schema.json'), 'utf8'));
  const client = await connectEmbeddedLocal({mode: 'local', owner: 'local',
    installation: {directory}});
  const execution = await client.aql(program, {format: 'json',
    requestId: 'nearest-json-control'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const result = execution.result('answer');
  const description = await result.describe();
  assert.deepEqual(description.columns, expectedSchema.columns);
  const rows = [];
  for await (const row of result.rows()) rows.push(row);
  rows.sort((left, right) => left.neighbor.rank - right.neighbor.rank);
  assert.deepEqual(rows, expectedRows);
});
