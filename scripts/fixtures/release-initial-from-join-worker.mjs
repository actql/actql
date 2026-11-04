// Runs only in the new empty ordinary-four consumer. No product files are copied.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {createRequire} from 'node:module';
import {readFile, writeFile} from 'node:fs/promises';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
import {selectInitialFromJoinCases, initialFromJoinFixture} from '../release-initial-from-join-cases.mjs';
import {canonical, installTwoSourceFixtures, observeTwoSourceProvider,
  openTwoSourcePublicHost, readTwoSourceJournal} from './two-source-public-query.mjs';
import {exercisePublicQueryInput} from './public-query-input.mjs';

const owner = ownTransportWorker();
try {
const transport = process.env.ACTQL_TEST_QUERY_TRANSPORT;
assert.ok(['local', 'remote'].includes(transport));
const mode = transport === 'remote' ? 'https' : 'local';
const {connect} = await import('@actql/node');
const {openInstalledRemoteHttpHost} = await import('@actql/local-node/http-host');
const packagePath = resolve(dirname(fileURLToPath(import.meta.resolve('@actql/local-node'))), 'package.json');
const duckdb = createRequire(packagePath)('@duckdb/node-api');
const json = async path => JSON.parse(await readFile(path, 'utf8'));
const vector = await json('scripts/fixtures/initial-from-join/independent-vector.json');
const fixture = initialFromJoinFixture(vector, {
  left: await json('adapters/host-node/fixtures/two-source/left.environment.json'),
  right: await json('adapters/host-node/fixtures/two-source/right.environment.json'),
});
const cases = selectInitialFromJoinCases(vector);
const root = resolve(`initial-join-${mode}`);
const installation = await installTwoSourceFixtures({root, fixture, duckdb});
const provider = observeTwoSourceProvider(duckdb, installation.databases);
const tls = {key: await readFile('remote.key'), cert: await readFile('remote.crt')};
// Same existing P15 fixture authority, with fresh keys confined to this Host.
const keys = generateKeyPairSync('ed25519');
const authorization = {
  accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'two-source-host', entries: [{entry_id: 'allow-owned-test-run',
      outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
    principalId: 'fixture-reviewer', publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'fixture-host-key', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
};
const records = [], closures = [];
let primary;
try {
  for (const selected of cases) {
    owner.check();
    const directory = resolve(root, selected.name + '-state');
    const before = provider.snapshot();
    const running = await openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost,
      mode, directory, sourceProfilePaths: [installation.profiles.left, installation.profiles.right],
      tls, authorization, hostCapacityPolicy: installation.hostCapacityPolicy});
    try {
      await exercisePublicQueryInput(connect, running.options, {
        requestPrefix: `${mode}-${selected.name}`, successes: [selected], refusals: [],
        observe: () => ({...provider.snapshot(), acceptedRuns: readTwoSourceJournal(directory).length}),
        persistSubmission: value => writeFile(resolve(directory, 'submission-ref.json'),
          JSON.stringify(value) + '\n', {flag: 'wx', mode: 0o600}),
        completedCase: value => records.push({name: selected.name, mode,
          ref: value.ref, submissionRef: value.submissionRef,
          beforeSubmit: value.beforeSubmit, beforeRead: value.beforeRead,
          afterReplay: value.afterReplay, results: value.observedResults}),
      });
      const scans = provider.snapshot().sourceReadCommands.slice(before.sourceReadCommands.length);
      const expected = Object.values(installation.databases).sort();
      assert.deepEqual([...new Set(scans.map(value => value.database))].sort(), expected);
      for (const database of expected) assert.equal(
        new Set(scans.filter(value => value.database === database).map(value => value.session)).size, 1);
    } finally {
      await running.close();
      closures.push({name: selected.name, mode, closed: true});
    }
  }
  assert.deepEqual(records.map(value => value.name), cases.map(value => value.name));
} catch (error) { primary = error; }
finally {
  provider.restore();
  await writeFile(resolve(`initial-from-join-${mode}.json`), JSON.stringify({mode,
    complete: primary === undefined, primaryError: primary?.message,
    completed: records, closures, sourceObservations: provider.snapshot()}, null, 2) + '\n', {flag: 'wx'});
}
if (primary !== undefined) throw primary;
} finally { owner.release(); }
