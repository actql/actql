// The normal installed SDK-only wheel is an external Python HTTPS consumer.
// The Host/Core/provider fixtures retain their separate Source qualifications.
import assert from 'node:assert/strict';
import {fork, spawn} from 'node:child_process';
import {appendFileSync} from 'node:fs';
import {readFile, writeFile} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import test from 'node:test';
import {publicSnowflakeFixture, publicSnowflakeInstallation} from '../adapters/connectors/snowflake/test/public-snowflake.fixture.mjs';
import {pending, resultBody} from '../adapters/connectors/snowflake/test/snowflake-read.fixture.mjs';

async function python(phase, facade, fixture, custody) {
  assert(process.env.ACTQL_PYTHON_WHEEL, 'Select an independently qualified normal SDK-only installation');
  const child = spawn(process.env.ACTQL_PYTHON_WHEEL, ['-I', '-B', '-X', `pycache_prefix=${join(fixture.root, 'unused-bytecode-prefix')}`,
    resolve('scripts/fixtures/python-snowflake-public.py'), phase, facade,
    fixture.remote.endpoint, fixture.remote.token, fixture.remote.caPath, custody],
  {cwd: fixture.root, env: {...process.env, PYTHONPATH: ''}, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', value => { stdout += value; });
  child.stderr.on('data', value => { stderr += value; });
  const terminal = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({pid: child.pid, code, signal}));
  });
  await writeFile(join(fixture.root, `python-${facade}-${phase}.json`),
    JSON.stringify({terminal, stdout, stderr}, null, 2) + '\n', {mode: 0o600});
  assert.equal(terminal.signal, null, stderr);
  assert.equal(terminal.code, 0, stderr);
  const result = JSON.parse(stdout);
  assert.equal(result.pid, terminal.pid);
  assert.deepEqual({phase: result.phase, facade: result.facade, success: result.success},
    {phase, facade, success: true});
  assert(result.sdk.includes('/site-packages/actql_sdk/'), 'Use actual installed SDK, not repository imports');
  return {terminal, result};
}

for (const facade of ['sync', 'async']) test(
  `ordinary SDK-only wheel ${facade}: Snowflake decimal38/NULL, bounded reader, typed rows and separate-process original attach`, async t => {
    const fixture = await publicSnowflakeFixture(t, 'HTTPS');
    assert.equal(fixture.state.requests.length, 0);
    fixture.state.onRequest = () => fixture.state.requests.length === 1
      ? {status: 202, body: pending('python-original')}
      : {body: resultBody({handle: 'python-original'})};
    const custody = join(fixture.root, `python-${facade}-original.json`);
    const normal = await python('normal', facade, fixture, custody);
    assert.deepEqual(fixture.state.requests.map(item => item.method), ['POST', 'GET']);
    const original = JSON.parse(await readFile(custody, 'utf8'));
    const attached = await python('attach', facade, fixture, custody);
    assert.notEqual(normal.terminal.pid, attached.terminal.pid);
    assert.deepEqual(fixture.state.requests.map(item => item.method), ['POST', 'GET'],
      'new Python process lookup/attach/explicit same-submission call never replays Snowflake');
    assert.deepEqual(JSON.parse(await readFile(custody, 'utf8')), original);
    await fixture.client.close();
    const cleanup = fixture.observations.filter(([name]) => name === 'dispatch_cleanup_completed');
    assert.equal(cleanup.length, 1);
    const usage = cleanup[0][1].resourceUsage;
    for (const field of ['heldBytes', 'reservedRetentionBytes', 'reservedExecutionBytes',
      'reservedTransferBytes', 'uncertainTransferBytes']) assert.equal(usage[field], '0', field);
    assert.equal(usage.holdings, '2', 'same cumulative capture/Compute issuance');
    assert.equal(usage.attempts, '2');
    t.diagnostic(JSON.stringify({facade, children: [normal, attached],
      providerRequests: fixture.state.requests.length, usage}));
  });

// Reuse the existing genuine Host process lifecycle and ordinary public
// startup, with this test's explicit disposable credential supplier. No
// original G Host/DB or Source is opened or modified.
async function childHost(t, installationPath) {
  const child = fork(resolve('scripts/fixtures/python-client-source-host.mjs'),
    [installationPath, ''], {stdio: ['ignore', 'ignore', 'pipe', 'ipc']});
  child.stderr.on('data', bytes => appendFileSync(
    `${installationPath}.host-${child.pid}.stderr.log`, bytes, {mode: 0o600}));
  const exited = new Promise(resolve => child.once('exit', (code, signal) => resolve({code, signal})));
  const endpoint = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', () => reject(new Error('Original Host exited before opening')));
    child.once('message', value => {assert.equal(value.pid, child.pid); resolve(value.endpoint);});
  });
  let closed = false;
  async function close() {
    if (closed) return;
    child.send('close');
    assert.deepEqual(await exited, {code: 0, signal: null}, 'original Host cleanup precedes process close');
    closed = true;
  }
  t.after(close);
  return {endpoint, pid: child.pid, close};
}

for (const facade of ['sync', 'async']) test(
  `ordinary SDK-only wheel ${facade}: same Snowflake Run and Result survive a fresh Host and Python process`, async t => {
    const fixture = await publicSnowflakeInstallation(t);
    // This is the existing source-Host fixture's explicit test-only resolver,
    // selected before any request. It is not a production fallback or grant.
    fixture.state.secret = 'test-only-secret';
    fixture.state.onRequest = entry => {
      assert.equal(entry.headers.authorization, 'Bearer test-only-secret');
      return fixture.state.requests.length === 1
        ? {status: 202, body: pending('restored-python-original')}
        : {body: resultBody({handle: 'restored-python-original'})};
    };
    const authorization = fixture.installation.authorization;
    const config = {directory: fixture.installation.directory,
      sourceProfilePath: fixture.path,
      hostTls: {keyPath: join(fixture.root, 'server.key'), certificatePath: join(fixture.root, 'server.crt')},
      authorization: {accountConfiguration: authorization.accountConfiguration,
        hostKey: authorization.hostKey, reviewers: authorization.reviewers}};
    const installationPath = join(fixture.root, 'original-host-installation.json');
    const bytes = JSON.stringify(config);
    await writeFile(installationPath, bytes, {mode: 0o600});
    const custody = join(fixture.root, `python-${facade}-original.json`);
    const first = await childHost(t, installationPath);
    fixture.remote = {endpoint: first.endpoint, token: 'owner-token', caPath: join(fixture.root, 'server.crt')};
    const normal = await python('normal', facade, fixture, custody);
    await first.close();
    const original = await readFile(custody, 'utf8');
    assert.deepEqual(fixture.state.requests.map(item => item.method), ['POST', 'GET']);
    const restored = await childHost(t, installationPath);
    assert.notEqual(first.pid, restored.pid);
    fixture.remote = {...fixture.remote, endpoint: restored.endpoint};
    const attached = await python('attach', facade, fixture, custody);
    await restored.close();
    assert.notEqual(normal.terminal.pid, attached.terminal.pid);
    assert.equal(await readFile(custody, 'utf8'), original, 'same saved reference, never regenerated');
    assert.equal(await readFile(installationPath, 'utf8'), bytes, 'same original installation');
    assert.deepEqual(fixture.state.requests.map(item => item.method), ['POST', 'GET'],
      'Host restart and public lookup/attach/same submission never resend the original Source');
    const events = (await readFile(`${installationPath}.python-owner-events.jsonl`, 'utf8'))
      .trim().split('\n').map(JSON.parse);
    assert.equal(events.filter(item => item.name === 'computed').length, 1);
    assert.equal(events.filter(item => item.name === 'acquisition_started').length, 1);
    assert.equal(events.filter(item => item.name === 'dispatch_cleanup_completed').length, 1);
    t.diagnostic(JSON.stringify({facade, hosts: [first.pid, restored.pid],
      children: [normal, attached], providerRequests: fixture.state.requests.length,
      computed: 1, originalCleanup: 1}));
  });
