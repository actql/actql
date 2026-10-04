// Source registration for the same helper copied by the pack-once harness.
// All provider work happens in owned child processes, so retained restoration
// really starts with a fresh Host, Client, Native driver and module graph.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {readFile, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import test from 'node:test';
import {fileURLToPath} from 'node:url';
import {createOwnedScratch} from '../../scripts/owned-scratch.mjs';
import {canonical, loadTwoSourceFixtures, installTwoSourceFixtures}
  from '../../scripts/fixtures/two-source-public-query.mjs';

const repository = fileURLToPath(new URL('../../', import.meta.url));
const driver = fileURLToPath(new URL('../../scripts/fixtures/two-source-restart.mjs', import.meta.url));
const fixtureDirectory = fileURLToPath(new URL('./fixtures/two-source/', import.meta.url));
const duckdbPackage = resolve(repository, 'adapters/connectors/duckdb/node/package.json');
const duckdb = createRequire(duckdbPackage)('@duckdb/node-api');

async function runChild(configuration, action, caseName = action, expectedSignal) {
  const child = spawn(process.execPath, [driver, configuration, action, caseName],
    {cwd: repository, env: {...process.env}, stdio: ['ignore', 'pipe', 'pipe']});
  let output = '';
  child.stdout.on('data', chunk => { output += chunk; });
  child.stderr.on('data', chunk => { output += chunk; });
  const timeout = setTimeout(() => child.kill('SIGKILL'), 90_000);
  try {
    const [code, signal] = await new Promise((resolve, reject) => {
      child.once('error', reject);
      child.once('exit', (code, signal) => resolve([code, signal]));
    });
    assert.equal(signal, expectedSignal ?? null, `${caseName}/${action}:\n${output}`);
    assert.equal(code, expectedSignal ? null : 0, `${caseName}/${action}:\n${output}`);
  } finally { clearTimeout(timeout); }
}

test('two installed sources use normal public Local/HTTPS execution and owned recovery',
  {timeout: 300_000}, async t => {
    const scratch = await createOwnedScratch({parent: resolve(repository, '_build'),
      prefix: 'two-source-public-', label: 'two-source public Host',
      digests: () => ['retained-two-source.json']});
    const root = scratch.path;
    const fixture = await loadTwoSourceFixtures(fixtureDirectory);
    const installation = await installTwoSourceFixtures({root, fixture, duckdb});
    execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
      '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
      '-subj', '/CN=localhost', '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
    {cwd: root, stdio: 'ignore'});
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
      authorization, runtime: {
        sdk: new URL('../../packages/sdk/index.mjs', import.meta.url).href,
        local: new URL('./embedded-local.mjs', import.meta.url).href,
        embeddedLocal: true, duckdbPackage,
      }}, null, 2) + '\n');
    const report = async (caseName, action) => JSON.parse(await readFile(
      resolve(root, `${caseName}.${action}.json`), 'utf8'));

    await t.test('Local and HTTPS: distinct, equal-content, unused source, then fresh retained attach/lookup/resend', async () => {
      await runChild(configuration, 'public-success');
      await runChild(configuration, 'retained');
      assert.equal((await report('public-success', 'public-success')).cases, 8);
      const restarted = await report('retained', 'retained');
      assert.equal(restarted.cases, 8);
      assert.deepEqual(restarted.provider.sourceProviderOpens, []);
    });
    for (const [name, action] of [['exact-inventory', 'recover-exact'],
      ['changed-second-binding', 'recover-changed-binding'],
      ['changed-second-generation', 'recover-changed-generation'],
      ['local-changed-second-binding', 'recover-changed-binding'],
      ['local-changed-second-generation', 'recover-changed-generation']]) {
      await t.test(`crash before physical start: ${name}`, async () => {
        await runChild(configuration, 'crash-before', name, 'SIGKILL');
        const crashed = await report(name, 'crash-before');
        assert.equal(crashed.journal[0].dispatch_reserved, 1);
        assert.equal(crashed.journal[0].physical_start_reserved, 0);
        assert.deepEqual(crashed.provider.sourceProviderOpens, []);
        await runChild(configuration, action, name);
      });
    }
    for (const [name, action] of [['changed-second-binding', 'recover-changed-binding'],
      ['changed-second-generation', 'recover-changed-generation']]) {
      assert.equal((await report(`local-${name}`, action)).refusalCode,
        (await report(name, action)).refusalCode, 'Local and HTTPS expose the same definitive refusal');
    }
    await t.test('crash after first Native acquisition: durable started_unknown and no silent reacquisition', async () => {
      const name = 'first-acquisition-crash';
      await runChild(configuration, 'crash-first', name, 'SIGKILL');
      const crashed = await report(name, 'crash-first');
      assert.equal(crashed.journal[0].physical_start_reserved, 1);
      assert.equal(crashed.journal[0].physical_close_confirmed, 0);
      assert.equal(crashed.provider.sourceReadSessions, 1);
      await runChild(configuration, 'recover-started', name);
      assert.deepEqual((await report(name, 'recover-started')).provider.sourceProviderOpens, []);
      await runChild(configuration, 'recover-started-drift', name);
      assert.deepEqual((await report(name, 'recover-started-drift')).provider.sourceProviderOpens, []);
    });
    for (const [action, label] of [
      ['failure-second', 'real second provider fails after first acquisition, cleanup releases its retained input'],
      ['cancel-second-boundary', 'cancel at awaited second-acquisition boundary, first acquisition holding is released'],
      ['cleanup-retry', 'failed first acquisition cleanup retains ownership, Host close retries without source reread'],
    ]) {
      await t.test(label, () => runChild(configuration, action));
      await t.test(`Broad: ${label}`, () => runChild(configuration, action, `broad-${action}`));
    }
    scratch.passed();
  });
