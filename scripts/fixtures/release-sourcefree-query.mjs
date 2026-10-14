import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {resolve} from 'node:path';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {selectInstalledSourcefreeQuerySuite} from '../release-sourcefree-query-cases.mjs';
import {exercisePublicQueryInput} from './public-query-input.mjs';
import {guardReleaseSourcefreeIo} from './release-sourcefree-io.mjs';
import {sourcefreeFixtureAuthorization} from './release-sourcefree-authorization.mjs';

const mode = process.argv[2];
assert.ok(['local', 'https'].includes(mode), 'Select one installed transport');
const suite = process.argv[3] ?? 'in-unnest';
const directory = resolve(`sourcefree-${mode}`);
const authorization = await sourcefreeFixtureAuthorization(mode, suite);
const cases = selectInstalledSourcefreeQuerySuite(suite), completed = [], completedRefusals = [], checkObservations = [];
let host, server;
let primary;
const io = guardReleaseSourcefreeIo();
try {
  // No Source/Effect/Model installation or external Provider is added. These
  // public factories and their bundled Owners are the execution implementation.
  const {open} = await import('@actql/node');
  const {connect} = await import('@actql/sdk');
  let connectClient, options;
  if (mode === 'local') {
    connectClient = open;
    options = {stateDir: directory, durability: 'durable', installation: {
      authorization, resolveSourceSecret: io.resolveSourceSecret}};
  } else {
    const {openInstalledRemoteHttpHost} = await import('@actql/local-node/http-host');
    host = await openInstalledRemoteHttpHost({directory, authorization,
      resolveSourceSecret() {return io.resolveSourceSecret();},
      authenticate: header => header === 'Bearer sourcefree-test' ? userInfo().username : undefined});
    server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    const endpoint = `https://127.0.0.1:${server.address().port}/`;
    io.allowTransportOrigin(new URL(endpoint).origin);
    connectClient = connect;
    options = {mode: 'remote', endpoint, token: 'sourcefree-test'};
  }
  const observe = () => {
    io.assertQuiet();
    const journal = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
    try {
      // Same durable admission fact as the existing public query harness.
      // Row/session zero is scoped to no installed Source readers and quiet
      // process/fetch/secret guards, not arbitrary filesystem I/O or Providers.
      return {acceptedRuns: journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count,
        sourceIo: io.attemptedProviderIo(), sourceReads: 0, sourceReadSessions: 0};
    } finally {journal.close();}
  };
  if (suite === 'aql-format') {
    const checking = await connectClient(options);
    try {
      const {getCheckInput, resolveCheckLocation} = await import('@actql/sdk');
      const verified = await checking.check('SELECT @p AS id', {kind: 'text', scope: 'bound_input',
        format: 'aql', parameterDeclarations: {p: {type: 'number', nullable: false}}, parameters: {p: 1}});
      assert.equal(verified.report.verdict, 'verified');
      assert.deepEqual(verified.report.reasons, []);
      assert.equal(getCheckInput(verified, 'source').text, 'SELECT @p AS id');
      const invalid = await checking.check('SELECT ', {kind: 'text', scope: 'bound_input', format: 'aql'});
      assert.equal(invalid.report.verdict, 'invalid');
      const reason = invalid.report.reasons.find(value => value.code === 'query_syntax_invalid');
      assert.ok(reason);
      assert.equal(resolveCheckLocation(invalid, reason.location).input, getCheckInput(invalid, 'source'));
      assert.equal(getCheckInput(invalid, 'source').text, 'SELECT ');
      checkObservations.push({verdict: verified.report.verdict, reasons: verified.report.reasons},
        {verdict: invalid.report.verdict, reasons: invalid.report.reasons});
      assert.equal(observe().acceptedRuns, 0, 'Checking cannot accept a Run');
    } finally {await checking.close();}
  }
  await exercisePublicQueryInput(connectClient, options, {
    requestPrefix: suite === 'in-unnest' ? `release-${mode}` : `release-${suite}-${mode}`,
    observe, ...cases,
    completedCase({name, ref, submissionRef, observedResults, beforeSubmit, beforeRead, afterReplay}) {
      completed.push({name, ref, submissionRef, observedResults, beforeSubmit, beforeRead, afterReplay});
    },
    completedRefusal({name, submissionRef, outcome, beforeSubmit, afterRefusal}) {
      completedRefusals.push({name, submissionRef, outcome, beforeSubmit, afterRefusal});
    },
  });
  assert.deepEqual(completed.map(value => value.name), cases.successes.map(value => value.name));
  assert.deepEqual(completedRefusals.map(value => value.name), cases.refusals.map(value => value.name));
  assert.equal(observe().acceptedRuns, cases.successes.length);
  io.assertQuiet();
} catch (error) {
  primary = error;
} finally {
  try {if (server) await new Promise(resolve => server.close(resolve));}
  catch (error) {primary ??= error;}
  try {await host?.close();}
  catch (error) {primary ??= error;}
  const providerObservation = io.snapshot();
  io.close();
  // Keep actual completed cases and refusals even when later cases never run.
  await writeFile(`sourcefree-${mode}.json`, JSON.stringify({mode, suite,
    complete: primary === undefined,
    actualNormal: completed.length, actualRefusal: completedRefusals.length,
    expectedSuccessNames: cases.successes.map(value => value.name),
    expectedRefusalNames: cases.refusals.map(value => value.name),
    successNames: completed.map(value => value.name), refusalNames: completedRefusals.map(value => value.name),
    completed, completedRefusals, checkObservations, providerObservation,
    observationScope: 'Empty Source inventory; process/fetch/secret guards and read-only durable Run admission. Store filesystem I/O is not Source I/O.'}, null, 2) + '\n', {flag: 'wx'});
}
if (primary !== undefined) throw primary;
