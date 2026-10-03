import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {pathToFileURL} from 'node:url';

const installation = process.argv[2];
const executable = process.argv[3];
const evidenceDirectory = process.argv[4] ?? installation;
if (!installation || !executable) {
  throw new Error('Usage: node test-native-sga-public-source.mjs ' +
    '<packed-installation> <native-client-executable>');
}
// Same independently authored current constructor/MATCH input as the packed
// Local/HTTPS snapshot regression. Retired SGA algorithms are not fallbacks.
const cases = ['property-graph-parallel'];
const requireInstalled = createRequire(join(installation, 'package.json'));
const {openInstalledRemoteHttpHost} = await import(pathToFileURL(
  requireInstalled.resolve('@actql/local-node/http-host')));
const host = await openInstalledRemoteHttpHost({
  directory: join(installation, 'sga-native-state'),
  sourceProfilePath: join(installation, 'source-profile.json'),
  authenticate: header => header === 'Bearer fixture-token'
    ? userInfo().username : undefined,
});
const server = createServer({
  key: await readFile(join(installation, 'remote.key')),
  cert: await readFile(join(installation, 'remote.crt')),
}, host.handler);
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const endpoint = `https://127.0.0.1:${server.address().port}/`;
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
  for (const name of cases) {
    const sourceFile = `${name}.program.json`;
    await writeFile(join(installation, sourceFile),
      await readFile(join(installation, 'fixtures', sourceFile)));
    // Two distinct edge keys survive the identical endpoints; order follows
    // the constructor's input occurrence order, not product output.
    const expected = {answer: {rows: [{key: 10}, {key: 11}]}};
    const requestId = `sga-native-${name}-${randomUUID()}`;
    const accepted = JSON.parse(await run('aql', '--program-file',
      sourceFile, '--format', 'json', '--request-id', requestId));
    assert.ok(accepted.ref, name);
    const refFile = `${name}.native-ref.json`;
    await writeFile(join(installation, refFile), JSON.stringify(accepted.ref));
    const state = JSON.parse(await run('wait', '--ref-file', refFile));
    assert.equal(state.status, 'succeeded', name);
    for (const [resultName, result] of Object.entries(expected)) {
      const payload = (await run('read', '--ref-file', refFile,
        '--result-name', resultName,
        '--attempt-id', `sga-native-read-${randomUUID()}`)).trimEnd();
      const rows = payload === '' ? []
        : payload.split('\n').map(line => JSON.parse(line));
      assert.deepEqual(rows, result.rows, `${name}.${resultName}`);
    }
    console.log(`native ${name} machine Program and Named Results passed`);
  }
} finally {
  await writeFile(join(evidenceDirectory, 'native-sga.log'),
    JSON.stringify({binaryCid, cases, log}, null, 2));
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
