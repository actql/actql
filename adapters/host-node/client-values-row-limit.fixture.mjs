// Exercise the installed Host configuration entry, not a post-lowering edit.
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '../../packages/sdk/index.mjs';
import {connectEmbeddedLocal, openInstalledRemoteHttpHost} from './embedded-local.mjs';
import {canonicalJson} from './local-account-config.mjs';

const {directory, entrance, output, ref} = JSON.parse(process.argv[2]);
const keys = generateKeyPairSync('ed25519');
let computes = 0;
const authorization = {
  accountConfiguration: canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'read-row-capacity', entries: [{entry_id: 'write', outcome: 'allow',
      principal: {all: true}, connection: {all: true}, resource: {all: true},
      operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  observe(name, detail) {
    if (name === 'computed') computes++;
    console.log('INSTALLED_READ_121_OWNER', name, detail?.code ?? '', detail?.cause?.constructor?.name ?? '');
  },
};
const installation = {directory: join(directory, 'host'), authorization,
  ...(ref === undefined ? {valuesMaxRows: 121} : {})};
let client, host, server;
const originalCAs = getCACertificates('default');
try {
  if (entrance === 'local') client = await connectEmbeddedLocal({mode: 'local', owner: 'local', installation});
  else {
    const [key, cert] = await Promise.all(['host.key', 'host.crt'].map(name => readFile(join(directory, name))));
    setDefaultCACertificates([...originalCAs, cert.toString('utf8')]);
    host = await openInstalledRemoteHttpHost({...installation, authenticate: () => userInfo().username});
    server = createServer({key, cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    client = await connect({mode: 'remote', token: 'fixture-token', endpoint: `https://127.0.0.1:${server.address().port}/`});
  }
  console.log('INSTALLED_READ_121_PHASE', 'connected');
  const program = JSON.parse(await readFile(new URL('./fixtures/read-121.program.json', import.meta.url), 'utf8'));
  const run = ref === undefined ? await client.start(program, {requestId: 'installed-read-121'}) : await client.attach(ref);
  console.log('INSTALLED_READ_121_PHASE', 'submitted');
  const status = await run.wait({signal: AbortSignal.timeout(15000)});
  console.log('INSTALLED_READ_121_PHASE', 'terminal', status.status);
  const request = await client.lookupRequest('installed-read-121');
  console.log('INSTALLED_READ_121_PHASE', 'request-found');
  const result = run.result('answer');
  const description = await result.describe();
  console.log('INSTALLED_READ_121_PHASE', 'described');
  const reader = result.rows();
  const rows = await Array.fromAsync(reader);
  console.log('INSTALLED_READ_121_PHASE', 'read', rows.length);
  const attempt = await result.deliveryAttempt(reader.attemptId);
  console.log('INSTALLED_READ_121_PHASE', 'receipt', attempt.record?.state);
  await writeFile(output, JSON.stringify({ref: run.ref, status, request,
    description, rows, attempt, readState: reader.state(), computes}));
} catch (error) {
  console.log('INSTALLED_READ_121_FAILURE', error.code ?? error.name, error.message);
  throw error;
} finally {
  await client?.close();
  if (server) {server.closeAllConnections(); await new Promise(resolve => server.close(resolve));}
  await host?.close();
  setDefaultCACertificates(originalCAs);
}
