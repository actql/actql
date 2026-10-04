// An owned fresh process. The source driver and the pack-once driver supply
// entry-point URLs; this file and its public acceptance helper stay unchanged.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {writeFileSync} from 'node:fs';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {canonical, loadTwoSourceFixtures, observeTwoSourceProvider,
  readTwoSourceJournal, openTwoSourcePublicHost, exerciseTwoSourcePublicQuery,
  verifyTwoSourceRetained} from './two-source-public-query.mjs';

const [configurationPath, action, caseName = action] = process.argv.slice(2);
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const {root, fixtureDirectory, runtime, installation, authorization: baseAuthorization} = configuration;
for (const key of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE', 'ACTQL_LOCAL_STATE_DIR']) {
  assert.equal(process.env[key], undefined, `${key} must not leak into acceptance`);
}
const sdk = await import(runtime.sdk);
const local = await import(runtime.local);
const connect = runtime.embeddedLocal
  ? options => options.mode === 'local' ? local.connectEmbeddedLocal(options) : sdk.connect(options)
  : sdk.connect;
const {openInstalledRemoteHttpHost} = local;
const duckdb = createRequire(runtime.duckdbPackage)('@duckdb/node-api');
const fixture = await loadTwoSourceFixtures(fixtureDirectory);
const tls = {key: await readFile(resolve(root, 'remote.key')),
  cert: await readFile(resolve(root, 'remote.crt'))};
setDefaultCACertificates([...getCACertificates('default'), tls.cert.toString('utf8')]);
const provider = observeTwoSourceProvider(duckdb, installation.databases);
const reportPath = resolve(root, `${caseName}.${action}.json`);
const report = value => writeFile(reportPath, JSON.stringify(value, null, 2) + '\n');
const noIo = () => {
  assert.deepEqual(provider.snapshot().sourceProviderOpens, [], 'recovery must not open either provider');
  assert.equal(provider.snapshot().sourceIo, 0, 'recovery must not execute Native provider SQL');
};
const pause = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
async function until(check, label) {
  const deadline = Date.now() + 30_000;
  while (Date.now() < deadline) {
    const value = await check();
    if (value) return value;
    await pause(10);
  }
  throw new Error(`Timed out: ${label}`);
}
function zeroRetained(usage) {
  assert.ok(usage, 'cleanup reports the actual shared acquisition ledger');
  for (const key of ['reservedTransferBytes', 'heldBytes', 'reservedRetentionBytes',
    'reservedExecutionBytes', 'uncertainTransferBytes']) assert.equal(usage[key], '0', key);
  assert.ok(BigInt(usage.holdings) > 0n, 'the fixture exercised positive acquisition retention');
}
function inventory(row) {
  const wire = JSON.parse(row.run_admission_evidence_json).sourceInventory;
  const value = JSON.parse(wire);
  assert.equal(value.acquisitions.length, 2);
  assert.deepEqual(value.acquisitions.map(item => [item.stage, item.input, item.task]), [[0, 0, 0], [1, 0, 1]]);
  assert.notEqual(value.acquisitions[0].checkedSource.requirementCid, value.acquisitions[1].checkedSource.requirementCid);
  assert.notEqual(value.acquisitions[0].checkedSource.sourceRef, value.acquisitions[1].checkedSource.sourceRef);
  assert.deepEqual(value.acquisitions.map(item => item.physicalBinding.database),
    [installation.databases.left, installation.databases.right]);
  assert.equal(wire, canonical(value));
  for (const item of value.acquisitions) {
    assert.equal(item.physicalBinding.database, item.readTuple.resource);
    for (const key of ['database', 'schema', 'table']) {
      assert.equal(Buffer.from(item.physicalBinding[key]).toString('hex'), item.physicalBinding.utf8_hex[key]);
    }
  }
  return wire;
}

if (action === 'public-success') {
  const retained = await exerciseTwoSourcePublicQuery({connect, openInstalledRemoteHttpHost,
    root, fixture, installation, provider, tls, authorization: baseAuthorization});
  await writeFile(resolve(root, 'retained-two-source.json'), JSON.stringify(retained, null, 2) + '\n');
  await report({cases: retained.length, provider: provider.snapshot()});
} else if (action === 'retained') {
  const retained = JSON.parse(await readFile(resolve(root, 'retained-two-source.json'), 'utf8'));
  const readerClosures = await verifyTwoSourceRetained({connect, openInstalledRemoteHttpHost,
    fixture, retained, provider, tls, authorization: baseAuthorization});
  await report({cases: retained.length, readerClosures, provider: provider.snapshot()});
} else {
  const directory = resolve(root, `${caseName}-state`), requestId = `two-source-${caseName}`;
  const mode = caseName.startsWith('local-') ? 'local' : 'https';
  let refusalCode;
  let sourceProfilePaths = [installation.profiles.left, installation.profiles.right];
  const events = [], faults = [];
  let releaseSecond, reachedSecond, reachedCleanup;
  const secondReached = new Promise(resolve => { reachedSecond = resolve; });
  const cleanupReached = new Promise(resolve => { reachedCleanup = resolve; });
  const secondBarrier = new Promise(resolve => { releaseSecond = resolve; });
  let rejectCleanup = action === 'cleanup-retry';
  if (['failure-second', 'cleanup-retry'].includes(action)) {
    sourceProfilePaths = [installation.profiles.left, installation.profiles.right_missing];
  }
  if (caseName.startsWith('broad-')) {
    sourceProfilePaths = [installation.profiles.left_broad, installation.profiles[
      ['failure-second', 'cleanup-retry'].includes(action) ? 'right_missing_broad' : 'right_broad']];
  }
  if (action === 'recover-changed-binding' || action === 'recover-started-drift') {
    const changed = JSON.parse(await readFile(installation.profiles.right, 'utf8'));
    changed.table = 'a_different_table';
    const path = resolve(root, `${caseName}-changed-right.profile.json`);
    await writeFile(path, canonical(changed)); sourceProfilePaths[1] = path;
  }
  if (action === 'recover-changed-generation') {
    const changed = JSON.parse(await readFile(installation.profiles.right, 'utf8'));
    const environment = JSON.parse(changed.checkEnvironmentWire);
    const cid = value => 'sha256:' + createHash('sha256').update(canonical(value)).digest('hex');
    const view = environment.source_views[0];
    view.connector_version = 'fixture-generation-2';
    delete view.contract_cid; view.contract_cid = cid(view);
    const catalog = environment.connector_catalogs[0];
    catalog.connector_version = view.connector_version;
    catalog.source_views = [structuredClone(view)];
    delete catalog.catalog_cid; catalog.catalog_cid = cid(catalog);
    for (const member of [...environment.schema_snapshots, ...environment.connector_capabilities]) {
      member.source_contract_cid = view.contract_cid;
      member.source_view_contract_cid = view.contract_cid;
    }
    delete environment.evidence_bundle_cid; environment.evidence_bundle_cid = cid(environment);
    changed.checkEnvironmentWire = canonical(environment);
    // Keep the public alias bound to the intentionally changed valid view.
    // The retained Run must reject generation drift at its dependency owner,
    // rather than failing unrelated Host alias publication during startup.
    changed.queryAliases = changed.queryAliases.map(alias => ({...alias,
      sourceViewContractCid: view.contract_cid}));
    const path = resolve(root, `${caseName}-changed-right.profile.json`);
    await writeFile(path, canonical(changed)); sourceProfilePaths[1] = path;
    // An ordinary public submission must reach accepted dispatch under the
    // new generation. The explicit pre-I/O hook stops this separate Run.
    let prepared = false;
    const preflight = await openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost,
      mode: 'https', directory: resolve(root, `${caseName}-generation-preflight`),
      sourceProfilePaths, tls, authorization: {...baseAuthorization,
        faultInjection(name) {
          if (name === 'dispatch_reserved') { prepared = true; throw new Error('GenerationPreparedBeforePhysicalStart'); }
        }}});
    const client = await preflight.connect();
    try {
      const execution = await client.aql(fixture.program, {format: 'json', requestId: 'generation-preflight'});
      assert.equal((await execution.wait({signal: AbortSignal.timeout(30_000)})).status, 'failed');
      assert.equal(prepared, true, 'changed source generation itself admits and prepares');
      noIo();
    } finally { client.close(); await preflight.close(); }
  }
  const authorization = {...baseAuthorization,
    observe: (name, detail) => events.push({name, ...detail}),
    async faultInjection(name, detail) {
      faults.push({name, ...detail});
      if (action === 'crash-before' && name === 'dispatch_reserved' ||
          action === 'crash-first' && name === 'acquisition_completed' && detail.task === 0) {
        const journal = readTwoSourceJournal(directory);
        assert.equal(journal.length, 1); inventory(journal[0]);
        if (action === 'crash-before') {
          assert.equal(journal[0].physical_start_reserved, 0); noIo();
        } else {
          assert.equal(journal[0].physical_start_reserved, 1);
          assert.ok(BigInt(detail.resourceUsage.heldBytes) > 0n);
          assert.equal(provider.snapshot().sourceReadSessions, 1);
        }
        writeFileSync(reportPath, JSON.stringify({ref: detail.ref, journal,
          provider: provider.snapshot(), faults}, null, 2) + '\n');
        // The process owns its scratch, TLS server and native database handles.
        // There is no graceful Host close or fabricated recovery receipt.
        process.kill(process.pid, 'SIGKILL');
        await new Promise(() => {});
      }
      if (action === 'cancel-second-boundary' && name === 'acquisition_started' && detail.task === 1) {
        reachedSecond(); await secondBarrier;
      }
      if (action === 'cleanup-retry' && name === 'acquisition_cleanup_started' && detail.task === 0) {
        assert.ok(BigInt(detail.resourceUsage.heldBytes) > 0n, 'failed cleanup retains real positive acquisition holding');
        reachedCleanup();
        if (rejectCleanup) throw new Error('FixtureFirstAcquisitionCloseFailed');
      }
    }};
  const running = await openTwoSourcePublicHost({connect, openInstalledRemoteHttpHost,
    mode, directory, sourceProfilePaths, tls, authorization});
  const client = await running.connect();
  try {
    if (action.startsWith('recover-')) {
      const crashAction = action.startsWith('recover-started') ? 'crash-first' : 'crash-before';
      const crash = JSON.parse(await readFile(resolve(root, `${caseName}.${crashAction}.json`), 'utf8'));
      assert.equal(inventory(readTwoSourceJournal(directory)[0]), inventory(crash.journal[0]));
      assert.deepEqual((await client.lookupRequest(requestId)).ref, crash.ref);
      const attached = await client.attach(crash.ref);
      noIo();
      if (action.startsWith('recover-changed-')) {
        await assert.rejects(client.aql(fixture.program, {format: 'json', requestId}), error => {
          assert.ok(['ClientRunStartDenied', 'ClientRequestIntentConflict'].includes(error.code), String(error.code));
          refusalCode = error.code;
          return true;
        });
        noIo();
        assert.deepEqual((await client.lookupRequest(requestId)).ref, crash.ref,
          'definitive refusal preserves the original accepted request');
        assert.deepEqual(readTwoSourceJournal(directory), crash.journal, 'refused replay preserves exact admitted inventory');
      } else if (action.startsWith('recover-started')) {
        const state = await running.host.inspectAcquisition({requestId, principalId: userInfo().username,
          connection: {mode: 'remote', owner: 'remote'}});
        assert.equal(state.state, 'started_unknown');
        assert.deepEqual(state.ref, crash.ref);
        const status = await attached.status();
        assert.ok(!['succeeded', 'failed', 'cancelled'].includes(status.status), JSON.stringify(status));
        const resent = await client.aql(fixture.program, {format: 'json', requestId});
        assert.deepEqual(resent.ref, crash.ref);
        assert.equal((await running.host.inspectAcquisition({requestId,
          principalId: userInfo().username, connection: {mode: 'remote', owner: 'remote'}})).state, 'started_unknown');
        await assert.rejects(attached.result('joined').all(), {code: 'ResultAccessDenied'});
        noIo();
        assert.deepEqual(readTwoSourceJournal(directory), crash.journal, 'unknown start is never reset or silently reacquired');
      } else {
        assert.equal(action, 'recover-exact');
        const resent = await client.aql(fixture.program, {format: 'json', requestId});
        assert.deepEqual(resent.ref, crash.ref);
        assert.equal((await resent.wait({signal: AbortSignal.timeout(30_000)})).status, 'succeeded');
        assert.deepEqual(await resent.result('joined').all(), fixture.expected.rows);
        assert.equal(provider.snapshot().sourceReadSessions, 2);
        assert.equal(inventory(readTwoSourceJournal(directory)[0]), inventory(crash.journal[0]));
      }
      await report({journal: readTwoSourceJournal(directory), provider: provider.snapshot(),
        ...(refusalCode === undefined ? {} : {refusalCode}), events, faults});
    } else {
      const execution = await client.aql(fixture.program, {format: 'json', requestId});
      if (action === 'cancel-second-boundary') {
        await secondReached;
        assert.equal(provider.snapshot().sourceReadSessions, 1);
        await execution.cancel(); releaseSecond();
      }
      if (action === 'cleanup-retry') {
        await cleanupReached;
        const beforeRetry = provider.snapshot();
        let firstClose;
        await assert.rejects(running.host.close(), error => {
          firstClose = error;
          assert.equal(error.code, 'ClientDispatchCleanupPending');
          assert.equal(error.cleanupPending, true);
          assert.equal(error.failures.length, 1);
          assert.ok(error.failures[0].primary, 'real second-provider failure is preserved');
          assert.ok(error.failures[0].cleanup, 'first acquisition cleanup failure is independently preserved');
          assert.notEqual(error.failures[0].primary, error.failures[0].cleanup);
          assert.match(error.failures[0].primary.message, /missing_records/u);
          assert.ok(error.failures[0].cleanup.errors.some(failure =>
            failure.message === 'FixtureFirstAcquisitionCloseFailed'));
          return true;
        });
        const attemptsBeforeRetry = faults.filter(event => event.name === 'acquisition_cleanup_started');
        assert.ok(attemptsBeforeRetry.length >= 2);
        for (const event of attemptsBeforeRetry) assert.ok(BigInt(event.resourceUsage.heldBytes) > 0n);
        rejectCleanup = false;
        await running.host.close();
        assert.deepEqual(provider.snapshot(), beforeRetry, 'cleanup retry never reacquires either source');
        const completed = events.filter(event => event.name === 'acquisition_cleanup_completed' && event.task === 0);
        assert.equal(completed.length, 1, 'one close receipt releases the original holding exactly once');
        zeroRetained(completed[0].resourceUsage);
        assert.equal(completed[0].resourceUsage.holdings,
          attemptsBeforeRetry[0].resourceUsage.holdings, 'retry does not issue another acquisition holding');
        assert.equal(completed[0].resourceUsage.attempts,
          attemptsBeforeRetry[0].resourceUsage.attempts, 'retry does not admit another acquisition');
        const final = events.filter(event => event.name === 'dispatch_cleanup_completed');
        assert.ok(final.length > 0); zeroRetained(final.at(-1).resourceUsage);
        const row = readTwoSourceJournal(directory)[0];
        assert.equal(row.physical_close_confirmed, 1); assert.equal(row.observed_terminal_outcome, 'failed');
        assert.equal(events.find(event => event.name === 'acquisition_completed').acquisition.selection.selectedCandidate,
          caseName.startsWith('broad-') ? 'broadQuery' : 'nativeQuery');
        await report({journal: [row], provider: provider.snapshot(), events, faults,
          failures: firstClose.failures.map(item => ({primary: item.primary.code ?? item.primary.message,
            cleanup: item.cleanup.code ?? item.cleanup.message}))});
      } else {
        const expected = action === 'cancel-second-boundary' ? 'cancelled' : 'failed';
        assert.equal((await execution.wait({signal: AbortSignal.timeout(30_000)})).status, expected);
        await until(() => events.find(event => event.name === 'dispatch_cleanup_completed'), 'dispatch cleanup receipt');
        assert.deepEqual(faults.filter(event => event.name === 'acquisition_started').map(event => event.task), [0, 1]);
        assert.deepEqual(faults.filter(event => event.name === 'acquisition_completed').map(event => event.task), [0]);
        assert.equal(provider.snapshot().sourceReadSessions, 1);
        zeroRetained(events.filter(event => event.name === 'dispatch_cleanup_completed').at(-1).resourceUsage);
        assert.equal(events.find(event => event.name === 'acquisition_completed').acquisition.selection.selectedCandidate,
          caseName.startsWith('broad-') ? 'broadQuery' : 'nativeQuery');
        const beforeRead = provider.snapshot();
        await assert.rejects(execution.result('joined').all(), {code: 'ResultAccessDenied'});
        assert.equal((await (await client.attach(execution.ref)).status()).status, expected);
        assert.deepEqual((await client.lookupRequest(requestId)).ref, execution.ref);
        assert.deepEqual((await client.aql(fixture.program, {format: 'json', requestId})).ref, execution.ref);
        assert.deepEqual(provider.snapshot(), beforeRead);
        if (action === 'cancel-second-boundary') {
          assert.ok(provider.snapshot().sourceProviderOpens.every(database => database === installation.databases.left),
            'cancellation at the awaited second-acquisition boundary prevents its provider open');
        } else {
          assert.ok(provider.snapshot().sourceProviderOpens.includes(installation.databases.right),
            'the authorized second provider opens and fails on the missing table');
        }
        await report({journal: readTwoSourceJournal(directory), provider: provider.snapshot(), events, faults});
      }
    }
  } finally { releaseSecond(); client.close(); await running.close(); }
}
provider.restore();
console.log(`Two-source process passed: ${caseName}/${action}`);
