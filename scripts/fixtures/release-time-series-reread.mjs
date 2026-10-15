// A new OS process reopens the same installed product and exact saved references.
import assert from 'node:assert/strict';
import {readFile, writeFile} from 'node:fs/promises';
import {resolve} from 'node:path';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {DatabaseSync} from 'node:sqlite';
import {sourcefreeFixtureAuthorization} from './release-sourcefree-authorization.mjs';
import {selectInstalledSourcefreeQuerySuite, sourcefreeSuiteRequiresReread}
  from '../release-sourcefree-query-cases.mjs';
import {guardReleaseSourcefreeIo} from './release-sourcefree-io.mjs';
const mode = process.argv[2];
assert.ok(['local', 'https'].includes(mode));
const suite = process.argv[3] ?? 'time-series';
assert.equal(sourcefreeSuiteRequiresReread(suite), true);
const saved = JSON.parse(await readFile(`sourcefree-${mode}.json`, 'utf8'));
const cases = selectInstalledSourcefreeQuerySuite(suite);
assert.equal(saved.suite, suite); assert.equal(saved.complete, true);
assert.deepEqual(saved.successNames, cases.successes.map(item => item.name));
assert.deepEqual(saved.refusalNames, cases.refusals.map(item => item.name));
const authorization = await sourcefreeFixtureAuthorization(mode, suite, {reopen: true});
const directory = resolve(`sourcefree-${mode}`), completed = [], io = guardReleaseSourcefreeIo();
let primary, host, server, client;
const count = () => {
  io.assertQuiet();
  const journal = new DatabaseSync(resolve(directory, 'requests/client-requests.sqlite3'), {readOnly: true});
  try {return journal.prepare('SELECT COUNT(*) AS count FROM client_requests').get().count;}
  finally {journal.close();}
};
try {
  const {open} = await import('@actql/node');
  const {connect} = await import('@actql/sdk');
  let factory = open, options = {stateDir: directory, durability: 'durable', installation: {
    authorization, resolveSourceSecret: io.resolveSourceSecret,
    ...(cases.calendarArtifact === undefined ? {} : {calendarArtifact: cases.calendarArtifact})}};
  if (mode === 'https') {
    const {openInstalledRemoteHttpHost} = await import('@actql/local-node/http-host');
    host = await openInstalledRemoteHttpHost({directory, authorization,
      resolveSourceSecret: io.resolveSourceSecret,
      ...(cases.calendarArtifact === undefined ? {} : {calendarArtifact: cases.calendarArtifact}),
      authenticate: header => header === 'Bearer sourcefree-test' ? userInfo().username : undefined});
    server = createServer({key: await readFile('remote.key'), cert: await readFile('remote.crt')}, host.handler);
    await new Promise((resolve, reject) => {server.once('error', reject); server.listen(0, '127.0.0.1', resolve);});
    const endpoint = `https://127.0.0.1:${server.address().port}/`;
    io.allowTransportOrigin(new URL(endpoint).origin);
    factory = connect; options = {mode: 'remote', endpoint, token: 'sourcefree-test'};
  }
  client = await factory(options);
  const before = count(); assert.equal(before, cases.successes.length);
  for (const [index, fixture] of cases.successes.entries()) {
    const original = saved.completed[index]; assert.equal(original.name, fixture.name);
    const execution = await client.attach(original.ref), observedResults = {};
    for (const [name, expected] of Object.entries(fixture.results)) {
      const result = execution.result(name);
      const rows = await result.all(), columns = (await result.describe()).columns;
      assert.deepEqual(rows, expected.rows); assert.deepEqual(columns, expected.columns);
      observedResults[name] = {rows, columns};
    }
    const lookup = await client.lookupSubmission(original.submissionRef);
    assert.equal(lookup.kind, 'ready'); assert.deepEqual(lookup.submissionRef, original.submissionRef);
    assert.deepEqual(lookup.admission.ref, original.ref);
    const {name, text, results, sourceReadCount, sourceReadSessionCount, ...input} = fixture;
    const resent = await client.startSource(text, {...input, submissionRef: original.submissionRef});
    assert.deepEqual(resent.ref, original.ref); assert.equal((await resent.wait()).status, 'succeeded');
    assert.equal(count(), before); io.assertQuiet();
    completed.push({name, ref: original.ref, submissionRef: original.submissionRef,
      observedResults, beforeAcceptedRuns: before, afterAcceptedRuns: count()});
  }
} catch (error) {primary = error;}
finally {
  try {await client?.close();} catch (error) {primary ??= error;}
  try {if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}}
  catch (error) {primary ??= error;}
  try {await host?.close();} catch (error) {primary ??= error;}
  const providerObservation = io.snapshot(); io.close();
  await writeFile(`sourcefree-reread-${mode}.json`, JSON.stringify({mode, suite,
    phase: 'fresh-process-reread', complete: primary === undefined, completed, providerObservation}, null, 2) + '\n',
  {flag: 'wx'});
}
if (primary !== undefined) throw primary;
