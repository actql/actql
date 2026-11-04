import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {blankGridRows, columns, errorGridRows, expectedRows, sheetsRoutes}
  from './sheets-api.fixture.mjs';
import {rangeProgram} from './sheets-range-program.fixture.mjs';
import {clearProgram} from './sheets-clear-program.fixture.mjs';

// Close live handles even when the caller retains the original fixture custody.
export async function closeSheetsAcceptanceCustody({root, closers = [],
  rangeCommand = false, acceptanceComplete, diagnostic = () => {},
  preserveScratch = process.env.ACTQL_TEST_PRESERVE_SCRATCH === '1'}) {
  try { for (const close of closers.reverse()) await close(); }
  finally {
    if (preserveScratch) diagnostic(`Retained Sheets acceptance custody: ${root}`);
    else if (rangeCommand && !acceptanceComplete) diagnostic(`Retained range acceptance custody: ${root}`);
    else await rm(root, {recursive: true, force: true});
  }
}

export async function registerSheetsAcceptance({connect, connectEmbeddedLocal,
  openInstalledRemoteHttpHost, publishInstalledSource, publishInstalledEffect,
  canonicalJson, fixtureCertificates, openHttpsExchangeFixture,
  replayEntry, scratch}) {
// Independent profile versions, not values extracted from implementation source.
const SHEETS_SITE_VERSION = 'actql-installed-sheets-site/0.1';
const SHEETS_SOURCE_VERSION = 'actql-installed-sheets-source/0.1';
const SHEETS_EFFECT_VERSION = 'actql-installed-sheets-effect/0.1';
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
const tls = await fixtureCertificates(tlsRoot);
setDefaultCACertificates([...getCACertificates('default'), tls.ca.toString('utf8')]);
after(() => closeSheetsAcceptanceCustody({root: tlsRoot}));
const owner = userInfo().username;
const secret = async () => 'fixture-only-secret';
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
const reviewerKeys = generateKeyPairSync('ed25519'), hostKeys = generateKeyPairSync('ed25519');
const signer = {keyId: 'reviewer-key', reviewerId: 'reviewer',
  sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
const entry = (entry_id, outcome, connection, resource, operation) => ({
  entry_id, outcome, exclusions: [], principal: {all: true},
  connection: {any_of: [connection]}, resource: {any_of: [resource]},
  operation: {any_of: [operation]},
});
const configuration = (connection, commit = 'delegate', rangeCommand = false) => canonicalJson({version: 'actql-execution-account-config/0.1',
  account_id: 'sheets-fixture', entries: [
    entry('append', commit, connection, 'append_rows', 'effect'),
    entry('append-read', 'allow', connection, 'append_rows', 'read'),
    entry('read', 'allow', connection, 'rows', 'read'),
    ...(rangeCommand ? [entry('range-read', 'allow', connection, 'range_target', 'read'),
      entry('range-effect', commit, connection, 'range_target', 'effect')] : []),
    // Status and Named Result inspection have their own Account tuples;
    // the business Source read and Run acceptance write grant neither.
    {entry_id: 'host-read', outcome: 'allow', exclusions: [],
      principal: {any_of: [owner]}, connection: {any_of: ['actql-remote-host']},
      resource: {any_of: ['result/answer', 'run']}, operation: {any_of: ['read']}},
    {entry_id: 'run', outcome: 'allow', exclusions: [], principal: {all: true},
      connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}},
  ].sort((a, b) => a.entry_id < b.entry_id ? -1 : a.entry_id > b.entry_id ? 1 : 0)});
const authorization = (accountConfiguration, reviewerPrincipal = 'reviewer-principal') => ({accountConfiguration,
  reviewers: [{keyId: 'reviewer-key', reviewerId: 'reviewer',
    principalId: reviewerPrincipal, publicKey: pem(reviewerKeys.publicKey)}],
  reviewReaders: [reviewerPrincipal], hostKey: {keyId: 'host-key', privateKey: pem(hostKeys.privateKey)},
  leaseMs: 10000, resumeAfterAnswer: false});

const readProgram = JSON.stringify({version: 'actql/0.1', id: 'sheets-read', stages: [{
  id: 'read', inputs: {sheet: {connector: 'sheet-book', resource: 'rows'}},
  steps: [{filter: 'true', as: 'scanned'},
    {select: ['text', 'number', 'flag'], as: 'out'}],
  results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
}, {id: 'compute', inputs: {captured: {result: {stage: 'read', result: 'rows'}}},
  steps: [{select: ['text', 'number', 'flag'], as: 'out'}],
  results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
}], results: {answer: {from: {stage: 'compute', result: 'rows'}}}});
const appendProgram = (mapping, rows) => JSON.stringify({version: 'actql/0.1', id: 'sheets-append', stages: [{
  id: 'write', inputs: {}, steps: [{values: {schema: {
    text: {type: 'string', nullable: false}, number: {type: 'number', nullable: true},
    flag: {type: 'boolean', nullable: true}}, rows}, as: 'out'}],
  results: {rows: {from: 'out', fields: ['text', 'number', 'flag']}},
  effects: {append: {create: {target: mapping.target, mapping: mapping.mappingRef,
    from: {result: 'rows'}}}},
}], results: {answer: {from: {stage: 'write', result: 'rows'}}}});
async function until(read) {
  for (let index = 0; index < 400; index++) {
    const result = await read();
    if (result) return result;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.fail('Sheets public execution did not reach its expected boundary');
}
const terminal = new Set(['succeeded', 'failed', 'cancelled']);
const settled = execution => until(async () => {
  const current = await execution.status();
  return terminal.has(current.status) || current.status === 'waiting_checkpoint' ? current : undefined;
});

async function installation(t, {faults = [], commit = 'delegate', reviewerPrincipal,
  rangeCommand = false, resumeAfterAnswer = false} = {}) {
  const state = {appended: [], ...(rangeCommand ? {rangeCommand, updated: [], cleared: []} : {})};
  const observations = [];
  const api = await openHttpsExchangeFixture(t, {routes: sheetsRoutes(state), faults});
  const root = await mkdtemp(join(scratch, 'host-'));
  const closers = [];
  t.after(() => closeSheetsAcceptanceCustody({root, closers, rangeCommand,
    acceptanceComplete: state.acceptanceComplete, diagnostic: message => t.diagnostic(message)}));
  const credential = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), pem(credential.privateKey), {mode: 0o600});
  const siteProfilePath = join(root, 'site.json');
  await writeFile(siteProfilePath, JSON.stringify({version: SHEETS_SITE_VERSION,
    apiOrigin: api.origin, spreadsheetId: 'book', appendSheetId: 7,
    gridRange: rangeCommand ? {sheetId: 7, startRow: 2, endRow: 4, startColumn: 0, endColumn: 3}
      : {sheetId: 0, startRow: 0, endRow: 4, startColumn: 0, endColumn: 3}, columns,
    namespaceId: 'fixture-namespace', environment: 'test', siteKey: 'sheet-site', siteGeneration: 1,
    credentialAuthorityId: 'authority', credentialKeyId: 'credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'), journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_SHEETS_TOKEN', caPath: api.caPath}));
  const connection = `sheets:${new URL(api.origin).host}/book`;
  let account = configuration(connection, commit, rangeCommand);
  const base = {siteProfilePath, publicationPath: join(root, 'publication.json'),
    connectorId: 'sheet-book', accountConfigurationWire: account};
  const sourceProfilePath = join(root, 'source.json'), effectProfilePath = join(root, 'effect.json');
  await writeFile(sourceProfilePath, JSON.stringify({...base, version: SHEETS_SOURCE_VERSION,
    ...(rangeCommand ? {rangeCommand} : {})}));
  await writeFile(effectProfilePath, JSON.stringify({...base, version: SHEETS_EFFECT_VERSION,
    ...(rangeCommand ? {rangeCommand}
      : {sources: columns.map(column => ({target: column.name, field: column.name, null_behavior: 'reject'}))})}));
  const directory = join(root, 'state');
  const publish = async effect => {
    try {
      return await (effect
        ? publishInstalledEffect({effectProfilePath, directory, resolveEffectSecret: secret})
        : publishInstalledSource({sourceProfilePath, directory, resolveSourceSecret: secret}));
    } catch (error) {
      const codes = [];
      for (let current = error, depth = 0; current && depth < 5; current = current.cause, depth++) {
        codes.push({code: current.code, issue: current.issue});
      }
      t.diagnostic(JSON.stringify(codes));
      throw error;
    }
  };
  async function open(effect, local = false) {
    const openObserved = async action => {
      try { return await action(); }
      catch (error) {
        const tag = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(value)
          ? value : undefined;
        const causes = [];
        for (let cause = error, depth = 0; cause && depth < 4; cause = cause.cause, depth++) {
          causes.push({code: tag(cause.code), messageTag: tag(cause.message),
            primaryCode: tag(cause.primaryFailure?.code),
            primaryTag: tag(cause.primaryFailure?.message), cleanupPending: cause.cleanupPending});
        }
        t.diagnostic(JSON.stringify({initialization: causes}));
        throw error;
      }
    };
    const options = {directory, ...(effect ? {effectProfilePath, resolveEffectSecret: secret}
      : {sourceProfilePath, resolveSourceSecret: secret}), authorization: {...authorization(account, reviewerPrincipal), resumeAfterAnswer,
        observe(name, detail) {
          observations.push([name, detail]);
        }}, ...(effect && rangeCommand ? {sourceProfilePath, resolveSourceSecret: secret} : {})};
    if (local) {
      const client = await openObserved(() => connectEmbeddedLocal({mode: 'local', owner: 'local', durability: 'durable',
        installation: options}));
      closers.push(() => client.close());
      return {client};
    }
    const host = await openObserved(() => openInstalledRemoteHttpHost({...options,
      authenticate: header => new Map([['owner-token', owner], ['reviewer-token', 'reviewer-principal']])
        .get(header?.replace(/^Bearer /u, ''))}));
    const server = createServer({key: tls.key, cert: tls.cert}, host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    let closed = false;
    const close = async () => {
      if (closed) return;
      server.closeAllConnections();
      await new Promise(resolve => server.close(resolve));
      await host.close();
      closed = true;
    };
    closers.push(close);
    const as = async token => {
      let client;
      try {
        client = await connect({mode: 'remote', endpoint: `https://127.0.0.1:${server.address().port}/`,
          token, durability: 'durable'});
      } catch (error) {
        t.diagnostic(JSON.stringify({code: error.code, cause: error.cause?.code,
          underlying: error.cause?.cause?.code}));
        throw error;
      }
      closers.push(() => client.close());
      return client;
    };
    return {as, close};
  }
  return {api, state, publish, open, root, observations,
    async replayInNewProcess(ref, expectedStatus, expectedRows) {
      const configPath = join(root, 'replay-fixture.json');
      await writeFile(configPath, JSON.stringify({ref, expectedStatus,
        ...(expectedRows === undefined ? {} : {expectedRows}),
        installation: {directory, effectProfilePath,
          ...(rangeCommand ? {sourceProfilePath} : {}),
          authorization: authorization(account, reviewerPrincipal)}}), {mode: 0o600});
      const {stdout} = await promisify(execFile)(process.execPath,
        [fileURLToPath(replayEntry), configPath], {timeout: 60_000,
          maxBuffer: 1_048_576, env: {...process.env, NODE_PATH: ''}});
      assert.match(stdout, /SHEETS_REPLAY_VERIFIED/u);
    },
    async revoke() {
      account = configuration(connection, 'deny', rangeCommand);
      const profile = JSON.parse(await readFile(effectProfilePath, 'utf8'));
      await writeFile(effectProfilePath, JSON.stringify({...profile, accountConfigurationWire: account}));
    }};
}

async function approve(host, execution) {
  const reviewer = host.client ?? await host.as('reviewer-token');
  const checkpoints = (await reviewer.checkpoints()).items;
  assert.equal(checkpoints.length, 1, 'one Set approval, not one approval per row');
  assert.equal(checkpoints[0].kind, 'effect_set');
  const answer = await reviewer.resolveCheckpoints([{checkpoint: checkpoints[0], decision: 'approved'}],
    {signer: {...signer, authorityScopeCid: execution.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
}
async function preparedAppend(setup, rows, {local = false, nonce = 'append-once'} = {}) {
  const [mapping] = (await setup.publish(true)).mappings;
  const first = await setup.open(true, local);
  const client = first.client ?? await first.as('owner-token');
  const execution = await client.startSource(appendProgram(mapping, rows), {
    format: 'json', submissionRef: client.newSubmission({nonce})});
  const state = await settled(execution);
  return {first, execution, state};
}
async function approvedAppend(setup, rows) {
  const initial = await preparedAppend(setup, rows);
  assert.equal(initial.state.status, 'waiting_checkpoint', JSON.stringify(initial.state));
  assert.equal(setup.state.appended.length, 0);
  await initial.first.close();
  const reviewer = await setup.open(true);
  await approve(reviewer, initial.execution);
  assert.equal(setup.state.appended.length, 0);
  await reviewer.close();
  return initial.execution;
}
const row = {text: '=literal e\u0301\r\n', number: 0, flag: false};

test('Sheets clear Command retains original requests through Local and HTTPS approval and cold restore', async t => {
  for (const local of [true, false]) {
    const setup = await installation(t, {rangeCommand: 'clear', resumeAfterAnswer: true,
      ...(local ? {reviewerPrincipal: owner} : {})});
    const [command] = (await setup.publish(true)).commands;
    assert.equal(command.commandRef, 'command:sheet-book.sheets.clear_range.v1');
    const first = await setup.open(true, local);
    const client = first.client ?? await first.as('owner-token');
    const execution = await client.startSource(clearProgram(command.commandRef), {
      format: 'json', submissionRef: client.newSubmission({nonce: 'clear-once'})});
    const waiting = await settled(execution);
    assert.equal(waiting.status, 'waiting_checkpoint', JSON.stringify(waiting));
    assert.equal(setup.state.cleared.length, 0, 'metadata acquisition is not a clear grant');
    const capturedCalls = setup.api.seen().length;
    if (first.client) await first.client.close(); else await first.close();
    const resumed = await setup.open(true, local);
    const resumedClient = resumed.client ?? await resumed.as('owner-token');
    const restored = await resumedClient.attach(execution.ref);
    assert.equal(setup.api.seen().length, capturedCalls, 'restore does not reacquire the target');
    await approve(resumed, restored);
    await restored.reconcile();
    const done = await until(async () => {
      const current = await restored.status();
      return terminal.has(current.status) || current.status === 'needs_reconciliation' ? current : undefined;
    });
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    assert.deepEqual(await restored.result('answer').all(), [{receipt: 'clear-request'}]);
    assert.equal(setup.state.cleared.length, 1);
    assert.deepEqual(setup.state.cleared[0].requests[0], {updateCells: {
      range: {sheetId: 7, startRowIndex: 2, endRowIndex: 4, startColumnIndex: 0, endColumnIndex: 3},
      rows: [], fields: 'userEnteredValue'}});
    assert.equal(setup.state.updated.length, 0);
    assert.equal(setup.state.appended.length, 0);
    const before = setup.api.seen().length;
    if (resumed.client) await resumed.client.close(); else await resumed.close();
    await setup.replayInNewProcess(execution.ref, 'succeeded', [{receipt: 'clear-request'}]);
    assert.equal(setup.api.seen().length, before, 'cold attach neither reacquires nor resends');
    setup.state.acceptanceComplete = true;
  }
});

test('Sheets clear keeps a lost response Unknown after cold restart without resend', async t => {
  const setup = await installation(t, {rangeCommand: 'clear', reviewerPrincipal: owner,
    faults: [{kind: 'apply-then-lose-reply', method: 'POST', pathname: '/v4/spreadsheets/book:batchUpdate'}]});
  const [command] = (await setup.publish(true)).commands;
  const first = await setup.open(true, true), client = first.client;
  const execution = await client.startSource(clearProgram(command.commandRef), {
    format: 'json', submissionRef: client.newSubmission({nonce: 'clear-unknown'})});
  assert.equal((await settled(execution)).status, 'waiting_checkpoint');
  assert.equal(setup.state.cleared.length, 0);
  await approve(first, execution);
  await execution.reconcile();
  let lastStatus;
  const unknown = await until(async () => {
    const current = await execution.status();
    lastStatus = current.status;
    return current.status === 'needs_reconciliation' || terminal.has(current.status) ||
      setup.observations.some(([name]) => name === 'effect_resume_failed') ? current : undefined;
  }).catch(error => {
    t.diagnostic(JSON.stringify({phase: 'clear-post-approval', status: lastStatus,
      clearedBatches: setup.state.cleared.length,
      resumeFailures: setup.observations.filter(([name]) => name === 'effect_resume_failed')
        .map(([, detail]) => typeof detail?.code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(detail.code)
          ? detail.code : 'UnavailableErrorTag')}));
    throw error;
  });
  assert.equal(unknown.status, 'needs_reconciliation', JSON.stringify({status: unknown.status,
    resumeFailures: setup.observations.filter(([name]) => name === 'effect_resume_failed')
      .map(([, detail]) => typeof detail?.code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(detail.code)
        ? detail.code : 'UnavailableErrorTag')}));
  assert.equal(unknown.result_available, false);
  assert.equal(setup.state.cleared.length, 1);
  const before = setup.api.seen().length;
  await client.close();
  await setup.replayInNewProcess(execution.ref, 'needs_reconciliation');
  assert.equal(setup.api.seen().length, before);
  await writeFile(join(setup.root, 'clear-unknown.json'), JSON.stringify({ref: execution.ref,
    status: unknown.status, resultAvailable: false, appliedBatches: 1,
    additionalRequestsAfterRestart: 0}), {mode: 0o600});
  // The actual Unknown, journal, credentials and cleanup responsibility remain.
});

test('Sheets range Command uses the real Local and HTTPS approval owners and original saved request', async t => {
  const rows = [row, {...row, text: 'second', number: -2.5, flag: true}];
  for (const local of [true, false]) {
    const setup = await installation(t, {rangeCommand: true, resumeAfterAnswer: true,
      ...(local ? {reviewerPrincipal: owner} : {})});
    const [command] = (await setup.publish(true)).commands;
    assert.equal(command.resource, 'range_target');
    const first = await setup.open(true, local);
    const client = first.client ?? await first.as('owner-token');
    const execution = await client.startSource(rangeProgram(command.commandRef, rows),
      {format: 'json', submissionRef: client.newSubmission({nonce: 'range-once'})});
    const waiting = await settled(execution);
    assert.equal(waiting.status, 'waiting_checkpoint', JSON.stringify(waiting));
    assert.equal(setup.state.updated.length, 0, 'metadata admission is not a write grant');
    await approve(first, execution);
    await execution.reconcile();
    const done = await until(async () => {
      const current = await execution.status();
      return terminal.has(current.status) || current.status === 'needs_reconciliation' ||
        setup.observations.some(([name]) => name === 'effect_resume_failed')
        ? current : undefined;
    });
    const safeTag = value => typeof value === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(value)
      ? value : undefined;
    assert.equal(done.status, 'succeeded', JSON.stringify({status: done.status,
      nextAction: done.next_action?.kind, updates: setup.state.updated.length,
      observations: setup.observations.map(([name, detail]) => ({name,
        code: safeTag(detail?.code), cause: safeTag(detail?.cause?.code),
        error: safeTag(detail?.error?.code), reason: safeTag(detail?.reason)}))}));
    assert.deepEqual(await execution.result('answer').all(), [{rows}]);
    assert.deepEqual(setup.state.updated, [[
      [{stringValue: '=literal e\u0301\r\n'}, {numberValue: 0}, {boolValue: false}],
      [{stringValue: 'second'}, {numberValue: -2.5}, {boolValue: true}],
    ]]);
    const before = setup.api.seen().length;
    if (first.client) await first.client.close(); else await first.close();
    await setup.replayInNewProcess(execution.ref, 'succeeded', [{rows}]);
    assert.equal(setup.api.seen().length, before, 'restart does not reacquire or resend');
    setup.state.acceptanceComplete = true;
  }
});

test('Sheets range Command retains an unknown acknowledgement across process restart without resend', async t => {
  const setup = await installation(t, {rangeCommand: true, reviewerPrincipal: owner,
    faults: [{kind: 'apply-then-lose-reply', method: 'POST', pathname: '/v4/spreadsheets/book:batchUpdate'}]});
  const [command] = (await setup.publish(true)).commands;
  const first = await setup.open(true, true);
  const client = first.client;
  const rows = [row, {...row, text: 'second', number: -2.5, flag: true}];
  const execution = await client.startSource(rangeProgram(command.commandRef, rows),
    {format: 'json', submissionRef: client.newSubmission({nonce: 'range-unknown'})});
  assert.equal((await settled(execution)).status, 'waiting_checkpoint');
  assert.equal(setup.state.updated.length, 0);
  await approve(first, execution);
  await execution.reconcile();
  const unknown = await until(async () => {
    const value = await execution.status();
    return value.status === 'needs_reconciliation' || terminal.has(value.status) ||
      setup.observations.some(([name]) => name === 'effect_resume_failed') ? value : undefined;
  });
  assert.equal(unknown.status, 'needs_reconciliation', JSON.stringify({status: unknown.status,
    resumeFailures: setup.observations.filter(([name]) => name === 'effect_resume_failed')
      .map(([, detail]) => typeof detail?.code === 'string' && /^[A-Za-z][A-Za-z0-9_]{0,100}$/u.test(detail.code)
        ? detail.code : 'UnavailableErrorTag')}));
  assert.equal(unknown.result_available, false);
  assert.equal(setup.state.updated.length, 1);
  const before = setup.api.seen().length;
  await client.close();
  await setup.replayInNewProcess(execution.ref, 'needs_reconciliation');
  assert.equal(setup.api.seen().length, before, 'the saved request is neither reacquired nor resent');
  await writeFile(join(setup.root, 'range-unknown.json'), JSON.stringify({ref: execution.ref,
    status: unknown.status, resultAvailable: false, appliedBatches: 1,
    additionalRequestsAfterRestart: 0}), {mode: 0o600});
  // Deliberately retain this original Unknown/DB/key custody after test closure.
});

test('Sheets rejects out-of-domain grid indexes before provider I/O', async t => {
  for (const field of ['appendSheetId', 'gridRange']) {
    const setup = await installation(t);
    const path = join(setup.root, 'site.json');
    const profile = JSON.parse(await readFile(path, 'utf8'));
    const invalid = field === 'appendSheetId' ? 2_147_483_648
      : {...profile.gridRange, startRow: 2_147_483_648, endRow: 2_147_483_652};
    await writeFile(path, JSON.stringify({...profile, [field]: invalid}));
    await assert.rejects(setup.publish(false), {code: 'InvalidInstalledSheetsSite'});
    assert.equal(setup.api.seen().length, 0);
  }
});

test('Sheets failed publication removes only its own unpublished temporary file', async t => {
  const setup = await installation(t);
  // The target directory forces the atomic rename to fail after writing bytes.
  await mkdir(join(setup.root, 'publication.json'));
  await assert.rejects(setup.publish(false), error => {
    assert.equal(error.code, 'InstalledHostInitializationFailed');
    assert.equal(error.cleanupPending, false);
    assert.ok(['EISDIR', 'EEXIST', 'ENOTEMPTY'].includes(error.primaryFailure?.code));
    return true;
  });
  assert.deepEqual((await readdir(setup.root)).filter(name => name.startsWith('publication.json')),
    ['publication.json']);
});

test('Sheets partial success retains the successful prefix and stops after an unknown row', async t => {
  const setup = await installation(t);
  const execution = await approvedAppend(setup, [row, row, row]);
  // Fault the second physical send, independently of the common Effect's
  // canonical row-key ordering. Equal rows still have distinct logical slots.
  setup.state.onAppend = () => {
    if (setup.state.appended.length === 2) throw new Error('FixtureSecondReplyLost');
  };
  const resumed = await setup.open(true);
  const attached = await (await resumed.as('owner-token')).attach(execution.ref);
  const unknown = await until(async () => {
    const current = await attached.status();
    return current.next_action?.kind === 'reconcile' ? current : undefined;
  });
  assert.equal(unknown.result_available, false);
  assert.equal(setup.state.appended.length, 2);
  const sends = () => setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length;
  assert.equal(sends(), 2);
  await attached.reconcile();
  assert.equal(sends(), 2);
  await resumed.close();
  await setup.replayInNewProcess(execution.ref, 'needs_reconciliation');
  assert.equal(sends(), 2, 'neither saved success nor unknown is resent; last row remains unsent');
});

test('Sheets Local append approves a complete Set and retains equal rows as separate sends', async t => {
  const setup = await installation(t, {reviewerPrincipal: owner, resumeAfterAnswer: true});
  const {first, execution, state} = await preparedAppend(setup, [row, row], {local: true});
  assert.equal(state.status, 'waiting_checkpoint', JSON.stringify(state));
  assert.equal(setup.state.appended.length, 0);
  await approve(first, execution);
  // This executing Host resumes its committed answer through the existing Owner.
  // reconcile observes the original Run; it does not start a disabled continuation.
  await execution.reconcile();
  const done = await settled(execution);
  assert.equal(done.status, 'succeeded', JSON.stringify(done));
  assert.deepEqual(await execution.result('answer').all(), [row, row]);
  assert.equal(setup.state.appended.length, 2);
  await first.client.close();
  const reopened = await setup.open(true, true);
  const replay = await reopened.client.attach(execution.ref);
  assert.equal((await replay.status()).status, 'succeeded');
  assert.deepEqual(await replay.result('answer').all(), [row, row]);
  assert.equal(setup.state.appended.length, 2);
});

for (const [name, faults, cancel, applied] of [
  ['lost acknowledgement', [{kind: 'apply-then-lose-reply'}], false, 1],
  ['cancel while the physical append reply is pending', [{kind: 'apply-then-lose-reply'}], true, 1],
  ['provider 503', [{kind: 'reply', reply: {status: 503, body: {error: 'fixture'}}}], false, 0],
]) {
  test(`Sheets ${name} preserves unknown custody and never resends`, async t => {
    const setup = await installation(t, {faults: faults.map(fault => ({...fault,
      method: 'POST', pathname: '/v4/spreadsheets/book:batchUpdate'}))});
    const execution = await approvedAppend(setup, [row, row]);
    let releaseReply;
    const pendingReply = new Promise(resolve => { releaseReply = resolve; });
    if (cancel) {
      // The responder has applied the row but cannot complete the exchange
      // until cancellation has been submitted through the public SDK.
      setup.state.onAppend = () => {
        setup.state.physicalAppendObserved = true;
        return pendingReply;
      };
      t.after(releaseReply);
    }
    const resumed = await setup.open(true);
    const attached = await (await resumed.as('owner-token')).attach(execution.ref);
    if (cancel) {
      await until(async () => setup.state.physicalAppendObserved);
      try { await attached.cancel(); }
      finally { releaseReply(); }
    }
    const unknown = await until(async () => {
      const current = await attached.status();
      return current.next_action?.kind === 'reconcile' ? current : undefined;
    });
    assert.equal(unknown.status, 'needs_reconciliation');
    assert.deepEqual(unknown.next_action, {kind: 'reconcile', effects: ['append']});
    assert.equal(unknown.result_available, false);
    assert.equal(setup.state.appended.length, applied);
    const sends = () => setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length;
    assert.equal(sends(), 1, 'unknown first row prevents the unsent second row');
    await attached.reconcile();
    assert.equal(sends(), 1);
    await resumed.close();
    const reopened = await setup.open(true);
    const replay = await (await reopened.as('owner-token')).attach(execution.ref);
    assert.equal((await replay.status()).status, 'needs_reconciliation');
    await replay.reconcile();
    assert.equal(sends(), 1);
    assert.equal(setup.state.appended.length, applied);
    if (cancel) assert.equal((await replay.status()).control.cancellation_requested, true);
    await reopened.close();
    await setup.replayInNewProcess(execution.ref, 'needs_reconciliation');
    assert.equal(sends(), 1, 'a new process does not resend an unknown row');
  });
}

for (const name of ['changed numeric tab', 'revoked account']) {
  test(`Sheets ${name} refuses an approved append before sending`, async t => {
    const setup = await installation(t);
    const execution = await approvedAppend(setup, [row]);
    if (name === 'changed numeric tab') setup.state.appendSheetId = 8;
    else await setup.revoke();
    const resumed = await setup.open(true);
    const attached = await (await resumed.as('owner-token')).attach(execution.ref);
    const failed = await settled(attached);
    assert.equal(failed.status, 'failed', JSON.stringify(failed));
    assert.equal(failed.result_available, false);
    assert.equal(setup.state.appended.length, 0);
    assert.equal(setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length, 0);
  });
}

test('Sheets unrepresentable cells and missing approval refuse before physical append', async t => {
  for (const [commit, value] of [['delegate', {...row, text: ''}],
    ['delegate', {...row, number: null}], ['allow', row]]) {
    const setup = await installation(t, {commit});
    const {state} = await preparedAppend(setup, [value]);
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(setup.state.appended.length, 0);
    assert.equal(setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length, 0);
  }
});

test('Sheets cleanup retry keeps the same ledger owner and never repeats append', async t => {
  const setup = await installation(t);
  const execution = await approvedAppend(setup, [row]);
  const original = DatabaseSync.prototype.close;
  let failed = false, attempts = 0, successes = 0;
  t.mock.method(DatabaseSync.prototype, 'close', function() {
    if (new Error().stack.includes('/effect-ledger.mjs')) {
      attempts++;
      if (!failed) { failed = true; throw new Error('FixtureLedgerClosePending'); }
      const value = original.call(this);
      successes++;
      return value;
    }
    return original.call(this);
  });
  const resumed = await setup.open(true);
  const attached = await (await resumed.as('owner-token')).attach(execution.ref);
  await until(async () => failed && setup.state.appended.length === 1);
  await resumed.close();
  assert.equal(successes, 1);
  assert.ok(attempts >= 2);
  const count = setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length;
  const reopened = await setup.open(true);
  const replay = await (await reopened.as('owner-token')).attach(execution.ref);
  assert.equal((await replay.status()).status, 'succeeded');
  assert.deepEqual(await replay.result('answer').all(), [row]);
  assert.equal(setup.api.seen().filter(item => item.pathname.endsWith(':batchUpdate')).length, count);
  assert.equal(count, 1);
});

test('Sheets read uses the installed public Local and HTTPS owners and retained Results', async t => {
  for (const [local, gridRows, expected] of [
    [true, undefined, expectedRows], [false, undefined, expectedRows],
    [true, blankGridRows, []], [false, blankGridRows, []],
  ]) {
    const setup = await installation(t);
    setup.state.gridRows = gridRows;
    await setup.publish(false);
    assert.equal(setup.api.seen().length, 1, 'publication checks numeric sheet identity once');
    const host = await setup.open(false, local);
    const client = host.client ?? await host.as('owner-token');
    assert.equal(setup.api.seen().length, 1, 'Host loading does not acquire Source data');
    const submissionRef = client.newSubmission({nonce: 'read-once'});
    let execution;
    try { execution = await client.startSource(readProgram, {format: 'json', submissionRef}); }
    catch (error) { t.diagnostic(JSON.stringify(error.outcome?.problem)); throw error; }
    let done;
    try { done = await settled(execution); }
    catch (error) {
      t.diagnostic(JSON.stringify(await execution.status()));
      t.diagnostic(JSON.stringify(setup.api.seen().map(item => [item.method, item.pathname])));
      t.diagnostic(JSON.stringify(setup.observations));
      throw error;
    }
    assert.equal(done.status, 'succeeded', JSON.stringify(done));
    assert.deepEqual(await execution.result('answer').all(), expected);
    assert.deepEqual(await execution.result('answer').all(), expected);
    const again = await client.startSource(readProgram, {format: 'json', submissionRef});
    assert.deepEqual(await again.result('answer').all(), expected);
    assert.equal(setup.api.seen().filter(item => item.pathname.endsWith(':getByDataFilter')).length, 1);
  }
});

test('Sheets evaluated formula errors fail the public read without publishing NULL rows', async t => {
  const setup = await installation(t);
  setup.state.gridRows = errorGridRows;
  await setup.publish(false);
  const host = await setup.open(false);
  const client = await host.as('owner-token');
  const execution = await client.startSource(readProgram, {format: 'json',
    submissionRef: client.newSubmission({nonce: 'formula-error'})});
  const state = await settled(execution);
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(state.result_available, false);
  assert.equal(setup.api.seen().filter(item => item.pathname.endsWith(':getByDataFilter')).length, 1);
  assert.equal(setup.state.appended.length, 0);
});

test('Sheets append keeps one common approval across restart and saves acknowledgements without row IDs', async t => {
  const setup = await installation(t);
  const [mapping] = (await setup.publish(true)).mappings;
  const first = await setup.open(true);
  const client = await first.as('owner-token');
  const rows = [{text: '=literal e\u0301\r\n', number: 0, flag: false}];
  const execution = await client.startSource(appendProgram(mapping, rows), {
    format: 'json', submissionRef: client.newSubmission({nonce: 'append-once'})});
  const held = await settled(execution);
  assert.equal(held.status, 'waiting_checkpoint', JSON.stringify(held));
  assert.equal(setup.state.appended.length, 0);
  await first.close();
  const second = await setup.open(true);
  const reviewer = await second.as('reviewer-token');
  const checkpoints = (await reviewer.checkpoints()).items;
  assert.equal(checkpoints.length, 1);
  assert.equal(checkpoints[0].kind, 'effect_set');
  const answer = await reviewer.resolveCheckpoints([{checkpoint: checkpoints[0], decision: 'approved'}],
    {signer: {...signer, authorityScopeCid: execution.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
  assert.equal(setup.state.appended.length, 0);
  await second.close();
  const third = await setup.open(true);
  const attached = await (await third.as('owner-token')).attach(execution.ref);
  const done = await settled(attached);
  assert.equal(done.status, 'succeeded', JSON.stringify(done));
  assert.deepEqual(await attached.result('answer').all(), rows);
  assert.deepEqual(setup.state.appended, [[{stringValue: '=literal e\u0301\r\n'}, {numberValue: 0}, {boolValue: false}]]);
  await third.close();
  const fourth = await setup.open(true);
  const replay = await (await fourth.as('owner-token')).attach(execution.ref);
  assert.equal((await replay.status()).status, 'succeeded');
  assert.deepEqual(await replay.result('answer').all(), rows);
  assert.equal(setup.state.appended.length, 1);
  await fourth.close();
  await setup.replayInNewProcess(execution.ref, 'succeeded');
  assert.equal(setup.state.appended.length, 1);
});
}
