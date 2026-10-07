import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {pathToFileURL} from 'node:url';

const installation = process.argv[2];
const executable = process.argv[3];
const evidenceDirectory = process.argv[4] ?? installation;
if (!installation || !executable) {
  throw new Error('Usage: node test-native-sga-public-source.mjs ' +
    '<packed-installation> <native-client-executable>');
}
const requireInstalled = createRequire(join(installation, 'package.json'));
const {graphSourceSuccesses, graphSourceRefusals} =
  await import(pathToFileURL(join(installation, 'graph-source-input.mjs')));
const {connect} = await import(pathToFileURL(requireInstalled.resolve('@actql/node')));
const sourceOnly = process.argv.includes('--authored-source-only');
// Reuse independently authored public sources/expectations, without converting
// them to machine Programs before submission. Keep the JSON control separate.
const caseSelection = process.argv.indexOf('--case');
const refusalSelection = process.argv.indexOf('--refusal');
const allCases = sourceOnly ? graphSourceSuccesses
  : [{name: 'graph-parallel', format: 'json',
    text: await readFile(join(installation, 'fixtures/graph-parallel.program.json'), 'utf8'),
    results: {answer: {rows: [{key: 10}, {key: 11}], columns: [
      {name: 'key', contract: {type: 'number', nullable: false}},
    ]}}}, ...graphSourceSuccesses];
const cases = caseSelection < 0 ? allCases
  : allCases.filter(entry => entry.name === process.argv[caseSelection + 1]);
const refusals = refusalSelection < 0 ? graphSourceRefusals
  : graphSourceRefusals.filter(entry => entry.name === process.argv[refusalSelection + 1]);
assert.ok(cases.length > 0 && refusals.length > 0, 'Native public selection must discover success and refusal cases');
let providerIo = 0, dispatches = 0;
// Values-only authored sources do not install or borrow an unused provider.
const DuckDBPreparedStatement = sourceOnly ? undefined : createRequire(
  requireInstalled.resolve('@actql/local-node'))('@duckdb/node-api').DuckDBPreparedStatement;
const stream = DuckDBPreparedStatement?.prototype.stream;
if (DuckDBPreparedStatement) DuckDBPreparedStatement.prototype.stream = function(...args) {
  providerIo++;
  return Reflect.apply(stream, this, args);
};
const {openInstalledRemoteHttpHost} = await import(pathToFileURL(
  requireInstalled.resolve('@actql/local-node/http-host')));
const host = await openInstalledRemoteHttpHost({
  directory: join(installation, 'sga-native-state'),
  // This isolated source-only corpus uses Values producers, so it needs no
  // external alias profile or provider schema injected by another test.
  ...(sourceOnly ? {} : {sourceProfilePath: join(installation, 'source-profile.json')}),
  beforeDispatch: () => { dispatches++; },
  authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined,
});
let loseReply = process.argv.includes('--lose-submission-reply');
const server = createServer({
  key: await readFile(join(installation, 'remote.key')),
  cert: await readFile(join(installation, 'remote.crt')),
}, (request, response) => {
  if (loseReply && request.url.endsWith('/submit-intent')) {
    loseReply = false;
    // The normal handler persists its outcome before ending the response.
    // Lose only that response; lookup must not submit the input again.
    response.end = () => {response.destroy(); return response;};
  }
  return host.handler(request, response);
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
let client;
const observe = () => {
  const journal = new DatabaseSync(join(installation, 'sga-native-state',
    'requests/client-requests.sqlite3'), {readOnly: true});
  try {
    return {providerIo, dispatches, acceptedRuns: journal.prepare(
      'SELECT COUNT(*) AS count FROM client_requests').get().count};
  } finally { journal.close(); }
};
const binaryCid = 'sha256:' + createHash('sha256')
  .update(await readFile(executable)).digest('hex');
await writeFile(join(installation, 'native-connection.json'),
  JSON.stringify({mode: 'remote', owner: 'remote', consentRefs: [], runners: []}));
await writeFile(join(installation, 'native-token.txt'), 'fixture-token\n', {mode: 0o600});
const common = ['--endpoint', endpoint,
  '--connection-root', installation, '--connection-file', 'native-connection.json',
  '--token-root', installation, '--token-file', 'native-token.txt',
  '--http-library', process.platform === 'darwin'
    ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
  '--ca', join(installation, 'remote.crt'),
  '--cert', join(installation, 'remote.crt'),
  '--key', join(installation, 'remote.key')];
const log = [];
const observations = [];
const run = (...args) => new Promise((resolve, reject) => {
  execFile(executable, [...common, ...args], {cwd: installation,
    timeout: 60000, maxBuffer: 1024 * 1024}, (error, stdout, stderr) => {
    log.push({args, code: error?.code ?? 0, stdout, stderr});
    if (error) {
      const failure = new Error(`${args[0]}: ${stderr}`, {cause: error});
      failure.outcome = stdout === '' ? undefined : JSON.parse(stdout);
      reject(failure);
    }
    else resolve(stdout);
  });
});
async function saveSubmission(name, nonce) {
  const issued = JSON.parse(await run('new-submission', '--nonce', nonce));
  assert.equal(issued.nonce, nonce);
  const file = `${name}.native-submission.json`;
  await writeFile(join(installation, file), JSON.stringify(issued));
  return {file, reference: issued};
}
function assertOriginalUnknown(error, original) {
  const match = error.message.match(/SubmissionUnknown submission-ref=(.+) lookup=lookup-submission/);
  assert.ok(match, error.message);
  assert.deepEqual(JSON.parse(match[1]), original.reference);
  assert.equal(error.outcome, undefined);
  return true;
}
try {
  const profile = JSON.parse(await run('connect'));
  assert.equal(profile.mode, 'remote');
  client = await connect({mode: 'remote', endpoint, token: 'fixture-token', durability: 'durable'});
  for (const {name, text, format, results} of cases) {
    const sourceFile = `${name}.native-source`;
    await writeFile(join(installation, sourceFile), text);
    const requestId = `sga-native-${name}-${randomUUID()}`;
    const original = await saveSubmission(name, requestId);
    const beforeSubmit = observe();
    let outcome;
    if (loseReply) {
      await assert.rejects(run('aql', '--program-file', sourceFile, '--format', format,
        '--submission-ref-file', original.file), error => assertOriginalUnknown(error, original));
      outcome = JSON.parse(await run('lookup-submission', '--submission-ref-file', original.file));
    } else outcome = JSON.parse(await run('aql', '--program-file',
      sourceFile, '--format', format, '--submission-ref-file', original.file));
    assert.equal(outcome.kind, 'ready');
    assert.deepEqual(outcome.submissionRef, original.reference);
    const accepted = outcome.admission;
    assert.ok(accepted.ref, name);
    const refFile = `${name}.native-ref.json`;
    await writeFile(join(installation, refFile), JSON.stringify(accepted.ref));
    const state = JSON.parse(await run('wait', '--ref-file', refFile));
    assert.equal(state.status, 'succeeded', name);
    const beforeRead = observe();
    assert.equal(beforeRead.acceptedRuns - beforeSubmit.acceptedRuns, 1, name);
    const attached = await client.attach(accepted.ref);
    for (const [resultName, result] of Object.entries(results)) {
      const payload = (await run('read', '--ref-file', refFile,
        '--result-name', resultName,
        '--attempt-id', `sga-native-read-${randomUUID()}`)).trimEnd();
      const rows = payload === '' ? []
        : payload.split('\n').map(line => JSON.parse(line));
      const canonical = value => Array.isArray(value) ? value.map(canonical)
        : value !== null && typeof value === 'object'
          ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
      if (result.unordered) assert.deepEqual(rows.map(row => JSON.stringify(canonical(row))).sort(),
        result.rows.map(row => JSON.stringify(canonical(row))).sort(), `${name}.${resultName}`);
      else assert.deepEqual(rows, result.rows, `${name}.${resultName}`);
      assert.deepEqual((await attached.result(resultName).describe()).columns,
        result.columns, `${name}.${resultName} declared columns/types/nullability`);
    }
    assert.deepEqual(JSON.parse(await run('aql', '--program-file', sourceFile,
      '--format', format, '--submission-ref-file', original.file)).admission.ref, accepted.ref);
    const restored = JSON.parse(await run('lookup-submission', '--submission-ref-file', original.file));
    assert.deepEqual(restored.submissionRef, original.reference);
    assert.equal(restored.kind, 'ready');
    assert.deepEqual(restored.admission.ref, accepted.ref);
    const changedSourceFile = `${name}.native-conflicting-source`;
    await writeFile(join(installation, changedSourceFile), text + '\n-- distinct submitted bytes');
    await assert.rejects(run('aql', '--program-file', changedSourceFile, '--format', format,
      '--submission-ref-file', original.file), error => assertOriginalUnknown(error, original));
    assert.deepEqual(JSON.parse(await run('lookup-submission', '--submission-ref-file', original.file)), restored);
    assert.deepEqual(observe(), beforeRead, 'read/describe/identical resubmit must not start execution again');
    observations.push({name, original: original.reference, run: accepted.ref,
      beforeSubmit, afterSubmit: beforeRead, afterReadAndLookup: observe(),
      conflictingInputRefused: true, originalLookupUnchanged: true});
    console.log(`native ${name} ${format === 'json' ? 'machine Program' : 'authored source'} and Named Results passed`);
  }
  const inputCodes = new Set(['ClientProgramInvalidInput', 'ClientParametersInvalid',
    'ClientParametersTooLarge', 'ClientProgramUnsupported', 'ClientProgramNeedsInputs', 'ClientProgramRejected']);
  for (const {name, text, format} of refusals) {
    const sourceFile = `${name}.native-source`;
    await writeFile(join(installation, sourceFile), text);
    const requestId = `sga-native-refuse-${name}-${randomUUID()}`;
    const original = await saveSubmission(name, requestId);
    const before = observe();
    let refusal;
    await assert.rejects(run('aql', '--program-file', sourceFile, '--format', format,
      '--submission-ref-file', original.file), error => {
      refusal = error.outcome;
      assert.ok(['not_accepted', 'preparation_failed'].includes(refusal?.kind),
        `durable preparation outcome: ${error.message}`);
      assert.deepEqual(refusal.submissionRef, original.reference);
      assert.ok(inputCodes.has(refusal.problem.code),
        `confirmed typed preparation refusal: ${refusal.problem.code}`);
      return true;
    });
    assert.deepEqual(JSON.parse(await run('lookup-submission', '--submission-ref-file', original.file)), refusal);
    assert.deepEqual(observe(), before, 'refused source must not admit a Run, dispatch or perform provider I/O');
    observations.push({name, original: original.reference, refusal,
      beforeSubmit: before, afterRefusalAndLookup: observe()});
    console.log(`native ${name} typed pre-admission refusal passed`);
  }
} finally {
  await writeFile(join(evidenceDirectory, 'native-sga.log'),
    JSON.stringify({binaryCid, cases: cases.map(({name, format}) => ({name, format})),
      refusals: refusals.map(({name, format}) => ({name, format})),
      lostSubmissionReply: process.argv.includes('--lose-submission-reply'), observations, log}, null, 2));
  await client?.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  if (DuckDBPreparedStatement) DuckDBPreparedStatement.prototype.stream = stream;
}
