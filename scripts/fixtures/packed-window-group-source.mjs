// Runs only in the empty installation prepared by test-packed-public-query.
// This fixture uses public package exports, not checkout runtime paths.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve, join} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {createServer} from 'node:https';
import {connect} from '@actql/node';
import {createInstalledConnectorTable} from '@actql/local-node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import * as moon from '@actql/local-node/runtime';
import * as helpers from '@actql/local-node/connector-installation';
import {installWindowGroupFixture} from './window-group-installed-source.mjs';
import {windowGroupSourceSuccesses as successes, windowGroupSourceRefusals as refusals}
  from './window-group-source-input.mjs';
import {exercisePublicQueryInput} from './public-query-input.mjs';
import {createVerifiedCaseReceipts} from './cte-value-table-receipts.mjs';
import {encodeRetainedFixture} from './retained-fixture-values.mjs';
import {requireCompleteInventory, transportWorker} from './packed-query-transport-owner.mjs';

const mode = process.env.ACTQL_TEST_QUERY_TRANSPORT;
assert.ok(['local', 'remote'].includes(mode));
const worker = transportWorker();
const directory = resolve(`window-state-${mode}`);
const installed = await installWindowGroupFixture({moon, helpers,
  createInstalledConnectorTable, directory: resolve(`window-installation-${mode}`)});
const {connectorTable, sourceProfilePath, observations, prepareCase} = installed;
const inventoryKey = (kind, index, item) => JSON.stringify(['window-group', kind, index, item.name,
  createHash('sha256').update(encodeRetainedFixture(item)).digest('hex')]);
const expectedInventory = ['successes', 'refusals'].flatMap(kind =>
  ({successes, refusals})[kind].map((item, index) => inventoryKey(kind, index, item)));
const completedInventory = [];
const receipts = createVerifiedCaseReceipts(mode, writeFile, {
  prefix: 'window-group', version: 'actql-window-group-acceptance/0.1',
});
const observe = () => {
  const journal = new DatabaseSync(join(directory, 'requests', 'client-requests.sqlite3'), {readOnly: true});
  try {
    return {...observations, acceptedRuns: journal.prepare(
      'SELECT COUNT(*) AS count FROM client_requests').get().count};
  } finally { journal.close(); }
};
let primary;
let host, server;
try {
  const installation = {directory, sourceProfilePath, connectorTable};
  let options = {mode: 'local', owner: 'local', durability: 'durable', installation};
  if (mode === 'remote') {
    host = await openInstalledRemoteHttpHost({...installation,
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined});
    server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    options = {mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'fixture-token', durability: 'durable'};
  }
  await exercisePublicQueryInput(connect, options, {
    requestPrefix: `packed-window-group-${mode}`, observe, successes, refusals,
    prepareCase: rows => { worker.check(); prepareCase(rows); },
    async completedCase(item) {
      await receipts.record(item);
      const index = successes.findIndex(candidate => candidate.name === item.name);
      completedInventory.push(inventoryKey('successes', index, successes[index]));
    },
    async completedRefusal(item) {
      await receipts.recordRefusal(item);
      const index = refusals.findIndex(candidate => candidate.name === item.name);
      completedInventory.push(inventoryKey('refusals', index, refusals[index]));
    },
  });
  assert.equal(observe().acceptedRuns, 9);
  assert.equal(observations.sourceReadSessions, 9);
  assert.equal(observations.sourceReads, 9);
  assert.equal(observations.acceptedPages, 9);
  assert.equal(observations.issuedGrants, 9);
  requireCompleteInventory(expectedInventory, completedInventory);
} catch (error) {
  primary = error;
} finally {
  if (server !== undefined) {
    server.closeAllConnections();
    await new Promise(resolve => server.close(resolve));
  }
  try { await host?.close(); } catch (error) { primary ??= error; }
  if (primary === undefined && observations.closedSites !== 1) {
    primary = new Error('WindowFixtureSiteCleanupIncomplete');
  }
  // Retain actual incomplete inventories on the first error, with no retry.
  await writeFile(`transport-completion.${mode}.json`, JSON.stringify({mode,
    expectedInventory, completedInventory, expectedRetainedCohorts: 0,
    needsTail: false, complete: primary === undefined,
    actualNormal: completedInventory.filter(key => JSON.parse(key)[1] === 'successes').length,
    actualRefusal: completedInventory.filter(key => JSON.parse(key)[1] === 'refusals').length,
    observations, primaryError: primary?.message}) + '\n');
  await writeFile(`retained-cohort-results.${mode}.json`, encodeRetainedFixture([]));
}
if (primary !== undefined) throw primary;
await receipts.complete();
