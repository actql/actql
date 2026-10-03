// Executed from an external tarball installation. The unchanged independent
// frontend fixtures go through the public Client and installed Local Host.
import assert from 'node:assert/strict';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {resolve} from 'node:path';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {exerciseNearestPublicInput} from './nearest-public-input.mjs';
import {installNearestSource} from './nearest-installed-source.mjs';
import {canonical, observeTwoSourceProvider, readTwoSourceJournal}
  from './two-source-public-query.mjs';

const root = resolve('nearest-public-acceptance');
const fixtureDirectory = resolve('nearest-keep-fixtures');
await mkdir(root, {recursive: true});
const duckdb = createRequire(new URL('./node_modules/@actql/local-node/package.json',
  import.meta.url))('@duckdb/node-api');
const templatePath = resolve('nearest-source-template.json');
const queries = await installNearestSource({root, name: 'queries',
  templatePath, duckdb});
const candidates = await installNearestSource({root, name: 'candidates',
  templatePath, duckdb});
const sourceProfilePaths = [queries.profile, candidates.profile];
const provider = observeTwoSourceProvider(duckdb,
  {queries: queries.database, candidates: candidates.database});
const tls = {key: await readFile(resolve('remote.key')),
  cert: await readFile(resolve('remote.crt'))};
const originalCAs = getCACertificates('default');
setDefaultCACertificates([...originalCAs, tls.cert.toString('utf8')]);
const keys = generateKeyPairSync('ed25519');
const authorization = {
  accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
    account_id: 'nearest-public-host', entries: [{entry_id: 'allow-test-run',
      outcome: 'allow', principal: {all: true}, connection: {all: true},
      resource: {all: true}, operation: {any_of: ['write']}, exclusions: []}]}),
  reviewers: [{keyId: 'nearest-reviewer-key', reviewerId: 'nearest-reviewer',
    principalId: userInfo().username,
    publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
  hostKey: {keyId: 'nearest-host-key',
    privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
};
const report = {cases: {}, sourceProfiles: sourceProfilePaths.length};
try {
  for (const mode of ['local', 'https']) {
    const directory = resolve(root, `${mode}-state`);
    const observe = () => ({...provider.snapshot(),
      acceptedRuns: readTwoSourceJournal(directory).length});
    let host, server;
    let options = {mode: 'local', owner: 'local', durability: 'durable',
      installation: {directory, sourceProfilePaths, authorization}};
    if (mode === 'https') {
      host = await openInstalledRemoteHttpHost({directory, sourceProfilePaths,
        authorization, authenticate: header => header === 'Bearer nearest-fixture'
          ? userInfo().username : undefined});
      server = createServer(tls, host.handler);
      await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
      options = {mode: 'remote', durability: 'durable', token: 'nearest-fixture',
        endpoint: `https://127.0.0.1:${server.address().port}/`};
    }
    try {
      await exerciseNearestPublicInput(connect, options,
        {directory: fixtureDirectory, requestPrefix: `nearest-${mode}`, observe});
      report.cases[mode] = {status: 'passed',
        admittedRuns: readTwoSourceJournal(directory).length};
    } finally {
      if (server) {
        server.closeAllConnections();
        await new Promise(resolve => server.close(resolve));
      }
      await host?.close();
    }
  }
  assert.equal(report.cases.local.status, 'passed');
  assert.equal(report.cases.https.status, 'passed');
  await writeFile(resolve('nearest-public-report.json'),
    JSON.stringify(report, null, 2) + '\n');
  console.log('Packed NEAREST Local and HTTPS acceptance passed');
} finally {
  provider.restore();
  setDefaultCACertificates(originalCAs);
}
