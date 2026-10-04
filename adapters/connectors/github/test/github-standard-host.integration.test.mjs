// Public Client acceptance of the GitHub Issue source on the standard
// installed HTTPS Host, against an independent HTTPS fixture that answers
// as the GitHub REST API (2026-03-10). Expected rows are written by hand
// from the fixture's stored Issues; nothing is derived from product output.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {generateKeyPairSync} from 'node:crypto';
import {mkdir, mkdtemp, readFile, readdir, rm, writeFile} from 'node:fs/promises';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {userInfo} from 'node:os';
import {join} from 'node:path';
import test, {after} from 'node:test';
import {getCACertificates, setDefaultCACertificates} from 'node:tls';
import {fileURLToPath} from 'node:url';
import * as commonMoon from
  '../../../../_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js';
import {connect} from '../../../../packages/sdk/index.mjs';
import {openInstalledRemoteHttpHost} from
  '../../../host-node/embedded-local.mjs';
import {publishInstalledSourceProfile} from
  '../../../host-node/installed-source.mjs';
import {canonicalJson} from '../../../host-node/local-account-config.mjs';
import {openHttpsExchangeFixture} from
  '../../../site-node/https-exchange-fixture.mjs';
import {graphqlRoute, issueReads} from './github-graphql.fixture.mjs';
import {observeTwoSourceProvider} from
  '../../../../scripts/fixtures/two-source-public-query.mjs';
// The comment Effect's acceptance runs with the source's.
import './github-comment-effect.integration.test.mjs';
import {INSTALLED_GITHUB_SITE_VERSION, INSTALLED_GITHUB_SOURCE_VERSION} from
  '../host/installed-github-source.mjs';

const repository = fileURLToPath(new URL('../../../../', import.meta.url));
const scratch = join(repository, '_build', 'github-standard-host');
await mkdir(scratch, {recursive: true});
const tlsRoot = await mkdtemp(join(scratch, 'tls-'));
execFileSync('openssl', ['req', '-x509', '-nodes', '-newkey', 'rsa:2048',
  '-keyout', 'host.key', '-out', 'host.crt', '-days', '1',
  '-subj', '/CN=localhost',
  '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'],
{cwd: tlsRoot, stdio: 'ignore'});
const tlsKey = await readFile(join(tlsRoot, 'host.key'));
const tlsCertificate = await readFile(join(tlsRoot, 'host.crt'));
setDefaultCACertificates([...getCACertificates('default'),
  tlsCertificate.toString('utf8')]);
after(() => rm(tlsRoot, {recursive: true, force: true}));

const owner = userInfo().username;
const runtimeUrl = new URL('../../../../_build/js/release/build/' +
  'connectors_builtin_node/connectors_builtin_node.js', import.meta.url);
const secret = async () => 'test-only-token';
const tokens = new Map([['owner-token', owner]]);
const repositoryId = 1296269;
// Repository A's Issues as GitHub's GraphQL `Repository.issues` states them
// (pull requests are a separate connection and never appear here).
const storedA = [{number: 1, comments: 1},
  {number: 3, state: 'CLOSED', closedAt: '2026-10-03T00:00:00Z'},
  {number: 4, body: 'text'}, {number: 5}];
// Repository B, which may take A's name.
const storedB = [{number: 1, title: 'B-1'}, {number: 2, title: 'B-2'}];

const accountConfiguration = connection => canonicalJson({
  version: 'actql-execution-account-config/0.1',
  account_id: 'github-source-account',
  entries: [{entry_id: 'issues-read', outcome: 'allow', exclusions: [],
    principal: {all: true}, connection: {any_of: [connection]},
    resource: {any_of: ['issues']}, operation: {any_of: ['read']}}]});

const program = JSON.stringify({version: 'actql/0.1', id: 'github-read',
  stages: [{id: 'acquire',
    inputs: {remote: {connector: 'gh-hello', resource: 'issues'}},
    steps: [{filter: "state = 'open'", as: 'open'},
      {select: ['number', 'title', 'author'], as: 'captured'}],
    results: {r: {from: 'captured', fields: ['number', 'title', 'author']}}},
  {id: 'compute',
    inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
    steps: [{select: ['number', 'title', 'author'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'title', 'author']}}}],
  results: {issues: {from: {stage: 'compute', result: 'r'}}}});

async function installation(t, {faults = [], retainedRelationOutput = false,
  observe, faultInjection, secondSource = false, mixedSource = false} = {}) {
  // The provider's current state; tests change it after publication while
  // the local Site profile stays fixed.
  const state = {
    repositories: new Map([['R_hello', {databaseId: repositoryId,
      nameWithOwner: 'octocat/hello', issues: storedA}]]),
    names: new Map([['octocat/hello', 'R_hello']]), pageSize: 2};
  if (secondSource) {
    state.repositories.set('R_copy', {databaseId: 1296270,
      nameWithOwner: 'octocat/copy', issues: [
        {number: 1, title: 'Copy 1'}, {number: 5, title: 'Copy 5'}]});
    state.names.set('octocat/copy', 'R_copy');
  }
  const api = await openHttpsExchangeFixture(t, {faults,
    routes: [graphqlRoute(() => state)]});
  const root = await mkdtemp(join(scratch, 'host-'));
  const closers = [];
  t.after(async () => {
    for (const close of closers.reverse()) await close();
    await rm(root, {recursive: true, force: true});
  });
  const authority = generateKeyPairSync('ed25519');
  await writeFile(join(root, 'credential.key'), authority.privateKey.export({
    type: 'pkcs8', format: 'pem'}));
  const site = {version: INSTALLED_GITHUB_SITE_VERSION, apiOrigin: api.origin,
    owner: 'octocat', repo: 'hello', namespaceId: 'namespace-a',
    environment: 'test', siteKey: 'github-site', siteGeneration: 1,
    credentialAuthorityId: 'host-credential-authority',
    credentialKeyId: 'host-credential-key',
    credentialPrivateKeyPath: join(root, 'credential.key'),
    journalRoot: join(root, 'credential-journal'),
    tokenEnvironment: 'ACTQL_TEST_GITHUB_TOKEN', caPath: api.caPath};
  const sitePath = join(root, 'github-site.json');
  await writeFile(sitePath, JSON.stringify(site));
  const connection = `github:${new URL(api.origin).host}/octocat/hello`;
  const profile = {version: INSTALLED_GITHUB_SOURCE_VERSION,
    siteProfilePath: sitePath,
    publicationPath: join(root, 'github-publication.json'),
    connectorId: 'gh-hello',
    accountConfigurationWire: accountConfiguration(connection)};
  const profilePath = join(root, 'source-profile.json');
  await writeFile(profilePath, JSON.stringify(profile));
  const secondProfilePath = join(root, 'source-profile-copy.json');
  if (secondSource) {
    const secondSitePath = join(root, 'github-site-copy.json');
    await writeFile(secondSitePath, JSON.stringify({...site,
      repo: 'copy',
      siteKey: 'github-site-copy',
      journalRoot: join(root, 'credential-journal-copy')}));
    await writeFile(secondProfilePath, JSON.stringify({...profile,
      siteProfilePath: secondSitePath,
      publicationPath: join(root, 'github-publication-copy.json'),
      connectorId: 'gh-copy',
      accountConfigurationWire: accountConfiguration(
        `github:${new URL(api.origin).host}/octocat/copy`)}));
  }
  const mixedProfilePath = join(root, 'duckdb-source-profile.json');
  let duckdb;
  if (mixedSource) {
    duckdb = createRequire(join(repository,
      'adapters/connectors/duckdb/node/package.json'))('@duckdb/node-api');
    const database = join(root, 'mixed-source.duckdb');
    const instance = await duckdb.DuckDBInstance.create(database);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE, amount DOUBLE)');
      await connection.run('INSERT INTO records VALUES (1, 100), (5, 500)');
    } finally { connection.closeSync(); instance.closeSync(); }
    const environment = JSON.parse(await readFile(join(repository,
      'adapters/host-node/fixtures/two-source/left.environment.json'), 'utf8'));
    const view = environment.source_views[0];
    await writeFile(mixedProfilePath, canonicalJson({
      version: 'actql-installed-duckdb-source/0.1', database,
      schema: 'main', table: 'records',
      acquisitionPlanning: {policy: 'priority',
        priority: ['nativeQuery', 'broadQuery']},
      sourceRef: environment.schema_snapshots[0].source_ref,
      queryAliases: [{name: 'mixed_records',
        sourceRef: environment.schema_snapshots[0].source_ref,
        sourceViewContractCid: view.contract_cid,
        schemaContractCid: view.output.schema.cid}],
      checkEnvironmentWire: canonicalJson(environment),
      accountConfigurationWire: canonicalJson({
        version: 'actql-execution-account-config/0.1',
        account_id: 'mixed-source', entries: [{entry_id: 'read-database',
          outcome: 'allow', principal: {all: true},
          connection: {any_of: ['local-database']},
          resource: {any_of: [database]}, operation: {any_of: ['read']},
          exclusions: []}]}),
    }));
  }
  const hostRoot = join(root, 'state');
  const hostKeys = observe === undefined ? undefined :
    generateKeyPairSync('ed25519');
  const hostAuthorization = hostKeys === undefined ? undefined : {
    accountConfiguration: canonicalJson({
      version: 'actql-execution-account-config/0.1',
      account_id: 'github-retained-host', entries: [{entry_id: 'query',
        outcome: 'allow', principal: {all: true}, connection: {all: true},
        resource: {all: true}, operation: {any_of: ['write']},
        exclusions: []}]}),
    hostKey: {keyId: 'host', privateKey: hostKeys.privateKey.export({
      type: 'pkcs8', format: 'pem'})},
    reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer',
      principalId: owner, publicKey: hostKeys.publicKey.export({
        type: 'spki', format: 'pem'})}],
    observe, faultInjection,
  };
  const publish = async () => {
    const first = await publishInstalledSourceProfile(profilePath, {
      root: hostRoot, principalId: owner, moon: commonMoon, runtimeUrl,
      resolveSecret: secret});
    if (secondSource) await publishInstalledSourceProfile(secondProfilePath, {
      root: hostRoot, principalId: owner, moon: commonMoon, runtimeUrl,
      resolveSecret: secret});
    return first;
  };
  const open = async () => {
    const host = await openInstalledRemoteHttpHost({directory: hostRoot,
      authenticate: header => tokens.get(header?.replace(/^Bearer /u, '')),
      ...(secondSource || mixedSource ? {sourceProfilePaths: [profilePath,
        secondSource ? secondProfilePath : mixedProfilePath]}
        : {sourceProfilePath: profilePath}),
      resolveSourceSecret: secret,
      retainedRelationOutput, authorization: hostAuthorization});
    const server = createServer({key: tlsKey, cert: tlsCertificate},
      host.handler);
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    let closed = false;
    const close = async () => {
      if (closed) return;
      closed = true;
      server.closeAllConnections?.();
      await new Promise(resolve => server.close(resolve));
      await host.close();
    };
    closers.push(close);
    const client = await connect({mode: 'remote',
      endpoint: `https://127.0.0.1:${server.address().port}/`,
      token: 'owner-token', durability: 'durable'});
    closers.push(() => client.close());
    return {client, close, host};
  };
  return {api, state, root, site, sitePath, profile, publish, open, duckdb,
    connection};
}

const listings = api => issueReads(api);
const assertAcquisitionReleased = observations => {
  const finished = observations.filter(([name]) =>
    name === 'dispatch_cleanup_completed');
  assert.ok(finished.length > 0, 'the shared acquisition owner completed cleanup');
  const usage = finished.at(-1)[1].resourceUsage;
  for (const key of ['reservedTransferBytes', 'heldBytes',
    'reservedRetentionBytes', 'reservedExecutionBytes',
    'uncertainTransferBytes']) assert.equal(usage[key], '0', key);
};
// Every provider request is the GraphQL endpoint: no name-addressed REST.
const onlyGraphql = api => api.seen().every(entry =>
  entry.method === 'POST' && entry.pathname === '/graphql');

test('public Client reads published GitHub Issues to a Named Result', async t => {
  const setup = await installation(t);
  // A Host start without a publication refuses before any provider I/O.
  await assert.rejects(setup.open(), {code: 'GitHubPublicationMissing'});
  assert.equal(setup.api.seen().length, 0);
  const published = await setup.publish();
  // The publication stores the node ID in the form the reads compare.
  assert.deepEqual(published.repository, {id: repositoryId,
    node_id: 'R_hello'});
  assert.equal(setup.api.seen().length, 1);
  const {client} = await setup.open();
  // The Host start restored the publication without provider I/O.
  assert.equal(setup.api.seen().length, 1);
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-1'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  // A's open Issues.
  assert.deepEqual(rows.map(row => [row.number, row.title, row.author])
    .sort((a, b) => a[0] - b[0]),
  [[1, 'Issue 1', 'octocat'], [4, 'Issue 4', 'octocat'],
    [5, 'Issue 5', 'octocat']]);
  // Two pages of A (page size 2 of 4 Issues), each by A's node ID.
  const reads = listings(setup.api);
  assert.deepEqual(reads.map(request => request.variables.id),
    ['R_hello', 'R_hello']);
  assert.equal(reads[0].variables.after, null);
  assert.equal(typeof reads[1].variables.after, 'string');
  assert.ok(onlyGraphql(setup.api));
  for (const entry of setup.api.seen()) {
    assert.equal(entry.headers['x-github-api-version'], '2026-03-10');
    assert.equal(entry.authorized, true);
  }
});

test('installed row source retains public output across Host reopen',
  async t => {
    let outputRepresentations;
    const setup = await installation(t, {retainedRelationOutput: true,
      observe(name, detail) {
        if (name === 'computed') outputRepresentations = detail.outputRepresentations;
      }});
    await setup.publish();
    const document = JSON.parse(program);
    document.id = 'github-retained-two-consumers';
    document.stages.push({id: 'audit',
      inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
      steps: [{select: ['number', 'title'], as: 'out'}],
      results: {r: {from: 'out', fields: ['number', 'title']}}});
    document.results.audit = {from: {stage: 'audit', result: 'r'}};
    const {client, close} = await setup.open().catch(error => {
      assert.fail(error.primaryFailure?.stack ?? error.stack);
    });
    const run = await client.aql(JSON.stringify(document), {format: 'json',
      requestId: 'github-retained-read'});
    const state = await run.wait();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const expected = [{number: 1, title: 'Issue 1', author: 'octocat'},
      {number: 4, title: 'Issue 4', author: 'octocat'},
      {number: 5, title: 'Issue 5', author: 'octocat'}];
    assert.deepEqual(await run.result('issues').all(), expected);
    const audit = expected.map(({number, title}) => ({number, title}));
    assert.deepEqual(await run.result('audit').all(), audit);
    assert.deepEqual(outputRepresentations,
      [{task: 1, representation: 'retained-file'},
        {task: 2, representation: 'retained-file'}]);
    const reads = listings(setup.api).length;
    assert.equal(reads, 2);
    assert.deepEqual(await readdir(join(setup.root, 'state',
      'carrier-snapshots')), []);
    const resent = await client.aql(JSON.stringify(document), {format: 'json',
      requestId: 'github-retained-read'});
    assert.deepEqual(resent.ref, run.ref);
    assert.equal(listings(setup.api).length, reads);
    await client.close();
    await close();
    const resumed = await setup.open();
    const attached = await resumed.client.attach(run.ref);
    assert.deepEqual(await attached.result('issues').all(), expected);
    assert.deepEqual(await attached.result('audit').all(), audit);
    assert.equal(listings(setup.api).length, reads);
  });

test('retained GitHub rows keep Event times through a fixed window', async t => {
  const setup = await installation(t, {retainedRelationOutput: true});
  await setup.publish();
  const document = JSON.parse(program);
  document.id = 'github-retained-fixed-events';
  document.stages[1] = {id: 'events',
    inputs: {rows: {result: {stage: 'acquire', result: 'r'}}},
    steps: [
      {from: 'rows', to_events: {id: 'number', time: 'number'}, as: 'source'},
      {from: 'source', window_events: {kind: 'fixed', size: 2},
        as: 'windowed'},
      {from: 'windowed', events: true, as: 'out'},
    ], results: {r: {from: 'out', fields: ['number', 'title', 'author',
      'window_start_ms', 'window_end_ms']}}};
  document.stages.push({id: 'consumer',
    inputs: {x: {result: {stage: 'events', result: 'r'}}},
    steps: [{select: ['number', 'window_start_ms'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'window_start_ms']}}});
  document.results = {windowed: {from: {stage: 'events', result: 'r'}},
    consumed: {from: {stage: 'consumer', result: 'r'}}};
  const {client, close} = await setup.open();
  const run = await client.aql(JSON.stringify(document), {format: 'json',
    requestId: 'github-retained-fixed-events'});
  const state = await run.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [
    {number: 1, title: 'Issue 1', author: 'octocat',
      window_start_ms: 0, window_end_ms: 2},
    {number: 4, title: 'Issue 4', author: 'octocat',
      window_start_ms: 4, window_end_ms: 6},
    {number: 5, title: 'Issue 5', author: 'octocat',
      window_start_ms: 4, window_end_ms: 6},
  ];
  assert.deepEqual(await run.result('windowed').all(), expected);
  assert.deepEqual(await run.result('consumed').all(), [
    {number: 1, window_start_ms: 0},
    {number: 4, window_start_ms: 4},
    {number: 5, window_start_ms: 4},
  ]);
  const reads = listings(setup.api).length;
  assert.equal(reads, 2);
  await close();
  const reopened = await setup.open();
  const attached = await reopened.client.attach(run.ref);
  assert.deepEqual(await attached.result('windowed').all(), expected);
  assert.equal(listings(setup.api).length, reads);
});

test('retained row source admits its exact row ceiling and refuses one more',
  async t => {
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      observe(name, detail) { observations.push([name, detail]); }});
    const repository = setup.state.repositories.get('R_hello');
    repository.issues = Array.from({length: 100}, (_, index) =>
      ({number: index + 1}));
    setup.state.pageSize = 100;
    await setup.publish();
    const {client} = await setup.open();
    const exact = await client.aql(program, {format: 'json',
      requestId: 'github-retained-exact-row-ceiling'});
    const exactState = await exact.wait();
    assert.equal(exactState.status, 'succeeded', JSON.stringify(exactState));
    assert.deepEqual(await exact.result('issues').all(),
      Array.from({length: 100}, (_, index) => ({number: index + 1,
        title: `Issue ${index + 1}`, author: 'octocat'})));
    const beforeExtra = listings(setup.api).length;
    repository.issues.push({number: 101});
    const excess = await client.aql(program, {format: 'json',
      requestId: 'github-retained-one-over-row-ceiling'});
    const excessState = await excess.wait();
    assert.equal(excessState.status, 'failed', JSON.stringify(excessState));
    assert.ok(observations.some(([name, detail]) =>
      name === 'dispatch_failed' && detail.code === 'GitHubReadRowLimit'),
    JSON.stringify(observations));
    assert.equal(excessState.result_available, false);
    assert.equal(excessState.result_availability.issues.state, 'unavailable');
    await assert.rejects(excess.result('issues').all(),
      {code: 'ResultAccessDenied'});
    assert.equal(listings(setup.api).length, beforeExtra + 2);
    assert.deepEqual(await readdir(join(setup.root, 'state',
      'carrier-snapshots')), []);
    const resent = await client.aql(program, {format: 'json',
      requestId: 'github-retained-one-over-row-ceiling'});
    assert.deepEqual(resent.ref, excess.ref);
    assert.equal(listings(setup.api).length, beforeExtra + 2);
  });

const twoRowSourceProgram = () =>
  ({version: 'actql/0.1', id: 'github-two-source-join',
      stages: [
        {id: 'left', inputs: {remote: {connector: 'gh-hello', resource: 'issues'}},
          steps: [{filter: "state = 'open'", as: 'open'},
            {select: ['number', 'title'], as: 'rows'}],
          results: {r: {from: 'rows', fields: ['number', 'title']}}},
        {id: 'right', inputs: {remote: {connector: 'gh-copy', resource: 'issues'}},
          steps: [{filter: "state = 'open'", as: 'open'},
            {select: ['number', 'title'], as: 'rows'}],
          results: {r: {from: 'rows', fields: ['number', 'title']}}},
        {id: 'join', inputs: {
          l: {result: {stage: 'left', result: 'r'}},
          r: {result: {stage: 'right', result: 'r'}}},
        steps: [{from: 'l', join: {with: 'r', kind: 'inner',
          on: [{left: 'number', right: 'number'}], max_output_rows: 100,
          select: {number: 'left.number', left_title: 'left.title',
            right_title: 'right.title'}}},
        {sort: [{number: 'asc'}], as: 'ordered'}],
        results: {r: {from: 'ordered', fields: ['number', 'left_title',
          'right_title']}}},
        {id: 'consumer_a', inputs: {x: {result: {stage: 'join', result: 'r'}}},
          steps: [{select: ['number', 'left_title'], as: 'rows'}],
          results: {r: {from: 'rows', fields: ['number', 'left_title']}}},
        {id: 'consumer_b', inputs: {x: {result: {stage: 'join', result: 'r'}}},
          steps: [{select: ['number', 'right_title'], as: 'rows'}],
          results: {r: {from: 'rows', fields: ['number', 'right_title']}}}],
      results: {joined: {from: {stage: 'join', result: 'r'}},
        consumed_a: {from: {stage: 'consumer_a', result: 'r'}},
        consumed_b: {from: {stage: 'consumer_b', result: 'r'}}}});

const twoSourceEventsWindowProgram = () => {
  const document = twoRowSourceProgram();
  document.id = 'github-two-source-events-window';
  document.stages.length = 3;
  document.stages.push({id: 'events',
    inputs: {rows: {result: {stage: 'join', result: 'r'}}},
    steps: [
      {from: 'rows', to_events: {id: 'number', time: 'number'}, as: 'source'},
      {from: 'source', window_events: {kind: 'fixed', size: 2},
        as: 'windowed'},
      {from: 'windowed', events: true, as: 'bridged'},
      {from: 'bridged', filter: 'number > 0', as: 'out'},
    ], results: {r: {from: 'out', fields: ['number', 'left_title',
      'right_title', 'window_start_ms', 'window_end_ms']}}},
  {id: 'consumer', inputs: {x: {result: {stage: 'events', result: 'r'}}},
    steps: [{select: ['number', 'window_start_ms'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'window_start_ms']}}});
  document.results = {windowed: {from: {stage: 'events', result: 'r'}},
    consumed: {from: {stage: 'consumer', result: 'r'}}};
  return document;
};

const useDuckDBAsSecondSource = document => {
  document.stages[1].inputs.remote = {connector: 'crm/main', resource: 'r'};
  document.stages[1].steps = [
    {filter: 'id >= 0', as: 'open'},
    {select: ['id', 'amount'], as: 'rows'},
  ];
  document.stages[1].results.r.fields = ['id', 'amount'];
  document.stages[2].steps[0].join.on = [{left: 'number', right: 'id'}];
  document.stages[2].steps[0].join.select = {
    number: 'left.number', left_title: 'left.title',
    amount: 'right.amount',
  };
  document.stages[2].results.r.fields = ['number', 'left_title', 'amount'];
  return document;
};

test('two installed row sources retain a joined public Named Result',
  async t => {
    let outputRepresentations;
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      secondSource: true,
      observe(name, detail) {
        observations.push([name, detail]);
        if (name === 'computed') outputRepresentations = detail.outputRepresentations;
      }});
    await setup.publish();
    const document = twoRowSourceProgram();
    const {client, close} = await setup.open();
    const run = await client.aql(JSON.stringify(document), {format: 'json',
      requestId: 'github-two-source-join'}).catch(error => {
        assert.fail(`${error.stack}\n${error.cause?.stack ?? ''}\n${JSON.stringify(observations)}`);
      });
    const state = await run.wait();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const joined = [
      {number: 1, left_title: 'Issue 1', right_title: 'Copy 1'},
      {number: 5, left_title: 'Issue 5', right_title: 'Copy 5'},
    ];
    const consumedA = joined.map(({number, left_title}) =>
      ({number, left_title}));
    const consumedB = joined.map(({number, right_title}) =>
      ({number, right_title}));
    assert.deepEqual(await run.result('joined').all(), joined);
    assert.deepEqual(await run.result('consumed_a').all(), consumedA);
    assert.deepEqual(await run.result('consumed_b').all(), consumedB);
    assert.deepEqual(outputRepresentations,
      [{task: 2, representation: 'retained-file'},
        {task: 3, representation: 'retained-file'},
        {task: 4, representation: 'retained-file'}]);
    assert.equal(observations.filter(([name]) => name === 'acquisition_completed').length, 2);
    assert.equal(observations.filter(([name]) => name === 'acquisition_cleanup_completed').length, 2);
    const capturedUsage = observations.filter(([name]) =>
      name === 'acquisition_completed').map(([, detail]) => detail.resourceUsage);
    assert.ok(capturedUsage.every(usage => BigInt(usage.transferredBytes) > 0n));
    assert.equal(capturedUsage.at(-1).holdings, '2');
    assertAcquisitionReleased(observations);
    assert.deepEqual(listings(setup.api).map(request => request.variables.id),
      ['R_hello', 'R_hello', 'R_copy']);
    assert.deepEqual(await readdir(join(setup.root, 'state',
      'carrier-snapshots')), []);
    const resent = await client.aql(JSON.stringify(document), {format: 'json',
      requestId: 'github-two-source-join'});
    assert.deepEqual(resent.ref, run.ref);
    assert.equal(listings(setup.api).length, 3);
    await client.close();
    await close();
    const reopened = await setup.open();
    const attached = await reopened.client.attach(run.ref);
    assert.deepEqual(await attached.result('joined').all(), joined);
    assert.deepEqual(await attached.result('consumed_a').all(), consumedA);
    assert.deepEqual(await attached.result('consumed_b').all(), consumedB);
    assert.equal(listings(setup.api).length, 3);
  });

test('retained two-source Join feeds an Events window and consumer', async t => {
  const observations = [];
  const setup = await installation(t, {retainedRelationOutput: true,
    secondSource: true,
    observe(name, detail) { observations.push([name, detail]); }});
  await setup.publish();
  const document = twoSourceEventsWindowProgram();
  const {client, close} = await setup.open();
  const run = await client.aql(JSON.stringify(document), {format: 'json',
    requestId: 'github-two-source-events-window'});
  const state = await run.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [
    {number: 1, left_title: 'Issue 1', right_title: 'Copy 1',
      window_start_ms: 0, window_end_ms: 2},
    {number: 5, left_title: 'Issue 5', right_title: 'Copy 5',
      window_start_ms: 4, window_end_ms: 6},
  ];
  assert.deepEqual(await run.result('windowed').all(), expected);
  assert.deepEqual(await run.result('consumed').all(), [
    {number: 1, window_start_ms: 0},
    {number: 5, window_start_ms: 4},
  ]);
  assert.equal(observations.filter(([name]) =>
    name === 'acquisition_completed').length, 2);
  assertAcquisitionReleased(observations);
  const representations = observations.filter(([name]) =>
    name === 'computed').at(-1)?.[1].outputRepresentations;
  assert.ok(representations?.some(item => item.task === 2 &&
    item.representation === 'retained-file'));
  assert.ok(representations.some(item =>
    item.representation === 'managed-local-memory'));
  const reads = listings(setup.api).length;
  assert.equal(reads, 3);
  await close();
  const reopened = await setup.open();
  const attached = await reopened.client.attach(run.ref);
  assert.deepEqual(await attached.result('windowed').all(), expected);
  assert.equal(listings(setup.api).length, reads);
});

test('mixed GitHub and DuckDB captures feed a retained Events window', async t => {
  const observations = [];
  const setup = await installation(t, {retainedRelationOutput: true,
    mixedSource: true,
    observe(name, detail) { observations.push([name, detail]); }});
  await setup.publish();
  const provider = observeTwoSourceProvider(setup.duckdb, {mixed:
    join(setup.root, 'mixed-source.duckdb')});
  t.after(() => provider.restore());
  const document = useDuckDBAsSecondSource(twoSourceEventsWindowProgram());
  document.id = 'github-duckdb-retained-events-window';
  document.stages[3].results.r.fields = ['number', 'left_title',
    'amount', 'window_start_ms', 'window_end_ms'];
  const wire = JSON.stringify(document);
  const {client, close} = await setup.open();
  const run = await client.aql(wire, {format: 'json',
    requestId: 'github-duckdb-retained-events-window'});
  const state = await run.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const expected = [
    {number: 1, left_title: 'Issue 1', amount: 100,
      window_start_ms: 0, window_end_ms: 2},
    {number: 5, left_title: 'Issue 5', amount: 500,
      window_start_ms: 4, window_end_ms: 6},
  ];
  assert.deepEqual(await run.result('windowed').all(), expected);
  assert.deepEqual(await run.result('consumed').all(), [
    {number: 1, window_start_ms: 0},
    {number: 5, window_start_ms: 4},
  ]);
  assert.equal(observations.filter(([name]) =>
    name === 'acquisition_completed').length, 2);
  assertAcquisitionReleased(observations);
  const representations = observations.filter(([name]) =>
    name === 'computed').at(-1)?.[1].outputRepresentations;
  assert.ok(representations?.some(item => item.task === 2 &&
    item.representation === 'retained-file'));
  assert.ok(representations.some(item =>
    item.representation === 'managed-local-memory'));
  const providerReads = provider.snapshot().sourceReads;
  assert.ok(providerReads > 0);
  const githubReads = listings(setup.api).length;
  assert.equal(githubReads, 2);
  await client.close();
  await close();
  const reopened = await setup.open();
  const attached = await reopened.client.attach(run.ref);
  assert.deepEqual(await attached.result('windowed').all(), expected);
  assert.equal(listings(setup.api).length, githubReads);
  assert.equal(provider.snapshot().sourceReads, providerReads);
});

test('retained two-source Events failure keeps cleanup for retry', async t => {
  let failClose = true;
  let reachedClose;
  const firstClose = new Promise(resolve => { reachedClose = resolve; });
  const observations = [];
  const setup = await installation(t, {retainedRelationOutput: true,
    secondSource: true,
    observe(name, detail) { observations.push([name, detail]); },
    faultInjection(name, detail) {
      if (name === 'acquisition_cleanup_started' && detail.task === 0) {
        reachedClose();
        if (failClose) throw new Error('FixtureEventsInputCloseFailed');
      }
    }});
  await setup.publish();
  const document = twoSourceEventsWindowProgram();
  document.id = 'github-two-source-events-failure';
  document.stages[3].steps[3].filter =
    'number / (number - number) > 0';
  const {client, host} = await setup.open();
  const run = await client.aql(JSON.stringify(document), {format: 'json',
    requestId: 'github-two-source-events-failure'});
  await firstClose;
  assert.ok(observations.some(([name, detail]) =>
    name === 'dispatch_failed' && detail.code === 'CapturedRunPublicationFailed'),
  JSON.stringify(observations));
  const reads = listings(setup.api).length;
  await assert.rejects(host.close(), error => {
    assert.equal(error.code, 'ClientDispatchCleanupPending');
    assert.ok(error.failures?.some(failure =>
      failure.cleanup?.errors?.some(cause =>
        cause.message === 'FixtureEventsInputCloseFailed')));
    return true;
  });
  const pending = observations.filter(([name, detail]) =>
    name === 'acquisition_cleanup_started' && detail.task === 0);
  assert.ok(pending.length >= 2);
  assert.ok(pending.every(([, detail]) =>
    BigInt(detail.resourceUsage.heldBytes) > 0n));
  failClose = false;
  await host.close();
  assert.equal(listings(setup.api).length, reads);
  assert.equal(observations.filter(([name]) =>
    name === 'acquisition_started').length, 2);
  assertAcquisitionReleased(observations);
  assert.deepEqual(await readdir(join(setup.root, 'state',
    'carrier-snapshots')), []);
  const reopened = await setup.open();
  const attached = await reopened.client.attach(run.ref);
  const state = await attached.status();
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(state.result_available, false);
  await assert.rejects(attached.result('windowed').all(),
    {code: 'ResultAccessDenied'});
  assert.equal(listings(setup.api).length, reads);
});

test('GitHub and DuckDB captures share one retained two-source owner',
  async t => {
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      mixedSource: true,
      observe(name, detail) { observations.push([name, detail]); }});
    await setup.publish();
    const provider = observeTwoSourceProvider(setup.duckdb, {mixed:
      join(setup.root, 'mixed-source.duckdb')});
    t.after(() => provider.restore());
    const document = twoRowSourceProgram();
    document.id = 'github-duckdb-retained-join';
    useDuckDBAsSecondSource(document);
    document.stages[4].steps[0].select = ['number', 'amount'];
    document.stages[4].results.r.fields = ['number', 'amount'];
    const wire = JSON.stringify(document);
    const {client, close} = await setup.open();
    const run = await client.aql(wire, {format: 'json',
      requestId: 'github-duckdb-retained-join'});
    const state = await run.wait();
    assert.equal(state.status, 'succeeded', JSON.stringify(state));
    const joined = [{number: 1, left_title: 'Issue 1', amount: 100},
      {number: 5, left_title: 'Issue 5', amount: 500}];
    assert.deepEqual(await run.result('joined').all(), joined);
    assert.deepEqual(await run.result('consumed_a').all(),
      [{number: 1, left_title: 'Issue 1'},
        {number: 5, left_title: 'Issue 5'}]);
    assert.deepEqual(await run.result('consumed_b').all(),
      [{number: 1, amount: 100}, {number: 5, amount: 500}]);
    assert.equal(observations.filter(([name]) =>
      name === 'acquisition_completed').length, 2);
    assertAcquisitionReleased(observations);
    const providerReads = provider.snapshot().sourceReads;
    assert.ok(providerReads > 0, 'the selected DuckDB source performed physical I/O');
    const reads = listings(setup.api).length;
    assert.equal(reads, 2);
    const resent = await client.aql(wire, {format: 'json',
      requestId: 'github-duckdb-retained-join'});
    assert.deepEqual(resent.ref, run.ref);
    assert.equal(listings(setup.api).length, reads);
    assert.equal(provider.snapshot().sourceReads, providerReads);
    const reversed = structuredClone(document);
    reversed.id = 'duckdb-github-retained-join';
    [reversed.stages[0], reversed.stages[1]] =
      [reversed.stages[1], reversed.stages[0]];
    const reverseRun = await client.aql(JSON.stringify(reversed),
      {format: 'json', requestId: 'duckdb-github-retained-join'});
    const reverseState = await reverseRun.wait();
    assert.equal(reverseState.status, 'succeeded', JSON.stringify(reverseState));
    assert.deepEqual(await reverseRun.result('joined').all(), joined);
    const reverseReads = provider.snapshot().sourceReads;
    assert.ok(reverseReads > providerReads);
    assert.equal(listings(setup.api).length, reads + 2);
    await client.close();
    await close();
    const reopened = await setup.open();
    const attached = await reopened.client.attach(run.ref);
    assert.deepEqual(await attached.result('joined').all(), joined);
    const reverseAttached = await reopened.client.attach(reverseRun.ref);
    assert.deepEqual(await reverseAttached.result('joined').all(), joined);
    assert.equal(listings(setup.api).length, reads + 2);
    assert.equal(provider.snapshot().sourceReads, reverseReads);
  });

test('a failed second row source preserves first-input cleanup without publication',
  async t => {
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      secondSource: true,
      observe(name, detail) { observations.push([name, detail]); }});
    await setup.publish();
    const normal = graphqlRoute(() => ({...setup.state, answer: undefined}));
    let page = 0;
    setup.state.answer = variables => ++page <= 2
      ? normal.handle({body: JSON.stringify({query: 'query ActqlIssues(',
        variables})})
      : {headers: {'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1790000000'},
        body: {data: null, errors: [{type: 'RATE_LIMITED',
          message: 'API rate limit exceeded'}]}};
    const {client} = await setup.open();
    const document = JSON.stringify(twoRowSourceProgram());
    const run = await client.aql(document, {format: 'json',
      requestId: 'github-two-source-second-fails'});
    const state = await run.wait();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(state.result_availability.joined.state, 'unavailable');
    await assert.rejects(run.result('joined').all(), {code: 'ResultAccessDenied'});
    assert.equal(observations.filter(([name]) => name === 'acquisition_completed').length, 1);
    assert.equal(observations.filter(([name]) => name === 'acquisition_cleanup_completed').length, 1);
    assertAcquisitionReleased(observations);
    assert.deepEqual(await readdir(join(setup.root, 'state',
      'carrier-snapshots')), []);
    const reads = listings(setup.api).length;
    assert.equal(reads, 3);
    const resent = await client.aql(document, {format: 'json',
      requestId: 'github-two-source-second-fails'});
    assert.deepEqual(resent.ref, run.ref);
    assert.equal(listings(setup.api).length, reads);
  });

test('two-source row cleanup retries without reacquisition after a later failure',
  async t => {
    let failClose = true;
    let reachedClose;
    const firstClose = new Promise(resolve => { reachedClose = resolve; });
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      secondSource: true,
      observe(name, detail) { observations.push([name, detail]); },
      faultInjection(name, detail) {
        if (name === 'acquisition_cleanup_started' && detail.task === 0) {
          reachedClose();
          if (failClose) throw new Error('FixtureRowCaptureCloseFailed');
        }
      }});
    await setup.publish();
    const normal = graphqlRoute(() => ({...setup.state, answer: undefined}));
    let page = 0;
    setup.state.answer = variables => ++page <= 2
      ? normal.handle({body: JSON.stringify({query: 'query ActqlIssues(',
        variables})})
      : {headers: {'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1790000000'},
        body: {data: null, errors: [{type: 'RATE_LIMITED',
          message: 'API rate limit exceeded'}]}};
    const {client, host} = await setup.open();
    const run = await client.aql(JSON.stringify(twoRowSourceProgram()),
      {format: 'json', requestId: 'github-two-source-cleanup-retry'});
    await firstClose;
    const beforeRetry = listings(setup.api).length;
    await assert.rejects(host.close(), error => {
      assert.equal(error.code, 'ClientDispatchCleanupPending');
      assert.ok(error.failures?.some(failure =>
        failure.cleanup?.errors?.some(cause =>
          cause.message === 'FixtureRowCaptureCloseFailed')));
      return true;
    });
    const pending = observations.filter(([name, detail]) =>
      name === 'acquisition_cleanup_started' && detail.task === 0);
    assert.ok(pending.length >= 2);
    assert.ok(pending.every(([, detail]) => BigInt(detail.resourceUsage.heldBytes) > 0n));
    failClose = false;
    await host.close();
    assert.equal(listings(setup.api).length, beforeRetry);
    const completed = observations.filter(([name, detail]) =>
      name === 'acquisition_cleanup_completed' && detail.task === 0);
    assert.equal(completed.length, 1);
    for (const key of ['reservedTransferBytes', 'heldBytes',
      'reservedRetentionBytes', 'reservedExecutionBytes']) {
      assert.equal(completed[0][1].resourceUsage[key], '0', key);
    }
    assert.equal(observations.filter(([name]) => name === 'acquisition_started').length, 2);
    assertAcquisitionReleased(observations);
    const reopened = await setup.open();
    const state = await (await reopened.client.attach(run.ref)).status();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
  });

test('two-source cancellation retains the first row capture until stop and cleanup',
  async t => {
    let reachedFirst;
    const firstCompleted = new Promise(resolve => { reachedFirst = resolve; });
    let releaseFirst;
    const pause = new Promise(resolve => { releaseFirst = resolve; });
    const observations = [];
    const setup = await installation(t, {retainedRelationOutput: true,
      secondSource: true,
      observe(name, detail) { observations.push([name, detail]); },
      faultInjection(name, detail) {
        if (name === 'acquisition_completed' && detail.task === 0) {
          reachedFirst();
          return pause;
        }
      }});
    t.after(() => releaseFirst());
    await setup.publish();
    const {client} = await setup.open();
    const document = JSON.stringify(twoRowSourceProgram());
    const run = await client.aql(document, {format: 'json',
      requestId: 'github-two-source-cancel'});
    await firstCompleted;
    const firstUsage = observations.find(([name, detail]) =>
      name === 'acquisition_completed' && detail.task === 0)?.[1].resourceUsage;
    assert.equal(firstUsage?.holdings, '1');
    assert.notEqual(firstUsage?.heldBytes, '0');
    await client.cancelRequest('github-two-source-cancel');
    releaseFirst();
    const state = await run.wait();
    assert.equal(state.status, 'cancelled', JSON.stringify(state));
    assert.equal(state.result_available, false);
    await assert.rejects(run.result('joined').all(), {code: 'ResultAccessDenied'});
    assert.equal(observations.filter(([name]) => name === 'acquisition_started').length, 1);
    assert.equal(observations.filter(([name]) => name === 'acquisition_cleanup_completed').length, 1);
    assertAcquisitionReleased(observations);
    assert.equal(listings(setup.api).length, 2);
  });

test('retained row source does not publish after a later page fails',
  async t => {
    const setup = await installation(t, {retainedRelationOutput: true,
      observe() {}});
    await setup.publish();
    const normal = graphqlRoute(() => ({...setup.state, answer: undefined}));
    setup.state.answer = variables => variables.after === null
      ? normal.handle({body: JSON.stringify({query: 'query ActqlIssues(',
        variables})})
      : {headers: {'x-ratelimit-remaining': '0',
        'x-ratelimit-reset': '1790000000'},
        body: {data: null, errors: [{type: 'RATE_LIMITED',
          message: 'API rate limit exceeded'}]}};
    const {client} = await setup.open();
    const run = await client.aql(program, {format: 'json',
      requestId: 'github-retained-later-page-failure'});
    const state = await run.wait();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(state.result_availability.issues.state, 'unavailable');
    assert.equal(listings(setup.api).length, 2);
    assert.deepEqual(await readdir(join(setup.root, 'state',
      'carrier-snapshots')), []);
    const resent = await client.aql(program, {format: 'json',
      requestId: 'github-retained-later-page-failure'});
    assert.deepEqual(resent.ref, run.ref);
    assert.equal(listings(setup.api).length, 2);
  });

test('a renamed repository binding is refused until it is published again',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    await writeFile(setup.sitePath, JSON.stringify({...setup.site,
      repo: 'hello-renamed'}));
    const seen = setup.api.seen().length;
    await assert.rejects(setup.open(), {code: 'GitHubRepositoryBindingChanged'});
    assert.equal(setup.api.seen().length, seen);
  });

test('a rate limit stated in an HTTP 200 stops the Run without a Result',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    setup.state.answer = () => ({
      headers: {'x-ratelimit-remaining': '0', 'x-ratelimit-reset': '1790000000'},
      body: {data: null, errors: [{type: 'RATE_LIMITED',
        message: 'API rate limit exceeded'}]}});
    const {client} = await setup.open();
    const execution = await client.aql(program, {format: 'json',
      requestId: 'github-read-limited'});
    const state = await execution.wait();
    assert.equal(state.status, 'failed', JSON.stringify(state));
    assert.equal(state.result_available, false);
    assert.equal(listings(setup.api).length, 1);
  });

// The local Site profile stays fixed in every case below; only the
// provider's state changes after publication.
const failsWithoutResult = async (setup, requestId) => {
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json', requestId});
  const state = await execution.wait();
  assert.equal(state.status, 'failed', JSON.stringify(state));
  assert.equal(state.result_available, false);
  assert.equal(state.result_availability.issues.state, 'unavailable');
};

test('A, then a same-name B, then A again: every request stays on A', async t => {
  const setup = await installation(t);
  await setup.publish();
  // B takes the name while the read runs; A keeps its node ID.
  let pages = 0;
  const original = setup.state;
  setup.state.repositories.set('R_other', {databaseId: 424242,
    nameWithOwner: 'octocat/hello', issues: storedB});
  const route = graphqlRoute(() => original);
  setup.state.answer = variables => {
    pages += 1;
    original.names.set('octocat/hello', pages === 1 ? 'R_other' : 'R_hello');
    const {answer} = original;
    original.answer = undefined;
    try { return route.handle({body: JSON.stringify({
      query: 'query ActqlIssues(', variables})}); }
    finally { original.answer = answer; }
  };
  const {client} = await setup.open();
  const execution = await client.aql(program, {format: 'json',
    requestId: 'github-read-aba'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  // Only A's rows; none of B's titles.
  assert.deepEqual(rows.map(row => row.title).sort(),
    ['Issue 1', 'Issue 4', 'Issue 5']);
  assert.ok(listings(setup.api).every(request =>
    request.variables.id === 'R_hello'));
  assert.ok(onlyGraphql(setup.api));
});

test('a node answer for repository B is refused without a Result', async t => {
  const setup = await installation(t);
  await setup.publish();
  const a = setup.state.repositories.get('R_hello');
  setup.state.repositories.set('R_hello', {...a, databaseId: 424242,
    issues: storedB});
  await failsWithoutResult(setup, 'github-read-foreign');
  assert.equal(listings(setup.api).length, 1);
});

test('a vanished or unreadable A is never replaced by a name lookup', async t => {
  const setup = await installation(t);
  await setup.publish();
  setup.state.repositories.delete('R_hello');
  setup.state.repositories.set('R_other', {databaseId: 424242,
    nameWithOwner: 'octocat/hello', issues: storedB});
  setup.state.names.set('octocat/hello', 'R_other');
  await failsWithoutResult(setup, 'github-read-vanished');
  assert.ok(listings(setup.api).every(request =>
    request.variables.id === 'R_hello'));
  // Only the publication used a name.
  assert.equal(setup.api.seen().filter(entry => JSON.parse(entry.body).query
    .startsWith('query ActqlRepository(')).length, 1);
});

test('a changed node ID representation needs an explicit re-publication',
  async t => {
    const setup = await installation(t);
    await setup.publish();
    setup.state.repositories.get('R_hello').answerId = 'R_hello_next';
    await failsWithoutResult(setup, 'github-read-id-spelling');
    // A new explicit publication would record the current spelling; a read
    // never rewrites the binding.
    const publication = JSON.parse(await readFile(
      setup.profile.publicationPath, 'utf8'));
    assert.equal(publication.repository.node_id, 'R_hello');
  });

// The body column is published exactly as GitHub stated it.
const bodyProgram = JSON.stringify({version: 'actql/0.1', id: 'github-body',
  stages: [{id: 'acquire',
    inputs: {remote: {connector: 'gh-hello', resource: 'issues'}},
    steps: [{filter: "state = 'open'", as: 'open'},
      {select: ['number', 'body'], as: 'captured'}],
    results: {r: {from: 'captured', fields: ['number', 'body']}}},
  {id: 'compute',
    inputs: {x: {result: {stage: 'acquire', result: 'r'}}},
    steps: [{select: ['number', 'body'], as: 'out'}],
    results: {r: {from: 'out', fields: ['number', 'body']}}}],
  results: {issues: {from: {stage: 'compute', result: 'r'}}}});

test('an empty body is published as an empty string, not NULL', async t => {
  const setup = await installation(t);
  setup.state.repositories.get('R_hello').issues = [
    {number: 1, body: ''}, {number: 2, body: 'text'}];
  await setup.publish();
  const {client} = await setup.open();
  const execution = await client.aql(bodyProgram, {format: 'json',
    requestId: 'github-body-1'});
  const state = await execution.wait();
  assert.equal(state.status, 'succeeded', JSON.stringify(state));
  const rows = await execution.result('issues').all();
  assert.deepEqual(rows.map(row => [row.number, row.body])
    .sort((a, b) => a[0] - b[0]), [[1, ''], [2, 'text']]);
});

test('a missing, null or invalid body fails the Run without a Result', async t => {
  for (const [requestId, mutate] of [
    ['github-body-missing', node => { delete node.body; }],
    ['github-body-null', node => { node.body = null; }],
    ['github-body-number', node => { node.body = 7; }],
  ]) {
    const setup = await installation(t);
    await setup.publish();
    const route = graphqlRoute(() => ({...setup.state, answer: undefined}));
    setup.state.answer = variables => {
      const reply = route.handle({body: JSON.stringify({
        query: 'query ActqlIssues(', variables})});
      for (const node of reply.body.data.node.issues.nodes) mutate(node);
      return reply;
    };
    await failsWithoutResult(setup, requestId);
  }
});
