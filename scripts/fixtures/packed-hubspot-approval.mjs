// Run only inside a verified ordinary installation. Product implementations
// and private bootstrap brands come from that same installed Local runtime.
import assert from 'node:assert/strict';
import test from 'node:test';
import {readFile, writeFile, mkdir, mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {fileURLToPath} from 'node:url';
import {generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {openHttpsExchangeFixture} from '../../adapters/site-node/https-exchange-fixture.mjs';
import {hubspotApprovalProvider} from './hubspot-approval/provider.mjs';
import {recordApprovalHostAccountConfiguration} from './record-approval/host-account.fixture.mjs';

const execute = promisify(execFile);
const pem = key => key.export({format: 'pem', type: key.type === 'private' ? 'pkcs8' : 'spki'});
const safe = error => ({name: error?.name, code: error?.code, message: error?.message});
const privateFile = {mode: 0o600, flag: 'wx'};

test('ordinary installed HubSpot reviews, approves once and reads original Saved before status',
  {timeout: 100000}, async t => {
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1', 'Preserve original state on every outcome');
  const parent = join(process.cwd(), 'hubspot-approval-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const stateRoot = join(root, 'host'), credentialRoot = join(root, 'credentials');
  await mkdir(join(root, 'home'));
  t.diagnostic(`Retained HubSpot approval original root: ${root}`);
  const selection = {recordId: '9007199254740993', controlId: '9007199254740994',
    previousName: 'Before HubSpot approval', nextName: 'After HubSpot approval'};
  const provider = hubspotApprovalProvider(selection), phases = [], cleanup = [], parentState = {};
  let tls, declared, services, parentPending = false, parentClosed = false, failed = false, primary;
  let closeParent = () => {};
  const local = new URL('./', import.meta.resolve('@actql/local-node'));
  const load = path => import(new URL(path, local));
  try {
    tls = await openHttpsExchangeFixture(undefined, {routes: provider.routes});
    const common = await load('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
    const {loadInstalledSource} = await load('adapters/host-node/installed-source.mjs');
    const {canonicalJson} = await load('adapters/host-node/local-account-config.mjs');
    const {openHostInitializationPreparation, closeHostInitializationPreparation} =
      await load('adapters/local-node/request-preparation-adapter.mjs');
    const {createInstalledHostServices, retireInstalledSourceInitialization} =
      await load('adapters/host-node/installed-host-services.mjs');
    const credential = generateKeyPairSync('ed25519'), reviewer = generateKeyPairSync('ed25519');
    const host = generateKeyPairSync('ed25519'), principal = userInfo().username;
    await writeFile(join(root, 'credential.key'), pem(credential.privateKey), privateFile);
    await writeFile(join(root, 'reviewer.key'), pem(reviewer.privateKey), privateFile);
    const siteProfilePath = join(root, 'site.json'), metadataPath = join(root, 'metadata.json');
    const sourceProfilePath = join(root, 'source.json'), effectProfilePath = join(root, 'effect.json');
    const site = {version: 'actql-installed-hubspot-site/0.1', apiOrigin: tls.origin,
      credentialAuthorityId: 'hubspot-tls-fixture', credentialKeyId: 'key',
      credentialPrivateKeyPath: join(root, 'credential.key'), environment: 'test', journalRoot: credentialRoot,
      namespaceId: 'hubspot-tls-fixture', siteGeneration: 1, siteKey: 'hubspot-tls-fixture',
      tokenEnvironment: 'ACTQL_HUBSPOT_TLS_FIXTURE_TOKEN', caPath: tls.caPath};
    await writeFile(siteProfilePath, JSON.stringify(site), privateFile);
    await writeFile(metadataPath, JSON.stringify({version: 'actql-hubspot-read-metadata/0.1',
      connectorId: 'hubspot', portalId: '7', apiOrigin: tls.origin,
      accountBody: Buffer.from(JSON.stringify(provider.account)).toString('base64'),
      objects: [{resource: 'companies', objectType: 'companies',
        propertiesBody: Buffer.from(JSON.stringify(provider.properties)).toString('base64')}]}), privateFile);
    const entries = [
      {entry_id: 'effect', outcome: 'delegate', principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
        resource: {any_of: ['companies']}, operation: {any_of: ['effect']}, exclusions: []},
      {entry_id: 'read', outcome: 'allow', principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'write', outcome: 'allow', principal: {all: true}, connection: {any_of: ['hubspot:hubspot']},
        resource: {any_of: ['companies']}, operation: {any_of: ['write']}, exclusions: []},
    ];
    const providerAccount = canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: 'hubspot-approval-fixture', entries});
    // One complete identity is passed to both original Account consumers.
    const fullAccount = recordApprovalHostAccountConfiguration(
      canonicalJson, providerAccount, principal, 'row-source-acquired');
    const profile = {version: 'actql-installed-hubspot-source/0.1', connectorId: 'hubspot', portalId: '7',
      resources: [{resource: 'companies', objectType: 'companies'}], metadataPath, siteProfilePath,
      metadataResources: {account: 'account', properties: 'properties'}, accountConfigurationWire: fullAccount,
      limits: {maxResponseBytes: 16384, maxNodes: 8000, maxDepth: 32, maxProperties: 16,
        maxNameUnits: 512, maxPages: 2, maxRows: 4, maxRequests: 6, perPage: 2,
        maxColumns: 3, maxCursorUnits: 128, maxValueNodes: 8000, maxValueTextBytes: 16384,
        maxRowsWireBytes: 16384, maxRowsWireNodes: 8000, maxRowsWireDepth: 32,
        maxObjects: 2, maxDeclarationBytes: 65536, maxDeclarationNodes: 8000, maxSecretBytes: 128}};
    await writeFile(sourceProfilePath, JSON.stringify(profile), privateFile);
    const assertCurrent = () => assert.equal(parentClosed, false);
    const initialPreparation = openHostInitializationPreparation(parentState, common,
      Object.freeze({root, purpose: 'original installed HubSpot schema bootstrap'}), assertCurrent, () => parentPending);
    services = createInstalledHostServices({root, principalId: principal, moon: common, initialPreparation, assertCurrent});
    parentPending = true;
    closeParent = () => {
      if (parentClosed) return;
      assert.equal(retireInstalledSourceInitialization(services), true);
      parentPending = false;
      closeHostInitializationPreparation(parentState);
      parentClosed = true;
    };
    let resolutions = 0;
    declared = await loadInstalledSource(sourceProfilePath, {root, principalId: principal, moon: common,
      runtimeUrl: new URL('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js', local),
      baseEnvironmentWire: await readFile(new URL('spec/local-check-environment.json', local), 'utf8'),
      resolveSecret: () => {resolutions++; return 'loopback-only-hubspot-token';}, installationServices: services});
    const environment = JSON.parse(declared.environmentWire);
    const view = environment.schema_snapshots.find(value => value.source_ref === declared.sourceReadAccesses[0].sourceRef);
    assert(view);
    assert.equal(declared.realizationKey, 'row-source-acquired');
    assert.equal(tls.seen().length, 0);
    assert.equal(resolutions, 0);
    await declared.close(); declared = undefined;
    closeParent();
    await writeFile(sourceProfilePath, JSON.stringify({...profile, queryAliases: [{name: 'hubspot.companies',
      sourceRef: view.source_ref, sourceViewContractCid: view.source_view_contract_cid,
      schemaContractCid: view.carrier_schema_contract_cid}]}));
    await writeFile(effectProfilePath, JSON.stringify({version: 'actql-installed-hubspot-effect/0.1',
      connectorId: 'hubspot', sourceProfilePath, writes: [{resource: 'companies', fields: ['name'],
        markerProperty: 'actql_request_id'}], queryUpdateTargets: [{name: 'hubspot.companies',
        targetRef: 'connector://hubspot/companies'}]}), privateFile);
    const authorization = {accountConfiguration: fullAccount,
      hostKey: {keyId: 'host', privateKey: pem(host.privateKey)},
      reviewers: [{keyId: 'reviewer', reviewerId: 'reviewer', principalId: principal,
        publicKey: pem(reviewer.publicKey)}], reviewReaders: [principal], leaseMs: 10000};
    const configuration = join(root, 'configuration.json');
    await writeFile(configuration, JSON.stringify({connect: {mode: 'local', installation: {directory: stateRoot,
      sourceProfilePath, effectProfilePath, authorization}}, selection, operatorModulePath: 'operator.mjs',
      signer: {keyId: 'reviewer', reviewerId: 'reviewer', privateKeyPath: 'reviewer.key'}}), privateFile);
    await writeFile(join(root, 'operator.mjs'),
      "export const configureConnection = options => ({...options, installation: {...options.installation,\n" +
      "  resolveSourceSecret: () => 'loopback-only-hubspot-token', resolveEffectSecret: () => 'loopback-only-hubspot-token'}});\n",
      privateFile);
    const env = {...process.env, HOME: join(root, 'home'), NODE_OPTIONS: '', NODE_PATH: ''};
    for (const key of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[key];
    for (const phase of ['capture', 'approve', 'recover']) {
      const before = provider.snapshot(), startedAt = new Date().toISOString();
      const args = [fileURLToPath(new URL('./hubspot-approval/installed-child.mjs', import.meta.url)),
        phase, configuration, join(root, 'receipt'), stateRoot, credentialRoot];
      let result;
      try {
        result = await execute(process.execPath, args,
          {cwd: process.cwd(), env, encoding: 'utf8', timeout: 30000, maxBuffer: 8 * 1024 ** 2});
      } catch (error) {
        await writeFile(join(root, phase + '.stdout'), error.stdout ?? '', privateFile);
        await writeFile(join(root, phase + '.stderr'), error.stderr ?? '', privateFile);
        throw error;
      }
      await writeFile(join(root, phase + '.stdout'), result.stdout, privateFile);
      await writeFile(join(root, phase + '.stderr'), result.stderr, privateFile);
      const outcome = JSON.parse(result.stdout);
      assert.equal(outcome.status, 'passed');
      assert.equal(outcome.publicClientClose, 'returned');
      assert.deepEqual(outcome.descriptors.before.openPaths, []);
      assert.deepEqual(outcome.descriptors.after.openPaths, []);
      const after = provider.snapshot();
      assert.deepEqual(after.control, before.control);
      assert.equal(after.writes, phase === 'capture' ? 0 : 1);
      assert.equal(after.target.name, phase === 'capture' ? selection.previousName : selection.nextName);
      if (phase === 'recover') assert.equal(after.requests.length, before.requests.length,
        'Saved first sends no provider request');
      phases.push({phase, startedAt, endedAt: new Date().toISOString(), ...outcome,
        requestsBefore: before.requests.length, requestsAfter: after.requests.length, writes: after.writes});
    }
  } catch (error) {failed = true; primary = error;}
  finally {
    if (declared) try {await declared.close();} catch (error) {cleanup.push(error);}
    if (services && !parentClosed) try {closeParent();} catch (error) {cleanup.push(error);}
    if (tls) try {await tls.close();} catch (error) {cleanup.push(error);}
    const snapshot = provider.snapshot();
    const summary = {qualification: 'Owned TLS functional consumer of the selected installed cohort; no real HubSpot, performance or physical cleanup ACK claim',
      passed: !failed && cleanup.length === 0, phases, provider: snapshot,
      publicFailure: failed ? safe(primary) : null, cleanup: cleanup.map(safe), bootstrapClosed: parentClosed};
    await writeFile(join(root, 'summary.json'), JSON.stringify(summary, null, 2) + '\n', privateFile);
  }
  if (failed && cleanup.length) throw new AggregateError([primary, ...cleanup],
    'HubSpotApprovalFixtureCleanupUnconfirmed', {cause: primary});
  if (failed) throw primary;
  assert.deepEqual(cleanup, [], 'Original fixture cleanup remains owned');
});
