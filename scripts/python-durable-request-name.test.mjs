// A normal SDK-only installation, actual HTTPS and fresh Host/Store processes.
import assert from 'node:assert/strict';
import {fork, spawn} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {appendFileSync} from 'node:fs';
import {mkdir, mkdtemp, readFile, writeFile} from 'node:fs/promises';
import {userInfo} from 'node:os';
import {join, resolve} from 'node:path';
import test from 'node:test';
import {fixtureCertificates} from '../adapters/site-node/https-exchange-fixture.mjs';

async function host(t, installation, fault) {
  const child = fork(resolve('scripts/fixtures/python-client-source-host.mjs'), [installation, fault],
    {stdio: ['ignore', 'ignore', 'pipe', 'ipc']});
  child.stderr.on('data', bytes => appendFileSync(`${installation}.host-${child.pid}.stderr.log`, bytes, {mode: 0o600}));
  const terminal = new Promise(resolve => child.once('exit', (code, signal) => resolve({code, signal})));
  const endpoint = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', () => reject(new Error('Named fixture Host exited before admission')));
    child.once('message', value => {assert.equal(value.pid, child.pid); resolve(value.endpoint);});
  });
  let closed = false;
  const close = async () => {
    if (closed) return;
    child.send('close');
    assert.deepEqual(await terminal, {code: 0, signal: null}, 'Original Host cleanup must confirm before reopening');
    closed = true;
    appendFileSync(`${installation}.host-processes.jsonl`, JSON.stringify({pid: child.pid, code: 0, signal: null}) + '\n', {mode: 0o600});
  };
  t.after(close);
  return {endpoint, pid: child.pid, close};
}

async function python(args, root, phase) {
  assert(process.env.ACTQL_PYTHON_WHEEL, 'Select an ordinary independently qualified SDK-only wheel');
  const child = spawn(process.env.ACTQL_PYTHON_WHEEL,
    ['-I', '-B', resolve('scripts/fixtures/python-durable-request-name.py'), ...args],
    {cwd: root, env: {...process.env, PYTHONPATH: ''}, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '';
  child.stdout.on('data', bytes => {stdout += bytes;});
  child.stderr.on('data', bytes => {stderr += bytes;});
  const terminal = await new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('close', (code, signal) => resolve({pid: child.pid, code, signal}));
  });
  await writeFile(join(root, `${phase}-python.json`), JSON.stringify({terminal, stdout, stderr}, null, 2) + '\n', {mode: 0o600});
  assert.equal(terminal.code, 0, stderr);
  assert.equal(terminal.signal, null, stderr);
  const result = JSON.parse(stdout);
  assert.equal(result.success, true);
  assert(result.sdk.includes('/site-packages/actql_sdk/'));
  return {terminal, result};
}

for (const facade of ['sync', 'async']) for (const surface of ['start', 'query']) for (const loss of ['normal', 'lost'])
  test(`installed Python ${facade}/${surface}/${loss}: durable name selects the same Run after fresh Host epoch`, async t => {
    const base = resolve('_build/python-named-public');
    await mkdir(base, {recursive: true});
    // Retain fresh DB/keys/raw on both success and failure; never operate an old fixture.
    const root = await mkdtemp(join(base, 'original-'));
    const certificates = await fixtureCertificates(root);
    const keys = generateKeyPairSync('ed25519'), principalId = userInfo().username;
    const installation = join(root, 'installation.json');
    const config = {directory: join(root, 'host'),
      hostTls: {keyPath: join(root, 'resource.key'), certificatePath: join(root, 'resource.crt')},
      authorization: {accountConfiguration: JSON.stringify({version: 'actql-execution-account-config/0.1',
        account_id: 'python-named-public', entries: [{entry_id: 'source-free-original', outcome: 'allow',
          principal: {all: true}, connection: {all: true}, resource: {all: true},
          operation: {any_of: ['write']}, exclusions: []}]}),
        reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId,
          publicKey: keys.publicKey.export({type: 'spki', format: 'pem'})}],
        hostKey: {keyId: 'host', privateKey: keys.privateKey.export({type: 'pkcs8', format: 'pem'})}}};
    await writeFile(installation, JSON.stringify(config), {mode: 0o600});
    const custody = join(root, 'original.json'), children = [];
    const first = await host(t, installation, loss === 'lost' ? 'submit-named-intent' : '');
    children.push(await python(['first', facade, surface, loss, first.endpoint, certificates.caPath, custody], root, 'first'));
    await first.close();
    const original = await readFile(custody, 'utf8');
    const second = await host(t, installation, '');
    children.push(await python(['restore', facade, surface, loss, second.endpoint, certificates.caPath, custody], root, 'restore'));
    await second.close();
    assert.notEqual(first.pid, second.pid);
    assert.notEqual(children[0].terminal.pid, children[1].terminal.pid);
    assert.equal(await readFile(custody, 'utf8'), original);
    const events = (await readFile(`${installation}.python-owner-events.jsonl`, 'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(events.filter(value => value.name === 'computed').length, 1, 'One original compute; named lookup, conflict and restore never resubmit');
    const requests = (await readFile(`${installation}.python-requests.jsonl`, 'utf8')).trim().split('\n').map(JSON.parse);
    assert.equal(requests.filter(value => value.operation === 'submit-named-intent' && value.pid === first.pid).length, 1, 'Lost reply never causes an automatic second submit');
    assert.equal(requests.filter(value => value.operation === 'submit-intent' || value.operation === 'submit').length, 0);
    await writeFile(join(root, 'receipt.json'), JSON.stringify({facade, surface, loss, root,
      hostPids: [first.pid, second.pid], children, computes: 1, events, requests}, null, 2) + '\n', {mode: 0o600});
    t.diagnostic(JSON.stringify({root, facade, surface, loss, hostPids: [first.pid, second.pid],
      pythonPids: children.map(value => value.terminal.pid), computes: 1}));
  });
