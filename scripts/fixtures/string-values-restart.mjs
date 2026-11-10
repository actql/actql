import {decodeRetainedFixture} from './retained-fixture-values.mjs';
import {observeRetainedGraphDispatch} from './retained-graph-observer.mjs';
import {publicQueryResultOracles} from './public-query-input.mjs';
// Fresh process, installed packages only: restore published Results, without
// submitting source or invoking a compiler to recreate missing data.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from
  '@actql/local-node/http-host';

import {transportWorker} from './packed-query-transport-owner.mjs';
const mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
assert.ok(mode === undefined || ['local', 'remote'].includes(mode));
const worker = mode === undefined ? undefined : transportWorker();
worker?.check();
function accepted(directory) {
  const db = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'),
    {readOnly: true});
  try { return db.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count; }
  finally { db.close(); }
}
const cohortOnly = process.env.ACTQL_TEST_RETAINED_COHORT_ONLY === '1';
if (!cohortOnly) {
const retained = JSON.parse(await readFile('retained-string-results.json', 'utf8'));
const {hostCapacityPolicy} = retained;
assert.ok(hostCapacityPolicy !== null && typeof hostCapacityPolicy === 'object');
const sourceProfilePath = mode => resolve(retained.sourceProfilePaths?.[mode] ?? 'source-profile.json');
async function readRetained(mode, options, directory) {
  const before = accepted(directory);
  const client = await connect(options);
  try {
    const item = retained[mode];
    const execution = await client.attach(item.ref);
    assert.equal((await execution.status()).status, 'succeeded');
    assert.deepEqual(await execution.result('main').all(), item.expected);
    assert.deepEqual((await execution.result('main').describe()).columns, item.columns);
    assert.equal(accepted(directory), before, 'restoring Results creates no Run');
    console.log(`Exact strings retained after fresh ${mode} Host process`);
  } finally { await client.close(); }
}
if (mode === undefined || mode === 'local') await readRetained('local', {mode: 'local', owner: 'local', durability: 'durable',
  installation: {directory: resolve('local-state'), sourceProfilePath: sourceProfilePath('local'), hostCapacityPolicy,
    ...(retained.local.authorization === undefined ? {} : {authorization: retained.local.authorization})}}, 'local-state');
if (mode === undefined || mode === 'remote') {
const host = await openInstalledRemoteHttpHost({directory: resolve('remote-state'),
  sourceProfilePath: sourceProfilePath('remote'), hostCapacityPolicy,
  ...(retained.remote.authorization === undefined ? {} : {authorization: retained.remote.authorization}),
  authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined});
const server = createServer({key: await readFile('remote.key'),
  cert: await readFile('remote.crt')}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
try {
  await readRetained('remote', {mode: 'remote', durability: 'durable',
    endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'}, 'remote-state');
} finally {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}

}

}

// Independent consumer regression for cohort ownership after every installation
// has closed. Attach, original-submission replay and lookup must all resolve in
// the recorded Store; reopening cannot create another Run or replace an oracle.
const cohorts = decodeRetainedFixture(await readFile('retained-cohort-results.json', 'utf8'));
assert.ok(cohorts.length > 0);
const canonicalRow = value => Array.isArray(value)
  ? '[' + value.map(canonicalRow).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key =>
      JSON.stringify(key) + ':' + canonicalRow(value[key])).join(',') + '}'
    : JSON.stringify(value);
async function readRetainedCohort(cohort, options) {
  const before = accepted(cohort.directory);
  const client = await connect(options);
  try {
    assert.ok(cohort.samples.length >= 1 && cohort.samples.length <= 2);
    if (cohort.expectedSampleNames !== undefined) {
      assert.deepEqual(cohort.samples.map(sample => sample.source.name), cohort.expectedSampleNames,
        'Fresh-process Graph reader requires every original boundary sample');
    }
    for (const {source, ref, submissionRef} of cohort.samples) {
      const execution = await client.attach(ref);
      assert.equal((await execution.status()).status, 'succeeded');
      const results = publicQueryResultOracles(source);
      for (const [name, oracle] of Object.entries(results)) {
        const actual = await execution.result(name).all();
        if (oracle.unordered) {
          assert.deepEqual(actual.map(canonicalRow).sort(), oracle.rows.map(canonicalRow).sort());
        } else assert.deepEqual(actual, oracle.rows);
        if (oracle.columns !== undefined) {
          assert.deepEqual((await execution.result(name).describe()).columns, oracle.columns);
        }
      }
      const {name, text, expected, columns, results: resultOracles, resultName, sourceRows,
        sourceReadCount, sourceReadSessionCount, ...input} = source;
      const replayed = await client.startSource(text, {...input, submissionRef});
      assert.deepEqual(replayed.ref, ref);
      assert.equal((await replayed.status()).status, 'succeeded');
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready');
      assert.deepEqual(lookup.admission.ref, ref);
      assert.equal(accepted(cohort.directory), before,
        'reopened cohort attach/replay/lookup must preserve the original Run');
    }
  } finally { await client.close(); }
}
const completedRoots = [];
// Count the real installed dispatch boundary, not only newly admitted Runs.
// These private hooks do not change account configuration or Run identity.
const physicalDispatches = [];
for (const cohort of cohorts) {
  if (mode !== undefined && cohort.mode !== mode) continue;
  worker?.check();
  const verifyNoPhysicalReplay = cohort.expectedSampleNames !== undefined;
  const replayAuthorization = verifyNoPhysicalReplay
    ? observeRetainedGraphDispatch(cohort.authorization, physicalDispatches) : cohort.authorization;
  const beforePhysical = physicalDispatches.length;
  if (cohort.mode === 'local') {
    await readRetainedCohort(cohort, {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory: cohort.directory, sourceProfilePath: cohort.sourceProfilePath,
        hostCapacityPolicy: cohort.hostCapacityPolicy,
        ...(cohort.retainedRelationOutput === true ? {retainedRelationOutput:true} : {}),
        ...(replayAuthorization === undefined ? {} : {authorization: replayAuthorization})}});
  } else {
    assert.equal(cohort.mode, 'remote');
    const host = await openInstalledRemoteHttpHost({directory: cohort.directory,
      sourceProfilePath: cohort.sourceProfilePath, hostCapacityPolicy: cohort.hostCapacityPolicy,
      ...(cohort.retainedRelationOutput === true ? {retainedRelationOutput:true} : {}),
      ...(replayAuthorization === undefined ? {} : {authorization: replayAuthorization}),
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
    const server = createServer({key: await readFile('remote.key'),
      cert: await readFile('remote.crt')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      await readRetainedCohort(cohort, {mode: 'remote', durability: 'durable',
        endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'});
    } finally {
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    }
  }
  if (verifyNoPhysicalReplay) assert.equal(physicalDispatches.length, beforePhysical,
    'Restored Graph Result attach/replay/lookup must not dispatch or advance Compute');
  completedRoots.push(cohort.directory);
}
if (mode !== undefined) await writeFile(`transport-restart.${mode}.json`,
  JSON.stringify({mode, stringComplete: !cohortOnly, completedRoots,
    physicalDispatches: physicalDispatches.length}) + '\n', {flag: 'wx'});
console.log('Retained cohort boundary Results preserve attach/replay ownership after fresh Host processes');
