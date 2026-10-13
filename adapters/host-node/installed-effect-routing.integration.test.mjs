// Public, source-free two-installation acceptance. Only HTTPS providers are
// fixtures: checking, Compute, approval, both installed adapters, the Ledger,
// publication and recovery are the production owners.
import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {generateKeyPairSync, sign} from 'node:crypto';
import {mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {tmpdir, userInfo} from 'node:os';
import {join} from 'node:path';
import test from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import {promisify} from 'node:util';
import {connect} from '../../packages/sdk/index.mjs';
import {canonicalJson} from '../../packages/sdk/host-port.mjs';
import {openInstalledRemoteHttpHost, publishInstalledEffect} from './embedded-local.mjs';
import {fixtureCertificates, openHttpsExchangeFixture} from '../site-node/https-exchange-fixture.mjs';
import {commentSends, graphqlRoute} from '../connectors/github/test/github-graphql.fixture.mjs';
import {columns, sheetsRoutes} from '../connectors/sheets/test/sheets-api.fixture.mjs';

const terminal = new Set(['succeeded', 'failed', 'needs_reconciliation', 'cancelled']);
const pem = key => key.export({type: key.type === 'private' ? 'pkcs8' : 'spki', format: 'pem'});
// Independently authored inputs and expectations; provider output never supplies
// a Mapping, an expected row, a request body or a simulated Effect outcome.
const input = Object.freeze({node_id: 'I_ALPHA', comment: 'routing comment',
  text: '=literal e\u0301\r\n', number: 0, flag: false});
const expectedComment = {subjectId: 'I_ALPHA', body: 'routing comment', databaseId: 1000};
const expectedCells = [{stringValue: '=literal e\u0301\r\n'}, {numberValue: 0}, {boolValue: false}];

async function until(read) {
  for (let attempt = 0; attempt < 400; attempt++) {
    const value = await read();
    if (value) return value;
    await new Promise(resolve => setTimeout(resolve, 25));
  }
  assert.fail('Installed Effect routing did not reach the expected public boundary');
}

function program(github, sheets) {
  return JSON.stringify({version: 'actql/0.1', id: 'installed-effect-routing', stages: [{
    id: 'write', inputs: {}, steps: [{values: {schema: {
      node_id: {type: 'string', nullable: false}, comment: {type: 'string', nullable: false},
      text: {type: 'string', nullable: false}, number: {type: 'number', nullable: true},
      flag: {type: 'boolean', nullable: true}}, rows: [input]}, as: 'out'}],
    results: {rows: {from: 'out', fields: ['node_id', 'comment', 'text', 'number', 'flag']}},
    effects: {
      a_comment: {create: {target: github.target, mapping: github.mappingRef, from: {result: 'rows'}}},
      b_append: {create: {target: sheets.target, mapping: sheets.mappingRef, from: {result: 'rows'}}},
    },
  }], results: {answer: {from: {stage: 'write', result: 'rows'}}}});
}

function accountConfiguration(github, sheets) {
  const entry = (entry_id, outcome, connection, resource, operation) => ({
    entry_id, outcome, exclusions: [], principal: {all: true},
    connection: {any_of: [connection]}, resource: {any_of: resource},
    operation: {any_of: [operation]},
  });
  return canonicalJson({version: 'actql-execution-account-config/0.1',
    account_id: 'routing-fixture', entries: [
      entry('github-commit', 'delegate', github, ['issue_comments'], 'effect'),
      entry('sheets-commit', 'delegate', sheets, ['append_rows'], 'effect'),
      entry('github-read', 'allow', github, ['issue_comments', 'issues'], 'read'),
      entry('sheets-read', 'allow', sheets, ['append_rows', 'rows'], 'read'),
      {entry_id: 'host-run', outcome: 'allow', exclusions: [], principal: {all: true},
        connection: {all: true}, resource: {all: true}, operation: {any_of: ['write']}},
    ]});
}

async function installation(t, {loseSheetsReply}) {
  const root = await mkdtemp(join(tmpdir(), 'actql-effect-routing-'));
  const owned = [];
  const own = close => {
    let closed = false;
    const once = async () => { if (!closed) { await close(); closed = true; } };
    owned.push(once);
    return once;
  };
  const originalCAs = getCACertificates('default');
  t.after(async () => {
    const failures = [];
    for (const close of owned.reverse()) {
      try { await close(); } catch (error) { failures.push(error); }
    }
    setDefaultCACertificates(originalCAs);
    if (failures.length === 0) await rm(root, {recursive: true, force: true});
    else throw new AggregateError(failures, 'EffectRoutingFixtureCleanupFailed');
  });
  await mkdir(join(root, 'tls'));
  const tls = await fixtureCertificates(join(root, 'tls'));
  setDefaultCACertificates([...originalCAs, tls.ca.toString('utf8')]);
  const githubState = {
    repositories: new Map([['R_ALPHA', {databaseId: 4101, nameWithOwner: 'fixture/alpha', issues: []}]]),
    names: new Map([['fixture/alpha', 'R_ALPHA']]),
    subjects: new Map([['I_ALPHA', {type: 'Issue', repository: 'R_ALPHA', number: 7}]]), comments: [],
  };
  const sendsInOrder = [];
  const sheetsState = {appended: [], onAppend: () => { sendsInOrder.push('append'); }};
  const githubRoute = graphqlRoute(() => githubState);
  const githubApi = await openHttpsExchangeFixture(undefined, {routes: [{...githubRoute,
    handle(exchange) {
      const reply = githubRoute.handle(exchange);
      if (JSON.parse(exchange.body).query.startsWith('mutation ActqlAddComment(')) {
        sendsInOrder.push('comment');
      }
      return reply;
    }}]});
  own(githubApi.close);
  const sheetsApi = await openHttpsExchangeFixture(undefined, {routes: sheetsRoutes(sheetsState),
    faults: loseSheetsReply ? [{kind: 'apply-then-lose-reply', method: 'POST',
      pathname: '/v4/spreadsheets/book:batchUpdate'}] : []});
  own(sheetsApi.close);
  const connections = [`github:${new URL(githubApi.origin).host}/fixture/alpha`,
    `sheets:${new URL(sheetsApi.origin).host}/book`];
  const configuration = accountConfiguration(...connections);
  const directory = join(root, 'state');
  const profiles = [];
  const sites = [];
  for (const [index, api] of [githubApi, sheetsApi].entries()) {
    const name = index === 0 ? 'github' : 'sheets';
    const location = join(root, name);
    await mkdir(location);
    const credential = generateKeyPairSync('ed25519');
    const credentialPrivateKeyPath = join(location, 'credential.key');
    await writeFile(credentialPrivateKeyPath, pem(credential.privateKey), {mode: 0o600});
    const siteProfilePath = join(location, 'site.json');
    const shared = {apiOrigin: api.origin, namespaceId: `routing-${name}`, environment: 'test',
      siteKey: `routing-${name}-site`, siteGeneration: 1, credentialAuthorityId: `routing-${name}-authority`,
      credentialKeyId: `routing-${name}-key`, credentialPrivateKeyPath,
      journalRoot: join(location, 'credential-journal'), tokenEnvironment: `ACTQL_TEST_${name.toUpperCase()}_TOKEN`,
      caPath: api.caPath};
    sites.push(shared);
    await writeFile(siteProfilePath, JSON.stringify(index === 0
      ? {...shared, version: 'actql-installed-github-site/0.1', owner: 'fixture', repo: 'alpha'}
      : {...shared, version: 'actql-installed-sheets-site/0.1', spreadsheetId: 'book', appendSheetId: 7,
        gridRange: {sheetId: 0, startRow: 0, endRow: 4, startColumn: 0, endColumn: 3}, columns}));
    const base = {siteProfilePath, publicationPath: join(location, 'publication.json'),
      connectorId: index === 0 ? 'gh-alpha' : 'sheet-book', accountConfigurationWire: configuration};
    const profile = index === 0 ? {...base, version: 'actql-installed-github-effect/0.1',
      writes: [{resource: 'issue_comments', sources: [
        {target: 'subject_id', field: 'node_id', null_behavior: 'reject'},
        {target: 'body', field: 'comment', null_behavior: 'reject'}]}]}
      : {...base, version: 'actql-installed-sheets-effect/0.1', sources: [
        {target: 'text', field: 'text', null_behavior: 'reject'},
        {target: 'number', field: 'number', null_behavior: 'reject'},
        {target: 'flag', field: 'flag', null_behavior: 'reject'}]};
    const effectProfilePath = join(location, 'effect.json');
    await writeFile(effectProfilePath, JSON.stringify(profile));
    profiles.push(effectProfilePath);
  }
  const secretCounts = [0, 0];
  const resolveEffectSecret = async scope => {
    const index = sites.findIndex(site => site.siteKey === scope.siteKey);
    assert.ok(index >= 0, 'credential access must select the original installation');
    assert.equal(scope.resourceOrigin, sites[index].apiOrigin);
    assert.equal(scope.namespaceId, sites[index].namespaceId);
    assert.equal(scope.connectorRegistration, index === 0 ? 'github' : 'sheets');
    secretCounts[index]++;
    return `synthetic-routing-${index}-secret`;
  };
  const mappings = [];
  for (const effectProfilePath of profiles) {
    const published = await publishInstalledEffect({effectProfilePath, directory, resolveEffectSecret});
    assert.equal(published.mappings.length, 1);
    mappings.push(published.mappings[0]);
  }
  assert.notEqual(mappings[0].mappingCid, mappings[1].mappingCid);
  const reviewerKeys = generateKeyPairSync('ed25519'), hostKeys = generateKeyPairSync('ed25519');
  const signer = {keyId: 'routing-reviewer-key', reviewerId: 'routing-reviewer',
    sign: bytes => sign(null, bytes, reviewerKeys.privateKey)};
  const authorization = {accountConfiguration: configuration,
    reviewers: [{keyId: signer.keyId, reviewerId: signer.reviewerId,
      principalId: 'routing-reviewer-principal', publicKey: pem(reviewerKeys.publicKey)}],
    reviewReaders: ['routing-reviewer-principal'],
    hostKey: {keyId: 'routing-host-key', privateKey: pem(hostKeys.privateKey)},
    leaseMs: 10000, resumeAfterAnswer: false};
  const tokens = new Map([['owner-token', userInfo().username], ['reviewer-token', 'routing-reviewer-principal']]);
  async function open(order) {
    const host = await openInstalledRemoteHttpHost({directory,
      effectProfilePaths: order.map(index => profiles[index]), resolveEffectSecret, authorization,
      authenticate: header => tokens.get(header?.replace(/^Bearer /u, ''))});
    const closeHost = own(() => host.close());
    const server = createServer({key: tls.key, cert: tls.cert}, host.handler);
    await new Promise((resolve, reject) => {
      server.once('error', reject);
      server.listen(0, '127.0.0.1', resolve);
    });
    const closeServer = own(async () => {
      server.closeAllConnections();
      await new Promise((resolve, reject) => server.close(error => error ? reject(error) : resolve()));
    });
    const clients = [];
    return {async as(token = 'owner-token') {
      const client = await connect({mode: 'remote', durability: 'durable', token,
        endpoint: `https://127.0.0.1:${server.address().port}/`});
      clients.push(own(() => client.close()));
      return client;
    }, async close() {
      for (const close of clients) await close();
      await closeServer();
      await closeHost();
    }};
  }
  const counts = () => ({github: commentSends(githubApi).length,
    sheets: sheetsApi.seen().filter(item => item.method === 'POST' &&
      item.pathname === '/v4/spreadsheets/book:batchUpdate').length});
  return {root, open, mappings, signer, githubState, sheetsState, sheetsApi, githubApi,
    counts, secretCounts, sendsInOrder, wire: program(...mappings),
    replayConfiguration: {directory, effectProfilePaths: [...profiles].reverse(), authorization}};
}

async function original(client, savedPath) {
  const saved = JSON.parse(await readFile(savedPath, 'utf8'));
  const lookup = await client.lookupSubmission(saved.submissionRef);
  assert.equal(lookup.kind, 'ready', JSON.stringify(lookup));
  assert.deepEqual(lookup.submissionRef, saved.submissionRef);
  assert.deepEqual(lookup.admission.ref, saved.runRef);
  return client.attach(saved.runRef);
}

async function prepareAndApprove(setup, nonce) {
  const first = await setup.open([0, 1]);
  const owner = await first.as();
  const submissionRef = owner.newSubmission({nonce});
  const savedPath = join(setup.root, 'original-run.json');
  await writeFile(savedPath, JSON.stringify({submissionRef}));
  const execution = await owner.startSource(setup.wire, {format: 'json', submissionRef});
  await writeFile(savedPath, JSON.stringify({submissionRef, runRef: execution.ref}));
  const held = await until(async () => {
    const current = await execution.status();
    return current.status === 'waiting_checkpoint' || terminal.has(current.status) ? current : undefined;
  });
  assert.equal(held.status, 'waiting_checkpoint', JSON.stringify(held));
  assert.deepEqual(setup.counts(), {github: 0, sheets: 0});
  await first.close();
  const reviewHost = await setup.open([1, 0]);
  const reviewer = await reviewHost.as('reviewer-token');
  const checkpoints = (await reviewer.checkpoints()).items;
  assert.equal(checkpoints.length, 1, 'both installations share one whole-Set approval');
  const [checkpoint] = checkpoints;
  assert.equal(checkpoint.kind, 'effect_set');
  const review = await reviewer.reviewCheckpoint(checkpoint);
  const preview = JSON.parse(new TextDecoder().decode(review.bytes));
  assert.equal(preview.version, 'actql-effect-preview/0.1');
  assert.equal(preview.effect_preview_cid, checkpoint.requiredArtifact.cid);
  assert.deepEqual(preview.effects.map(member => [member.effect_id, member.effect_kind]),
    [['a_comment', 'create'], ['b_append', 'create']]);
  assert.deepEqual(preview.effects.map(member => member.resolved_mapping_contract_cid),
    setup.mappings.map(mapping => mapping.mappingCid));
  assert.deepEqual(preview.effects.map(member => member.changes.map(change => change.after.value)),
    [[{subject_id: 'I_ALPHA', body: 'routing comment'}],
      [{text: '=literal e\u0301\r\n', number: 0, flag: false}]]);
  const answer = await reviewer.resolveCheckpoints([{checkpoint, decision: 'approved'}],
    {signer: {...setup.signer, authorityScopeCid: execution.ref.authorityScopeCid}});
  assert.deepEqual(answer.results.map(item => item.status), ['committed']);
  await reviewHost.close();
  assert.deepEqual(setup.counts(), {github: 0, sheets: 0}, 'approval alone sends nothing');
  return savedPath;
}

async function resume(setup, savedPath, order, expectedStatus) {
  const host = await setup.open(order);
  const execution = await original(await host.as(), savedPath);
  const state = await until(async () => {
    const current = await execution.status();
    return terminal.has(current.status) ? current : undefined;
  });
  assert.equal(state.status, expectedStatus, JSON.stringify(state));
  return {host, execution, state};
}

for (const loseSheetsReply of [false, true]) {
  test(`real GitHub + Sheets routing: ${loseSheetsReply ? 'successful prefix and unknown append' : 'complete success'} survives restart`,
    {concurrency: false}, async t => {
      const setup = await installation(t, {loseSheetsReply});
      const savedPath = await prepareAndApprove(setup, loseSheetsReply ? 'routing-lost' : 'routing-success');
      const expectedStatus = loseSheetsReply ? 'needs_reconciliation' : 'succeeded';
      const resumed = await resume(setup, savedPath, [0, 1], expectedStatus);
      assert.deepEqual(setup.counts(), {github: 1, sheets: 1});
      assert.deepEqual(setup.githubState.comments, [expectedComment]);
      assert.deepEqual(commentSends(setup.githubApi).map(request => request.variables),
        [{subjectId: 'I_ALPHA', body: 'routing comment'}]);
      assert.deepEqual(setup.sheetsState.appended, [expectedCells]);
      assert.deepEqual(setup.sendsInOrder, ['comment', 'append']);
      assert.equal(setup.sheetsApi.remainingFaults(), 0);
      if (loseSheetsReply) {
        assert.deepEqual(resumed.state.next_action, {kind: 'reconcile', effects: ['b_append']});
        assert.equal(resumed.state.result_available, false);
        await resumed.execution.reconcile();
        assert.equal((await resumed.execution.status()).status, 'needs_reconciliation');
      } else {
        assert.deepEqual(await resumed.execution.result('answer').all(), [input]);
      }
      assert.deepEqual(setup.counts(), {github: 1, sheets: 1});
      await resumed.host.close();
      const repeated = await resume(setup, savedPath, [1, 0], expectedStatus);
      if (loseSheetsReply) {
        assert.deepEqual(repeated.state.next_action, {kind: 'reconcile', effects: ['b_append']});
        await repeated.execution.reconcile();
        assert.equal((await repeated.execution.status()).status, 'needs_reconciliation');
      } else assert.deepEqual(await repeated.execution.result('answer').all(), [input]);
      await repeated.host.close();
      const saved = JSON.parse(await readFile(savedPath, 'utf8'));
      const replayPath = join(setup.root, 'fresh-process.json');
      await writeFile(replayPath, JSON.stringify({ref: saved.runRef, expectedStatus,
        expectedRows: [input], installation: setup.replayConfiguration}), {mode: 0o600});
      const {stdout} = await promisify(execFile)(process.execPath,
        [fileURLToPath(new URL('./fixtures/installed-effect-routing-replay.mjs', import.meta.url)), replayPath],
        {timeout: 60000, maxBuffer: 1048576, env: {...process.env, NODE_PATH: ''}});
      assert.match(stdout, /INSTALLED_EFFECT_ROUTING_REPLAY_VERIFIED/u);
      assert.deepEqual(setup.counts(), {github: 1, sheets: 1}, 'neither completed nor uncertain occurrence is resent');
      assert.deepEqual(setup.githubState.comments, [expectedComment]);
      assert.deepEqual(setup.sheetsState.appended, [expectedCells]);
      assert.deepEqual(setup.sendsInOrder, ['comment', 'append']);
    });
}
