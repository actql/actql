// Packed acceptance of the public Client Checkpoint connection: a clean
// installation of the packed packages, the public Client in separate
// processes and the installed Remote Host as a separate, restarted process.
// Applications use only @actql/node; they never open a journal or owner.
import assert from 'node:assert/strict';
import {spawn, spawnSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {once} from 'node:events';
import {mkdir, mkdtemp, readFile, readdir, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {fileURLToPath} from 'node:url';

const repository = fileURLToPath(new URL('../', import.meta.url));
const build = join(repository, '_build');
await mkdir(build, {recursive: true});
const root = await mkdtemp(join(build, 'client-checkpoint-package-'));
const environment = {...process.env,
  npm_config_cache: join(root, 'npm-cache'),
  NODE_EXTRA_CA_CERTS: join(root, 'remote.crt')};

function run(command, args, cwd = root) {
  const result = spawnSync(command, args, {cwd, env: environment,
    encoding: 'utf8', timeout: 60000});
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
    resource: {any_of: ['source-free-values']}}]});
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
    leaseMs: Number(process.env.LEASE_MS ?? 2000),
    checkpointTtlMs: Number(process.env.TTL_MS ?? 86400000),
    observe: mark,
  },
});
const server = createServer({key: readFileSync('remote.key'),
  cert: readFileSync('remote.crt')}, host.handler);
server.listen(0, '127.0.0.1', () => {
  console.log('READY:' + server.address().port);
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
const text = requestId === undefined ? document : variant(requestId);
async function held() {
  const owner = await as('owner-token');
  try {
    await owner.aql(text, {format: 'json', requestId});
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
    if (['succeeded', 'failed', 'cancelled'].includes(state.status)) break;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.equal(state.status, process.env.EXPECT_STATUS ?? 'succeeded');
  if (state.status === 'succeeded') {
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
    child.stdout.setEncoding('utf8').on('data', chunk => {
      output += chunk;
      const ready = output.match(/READY:(\d+)/u);
      if (ready) resolve(Number(ready[1]));
    });
    child.stderr.setEncoding('utf8').on('data', chunk => { output += chunk; });
    child.on('exit', code => reject(new Error(
      `Remote Host exited before ready (${code}): ${output}`)));
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
  'physical_start_reserved', 'computed'];
async function counts(name) {
  const logged = await events(name);
  return Object.fromEntries(STEPS.map(step =>
    [step, logged.filter(item => item === step).length]));
}
const none = Object.fromEntries(STEPS.map(step => [step, 0]));
const ran = (extra = {}) => ({...none, dispatch_reserved: 1, hook: 1,
  physical_start_reserved: 1, computed: 1, ...extra});
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
  await withHost(name, extra, started => client(started, 'hold',
    [requestId]));
  await withHost(name, {RESUME_AFTER_ANSWER: '0', ...extra}, started => {
    client(started, 'review', [requestId]);
    client(started, 'approve', [requestId]);
    client(started, 'resumeWaiting', [requestId]);
  });
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
  ['intent_completed', 'succeeded', ran()],
  ['dispatch_reserved', 'succeeded', ran({dispatch_reserved: 2})],
  ['hook', 'succeeded', ran({dispatch_reserved: 2, hook: 2})],
  ['physical_start_reserved', 'running', ran({computed: 0})],
]) {
  const name = `crash-${step}`;
  await approvedAndStopped(name, name);
  await crashed(name, {CRASH_AT: step});
  await withHost(name, {}, started => client(started, 'finished', [name],
    {EXPECT_STATUS: expectStatus}));
  assert.deepEqual(await counts(name), expected, step);
  await assertRetired(name, expectStatus === 'succeeded' ? 'retired'
    : 'held');
}

// 5. A claim whose lease lapses before the admission sends nothing; the
// Host itself continues the durable intent under a later claim.
await approvedAndStopped('lease', 'lease-a', {LEASE_MS: '1000'});
await withHost('lease', {LEASE_MS: '1000', STALL_AT: 'resume_claimed',
  STALL_MS: '1500'}, started => client(started, 'finished', ['lease-a']));
assert.deepEqual(await counts('lease'), ran());

// 5. An approval whose own permission expired before the Host resumed
// starts nothing; the request ends without a Run.
await approvedAndStopped('expired', 'expired-a', {TTL_MS: '3000'});
await new Promise(resolve => setTimeout(resolve, 3500));
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
