// Run after an ordinary installation of one verified six-package cohort.
// Only the HTTPS metadata service is a fixture; all preparation, authorization,
// projection, Gateway and React code comes from the installed public exports.
import assert from 'node:assert/strict';
import test from 'node:test';
import {generateKeyPairSync, createHash, type BinaryLike} from 'node:crypto';
import {createRequire} from 'node:module';
import {mkdir, readFile, realpath, writeFile} from 'node:fs/promises';
import {join, sep} from 'node:path';
import {pathToFileURL} from 'node:url';
import {createServer, type Server} from 'node:https';
import {DatabaseSync} from 'node:sqlite';
import {userInfo} from 'node:os';
import {open} from '@actql/node';
import {publishEffect} from '@actql/local-node';
import {startExplorer} from '@actql/explorer/launcher';
import {createExplorerBrowserSource} from '@actql/explorer/browser-source';
import {fixtureCertificates} from '../../adapters/site-node/https-exchange-fixture.mjs';
import type {StaticExplanationReadModel} from '@actql/explorer-ui/read-model';
import type {Browser, BrowserModule} from './packed-explorer-browser.mjs';

type Client = Awaited<ReturnType<typeof open>>;
type Gateway = Awaited<ReturnType<typeof startExplorer>>;
type ProviderRequest = {method: string | undefined; path: string};
type Census = Record<string, number | bigint>;
type Publication = {generationCid: string; environmentCid: string; mappings: readonly Readonly<{
  mappingRef: string; mappingCid: string; resource: string; kind: string}>[]};
type BrowserReceipt = {paths: string[]; errors: string[]; foreign: string[]; lastAction: string; visibleText?: string};
type Failure = {name?: string; code?: string; primaryFailure?: Failure;
  cleanupHandle?: {status(): {pending: boolean; owners: unknown}}};
type Receipt = {
  profile: string;
  complete: boolean;
  cases: Record<string, unknown>[];
  cleanup: {name: string; acknowledged: boolean}[];
  productImports: {name: string; path: string; sha256: string}[];
  ProviderIOWhilePlanning: number | null;
  newRuns: number | null;
  newSubmissions: number | null;
  signedResolutions: number;
  metadataPublication?: Publication & {requests: ProviderRequest[]; secretCalls: number};
  originalPlan?: Awaited<ReturnType<Client['plan']>>;
  browserVersion?: string;
  browser?: BrowserReceipt;
  journalBefore?: Census;
  journalCounts?: {before: Census; after: Census};
  journalBeforeClose?: Census;
  providerRequests?: ProviderRequest[];
  totalSecretCalls?: number;
  failure?: {phase: string; kind?: string; primaryKind?: string};
  initializationCleanup?: {pending: boolean; owners: unknown};
};

const hash = (bytes: BinaryLike) => createHash('sha256').update(bytes).digest('hex');
const canonical = (value: unknown) => JSON.stringify(value, function (_key, member: unknown) {
  if (member === null || typeof member !== 'object' || Array.isArray(member)) return member;
  const fields = member as Record<string, unknown>;
  return Object.fromEntries(Object.keys(fields).sort().map(key => [key, fields[key]]));
});
const receipt: Receipt = {profile: 'installed Local Effectful static Plan', complete: false,
  cases: [], cleanup: [], productImports: [], ProviderIOWhilePlanning: null,
  newRuns: null, newSubmissions: null, signedResolutions: 0};
const root = process.cwd(), evidence = process.env.ACTQL_TEST_EVIDENCE_DIRECTORY;
const browserModule = process.env.ACTQL_TEST_PLAYWRIGHT_MODULE;
const executablePath = process.env.ACTQL_TEST_BROWSER_EXECUTABLE;
assert(evidence && browserModule && executablePath, 'Explicit evidence and browser tooling required');
const require = createRequire(import.meta.url);
for (const name of ['@actql/node', '@actql/local-node', '@actql/explorer/launcher',
  '@actql/explorer/browser-source']) {
  const path = await realpath(require.resolve(name));
  assert(path.startsWith(join(root, 'node_modules') + sep));
  receipt.productImports.push({name, path, sha256: hash(await readFile(path))});
}
const {chromium}: BrowserModule = await import(pathToFileURL(browserModule).href);

// This observer uses SQLite's normal read-only WAL-aware connection. It does
// not checkpoint, mutate the journal, or interpret a saved Allow as permission.
function journalCounts(path: string): Census {
  const db = new DatabaseSync(path, {readOnly: true});
  try {
    const tables = db.prepare("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name").all();
    return Object.fromEntries(tables.map(({name}) => {
      assert(typeof name === 'string' && /^[a-z_]+$/u.test(name));
      const count = db.prepare(`SELECT count(*) AS n FROM "${name}"`).get()?.n;
      assert(typeof count === 'number' || typeof count === 'bigint');
      return [name, count];
    }));
  } finally {db.close();}
}

await test('ordinary installed Local Explorer shows checked update declarations without executing a Run', async () => {
  let client: Client | undefined, gateway: Gateway | undefined, browser: Browser | undefined, server: Server | undefined;
  let journalPath: string | undefined, phase = 'metadata fixture', primary: Error | undefined;
  const sends: ProviderRequest[] = [], unexpected: ProviderRequest[] = [];
  let secretCalls = 0;
  const secret = 'synthetic-static-plan-provider-token';
  const stateDir = join(root, 'state'), tlsDir = join(root, 'provider-tls');
  await mkdir(tlsDir);
  try {
    const tls = await fixtureCertificates(tlsDir);
    const metadata = server = createServer({cert: tls.cert, key: tls.key}, (request, response) => {
      assert(request.url);
      const path = new URL(request.url, 'https://fixture.invalid').pathname;
      const observed = {method: request.method, path};
      sends.push(observed);
      if (request.method !== 'GET' || path !== '/services/data/v62.0/sobjects/Test_Record__c/describe' ||
        request.headers.authorization !== `Bearer ${secret}`) {
        unexpected.push(observed); response.writeHead(403).end(); return;
      }
      const bytes = JSON.stringify({name: 'Test_Record__c', queryable: true,
        createable: true, updateable: true, fields: [
          {name: 'Id', type: 'id', nillable: false, sortable: false},
          {name: 'Name', type: 'string', nillable: false, defaultedOnCreate: false,
            createable: true, updateable: true},
        ]});
      response.writeHead(200, {'content-type': 'application/json'}).end(bytes);
    });
    await new Promise<void>((resolve, reject) => {
      metadata.once('error', reject); metadata.listen(0, '127.0.0.1', resolve);
    });
    const address = metadata.address();
    assert(address && typeof address !== 'string');
    const providerOrigin = `https://127.0.0.1:${address.port}`;
    // A new disposable test credential signs metadata grants only. No
    // operational credential, Reviewer key or Host-attestation key is read.
    const key = generateKeyPairSync('ed25519');
    const credentialPath = join(root, 'metadata-credential.key');
    await writeFile(credentialPath, key.privateKey.export({type: 'pkcs8', format: 'pem'}), {mode: 0o600});
    const sitePath = join(root, 'site.json'), effectPath = join(root, 'effect.json');
    await writeFile(sitePath, JSON.stringify({version: 'actql-installed-salesforce-site/0.1',
      apiVersion: 'v62.0', cliAlias: 'static-plan-fixture', cliUsername: 'static@example.test',
      connectionRevision: 'static-connection-a', credentialAuthorityId: 'static-metadata-authority',
      credentialKeyId: 'metadata-key', credentialPrivateKeyPath: credentialPath,
      environment: 'static-plan-fixture', instanceOrigin: providerOrigin,
      journalRoot: join(root, 'metadata-credential-journal'), orgId: '00D000000000001EAA',
      siteGeneration: 1, siteKey: 'static-site', namespaceId: 'static-namespace', caPath: tls.caPath}));
    await writeFile(effectPath, JSON.stringify({version: 'actql-installed-salesforce-effect/0.1',
      siteProfilePath: sitePath, publicationPath: join(root, 'effect-publication.json'),
      connectorId: 'crm-main', writes: [{resource: 'Test_Record__c', kind: 'update', fields: ['Name']}],
      accountConfigurationWire: canonical({version: 'actql-execution-account-config/0.1',
        account_id: 'static-plan-account', entries: [
          {entry_id: 'effect-commit', outcome: 'delegate', exclusions: [], principal: {all: true},
            connection: {any_of: ['salesforce:00D000000000001EAA']},
            resource: {any_of: ['Test_Record__c']}, operation: {any_of: ['effect']}},
          {entry_id: 'structural-run-read', outcome: 'allow', exclusions: [], principal: {all: true},
            connection: {all: true}, resource: {any_of: ['run']}, operation: {any_of: ['read']}},
          {entry_id: 'target-read', outcome: 'allow', exclusions: [], principal: {all: true},
            connection: {any_of: ['salesforce:00D000000000001EAA']},
            resource: {any_of: ['Test_Record__c']}, operation: {any_of: ['read']}},
        ]})}));
    const resolveEffectSecret = async () => {secretCalls++; return secret;};
    phase = 'explicit Effect metadata publication';
    const published = await publishEffect({directory: stateDir, effectProfilePath: effectPath, resolveEffectSecret}) as Publication;
    assert.equal(published.mappings.length, 1);
    const mapping = published.mappings[0];
    assert.equal(mapping.resource, 'Test_Record__c'); assert.equal(mapping.kind, 'update');
    assert(sends.length > 0); assert.equal(unexpected.length, 0);
    receipt.metadataPublication = {requests: [...sends], secretCalls, generationCid: published.generationCid,
      environmentCid: published.environmentCid, mappings: published.mappings};
    phase = 'ordinary embedded Local open';
    // The installed Effect Host requires its ordinary explicit registration
    // even for a read-only viewer. These disposable keys are not invoked to
    // sign an Approval. This Account has no Host Run write Allow.
    const reviewer = generateKeyPairSync('ed25519'), host = generateKeyPairSync('ed25519');
    const authorization = {
      accountConfiguration: JSON.parse(await readFile(effectPath, 'utf8')).accountConfigurationWire,
      reviewers: [{keyId: 'static-reviewer-key', reviewerId: 'static-reviewer',
        principalId: userInfo().username, publicKey: reviewer.publicKey.export({type: 'spki', format: 'pem'})}],
      reviewReaders: [userInfo().username],
      hostKey: {keyId: 'static-host-key', privateKey: host.privateKey.export({type: 'pkcs8', format: 'pem'})},
      leaseMs: 10000, resumeAfterAnswer: false,
    };
    const publicationSends = sends.length, publicationSecrets = secretCalls;
    client = await open({stateDir, installation: {effectProfilePath: effectPath, resolveEffectSecret, authorization}});
    assert.equal(sends.length, publicationSends, 'Restore does not republish metadata');
    assert.equal(secretCalls, publicationSecrets, 'Restore does not reacquire a provider secret');
    const journal = join(stateDir, 'requests', 'client-requests.sqlite3');
    journalPath = journal;
    const before = journalCounts(journal), baselineSends = sends.length, baselineSecrets = secretCalls;
    receipt.journalBefore = before;
    assert.equal(before.client_requests, 0); assert.equal(before.client_submitted_intents, 0);
    const program = {version: 'actql/0.1', id: 'installed-static-update', stages: [{id: 'source', inputs: {},
      steps: [{values: {schema: {id: {type: 'string', nullable: false}, next_name: {type: 'string', nullable: false}},
        rows: [{id: 'a00000000000001', next_name: 'must-remain-unknown'}]}, as: 'selected'}],
      results: {rows: {from: 'selected', fields: ['id', 'next_name']}},
      effects: {save: {update: {target: 'connector://crm-main/Test_Record__c', mapping: mapping.mappingRef,
        from: {result: 'rows'}, id: 'id', set: {Name: {field: 'next_name'}}}}}}],
      results: {answer: {from: {stage: 'source', result: 'rows'}}}};
    const expectedMember = {member_ordinal: 0, stage_ordinal: 0, effect_id: 'save', effect_kind: 'update',
      failure_policy: 'halt', contract: {kind: 'mapping', reference: mapping.mappingRef,
        contract_cid: mapping.mappingCid, declared_target: 'connector://crm-main/Test_Record__c'},
      // The Salesforce catalog Owner emits "none" for this Mapping. It is
      // not current permission: the installed Account still delegates Effect.
      input: {kind: 'result', result_name: 'rows'}, minimum_approval: {kind: 'contract_minimum', value: 'none'}};
    phase = 'installed SDK static Plan';
    const direct = await client.plan(program);
    receipt.originalPlan = direct;
    assert.equal(direct.version, 'actql-effectful-static-plan-view/0.1');
    // Publication identifies the connector Environment. The installed Host
    // additionally binds its own capacity profile before preparing a Program.
    // Keep those identities distinct; compare the checked Host's original
    // projection through SDK, Gateway and UI, not against the pre-Host CID.
    assert.match(direct.check_environment_cid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(direct.computation.scope, 'computation_component');
    assert.equal(direct.effect_set.unit_id, 'source');
    assert.deepEqual(direct.effect_set.members, [expectedMember]);
    assert.equal(direct.program_definition_cid, direct.computation.plan_view.logical_map.program_definition_cid);
    assert.equal(direct.observations.permission.state, 'unknown');
    assert.equal(direct.observations.preview.state, 'unavailable');
    phase = 'installed Gateway browser source';
    const connected = gateway = await startExplorer({client});
    let cookie: string | undefined;
    const paths: string[] = [];
    const source = createExplorerBrowserSource({origin: connected.origin, fetch: async (url, init) => {
      const headers = new Headers(init?.headers); headers.set('Origin', connected.origin);
      if (cookie) headers.set('Cookie', cookie);
      paths.push(new URL(url instanceof Request ? url.url : url).pathname);
      const response = await fetch(url, {...init, headers});
      cookie = response.headers.get('set-cookie')?.split(';')[0] ?? cookie; return response;
    }});
    try {
      const capabilities = await source.connect(connected.issueBootstrap().bootstrap);
      assert.equal(capabilities.plan, true); assert.equal(capabilities.control, false); assert.equal(capabilities.sample, false);
      const model = await source.plan(program);
      assert.equal(model.compiledPlanCid, direct.computation.plan_view.compiled_plan_cid);
      assert.equal(model.logicalMapCid, direct.computation.plan_view.logical_map.self_cid);
      assert(model.effectful);
      assert.equal(model.effectful.checkEnvironmentCid, direct.check_environment_cid);
      assert.equal(model.effectful.parameterValuesCid, direct.parameter_values_cid);
      assert.equal(model.programDefinitionCid, direct.program_definition_cid);
      assert.deepEqual(model.effectful.members, [expectedMember]);
      assert.deepEqual(model.nodes.map(node => node.operator), ['values']); assert.deepEqual(model.edges, []);
      assert.deepEqual(model.nodes.map(node => [node.id, node.ports]), direct.computation.plan_view.logical_map.steps.map(step => [step.step_id, step.ports]));
      assert.equal(model.effectful.observations.permission.state, 'unknown');
      assert.equal(model.effectful.observations.preview.state, 'unavailable');
    } finally {source.close();}
    assert.deepEqual(paths, ['/api/session', '/api/read/plan']);
    phase = 'Chromium launch';
    // The consumer HOME is empty. Test tooling is explicit and independent
    // of product installation; never search the developer's HOME implicitly.
    browser = await chromium.launch({headless: true, executablePath});
    receipt.browserVersion = browser.version();
    phase = 'installed built React in Chromium';
    const page = await browser.newPage({viewport: {width: 1440, height: 1100}});
    page.setDefaultTimeout(10000);
    const browserPaths: string[] = [], errors: string[] = [], foreign: string[] = [];
    const ui: BrowserReceipt = receipt.browser = {paths: browserPaths, errors, foreign, lastAction: 'open page'};
    page.on('pageerror', error => errors.push(error.name));
    page.on('request', request => {const url = new URL(request.url());
      if (url.pathname.startsWith('/api/')) browserPaths.push(url.pathname);});
    await page.route('**/*', route => {
      if (new URL(route.request().url()).origin === connected.origin) return route.continue();
      foreign.push('foreign origin refused'); return route.abort();
    });
    try {
      await page.goto(connected.origin, {waitUntil: 'networkidle'});
      await page.getByRole('button', {name: 'Connect to Local', exact: true}).click();
      ui.lastAction = 'fill bootstrap';
      await page.getByLabel('One-use bootstrap').fill(connected.issueBootstrap().bootstrap);
      ui.lastAction = 'connect';
      await page.getByRole('button', {name: 'Connect', exact: true}).click();
      ui.lastAction = 'wait connected status';
      await page.getByText('Local', {exact: false}).and(page.locator('.connection-menu > summary')).waitFor();
      ui.lastAction = 'edit Program draft';
      await page.getByRole('button', {name: 'Edit', exact: true}).click();
      await page.getByLabel('Query options').click();
      await page.locator('.query-panel select[name="format"]').selectOption('program');
      await page.getByRole('textbox', {name: 'Program', exact: true}).fill(JSON.stringify(program));
      ui.lastAction = 'read Plan';
      await page.getByRole('button', {name: 'Read Plan', exact: true}).click();
      const section = page.getByRole('region', {name: 'ActQL static Plan', exact: true});
      ui.lastAction = 'wait computation component';
      await section.getByRole('heading', {name: 'Computation component', exact: true}).waitFor();
      ui.lastAction = 'verify original declared Effects in Graph metadata';
      assert.equal(await section.getByRole('navigation', {name: 'Plan presentation'}).count(), 0);
      await section.getByText('Original Plan metadata', {exact: true}).click();
      const text = await section.getByRole('region', {name: 'Declared Effects', exact: true}).innerText();
      for (const expected of ['unit source', 'save', 'update', mapping.mappingRef, mapping.mappingCid,
        direct.check_environment_cid, direct.parameter_values_cid,
        'Declared target: connector://crm-main/Test_Record__c', 'Result: rows', 'none',
        'Resolved targets: unknown.', 'Changed values: unknown.', 'Current permission: unknown.',
        'Gate: unknown.', 'Approval: unknown.', 'Sealed Preview: unavailable.']) assert(text.includes(expected), expected);
      assert(text.includes('Required approval does not imply a human-only reviewer.'));
      assert(text.includes('Contract minimum is not current permission.'));
      const nodes = section.locator('.react-flow__node');
      await nodes.first().waitFor();
      assert.deepEqual(await nodes.evaluateAll(cards => cards.map(card => card.getAttribute('data-id'))),
        direct.computation.plan_view.logical_map.steps.map(step => step.step_id));
      const openRun = page.getByRole('button', {name: 'Open Run', exact: true});
      await openRun.click();
      assert.equal(await page.locator('textarea[name="ref"]').inputValue(), '');
      await page.getByRole('button', {name: 'Close dialog', exact: true}).click();
      assert.equal(await page.locator('input[name="bootstrap"]').count(), 0);
      ui.lastAction = 'explain through the installed Story renderer';
      const received = page.waitForResponse(response =>
        response.url() === connected.origin + '/api/read/static-explanation');
      await page.getByRole('button', {name: 'Explain', exact: true}).click();
      const response = await received;
      assert.equal(response.status(), 200, 'Installed Gateway must load the structural renderer');
      const packet = await response.json();
      assert(packet && typeof packet === 'object' && 'data' in packet);
      const explained = packet.data as StaticExplanationReadModel;
      assert.equal(explained.plan.logicalMapCid, direct.computation.plan_view.logical_map.self_cid);
      assert.equal(explained.plan.compiledPlanCid, direct.computation.plan_view.compiled_plan_cid);
      assert.equal(explained.plan.programDefinitionCid, direct.program_definition_cid);
      assert(explained.plan.effectful);
      assert.deepEqual(explained.plan.effectful.members, [expectedMember]);
      const declared = explained.context.find(item => item.origin.kind === 'effect_set');
      assert(declared?.origin.kind === 'effect_set');
      assert.deepEqual(declared.origin.members, [{declaration: expectedMember,
        write_fields: {state: 'declared', fields: ['Name']}}]);
      assert.equal(declared.origin.unit_id, direct.effect_set.unit_id);
      assert.match(declared.text, /Current decision unknown/u);
      assert.doesNotMatch(JSON.stringify(explained), /must-remain-unknown/u);
      await page.getByRole('region', {name: 'Original story', exact: true}).waitFor();
      const heading = (await page.getByRole('heading', {level: 1}).textContent()) ?? '';
      assert.match(heading, /Plan to update Test_Record__c in crm-main/u);
      assert.doesNotMatch(heading, /connector:\/\/|\baql_|Predicate form not projected/u);
      const effectCard = page.locator('.story-card').filter({
        has: page.locator('summary > strong').filter({hasText: /^Update Name on Test_Record__c$/u}),
      });
      await effectCard.locator('summary').first().click();
      await effectCard.getByText('Original Effect declarations', {exact: true}).click();
      assert.match(await effectCard.innerText(), /Fields: Name/u);
      assert.match(await effectCard.innerText(), /connector:\/\/crm-main\/Test_Record__c/u);
      assert.match(await effectCard.innerText(), /Current decision unknown/u);
      assert.deepEqual(browserPaths, ['/api/session', '/api/read/launch', '/api/read/plan', '/api/read/static-explanation']);
      assert.deepEqual(errors, []); assert.deepEqual(foreign, []);
      assert.deepEqual(await page.evaluate(() => ({local: Object.keys(localStorage), session: Object.keys(sessionStorage),
        cookie: document.cookie, query: location.search, hash: location.hash})), {local: [], session: [], cookie: '', query: '', hash: ''});
      await page.screenshot({path: join(evidence, 'installed-effectful-static-plan.png'), fullPage: true});
      receipt.cases.push({name: 'installed Local SDK/Gateway/built React checked update Plan and Story', passed: true,
        paths, browserPaths, member: expectedMember, sourceFreeValues: true, executionEdges: 0,
        permission: 'unknown', gate: 'unknown', approval: 'unknown', preview: 'unavailable'});
    } catch (error) {
      // innerText excludes password values and in-memory Gateway credentials.
      // Never record Playwright's raw call log, which can contain fill values.
      ui.visibleText = (await page.locator('body').innerText({timeout: 1000})).slice(0, 16384);
      await page.screenshot({path: join(evidence, 'failed-effectful-static-plan.png'), fullPage: true});
      throw error;
    } finally {await page.close();}
    const after = journalCounts(journal);
    assert.deepEqual(after, before); assert.equal(sends.length, baselineSends); assert.equal(secretCalls, baselineSecrets);
    receipt.journalCounts = {before, after}; receipt.ProviderIOWhilePlanning = 0;
    receipt.newRuns = 0; receipt.newSubmissions = 0; receipt.providerRequests = sends;
    receipt.complete = true;
  } catch (error) {
    const failure = error as Failure | null | undefined;
    receipt.failure = {phase, kind: failure?.code ?? failure?.name};
    if (failure?.primaryFailure) receipt.failure.primaryKind = failure.primaryFailure.code ?? failure.primaryFailure.name;
    if (failure?.cleanupHandle?.status) {
      const status = failure.cleanupHandle.status();
      receipt.initializationCleanup = {pending: status.pending, owners: status.owners};
    }
    primary = new Error(`Installed static Plan failed at ${phase}: ${receipt.failure.kind}`);
    throw primary;
  }
  finally {
    const failures = [];
    receipt.providerRequests = sends;
    receipt.totalSecretCalls = secretCalls;
    if (journalPath) {
      try {receipt.journalBeforeClose = journalCounts(journalPath);}
      catch (error) {receipt.complete = false; failures.push(error);}
    }
    const owners: [string, () => Promise<unknown> | undefined][] =
      [['Chromium', () => browser?.close()], ['Gateway', () => gateway?.close()],
      ['Local Client', () => client?.close()], ['metadata HTTPS fixture', async () => {
        const metadata = server;
        if (metadata) {
          metadata.closeAllConnections();
          await new Promise<void>((resolve, reject) => metadata.close(error => error ? reject(error) : resolve()));
        }
      }]];
    for (const [name, close] of owners) {
      try {await close(); receipt.cleanup.push({name, acknowledged: true});}
      catch (error) {receipt.complete = false; receipt.cleanup.push({name, acknowledged: false}); failures.push(error);}
    }
    await writeFile(join(evidence, 'installed-effectful-static-plan-receipt.json'), JSON.stringify(receipt, null, 2) + '\n', {flag: 'wx'});
    if (failures.length) {
      throw new AggregateError(primary ? [primary, ...failures] : failures, 'InstalledStaticPlanCleanupPending', {cause: primary});
    }
  }
});
