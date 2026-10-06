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
const cases = sourceOnly ? graphSourceSuccesses
  : [{name: 'graph-parallel', format: 'json',
    text: await readFile(join(installation, 'fixtures/graph-parallel.program.json'), 'utf8'),
    results: {answer: {rows: [{key: 10}, {key: 11}], columns: [
      {name: 'key', contract: {type: 'number', nullable: false}},
    ]}}}, ...graphSourceSuccesses];
let providerIo = 0, dispatches = 0;
const {DuckDBPreparedStatement} = createRequire(
  requireInstalled.resolve('@actql/local-node'))('@duckdb/node-api');
const stream = DuckDBPreparedStatement.prototype.stream;
DuckDBPreparedStatement.prototype.stream = function(...args) {
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
const server = createServer({
  key: await readFile(join(installation, 'remote.key')),
  cert: await readFile(join(installation, 'remote.crt')),
}, host.handler);
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
const run = (...args) => new Promise((resolve, reject) => {
  execFile(executable, [...common, ...args], {cwd: installation,
    timeout: 60000, maxBuffer: 1024 * 1024}, (error, stdout, stderr) => {
    log.push({args, code: error?.code ?? 0, stdout, stderr});
    if (error) reject(new Error(`${args[0]}: ${stderr}`, {cause: error}));
    else resolve(stdout);
  });
});
try {
  const profile = JSON.parse(await run('connect'));
  assert.equal(profile.mode, 'remote');
  client = await connect({mode: 'remote', endpoint, token: 'fixture-token', durability: 'durable'});
  for (const {name, text, format, results} of cases) {
    const sourceFile = `${name}.native-source`;
    await writeFile(join(installation, sourceFile), text);
    const requestId = `sga-native-${name}-${randomUUID()}`;
    const beforeSubmit = observe();
    const accepted = JSON.parse(await run('aql', '--program-file',
      sourceFile, '--format', format, '--request-id', requestId));
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
      '--format', format, '--request-id', requestId)).ref, accepted.ref);
    assert.deepEqual(JSON.parse(await run('lookup-request', '--request-id', requestId)).ref, accepted.ref);
    assert.deepEqual(observe(), beforeRead, 'read/describe/identical resubmit must not start execution again');
    console.log(`native ${name} ${format === 'json' ? 'machine Program' : 'authored source'} and Named Results passed`);
  }
  const inputCodes = new Set(['ClientProgramInvalidInput', 'ClientParametersInvalid',
    'ClientParametersTooLarge', 'ClientProgramUnsupported', 'ClientProgramNeedsInputs', 'ClientProgramRejected']);
  for (const {name, text, format} of graphSourceRefusals) {
    const sourceFile = `${name}.native-source`;
    await writeFile(join(installation, sourceFile), text);
    const requestId = `sga-native-refuse-${name}-${randomUUID()}`;
    const before = observe();
    await assert.rejects(run('aql', '--program-file', sourceFile, '--format', format,
      '--request-id', requestId), error => {
      const code = /^aql: actql-native-client: (\w+)\s*$/u.exec(String(error.message))?.[1];
      assert.ok(inputCodes.has(code), `confirmed typed preparation refusal: ${code}`);
      return true;
    });
    assert.deepEqual(JSON.parse(await run('lookup-request', '--request-id', requestId)), {kind: 'not_found'});
    assert.deepEqual(observe(), before, 'refused source must not admit a Run, dispatch or perform provider I/O');
    console.log(`native ${name} typed pre-admission refusal passed`);
  }
} finally {
  await writeFile(join(evidenceDirectory, 'native-sga.log'),
    JSON.stringify({binaryCid, cases: cases.map(({name, format}) => ({name, format})),
      refusals: graphSourceRefusals.map(({name, format}) => ({name, format})), log}, null, 2));
  client?.close();
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
  DuckDBPreparedStatement.prototype.stream = stream;
}
