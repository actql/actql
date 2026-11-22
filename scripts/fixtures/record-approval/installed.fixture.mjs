// The ordinary runner requires a verified installation. Its product/runtime
// originals come from that installation; the shared TLS opener below is
// fixture-only and loads no Host, Common or installed product.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir, mkdtemp} from 'node:fs/promises';
import {isAbsolute, join} from 'node:path';
import {userInfo} from 'node:os';
import {fileURLToPath} from 'node:url';
import {generateKeyPairSync} from 'node:crypto';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {openHttpsExchangeFixture} from '../../../adapters/site-node/https-exchange-fixture.mjs';
import {recordApprovalFixtureResultNames, recordApprovalHostAccountConfiguration} from './host-account.fixture.mjs';
import {recordUpdateFixtureState, recordUpdateReplyLossFaults} from './cases.mjs';
import {readAuthoredCase} from './command.mjs';
import {recordApprovalReplyLossExpectation} from './workflow.mjs';
export {recordApprovalReplyLossExpectationFromEnvironment as installedRecordReplyLossExpectation} from './workflow.mjs';

export function installedRecordDecision(env = process.env) {
  const decision = env.ACTQL_RECORD_APPROVAL_DECISION ?? 'approved';
  assert(['approved', 'rejected'].includes(decision), 'Invalid installed record fixture decision');
  return decision;
}

export function installedRecordHttpCase(defaultCasePath, env = process.env) {
  const path = env.ACTQL_RECORD_APPROVAL_HTTP_CASE;
  assert(path === undefined || typeof path === 'string' && isAbsolute(path), 'Use an absolute authored HTTP case path');
  const wire = env.ACTQL_RECORD_APPROVAL_RESULT_NAMES;
  if (wire === undefined) return {casePath: path ?? defaultCasePath};
  assert(path !== undefined, 'Explicit fixture Result names require an authored HTTP case');
  try {
    assert(typeof wire === 'string' && wire.length <= 4096);
    return {casePath: path, authorizedResultNames: recordApprovalFixtureResultNames(JSON.parse(wire))};
  } catch {
    throw new TypeError('InvalidRecordApprovalFixtureResultNames');
  }
}

const execute = promisify(execFile);
const pem = key => key.export({format: 'pem', type: key.type === 'private' ? 'pkcs8' : 'spki'});
const safe = error => ({name: error?.name, code: error?.code, message: error?.message});
const privateFile = {mode: 0o600, flag: 'wx'};

// Same existing transport/fault seam for the ordinary harness and direct TLS
// protocol controls. This helper never classifies a public Run outcome.
export function openRecordApprovalExchange(t, fixture) {
  return openHttpsExchangeFixture(t, {routes: fixture.provider.routes, faults: fixture.faults ?? []});
}

export function assertRecordApprovalTarget(snapshot, expected) {
  const target = snapshot.target === null ? null : {id: snapshot.target.id, name: snapshot.target.name};
  assert.deepEqual(target, expected.target, 'Independent provider target state');
}

function assertRecordApprovalControl(snapshot, expected) {
  const {id, name} = snapshot.control;
  assert.deepEqual({id, name}, expected.control, 'Independent provider control state');
}

export function assertRecordApprovalSourceSchema(view, expected) {
  const observed = {sourceRef: view.source_ref, sourceViewContractCid: view.source_view_contract_cid,
    carrierSchemaContractCid: view.carrier_schema_contract_cid};
  assert.deepEqual(observed, expected, 'Independent provider Source View and schema');
  return observed;
}

export async function runInstalledRecordApprovalFixture(t, input) {
  const authored = input.casePath === undefined ? undefined : await readAuthoredCase(input.casePath);
  const authoredFixture = authored?.fixture;
  let fixture = input;
  if (authoredFixture !== undefined) {
    assert.equal(typeof input.createInstallation, 'function', 'Select an original provider fixture adapter');
    assert(input.selection === undefined && input.provider === undefined, 'Select one original provider seed');
    const kind = authored.review.kind ?? 'update';
    fixture = {...input, ...input.createInstallation(authoredFixture.seed, kind)};
    assert.equal(fixture.write?.kind ?? 'update', kind, 'The provider admits the original authored effect kind');
  }
  const {connectorId, resource, alias, selection, provider, decision = 'approved'} = fixture;
  assert(['approved', 'rejected'].includes(decision));
  const rejecting = decision === 'rejected';
  const expected = authoredFixture?.expected ?? recordUpdateFixtureState(selection);
  if (authoredFixture !== undefined) {
    const original = provider.snapshot();
    assertRecordApprovalTarget(original, expected.before);
    assertRecordApprovalControl(original, expected.before);
  }
  const faults = authoredFixture?.faults;
  if (faults !== undefined) {
    assert(fixture.replyLossExpectation === undefined && fixture.faults === undefined, 'Select one original fixture fault schedule');
  }
  const loss = recordApprovalReplyLossExpectation(faults === undefined ? fixture.replyLossExpectation : faults[0]?.expected);
  assert(!rejecting || (loss === undefined && fixture.faults === undefined), 'The rejection case selects only the ordinary provider');
  if (loss !== undefined) assert.equal(fixture.faults, undefined, 'Select one original reply-loss fault only');
  assert.equal(process.env.ACTQL_TEST_PRESERVE_SCRATCH, '1', 'Preserve original state on every outcome');
  const parent = join(process.cwd(), connectorId + '-approval-original-roots');
  await mkdir(parent, {recursive: true});
  const root = await mkdtemp(join(parent, 'approval-'));
  const stateRoot = join(root, 'host'), credentialRoot = join(root, 'credentials');
  await mkdir(join(root, 'home'));
  t.diagnostic(`Retained ${connectorId} approval original root: ${root}`);
  const phases = [], cleanup = [], parentState = {};
  let tls, declared, services, parentPending = false, parentClosed = false, failed = false, primary;
  let fixtureSourceSchema;
  let closeParent = async () => {};
  const local = new URL('./', import.meta.resolve('@actql/local-node'));
  const load = path => import(new URL(path, local));
  try {
    tls = await openRecordApprovalExchange(undefined, loss === undefined ? fixture
      : {...fixture, faults: recordUpdateReplyLossFaults(provider)});
    const common = await load('_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js');
    const {loadInstalledSource} = await load('adapters/host-node/installed-source.mjs');
    const {canonicalJson} = await load('adapters/host-node/local-account-config.mjs');
    const {openHostInitializationPreparation, closeHostInitializationPreparation} =
      await load('adapters/local-node/request-preparation-adapter.mjs');
    const {createInstalledHostServices, retireInstalledSourceInitialization, closeInstalledAccountConstruction} =
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
    // The fixture owner selects the allowed Results separately from any case.
    // Both original Account consumers receive the same complete identity.
    const fullAccount = recordApprovalHostAccountConfiguration(
      canonicalJson, providerAccount, principal, 'row-source-acquired', fixture.authorizedResultNames);
    const profile = {...fixture.source, version: `actql-installed-${connectorId}-source/0.1`,
      connectorId, metadataPath, siteProfilePath, accountConfigurationWire: fullAccount};
    await writeFile(sourceProfilePath, JSON.stringify(profile), privateFile);
    const assertCurrent = () => assert.equal(parentClosed, false);
    const initialPreparation = openHostInitializationPreparation(parentState, common,
      Object.freeze({root, purpose: 'original installed record approval schema bootstrap'}), assertCurrent, () => parentPending);
    services = createInstalledHostServices({root, principalId: principal, moon: common, initialPreparation, assertCurrent, accountCurrent: assertCurrent});
    parentPending = true;
    closeParent = async () => {
      if (parentClosed) return;
      assert.equal(await closeInstalledAccountConstruction(services), true,
        'Original Account reads must close before Source retirement');
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
    if (authoredFixture?.schema !== undefined) fixtureSourceSchema = assertRecordApprovalSourceSchema(view, authoredFixture.schema);
    await declared.close(); declared = undefined;
    await closeParent();
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
    const casePath = 'case.json';
    if (authored !== undefined) await writeFile(join(root, casePath), JSON.stringify(authored), privateFile);
    await writeFile(configuration, JSON.stringify({connect: {mode: 'local', installation: {directory: stateRoot,
      sourceProfilePath, effectProfilePath, authorization}},
      ...(authored === undefined ? {selection} : {casePath}), operatorModulePath: 'operator.mjs',
      ...(rejecting ? {decision} : {}),
      signer: {keyId: 'reviewer', reviewerId: 'reviewer', privateKeyPath: 'reviewer.key'}}), privateFile);
    await writeFile(join(root, 'operator.mjs'),
      "export const configureConnection = options => ({...options, installation: {...options.installation,\n" +
      "  resolveSourceSecret: () => 'loopback-only-record-approval-token', resolveEffectSecret: () => 'loopback-only-record-approval-token'}});\n",
      privateFile);
    const env = {...process.env, HOME: join(root, 'home'), NODE_OPTIONS: '', NODE_PATH: ''};
    for (const key of ['ACTQL_LOCAL_SOURCE_PROFILE', 'ACTQL_LOCAL_EFFECT_PROFILE',
      'ACTQL_RECORD_APPROVAL_DECISION']) delete env[key];
    delete env.ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION;
    delete env.ACTQL_RECORD_APPROVAL_SOURCE_SCHEMA;
    if (loss !== undefined) env.ACTQL_RECORD_APPROVAL_REPLY_LOSS_EXPECTATION = JSON.stringify(loss);
    if (fixtureSourceSchema !== undefined) env.ACTQL_RECORD_APPROVAL_SOURCE_SCHEMA = JSON.stringify(fixtureSourceSchema);
    for (const phase of ['capture', rejecting ? 'reject' : 'approve', 'recover']) {
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
      assert.equal(outcome.decision, rejecting ? decision : undefined);
      assert.deepEqual(outcome.replyLossExpectation, loss, 'The child retains the exact selected fixture expectation');
      assert.equal(outcome.publicClientClose, 'returned');
      assert.deepEqual(outcome.descriptors.before.openPaths, []);
      assert.deepEqual(outcome.descriptors.after.openPaths, []);
      const after = provider.snapshot();
      assert.deepEqual(after.control, before.control);
      const writesExpected = rejecting || phase === 'capture' ? 0 : 1;
      assert.equal(after.writes, writesExpected);
      const expectedState = writesExpected === 0 ? expected.before : expected.after;
      assertRecordApprovalTarget(after, expectedState);
      assertRecordApprovalControl(after, expectedState);
      if (rejecting) assert.deepEqual(after.target, before.target, 'A rejected checkpoint preserves the entire target and revision');
      if (phase === 'recover' && loss === undefined) assert.equal(after.requests.length, before.requests.length,
        'Saved first sends no provider request');
      if (loss !== undefined) {
        assert.equal(tls.remainingFaults(), phase === 'capture' ? 1 : 0);
      }
      const {method, pathname, methodOverride, bodyIncludes} = provider.writeRequest;
      const writeCount = tls.seen().filter(request => request.method === method && request.pathname === pathname &&
        (methodOverride === undefined || (request.headers['x-http-method-override'] ?? null) === methodOverride) &&
        (bodyIncludes === undefined || request.body.includes(bodyIncludes))).length;
      assert.equal(writeCount, writesExpected, 'Count every selected write request, including refused attempts');
      phases.push({phase, startedAt, endedAt: new Date().toISOString(), ...outcome,
        requestsBefore: before.requests.length, requestsAfter: after.requests.length, writes: after.writes});
    }
  } catch (error) {failed = true; primary = error;}
  finally {
    if (declared) try {await declared.close();} catch (error) {cleanup.push(error);}
    if (services && !parentClosed) try {await closeParent();} catch (error) {cleanup.push(error);}
    if (tls) try {await tls.close();} catch (error) {cleanup.push(error);}
    const snapshot = provider.snapshot();
    const summary = {qualification: rejecting
      ? 'Owned TLS rejection: one original resolution, unchanged provider state and separate-process lookup'
      : loss === undefined
      ? 'Owned TLS functional consumer of the selected installed cohort; no real provider authentication, performance or physical cleanup ACK claim'
      : 'Owned TLS applied-write reply-loss consumer: original public outcome and separate-process same-Run lookup only; expected Unknown is not success, Result, physical stop or cleanup ACK',
      ...(rejecting ? {decision} : {}),
      ...(loss === undefined ? {} : {replyLossExpectation: loss, remainingFaults: tls?.remainingFaults()}),
      passed: !failed && cleanup.length === 0 && snapshot.failures.length === 0, phases, provider: snapshot,
      publicFailure: failed ? safe(primary) : null, cleanup: cleanup.map(safe), bootstrapClosed: parentClosed};
    await writeFile(join(root, 'summary.json'), JSON.stringify(summary, null, 2) + '\n', privateFile);
  }
  if (failed && cleanup.length) throw new AggregateError([primary, ...cleanup],
    'RecordApprovalFixtureCleanupUnconfirmed', {cause: primary});
  if (failed) throw primary;
  assert.deepEqual(cleanup, [], 'Original fixture cleanup remains owned');
  assert.deepEqual(provider.snapshot().failures, [], 'No rejected provider route may be hidden by later success');
}
