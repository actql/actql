// One owned worker per installed transport; all assertions stay in the shared
// original Graph CHECK helper. No replacement checker or execution owner.
import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {dirname, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {ownTransportWorker} from './packed-query-transport-owner.mjs';
import {exerciseGraphArgumentChecks, graphArgumentCheckInventory,
  graphArgumentNoExecution, requireGraphArgumentCheckReport} from './graph-argument-check.mjs';
import {graphCheckSourceProfile} from '../release-graph-argument-check-cases.mjs';
import {observeTwoSourceProvider} from './two-source-public-query.mjs';

const owner = ownTransportWorker();
try {
  const mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
  assert.ok(['local', 'remote'].includes(mode));
  const {connect} = await import('@actql/node');
  const sdk = await import('@actql/sdk');
  const {openInstalledRemoteHttpHost} = await import('@actql/local-node/http-host');
  const packagePath = resolve(dirname(fileURLToPath(import.meta.resolve('@actql/local-node'))), 'package.json');
  const duckdb = createRequire(packagePath)('@duckdb/node-api');
  const environment = JSON.parse(await readFile(
    'adapters/host-node/fixtures/query-amount-environment.json', 'utf8'));
  const database = resolve(`graph-check-${mode}.duckdb`);
  // A real local Source target exists before observation. A regression that
  // opens it while checking is still a failure, even if no rows are read.
  const instance = await duckdb.DuckDBInstance.create(database);
  const connection = await instance.connect();
  try { await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)'); }
  finally { connection.closeSync(); instance.closeSync(); }
  const provider = observeTwoSourceProvider(duckdb, {records: database});
  const report = {version: 'actql-graph-argument-check/0.1', mode,
    expectedInventory: [...graphArgumentCheckInventory], completedInventory: [],
    cases: [], noExecution: null, beforeDispatchCalls: mode === 'remote' ? 0 : null,
    complete: false, primaryError: null};
  const path = `graph-argument-check-${mode}.json`;
  const directories = [], cleanup = [], clients = {};
  let primary;
  const counts = () => {
    const observed = provider.snapshot();
    const value = {runs: 0, dispatchReservations: 0, physicalReservations: 0,
      sourceOpens: observed.sourceProviderOpens.length, sourceIo: observed.sourceIo,
      sourceReads: observed.sourceReads, sourceReadSessions: observed.sourceReadSessions};
    for (const directory of directories) {
      const journal = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
      try {
        const row = journal.prepare(`SELECT COUNT(*) AS runs,
          COALESCE(SUM(dispatch_reserved), 0) AS dispatchReservations,
          COALESCE(SUM(physical_start_reserved), 0) AS physicalReservations FROM client_requests`).get();
        for (const key of ['runs', 'dispatchReservations', 'physicalReservations']) value[key] += row[key];
      } finally { journal.close(); }
    }
    return value;
  };
  const save = () => writeFile(path, JSON.stringify(report, null, 2) + '\n');
  try {
    for (const name of ['denied', 'absent']) {
      owner.check();
      const directory = resolve(`graph-check-${mode}-${name}-state`);
      const sourceProfilePath = resolve(`graph-check-${mode}-${name}-profile.json`);
      await writeFile(sourceProfilePath, JSON.stringify(
        graphCheckSourceProfile(environment, database, name)), {flag: 'wx'});
      const installation = {directory, sourceProfilePath,
        hostCapacityPolicy: environment.host_policy_profile.capacity};
      if (mode === 'local') {
        clients[name] = await connect({mode: 'local', owner: 'local', durability: 'durable', installation});
      } else {
        const host = await openInstalledRemoteHttpHost({...installation,
          beforeDispatch() { report.beforeDispatchCalls++; throw new Error('UnexpectedGraphCheckDispatch'); },
          authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
        cleanup.push(() => host.close());
        const server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
        cleanup.push(async () => {
          server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
        });
        await new Promise((resolve, reject) => {
          server.once('error', reject); server.listen(0, '127.0.0.1', resolve);
        });
        clients[name] = await connect({mode: 'remote', durability: 'durable',
          endpoint: `https://127.0.0.1:${server.address().port}/`, token: 'fixture-token'});
      }
      cleanup.push(() => clients[name].close()); directories.push(directory);
    }
    await exerciseGraphArgumentChecks(clients, sdk, async id => {
      owner.check();
      assert.equal(id, graphArgumentCheckInventory[report.completedInventory.length]);
      const noExecution = counts(); assert.deepEqual(noExecution, graphArgumentNoExecution, id);
      assert.equal(report.beforeDispatchCalls, mode === 'remote' ? 0 : null);
      report.completedInventory.push(id); report.cases.push({id, noExecution}); await save();
    });
    report.noExecution = counts(); report.complete = true;
    requireGraphArgumentCheckReport(report, mode);
  } catch (error) { primary = error; }
  finally {
    for (const close of cleanup.reverse()) {
      try { await close(); } catch (error) { primary ??= error; }
    }
    try { report.noExecution = counts(); assert.deepEqual(report.noExecution, graphArgumentNoExecution); }
    catch (error) { primary ??= error; }
    provider.restore(); report.primaryError = primary?.message ?? null;
    report.complete = primary === undefined && report.complete; await save();
  }
  if (primary !== undefined) throw primary;
} finally { owner.release(); }
