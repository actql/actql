import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {createHash, randomUUID} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
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
const {openInstalledRemoteHttpHost} = await import(pathToFileURL(join(
  installation, 'node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs')));
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
await writeFile(join(installation, 'normalize-rows.named.aql'),
  await readFile(join(installation, 'sga-fixtures/normalize-rows.named.aql')));
const common = ['--endpoint', endpoint,
  '--connection-root', installation, '--connection-file', 'native-connection.json',
  '--token-root', installation, '--token-file', 'native-token.txt',
  '--http-library', process.platform === 'darwin'
    ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
  '--ca', join(installation, 'remote.crt'),
  '--cert', join(installation, 'remote.crt'),
  '--key', join(installation, 'remote.key')];
const log = [];
const requestId = `sga-native-normalize-rows-${randomUUID()}`;
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
  const accepted = JSON.parse(await run('aql', '--program-file',
    'normalize-rows.named.aql', '--format', 'aql-text',
    '--request-id', requestId));
  assert.ok(accepted.ref);
  await writeFile(join(installation, 'sga-native-ref.json'), JSON.stringify(accepted.ref));
  const state = JSON.parse(await run('wait', '--ref-file', 'sga-native-ref.json'));
  assert.equal(state.status, 'succeeded');
  const rows = (await run('read', '--ref-file', 'sga-native-ref.json',
    '--result-name', 'answer', '--attempt-id', `sga-native-read-${randomUUID()}`))
    .trimEnd().split('\n').map(line => JSON.parse(line));
  assert.deepEqual(rows, [{id: 'A'}, {id: 'B'}]);
  console.log('native SGA source and Named Result passed');
} finally {
  await writeFile(join(evidenceDirectory, 'native-sga.log'),
    JSON.stringify({binaryCid, log}, null, 2));
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
  await host.close();
}
