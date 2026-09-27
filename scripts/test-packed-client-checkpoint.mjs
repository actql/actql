// Packed acceptance of the public Client Checkpoint connection: a clean
// installation of the packed packages, the public Client in separate
// processes and the installed Remote Host as a separate, restarted process.
// Applications use only @actql/node; they never open a journal or owner.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from 'node:fs/promises';
import {createRequire} from 'node:module';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {canonicalText} from './check-canonical-json.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'client-checkpoint-package-'));
const environment = {...process.env,
  npm_config_cache: join(root, 'npm-cache'),
  NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};

function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: command === 'npm' && args[0] === 'pack' ? 180000 : 60000});
  if (result.error || result.status !== 0) {
    throw new Error(`${command} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}`, {cause: result.error});
  }
  return result.stdout;
}

for (const name of ['client-wire', 'sdk', 'run-host-core', 'local-node',
  'node']) {
  run('npm', ['pack', '--pack-destination', root, '--json'],
    join(repository, 'packages', name));
}
await writeFile(join(root, 'package.json'),
  '{"private":true,"type":"module"}\n');
run('npm', ['install', '--ignore-scripts', '--no-save', ...[
  'client-wire', 'sdk', 'run-host-core', 'local-node', 'node'].map(name =>
  join(root, `actql-${name}-0.0.0-development.tgz`))]);
assert.deepEqual((await readdir(join(root, 'node_modules', '@actql'))).sort(),
  ['client-wire', 'local-node', 'node', 'run-host-core', 'sdk']);
// The light SDK carries no runtime, DuckDB or Store code.
const sdkFiles = (await readdir(join(root, 'node_modules/@actql/sdk'))).sort();
assert.deepEqual(sdkFiles.filter(name => /\.(m?js|json)$/u.test(name)),
  ['checkpoints.mjs', 'host-port.mjs', 'index.mjs', 'package.json']);
run('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'remote.key', '-out', 'remote.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1']);

const document = await readFile(join(repository,
  'packages/sdk/fixtures/values.json'), 'utf8');
await writeFile(join(root, 'values.json'), document);
// The Named Result is computed here from the submitted document itself,
// independently of the Host.
const expected = JSON.parse(document).stages[0].steps[0].values.rows;
await writeFile(join(root, 'expected.json'), JSON.stringify(expected));

// The installed DuckDB source for Programs with real input: a real table,
// its checked Catalog view and the source's own read account (delegate).
await writeFile(join(root, 'source-program.json'), await readFile(join(
  repository, 'adapters/connectors/duckdb/node/examples/program.json')));
{
  const environment = JSON.parse(await readFile(join(repository,
    'adapters/host-node/fixtures/query-amount-environment.json'), 'utf8'));
  const database = join(root, 'records.duckdb');
  const {DuckDBInstance} = createRequire(join(root, 'node_modules', '@actql',
    'local-node', 'package.json'))('@duckdb/node-api');
  const instance = await DuckDBInstance.create(database);
  const connection = await instance.connect();
  try {
    await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
    await connection.run('INSERT INTO records VALUES (3,30),(1,NULL),' +
      '(2,20),(3,30)');
  } finally {
    connection.closeSync();
    instance.closeSync();
  }
  await writeFile(join(root, 'source-profile.json'), JSON.stringify({
    version: 'actql-installed-duckdb-source/0.1', database, schema: 'main',
    table: 'records', sourceRef: 'connector://crm/main/r#v',
    checkEnvironmentWire: canonicalText(environment),
    accountConfigurationWire: canonicalText({
      version: 'actql-execution-account-config/0.1',
      account_id: 'source-account', entries: [{entry_id: 'source-read',
        exclusions: [], operation: {any_of: ['read']}, outcome: 'delegate',
        principal: {all: true}, connection: {all: true},
        resource: {all: true}}]}),
  }));
}

const pem = key => key.export({type: key.type === 'private' ? 'pkcs8'
  : 'spki', format: 'pem'});
const reviewer = generateKeyPairSync('ed25519');
const host = generateKeyPairSync('ed25519');
await writeFile(join(root, 'reviewer.pub'), pem(reviewer.publicKey));
await writeFile(join(root, 'reviewer.key'), pem(reviewer.privateKey),
  {mode: 0o600});
await writeFile(join(root, 'host.key'), pem(host.privateKey), {mode: 0o600});

// The installed Remote Host process. The operator selects the account
// configuration; nothing defaults to allow. The event log records protected
// dispatches and Host decision calls for the assertions.
await writeFile(join(root, 'remote-host.mjs'), `
import {appendFileSync, existsSync, readFileSync, writeFileSync} from
  'node:fs';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {openInstalledRemoteHttpHost} from
  './node_modules/@actql/local-node/adapters/host-node/embedded-local.mjs';
const log = event => appendFileSync(process.env.EVENTS, event + '\\n');
const outcome = process.env.OUTCOME;
const canonical = value => Array.isArray(value)
  ? '[' + value.map(canonical).join(',') + ']'
  : value !== null && typeof value === 'object'
    ? '{' + Object.keys(value).sort().map(key => JSON.stringify(key) + ':' +
      canonical(value[key])).join(',') + '}'
    : JSON.stringify(value);
const configuration = outcome === 'missing' ? undefined : canonical({
  version: 'actql-execution-account-config/0.1', account_id: 'remote-account',
  entries: [{entry_id: 'run-acceptance', exclusions: [],
    connection: {any_of: ['actql-remote-host']},
    operation: {any_of: ['write']}, outcome, principal: {all: true},
    resource: {any_of: ['duckdb-acquired', 'source-free-values']}}]});
const tokens = new Map([['owner-token', userInfo().username],
  ['reviewer-token', 'reviewer-principal'],
  ['reader-token', 'reader-principal'],
  ['stranger-token', 'stranger-principal']]);
// Every protected step is logged. A test may crash (SIGKILL) or stall the
// Host once at a named step.
const once = marker => !existsSync(marker) &&
  (writeFileSync(marker, ''), true);
async function mark(name) {
  log(name);
  if (process.env.CRASH_AT === name && once(process.env.STATE + '.crashed')) {
    process.kill(process.pid, 'SIGKILL');
    await new Promise(() => {});
  }
  // A fault injected into the Host's own recovery step (once, or always).
  if (process.env.FAIL_AT === name && (process.env.FAIL_ALWAYS === '1' ||
      once(process.env.STATE + '.failed'))) {
    throw Object.assign(new Error(process.env.FAIL_CODE),
      {code: process.env.FAIL_CODE});
  }
  if (process.env.STALL_AT === name && once(process.env.STATE + '.stalled')) {
    await new Promise(resolve => setTimeout(resolve,
      Number(process.env.STALL_MS)));
  }
}
const decide = process.env.DECIDE === 'none' ? undefined : view => {
  log('decide');
  return {decision: process.env.DECIDE, subject: view.subject,
    authority: 'host-policy'};
};
const host = await openInstalledRemoteHttpHost({
  directory: process.env.STATE,
  ...(process.env.ACQUIRED === '1' ?
    {sourceProfilePath: new URL('source-profile.json',
      'file://' + process.cwd() + '/').pathname} : {}),
  authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
  beforeDispatch: async () => {
    await mark('hook');
    if (process.env.HOLD_DISPATCH === '1') await new Promise(() => {});
  },
  authorization: {
    ...(configuration === undefined ? {} :
      {accountConfiguration: configuration}),
    reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
      principalId: 'reviewer-principal',
      publicKey: readFileSync('reviewer.pub', 'utf8')}],
    reviewReaders: ['reader-principal'],
    hostKey: {keyId: 'host-key', privateKey: readFileSync('host.key', 'utf8')},
    ...(decide === undefined ? {} :
      {decide, answeringAuthorities: ['host-policy']}),
    resumeAfterAnswer: process.env.RESUME_AFTER_ANSWER !== '0',
    leaseMs: Number(process.env.LEASE_MS ?? 10000),
    checkpointTtlMs: Number(process.env.TTL_MS ?? 86400000),
    faultInjection: mark,
  },
});
const server = createServer({key: readFileSync('remote.key'),
  cert: readFileSync('remote.crt')}, host.handler);
server.listen(0, '127.0.0.1', () => {
  console.log('READY:' + server.address().port);
});
// Graceful stop: running work and retention settle before the owner exits.
process.on('SIGTERM', async () => {
  server.close();
  server.closeAllConnections();
  await host.close();
  process.exit(0);
});
`);

// One application step: a separate process using only @actql/node.
await writeFile(join(root, 'client.mjs'), `
import assert from 'node:assert/strict';
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync, writeFileSync} from 'node:fs';
import {connect, ClientError, RequestHeld} from '@actql/node';
const as = token => connect({mode: 'remote',
  endpoint: process.env.ENDPOINT, token, durability: 'durable'});
const document = readFileSync('values.json', 'utf8');
const expected = JSON.parse(readFileSync('expected.json', 'utf8'));
const privateKey = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, privateKey)};
const save = (name, value) => writeFileSync(name + '.json',
  JSON.stringify(value));
const load = name => JSON.parse(readFileSync(name + '.json', 'utf8'));
const variant = id => {
  const value = JSON.parse(document);
  value.id = id;
  return JSON.stringify(value);
};
const step = process.argv[2];
const requestId = process.argv[3];
// A Program with real input reads the installed DuckDB source.
const acquired = process.env.ACQUIRED === '1';
const text = acquired ? readFileSync('source-program.json', 'utf8')
  : requestId === undefined ? document : variant(requestId);
const submitOptions = acquired ? {parameters: {minimum: 1}} : {};
async function held() {
  const owner = await as('owner-token');
  try {
    await owner.aql(text, {format: 'json', requestId, ...submitOptions});
  } catch (error) {
    assert.equal(error instanceof RequestHeld, true, String(error?.code));
    assert.equal(error.code, 'RequestHeld');
    assert.equal(error.held.state, 'waiting_checkpoint');
    assert.equal('ref' in error.held, false);
    return error.held;
  }
  assert.fail('expected a held request');
}
async function finished(id = requestId) {
  const owner = await as('owner-token');
  let lookup;
  for (let attempt = 0; attempt < 400; attempt++) {
    lookup = await owner.lookupRequest(id);
    if (lookup.kind === 'found') break;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.equal(lookup.kind, 'found', JSON.stringify(lookup));
  // Only lookup, attach, status and wait: the Host carries the Run on by
  // itself, the Client never submits again.
  const execution = await owner.attach(lookup.ref);
  let state;
  for (let attempt = 0; attempt < 400; attempt++) {
    state = await execution.wait();
    if (['succeeded', 'failed', 'cancelled', 'needs_reconciliation']
      .includes(state.status)) break;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.equal(state.status, process.env.EXPECT_STATUS ?? 'succeeded');
  if (state.status === 'succeeded' && acquired) {
    // Independent expectation from the source rows (amount >= 1).
    assert.deepEqual((await execution.result('b').all()).map(row => row.id)
      .sort(), [2, 3, 3]);
    assert.deepEqual((await execution.result('c').all()).map(row => row.id)
      .sort(), [3, 3]);
  } else if (state.status === 'succeeded') {
    assert.deepEqual(await execution.result('answer').all(), expected);
  }
  return lookup.ref;
}
const steps = {
  async allowed() {
    const owner = await as('owner-token');
    const execution = await owner.aql(text, {format: 'json', requestId});
    assert.equal((await execution.wait()).status, 'succeeded');
    assert.deepEqual(await execution.result('answer').all(), expected);
    assert.deepEqual((await (await as('reviewer-token')).checkpoints())
      .items, []);
  },
  async refused() {
    const owner = await as('owner-token');
    await assert.rejects(owner.aql(text, {format: 'json', requestId}),
      {code: process.env.CODE});
    assert.deepEqual(await owner.lookupRequest(requestId),
      {kind: 'not_found'});
  },
  async hold() { save('held-' + requestId, await held()); },
  async review() {
    const reviewer = await as('reviewer-token');
    const reader = await as('reader-token');
    const owner = await as('owner-token');
    await assert.rejects(as('stranger-token'),
      {code: 'ClientConnectionDenied'});
    const {items} = await reviewer.checkpoints();
    const summary = items.find(item =>
      item.subject.requestId === requestId);
    assert.ok(summary);
    assert.equal(summary.subject.kind, 'prepare_attempt');
    assert.equal(JSON.stringify(items).includes('"rows"'), false);
    // Separate permissions: status and answer rights do not read the body.
    await assert.rejects(reviewer.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(owner.reviewCheckpoint(summary),
      {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint('sha256:' +
      '0'.repeat(64)), {code: 'CheckpointReviewDenied'});
    await assert.rejects(reader.reviewCheckpoint(summary, {maxBytes: 16}),
      {code: 'CheckpointReviewTooLarge'});
    // An aborted read ends only the read attempt.
    const controller = new AbortController();
    controller.abort();
    await assert.rejects(reader.reviewCheckpoint(summary,
      {signal: controller.signal}));
    assert.equal((await owner.lookupRequest(requestId)).state,
      'waiting_checkpoint');
    const review = await reader.reviewCheckpoint(summary);
    const projection = JSON.parse(new TextDecoder().decode(review.bytes));
    assert.equal(projection.version, 'actql-run-review-projection/0.1');
    assert.equal(projection.displayed_scope.request_id, requestId);
    assert.deepEqual(JSON.parse(projection.displayed_scope.document),
      JSON.parse(text));
    save('summary-' + requestId, summary);
  },
  async approve() {
    const reviewer = await as('reviewer-token');
    const summary = load('summary-' + requestId);
    // The first reply is lost in transit: the answer is stored, the Client
    // only knows it is unknown, and resends the identical signed answer.
    const real = globalThis.fetch;
    let dropped = false;
    globalThis.fetch = async (url, init) => {
      const response = await real(url, init);
      if (!dropped && String(url).endsWith('/resolve')) {
        dropped = true;
        await response.body?.cancel();
        throw new TypeError('reply lost');
      }
      return response;
    };
    let lost;
    try {
      await reviewer.resolveCheckpoints([{checkpoint: summary,
        decision: 'approved'}], {signer});
    } catch (error) { lost = error; }
    globalThis.fetch = real;
    assert.equal(lost?.code, 'ResolutionUnknown');
    const resent = await reviewer.resolveCheckpoints(lost.signed);
    assert.deepEqual(resent.results.map(item => item.status), ['duplicate']);
    assert.equal(resent.results[0].decision, 'approved');
    // A contradicting answer cannot replace it.
    const contradict = await reviewer.resolveCheckpoints([{checkpoint:
      summary, decision: 'rejected'}], {signer});
    assert.deepEqual(contradict.results.map(item => item.status),
      ['conflicting']);
  },
  async finished() { save('ref-' + requestId, await finished()); },
  // Cancel a held request by its ID (no Run yet); the first reply is lost
  // and the same cancellation is resent and matched.
  async cancelHeld() {
    const owner = await as('owner-token');
    const real = globalThis.fetch;
    let dropped = false;
    globalThis.fetch = async (url, init) => {
      const response = await real(url, init);
      if (!dropped && String(url).endsWith('/cancel-request')) {
        dropped = true;
        await response.body?.cancel();
        throw new TypeError('reply lost');
      }
      return response;
    };
    let lost;
    try { await owner.cancelRequest(requestId); }
    catch (error) { lost = error; }
    globalThis.fetch = real;
    assert.equal(lost?.code, 'CancellationUnknown');
    const again = await owner.cancelRequest(requestId);
    assert.equal(again.kind, 'already_requested');
    assert.equal('ref' in again, false);
    await assert.rejects((await as('reviewer-token'))
      .cancelRequest(requestId), {code: 'ClientConnectionDenied'});
  },
  // Cancel a request with no Run yet whose answer was already stored.
  async cancelResuming() {
    const owner = await as('owner-token');
    const cancelled = await owner.cancelRequest(requestId);
    assert.equal(cancelled.kind, 'accepted');
    assert.equal('ref' in cancelled, false);
  },
  // Cancel the existing Run of a held request through the public Client.
  async cancelRun() {
    const owner = await as('owner-token');
    const lookup = await owner.lookupRequest(requestId);
    assert.equal(lookup.kind, 'found');
    const execution = await owner.attach(lookup.ref);
    await execution.cancel();
    assert.equal((await execution.status()).status, 'cancelled');
  },
  // The same request submitted again: the existing Run, which only the
  // Host's resumed authorization may start.
  async resubmitted() {
    const owner = await as('owner-token');
    const execution = await owner.aql(text, {format: 'json', requestId});
    let state;
    for (let attempt = 0; attempt < 400; attempt++) {
      state = await execution.wait();
      if (['succeeded', 'failed', 'cancelled'].includes(state.status)) break;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    assert.equal(state.status, process.env.EXPECT_STATUS);
  },
  // An answer after the request was cancelled is not resumed.
  async lateApproval() {
    const reviewer = await as('reviewer-token');
    const summary = load('summary-' + requestId);
    const answered = await reviewer.resolveCheckpoints([{checkpoint: summary,
      decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['cancelled']);
  },
  async resumeWaiting() {
    const owner = await as('owner-token');
    const lookup = await owner.lookupRequest(requestId);
    assert.equal(lookup.kind, 'held');
    assert.equal(lookup.state, 'resuming');
  },
  async ended() {
    const owner = await as('owner-token');
    let lookup;
    for (let attempt = 0; attempt < 400; attempt++) {
      lookup = await owner.lookupRequest(requestId);
      if (lookup.state === 'ended') break;
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    assert.equal(lookup.kind, 'held');
    assert.equal(lookup.state, 'ended');
    assert.equal(lookup.endReason, process.env.END_REASON);
    assert.equal('ref' in lookup, false);
  },
  async batch() {
    const reviewer = await as('reviewer-token');
    const [first, second] = process.argv.slice(3).map(id =>
      load('summary-' + id));
    const answered = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'rejected'},
      {checkpoint: second, decision: 'approved'}], {signer});
    assert.deepEqual(answered.results.map(item => item.status),
      ['committed', 'committed']);
    const mixed = await reviewer.resolveCheckpoints([
      {checkpoint: first, decision: 'approved'},
      ...answered.signed.slice(1)], {signer});
    assert.deepEqual(mixed.results.map(item => item.status),
      ['conflicting', 'duplicate']);
    // An answer from a principal that is not the signing reviewer.
    const reader = await as('reader-token');
    await assert.rejects(reader.resolveCheckpoints(answered.signed),
      {code: 'CheckpointAnswerDenied'});
  },
};
await steps[step]();
`);

async function startHost(name, options) {
  const child = spawn(process.execPath, ['remote-host.mjs'], {cwd: root,
    env: {...environment, STATE: join(root, name), EVENTS: join(root,
      `${name}.events`), OUTCOME: 'delegate', DECIDE: 'none',
    RESUME_AFTER_ANSWER: '1', HOLD_DISPATCH: '0', ...options}});
  let output = '';
  const port = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      child.kill('SIGKILL');
      reject(new Error(`Remote Host readiness timed out: ${output}`));
    }, 30000);
    child.stdout.setEncoding('utf8').on('data', chunk => {
      output += chunk;
      const ready = output.match(/READY:(\d+)/u);
      if (ready) {
        clearTimeout(timer);
        resolve(Number(ready[1]));
      }
    });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('exit', code => {
      clearTimeout(timer);
      reject(new Error(`Remote Host exited before ready (${code}): ${output}`));
    });
  });
  return {child, endpoint: `https://127.0.0.1:${port}/`, output: () => output};
}
async function stopHost(started, signal = 'SIGTERM') {
  if (started.child.exitCode !== null) return;
  const stopped = once(started.child, 'exit');
  started.child.kill(signal);
  await stopped;
}
function client(started, step, args = [], extra = {}) {
  const result = spawnSync(process.execPath, ['client.mjs', step, ...args], {
    cwd: root, encoding: 'utf8', timeout: 60000,
    env: {...environment, ENDPOINT: started.endpoint, ...extra}});
  if (result.status !== 0) {
    throw new Error(`client ${step} ${args.join(' ')} failed:\n` +
      `${result.stdout}\n${result.stderr}\nHost:\n${started.output()}`);
  }
}
async function events(name) {
  try {
    return (await readFile(join(root, `${name}.events`), 'utf8'))
      .split('\n').filter(Boolean);
  } catch (error) {
    if (error?.code === 'ENOENT') return [];
    throw error;
  }
}
// Separate counts of each protected step: the Host decision call, the
// dispatch reservation, the pre-start hook, the physical start reservation
// and the completed computation.
const STEPS = ['decide', 'dispatch_reserved', 'hook',
  'physical_start_reserved', 'acquisition_started', 'acquisition_completed',
  'computed'];
async function counts(name) {
  const logged = await events(name);
  return Object.fromEntries(STEPS.map(step =>
    [step, logged.filter(item => item === step).length]));
}
const none = Object.fromEntries(STEPS.map(step => [step, 0]));
const ran = (extra = {}) => ({...none, dispatch_reserved: 1, hook: 1,
  physical_start_reserved: 1, computed: 1, ...extra});
// The answer deadline of a request's Checkpoint, from its listed summary.
const expiresAt = async requestId => Date.parse(JSON.parse(await readFile(
  join(root, `summary-${requestId}.json`), 'utf8')).expiresAt);
// Wait until a wall-clock instant has passed (plus a margin).
const untilPast = async instant => {
  const remaining = instant + 500 - Date.now();
  if (remaining > 0) {
    await new Promise(resolve => setTimeout(resolve, remaining));
  }
};
async function withHost(name, options, work) {
  const started = await startHost(name, options);
  try { return await work(started); }
  finally { await stopHost(started); }
}
// A Host that crashes at its step, possibly before it is ready.
async function crashed(name, options) {
  const child = spawn(process.execPath, ['remote-host.mjs'], {cwd: root,
    env: {...environment, STATE: join(root, name), EVENTS: join(root,
      `${name}.events`), OUTCOME: 'delegate', DECIDE: 'none',
    RESUME_AFTER_ANSWER: '1', HOLD_DISPATCH: '0', ...options}});
  let output = '';
  child.stdout.setEncoding('utf8').on('data', chunk => { output += chunk; });
  child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
  const timer = setTimeout(() => child.kill('SIGTERM'), 30000);
  const [code, signal] = await once(child, 'exit');
  clearTimeout(timer);
  assert.equal(signal, 'SIGKILL', `${name}: ${code} ${output}`);
}
// Hold one request and approve it on a Host that only stores answers.
async function approvedAndStopped(name, requestId, extra = {}) {
  // Client steps use the same Program kind as the Host (real input or not).
  const env = extra.ACQUIRED === undefined ? {} : {ACQUIRED: extra.ACQUIRED};
  await withHost(name, extra, started => client(started, 'hold',
    [requestId], env));
  await withHost(name, {RESUME_AFTER_ANSWER: '0', ...extra}, started => {
    client(started, 'review', [requestId], env);
    client(started, 'approve', [requestId], env);
    client(started, 'resumeWaiting', [requestId], env);
  });
}
// Wait (bounded) until the running Host has released the held evidence.
async function untilRetired(name, maxWaitMs = 20_000) {
  const deadline = Date.now() + maxWaitMs;
  while (Date.now() < deadline) {
    try { await assertRetired(name); return; }
    catch {}
    await new Promise(resolve => setTimeout(resolve, 200));
  }
  await assertRetired(name);
}
// The continuation's private evidence is retired after a terminal Run and
// held while the Run is not terminal.
async function assertRetired(name, state = 'retired') {
  const ledgers = join(root, name, 'checkpoints', 'attempts');
  for (const file of await readdir(ledgers)) {
    const ledger = JSON.parse(await readFile(join(ledgers, file), 'utf8'));
    for (const holding of ledger.holdings.filter(item =>
      item.name !== 'invocation_request')) {
      assert.equal(holding.state, state, `${file} ${holding.name}`);
    }
  }
}

// 1 and 9. allow runs with no Checkpoint and no Host policy call; deny and a
// missing configuration make no protected call.
await withHost('allow', {OUTCOME: 'allow', DECIDE: 'permit'}, started =>
  client(started, 'allowed', ['allow-a']));
assert.deepEqual(await counts('allow'), ran());
for (const [outcome, code] of [['deny', 'ACTQL_E_ACCOUNT_DENIED'],
  ['missing', 'ACTQL_E_ACCOUNT_CONFIG_INVALID']]) {
  await withHost(outcome, {OUTCOME: outcome}, started =>
    client(started, 'refused', [`${outcome}-a`], {CODE: code}));
  assert.deepEqual(await counts(outcome), none, outcome);
}

// 2. delegate with an immediate Host permit or reject.
await withHost('permit', {DECIDE: 'permit'}, started =>
  client(started, 'allowed', ['permit-a']));
assert.deepEqual(await counts('permit'), ran({decide: 1}));
await withHost('reject', {DECIDE: 'reject'}, started =>
  client(started, 'refused', ['reject-a'],
    {CODE: 'ACTQL_E_DELEGATION_REJECTED'}));
assert.deepEqual(await counts('reject'), {...none, decide: 1});

// 3, 4, 6 and 7. Hold -> Host exits -> review, lost-reply answer and
// contradiction from other processes on an answer-only Host -> a restarted
// Host resumes by itself -> Named Result, with lookup/attach/wait only.
await approvedAndStopped('held', 'held-a');
assert.deepEqual(await counts('held'), none);
await withHost('held', {}, started => client(started, 'finished',
  ['held-a']));
assert.deepEqual(await counts('held'), ran());
await assertRetired('held');

// 4. The Host crashes at each step of the resume; a restarted Host carries
// the same request on by itself (no Client resubmission). Before the
// physical start reservation it starts the Run once; after it, the start is
// unknown and is never sent again.
for (const [step, expectStatus, expected] of [
  ['resume_claimed', 'succeeded', ran()],
  ['definition_admitted', 'succeeded', ran()],
  ['dispatch_reserved', 'succeeded', ran({dispatch_reserved: 2})],
  ['hook', 'succeeded', ran({dispatch_reserved: 2, hook: 2})],
  ['physical_start_reserved', 'needs_reconciliation', ran({computed: 0})],
]) {
  // A short lease: the crashed claimant's lease must lapse for the restart.
  const name = `crash-${step}`;
  await approvedAndStopped(name, name, {LEASE_MS: '2000'});
  await crashed(name, {CRASH_AT: step, LEASE_MS: '2000'});
  await withHost(name, {LEASE_MS: '2000'}, started => client(started,
    'finished', [name], {EXPECT_STATUS: expectStatus}));
  assert.deepEqual(await counts(name), expected,
    `${step}: ${(await events(name)).join(',')}`);
  await assertRetired(name, expectStatus === 'succeeded' ? 'retired'
    : 'held');
}

// 5. A Run defined but not started when the Host stopped is authorized
// again before its physical start: a configuration changed to deny, or an
// approval that expired meanwhile, starts nothing; the Run fails before
// dispatch.
for (const [name, crashAt, restart, extra, step] of [
  ['deny-defined', 'definition_admitted', {OUTCOME: 'deny'},
    {LEASE_MS: '2000'}, 'finished'],
  ['deny-reserved', 'hook', {OUTCOME: 'deny'}, {LEASE_MS: '2000'},
    'finished'],
  ['expired-defined', 'definition_admitted', {},
    {TTL_MS: '90000', LEASE_MS: '2000'}, 'finished'],
  // The owner submits the same request again after the restart: it is
  // the existing Run, still started only under the resumed authorization.
  ['expired-resubmit', 'definition_admitted', {},
    {TTL_MS: '90000', LEASE_MS: '2000'}, 'resubmitted'],
]) {
  // Two Host starts, review and signing must fit before these expiry cases
  // inject their pre-start crash. Expiry is then observed after the crash.
  await approvedAndStopped(name, name, extra);
  await crashed(name, {CRASH_AT: crashAt, ...extra});
  // Past the Checkpoint's answer deadline, which bounds the approval.
  if (extra.TTL_MS !== undefined) await untilPast(await expiresAt(name));
  await withHost(name, {...restart, ...extra}, started => client(started,
    step, [name], {EXPECT_STATUS: 'failed'}));
  const counted = await counts(name);
  assert.equal(counted.physical_start_reserved, 0, name);
  assert.equal(counted.computed, 0, name);
  await assertRetired(name);
}

// 8. A Run defined before a crash is cancelled through the public Client
// on a restarted Host whose resume is stalled; that Host is killed. The
// next Host settles the held request as cancelled by itself: no physical
// start, and its evidence is released.
{
  const name = 'cancel-restart';
  await approvedAndStopped(name, name, {LEASE_MS: '2000'});
  // Keep the dead claimant fenced through startup. Otherwise a slow start
  // can enter the long injected stall before the HTTP listener exists.
  await crashed(name, {CRASH_AT: 'definition_admitted', LEASE_MS: '30000'});
  const stalled = await startHost(name, {LEASE_MS: '2000',
    STALL_AT: 'resume_claimed', STALL_MS: '600000'});
  try {
    const deadline = Date.now() + 40000;
    for (;;) {
      try { await readFile(join(root, name + '.stalled')); break; }
      catch (error) { if (error.code !== 'ENOENT') throw error; }
      assert(Date.now() < deadline, 'resume did not reach its injected stall');
      await new Promise(resolve => setTimeout(resolve, 25));
    }
    client(stalled, 'cancelRun', [name]);
  }
  finally { await stopHost(stalled, 'SIGKILL'); }
  // The running Host settles once the killed claimant's lease lapses.
  await withHost(name, {LEASE_MS: '2000'}, async started => {
    client(started, 'finished', [name], {EXPECT_STATUS: 'cancelled'});
    // The killed claimant held a 30-second lease. A fast restart can observe
    // the cancelled Run before that lease permits its preparation to retire.
    await untilRetired(name, 45_000);
  });
  const counted = await counts(name);
  assert.equal(counted.physical_start_reserved, 0, name);
  assert.equal(counted.computed, 0, name);
}

// D-next-2 (A3): a Program with real input is held before its source read,
// answered later from another process, and resumed by a restarted Host to
// Results computed from the real DuckDB table. The source is read once.
// The run itself is allowed, so the only hold is the source read.
const readOnly = {ACQUIRED: '1', OUTCOME: 'allow'};
const readHeld = ran({acquisition_started: 1, acquisition_completed: 1});
await approvedAndStopped('acq-held', 'acq-held', readOnly);
assert.deepEqual(await counts('acq-held'), none);
await withHost('acq-held', readOnly, started =>
  client(started, 'finished', ['acq-held'], readOnly));
assert.deepEqual(await counts('acq-held'), readHeld);
await assertRetired('acq-held');

// A6: the Host crashes after the acquisition started. The restarted Host
// keeps the Run unknown and never reads the source again.
await approvedAndStopped('acq-crash', 'acq-crash', {...readOnly,
  LEASE_MS: '2000'});
await crashed('acq-crash', {...readOnly, LEASE_MS: '2000',
  CRASH_AT: 'acquisition_started'});
await withHost('acq-crash', {...readOnly, LEASE_MS: '2000'}, started =>
  client(started, 'finished', ['acq-crash'], {...readOnly,
    EXPECT_STATUS: 'needs_reconciliation'}));
assert.deepEqual(await counts('acq-crash'),
  ran({acquisition_started: 1, computed: 0}));
await assertRetired('acq-crash', 'held');

// C1 with real input: the owner cancels a request held before its source
// read; nothing is read and its evidence is released.
await withHost('acq-cancel', readOnly, started => {
  client(started, 'hold', ['acq-cancel'], readOnly);
  client(started, 'review', ['acq-cancel'], readOnly);
  client(started, 'cancelHeld', ['acq-cancel'], readOnly);
  client(started, 'ended', ['acq-cancel'], {...readOnly,
    END_REASON: 'cancelled'});
});
assert.deepEqual(await counts('acq-cancel'), none);
await assertRetired('acq-cancel');

// 8. The owner cancels a held request before any Run exists, from another
// process; the lost reply is resent and matched; a late answer does not
// resume it; nothing starts; its evidence is released.
await withHost('cancel-held', {}, started => {
  client(started, 'hold', ['cancel-held']);
  client(started, 'review', ['cancel-held']);
  client(started, 'cancelHeld', ['cancel-held']);
  client(started, 'ended', ['cancel-held'], {END_REASON: 'cancelled'});
  client(started, 'lateApproval', ['cancel-held']);
});
assert.deepEqual(await counts('cancel-held'), none);
await assertRetired('cancel-held');

// 8. A request answered on an answer-only Host is cancelled there; the next
// Host start settles it by itself: no start, evidence released.
await withHost('cancel-resuming', {}, started =>
  client(started, 'hold', ['cancel-resuming']));
// The answer and the cancellation reach the same answer-only Host, before
// any Host start could resume the request.
await withHost('cancel-resuming', {RESUME_AFTER_ANSWER: '0'}, started => {
  client(started, 'review', ['cancel-resuming']);
  client(started, 'approve', ['cancel-resuming']);
  client(started, 'cancelResuming', ['cancel-resuming']);
});
await withHost('cancel-resuming', {}, async started => {
  client(started, 'ended', ['cancel-resuming'], {END_REASON: 'cancelled'});
  await untilRetired('cancel-resuming');
});
assert.deepEqual(await counts('cancel-resuming'), none);

// 6. The Run-side duty: a Host that stopped after computing but before
// recording the end. A transient failure of its recovery is retried by the
// Host itself (no answer, submit or restart); a permanent one is observed
// and not retried, and the evidence is kept.
for (const [name, fail, retried] of [
  ['recover-transient', {FAIL_CODE: 'TransientRunReadFailure'}, true],
  ['recover-permanent', {FAIL_CODE: 'HeldRunDefinitionMissing',
    FAIL_ALWAYS: '1'}, false],
]) {
  await approvedAndStopped(name, name, {LEASE_MS: '1000'});
  await crashed(name, {CRASH_AT: 'computed', LEASE_MS: '1000'});
  const observedBefore = (await events(name)).filter(item =>
    item === 'run_observed').length;
  const started = await startHost(name, {LEASE_MS: '1000',
    FAIL_AT: 'run_observed', ...fail});
  try {
    await new Promise(resolve => setTimeout(resolve, 2500));
    const observed = (await events(name)).filter(item =>
      item === 'run_observed').length - observedBefore;
    assert.equal(observed, retried ? 2 : 1, name);
    client(started, 'finished', [name]);
  } finally { await stopHost(started); }
  assert.deepEqual({...await counts(name), decide: 0}, ran(), name);
  await assertRetired(name, retried ? 'retired' : 'held');
}

// 5. A claim whose lease lapses before the admission sends nothing; the
// Host itself continues the durable intent under a later claim.
await approvedAndStopped('lease', 'lease-a', {LEASE_MS: '1000'});
await withHost('lease', {LEASE_MS: '1000', STALL_AT: 'resume_claimed',
  STALL_MS: '1500'}, started => client(started, 'finished', ['lease-a']));
assert.deepEqual(await counts('lease'), ran());

// 5. An approval whose own permission expired before the Host resumed
// starts nothing; the request ends without a Run.
await approvedAndStopped('expired', 'expired-a', {TTL_MS: '10000'});
await untilPast(await expiresAt('expired-a'));
await withHost('expired', {}, started => client(started, 'ended',
  ['expired-a'], {END_REASON: 'failed'}));
assert.deepEqual(await counts('expired'), none);

// 5. A configuration changed while waiting (to allow) does not resume the
// held request: it ends without a Run and nothing is dispatched.
await approvedAndStopped('changed', 'changed-a');
await withHost('changed', {OUTCOME: 'allow'}, started =>
  client(started, 'ended', ['changed-a'],
    {END_REASON: 'revalidation_failed'}));
assert.deepEqual(await counts('changed'), none);

// 5. A second Host on the same state is refused by the Store's single
// owner before it can claim anything; the first resumes exactly once.
await approvedAndStopped('race', 'race-a');
const owning = await startHost('race', {});
try {
  await assert.rejects(startHost('race', {}), /PublicationStoreBusy/u);
  client(owning, 'finished', ['race-a']);
} finally { await stopHost(owning); }
assert.deepEqual(await counts('race'), ran());

// 6. A batch with independent per-item results; rejection ends the request
// without a Run, the approved one runs on the next Host start.
await withHost('batch', {RESUME_AFTER_ANSWER: '0'}, started => {
  client(started, 'hold', ['batch-a']);
  client(started, 'hold', ['batch-b']);
  client(started, 'review', ['batch-a']);
  client(started, 'review', ['batch-b']);
  client(started, 'batch', ['batch-a', 'batch-b']);
  client(started, 'ended', ['batch-a'], {END_REASON: 'rejected'});
  client(started, 'resumeWaiting', ['batch-b']);
});
await withHost('batch', {}, started =>
  client(started, 'finished', ['batch-b']));
assert.deepEqual(await counts('batch'), ran());
console.log('packed client Checkpoint acceptance: ok');
