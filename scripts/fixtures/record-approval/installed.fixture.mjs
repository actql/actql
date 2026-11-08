// Run only inside a verified ordinary installation. Product implementations
// and private bootstrap brands come from that same installed Local runtime.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir, mkdtemp} from 'node:fs/promises';
import {join} from 'node:path';
import {userInfo} from 'node:os';
import {fileURLToPath} from 'node:url';
import {generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {openHttpsExchangeFixture} from '../../../adapters/site-node/https-exchange-fixture.mjs';
import {recordApprovalHostAccountConfiguration} from './host-account.fixture.mjs';

const execute = promisify(execFile);
const pem = key => key.export({format: 'pem', type: key.type === 'private' ? 'pkcs8' : 'spki'});
const safe = error => ({name: error?.name, code: error?.code, message: error?.message});
const privateFile = {mode: 0o600, flag: 'wx'};

export async function runInstalledRecordApprovalFixture(t, fixture) {
  const {connectorId, resource, alias, selection, provider} = fixture;
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1', 'Preserve original state on every outcome');
  const parent = join(process.cwd(), connectorId + '-approval-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const stateRoot = join(root, 'host'), credentialRoot = join(root, 'credentials');
  await mkdir(join(root, 'home'));
  t.diagnostic(`Retained ${connectorId} approval original root: ${root}`);
  const phases = [], cleanup = [], parentState = {};
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
    const site = {version: `actql-installed-${connectorId}-site/0.1`, apiOrigin: tls.origin,
      credentialAuthorityId: connectorId + '-tls-fixture', credentialKeyId: 'key',
      credentialPrivateKeyPath: join(root, 'credential.key'), environment: 'test', journalRoot: credentialRoot,
      namespaceId: connectorId + '-tls-fixture', siteGeneration: 1, siteKey: connectorId + '-tls-fixture',
      tokenEnvironment: 'ACTQL_RECORD_APPROVAL_TLS_FIXTURE_TOKEN', caPath: tls.caPath};
    await writeFile(siteProfilePath, JSON.stringify(site), privateFile);
    await writeFile(metadataPath, JSON.stringify({...fixture.metadata, connectorId, apiOrigin: tls.origin}), privateFile);
    const entries = [
      {entry_id: 'effect', outcome: 'delegate', principal: {all: true}, connection: {any_of: [connectorId + ':' + connectorId]},
        resource: {any_of: [resource]}, operation: {any_of: ['effect']}, exclusions: []},
      {entry_id: 'read', outcome: 'allow', principal: {all: true}, connection: {any_of: [connectorId + ':' + connectorId]},
        resource: {all: true}, operation: {any_of: ['read']}, exclusions: []},
      {entry_id: 'write', outcome: 'allow', principal: {all: true}, connection: {any_of: [connectorId + ':' + connectorId]},
        resource: {any_of: [resource]}, operation: {any_of: ['write']}, exclusions: []},
    ];
    const providerAccount = canonicalJson({version: 'actql-execution-account-config/0.1',
      account_id: connectorId + '-approval-fixture', entries});
    // One complete identity is passed to both original Account consumers.
    const fullAccount = recordApprovalHostAccountConfiguration(
      canonicalJson, providerAccount, principal, 'row-source-acquired');
    const profile = {...fixture.source, version: `actql-installed-${connectorId}-source/0.1`,
      connectorId, metadataPath, siteProfilePath, accountConfigurationWire: fullAccount};
    await writeFile(sourceProfilePath, JSON.stringify(profile), privateFile);
    const assertCurrent = () => assert.equal(parentClosed, false);
    const initialPreparation = openHostInitializationPreparation(parentState, common,
      Object.freeze({root, purpose: 'original installed record approval schema bootstrap'}), assertCurrent, () => parentPending);
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
      resolveSecret: () => {resolutions++; return 'loopback-only-record-approval-token';}, installationServices: services});
    const environment = JSON.parse(declared.environmentWire);
    const view = environment.schema_snapshots.find(value => value.source_ref === declared.sourceReadAccesses[0].sourceRef);
    assert(view);
    assert.equal(declared.realizationKey, 'row-source-acquired');
    assert.equal(tls.seen().length, 0);
    assert.equal(resolutions, 0);
    await declared.close(); declared = undefined;
    closeParent();
    await writeFile(sourceProfilePath, JSON.stringify({...profile, queryAliases: [{name: alias,
      sourceRef: view.source_ref, sourceViewContractCid: view.source_view_contract_cid,
      schemaContractCid: view.carrier_schema_contract_cid}]}));
    await writeFile(effectProfilePath, JSON.stringify({version: `actql-installed-${connectorId}-effect/0.1`,
      connectorId, sourceProfilePath, writes: [fixture.write],
      queryUpdateTargets: [{name: alias, targetRef: `connector://${connectorId}/${resource}`}]}), privateFile);
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
      "  resolveSourceSecret: () => 'loopback-only-record-approval-token', resolveEffectSecret: () => 'loopback-only-record-approval-token'}});\n",
      privateFile);
    const env = {...process.env, HOME: join(root, 'home'), NODE_OPTIONS: '', NODE_PATH: ''};
    for (const key of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE']) delete env[key];
    for (const phase of ['capture', 'approve', 'recover']) {
      const before = provider.snapshot(), startedAt = new Date().toISOString();
      const args = [fileURLToPath(new URL('./installed-child.mjs', import.meta.url)),
        connectorId, phase, configuration, join(root, 'receipt'), stateRoot, credentialRoot];
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
    const summary = {qualification: 'Owned TLS functional consumer of the selected installed cohort; no real provider authentication, performance or physical cleanup ACK claim',
      passed: !failed && cleanup.length === 0, phases, provider: snapshot,
      publicFailure: failed ? safe(primary) : null, cleanup: cleanup.map(safe), bootstrapClosed: parentClosed};
    await writeFile(join(root, 'summary.json'), JSON.stringify(summary, null, 2) + '\n', privateFile);
  }
  if (failed && cleanup.length) throw new AggregateError([primary, ...cleanup],
    'RecordApprovalFixtureCleanupUnconfirmed', {cause: primary});
  if (failed) throw primary;
  assert.deepEqual(cleanup, [], 'Original fixture cleanup remains owned');
}
