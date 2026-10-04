// Runs inside the existing tarball consumer, using its one installed pack set.
// The same acceptance helper and fresh-process driver back the source tests.
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {connect} from '@actql/node';
import {openInstalledRemoteHttpHost} from '@actql/local-node/http-host';
import {canonical, loadTwoSourceFixtures, installTwoSourceFixtures}
  from './two-source-public-query.mjs';

assert.equal(typeof connect, 'function');
assert.equal(typeof openInstalledRemoteHttpHost, 'function');
assert.equal(spawnSync('moon', ['version']).error?.code, 'ENOENT');
const root = resolve('two-source-acceptance');
const fixtureDirectory = resolve('two-source-fixtures');
const driver = fileURLToPath(new URL('./two-source-restart.mjs', import.meta.url));
const duckdbPackage = fileURLToPath(new URL(
  './node_modules/@actql/local-node/package.json', import.meta.url));
const duckdb = createRequire(duckdbPackage)('@duckdb/node-api');
const reportPath = resolve('two-source-packed-report.json');
const summary = {status: 'running', runtime: {
  client: '@actql/node', httpHost: '@actql/local-node/http-host',
  localProvider: '@actql/local-node', toolchainAvailable: false,
}, commands: [], observations: {}};
const persist = () => writeFile(reportPath, JSON.stringify(summary, null, 2) + '\n');
await persist();
try {
  const fixture = await loadTwoSourceFixtures(fixtureDirectory);
  const installation = await installTwoSourceFixtures({root, fixture, duckdb});
  await mkdir(root, {recursive: true});
  for (const name of ['remote.key', 'remote.crt']) {
    await writeFile(resolve(root, name), await readFile(name));
  }
  const keys = generateKeyPairSync('ed25519');
  const authorization = {
    accountConfiguration: canonical({version: 'actql-execution-account-config/0.1',
      account_id: 'two-source-host', entries: [{entry_id: 'allow-owned-test-run',
        outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']}, exclusions: []}]}),
    reviewers: [{keyId: 'fixture-reviewer-key', reviewerId: 'fixture-reviewer',
      principalId: 'fixture-reviewer', publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
    hostKey: {keyId: 'fixture-host-key', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})},
  };
  const configuration = resolve(root, 'two-source-configuration.json');
  await writeFile(configuration, JSON.stringify({root, fixtureDirectory, installation,
    authorization, runtime: {sdk: '@actql/node', local: '@actql/local-node/http-host',
      embeddedLocal: false, duckdbPackage}}, null, 2) + '\n');
  async function runChild(action, caseName = action, expectedSignal) {
    const started = performance.now();
    const result = spawnSync(process.execPath, [driver, configuration, action, caseName],
      {encoding: 'utf8', timeout: 90_000, killSignal: 'SIGKILL', maxBuffer: 8 * 1024 * 1024});
    summary.commands.push({action, caseName, status: result.status,
      signal: result.signal, expectedSignal: expectedSignal ?? null,
      elapsedMs: performance.now() - started, error: result.error?.code ?? null});
    await persist();
    if (result.stdout) process.stdout.write(result.stdout);
    if (result.stderr) process.stderr.write(result.stderr);
    assert.equal(result.error, undefined, `${caseName}/${action}`);
    assert.equal(result.signal, expectedSignal ?? null, `${caseName}/${action}`);
    assert.equal(result.status, expectedSignal ? null : 0, `${caseName}/${action}`);
    const observation = JSON.parse(await readFile(resolve(root,
      `${caseName}.${action}.json`), 'utf8'));
    summary.observations[`${caseName}/${action}`] = observation;
    await persist();
    return observation;
  }

  const first = await runChild('public-success');
  assert.equal(first.cases, 8);
  const retained = await runChild('retained');
  assert.equal(retained.cases, 8);
  assert.deepEqual(retained.provider.sourceProviderOpens, []);
  for (const [name, action] of [['exact-inventory', 'recover-exact'],
    ['changed-second-binding', 'recover-changed-binding'],
    ['changed-second-generation', 'recover-changed-generation'],
    ['local-changed-second-binding', 'recover-changed-binding'],
    ['local-changed-second-generation', 'recover-changed-generation']]) {
    const crashed = await runChild('crash-before', name, 'SIGKILL');
    assert.equal(crashed.journal[0].dispatch_reserved, 1);
    assert.equal(crashed.journal[0].physical_start_reserved, 0);
    assert.deepEqual(crashed.provider.sourceProviderOpens, []);
    await runChild(action, name);
  }
  for (const [name, action] of [['changed-second-binding', 'recover-changed-binding'],
    ['changed-second-generation', 'recover-changed-generation']]) {
    assert.equal(summary.observations[`local-${name}/${action}`].refusalCode,
      summary.observations[`${name}/${action}`].refusalCode,
      'packed Local and HTTPS expose the same definitive refusal');
  }
  const crashed = await runChild('crash-first', 'first-acquisition-crash', 'SIGKILL');
  assert.equal(crashed.journal[0].physical_start_reserved, 1);
  assert.equal(crashed.journal[0].physical_close_confirmed, 0);
  assert.equal(crashed.provider.sourceReadSessions, 1);
  for (const action of ['recover-started', 'recover-started-drift']) {
    const resumed = await runChild(action, 'first-acquisition-crash');
    assert.deepEqual(resumed.provider.sourceProviderOpens, []);
  }
  for (const action of ['failure-second', 'cancel-second-boundary', 'cleanup-retry']) {
    await runChild(action);
    await runChild(action, `broad-${action}`);
  }
  summary.status = 'passed';
  summary.publicSuccessCases = 8;
  summary.freshRetainedCases = 8;
  summary.recoveryAndFailureScenarios = 12;
  console.log('Packed two-source Local/HTTPS success, retained recovery, refusal, failure and cleanup acceptance passed');
} catch (error) {
  summary.status = 'failed';
  throw error;
} finally { await persist(); }
