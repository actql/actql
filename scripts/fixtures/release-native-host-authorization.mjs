// Installed-package companion to the Native Remote CLI positive fixture.
// SDK requests exercise the same real HTTPS Host with one permission removed.
import assert from 'node:assert/strict';
import {createServer} from 'node:https';
import {readFile, writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {setTimeout as sleep} from 'node:timers/promises';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';

function fixtureAuthorization(omitted) {
  // Independently match the positive fixture's exact finite Account; never
  // replace a missing Run read with a Result read or broaden either scope.
  const permissions = [
    ['compute-write', 'source-free-values', 'write'],
    ['result-main-read', 'result/main', 'read'],
    ['run-read', 'run', 'read'],
  ];
  return {accountConfiguration: JSON.stringify({
    version: 'actql-execution-account-config/0.1', account_id: 'native-release-http',
    entries: permissions.filter(([entryId]) => entryId !== omitted)
      .map(([entryId, resource, operation]) => ({entry_id: entryId, outcome: 'allow',
        principal: {any_of: [userInfo().username]},
        connection: {any_of: ['actql-remote-host']},
        resource: {any_of: [resource]}, operation: {any_of: [operation]}, exclusions: []})),
  })};
}

async function readReadyResult(execution, receipt) {
  const signal = AbortSignal.timeout(30_000);
  const result = execution.result('main');
  receipt.pendingResultReads = [];
  receipt.resultReadAttempts = 0;
  for (let attempt = 1; attempt <= 300; attempt++) {
    signal.throwIfAborted();
    receipt.resultReadAttempts = attempt;
    try {return await result.all({signal});}
    catch (error) {
      // A not-yet-committed Result also returns this zero-row refusal. Poll
      // only that original Result; no Run observation or new submission is
      // authorized here. Eventual rows prove the separate permission works.
      if (error?.code !== 'ResultAccessDenied' || error.rowsYielded !== 0 ||
          signal.aborted || attempt === 300) throw error;
      receipt.pendingResultReads.push({attempt, code: error.code, rowsYielded: error.rowsYielded});
      await sleep(100, undefined, {signal});
    }
  }
}

const root = process.cwd(), receipts = [];
const tls = {key: await readFile('remote.key'), cert: await readFile('remote.crt')};
async function exercise(omitted) {
  const receipt = {omitted, computes: 0, denials: [],
    clientCloseReturned: false, serverCloseReturned: false, hostCloseReturned: false};
  receipts.push(receipt);
  let host, server, client, primary;
  const denied = async (operation, action, code, rowsYielded) => {
    await assert.rejects(action, error => {
      assert.equal(error.code, code);
      if (rowsYielded !== undefined) assert.equal(error.rowsYielded, rowsYielded);
      receipt.denials.push({operation, code: error.code,
        ...(rowsYielded === undefined ? {} : {rowsYielded: error.rowsYielded})});
      return true;
    });
  };
  try {
    host = await openInstalledRemoteHttpHost({
      directory: join(root, 'authorization-host-state', omitted),
      authorization: fixtureAuthorization(omitted),
      beforeDispatch: () => {receipt.computes++;},
      authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined,
    });
    server = createServer(tls, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'fixture-token', durability: 'durable'});
    const submissionRef = client.newSubmission({nonce: `native-release-without-${omitted}`});
    const execution = await client.startSource('SELECT 1 AS id UNION ALL SELECT 2 AS id ORDER BY id',
      {format: 'sql', submissionRef, attemptId: `native-release-without-${omitted}-submit`});
    receipt.ref = execution.ref;
    if (omitted === 'run-read') {
      for (const [operation, action] of [
        ['wait', () => execution.wait({signal: AbortSignal.timeout(30_000)})],
        ['status', () => execution.status()],
        ['attach', () => client.attach(execution.ref)],
        ['lookup-submission', () => client.lookupSubmission(submissionRef)],
      ]) await denied(operation, action, 'ClientConnectionDenied');
      // The separate Result permission remains usable on that same Run.
      receipt.rows = await readReadyResult(execution, receipt);
      assert.deepEqual(receipt.rows, [{id: 1}, {id: 2}]);
    } else {
      assert.equal(omitted, 'result-main-read');
      assert.equal((await execution.wait({signal: AbortSignal.timeout(30_000)})).status, 'succeeded');
      assert.deepEqual((await client.attach(execution.ref)).ref, execution.ref);
      const lookup = await client.lookupSubmission(submissionRef);
      assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.admission.ref, execution.ref);
      await denied('read', () => execution.result('main').all({signal: AbortSignal.timeout(30_000)}),
        'ResultAccessDenied', 0);
      await denied('result-describe', () => execution.result('main').describe(), 'ResultAccessDenied');
      assert.equal((await execution.status()).status, 'succeeded');
    }
    assert.equal(receipt.computes, 1, 'Permission denials and observations never resend the original submission');
  } catch (error) {primary = error;}
  finally {
    const cleanupErrors = [];
    for (const [resource, close, key] of [
      [client, () => client.close(), 'clientCloseReturned'],
      [server, async () => {server.closeAllConnections(); await new Promise((resolve, reject) =>
        server.close(error => error ? reject(error) : resolve()));}, 'serverCloseReturned'],
      [host, () => host.close(), 'hostCloseReturned'],
    ]) if (resource !== undefined) {
      try {await close(); receipt[key] = true;}
      catch (error) {cleanupErrors.push(error);}
    }
    if (cleanupErrors.length) primary = new AggregateError(
      [...(primary === undefined ? [] : [primary]), ...cleanupErrors], 'Authorization fixture cleanup failed');
  }
  if (primary !== undefined) throw primary;
}

try {
  for (const omitted of ['run-read', 'result-main-read']) await exercise(omitted);
} finally {
  await writeFile('native-host-authorization.json', JSON.stringify({
    version: 'actql-native-release-host-authorization/0.1', receipts,
  }, null, 2));
}
console.log(JSON.stringify({stage: 'native-host-authorization-passed', receipts}));
