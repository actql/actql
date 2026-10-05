// Real-process acceptance for the outbound-only resident Site: a native
// control process polls a bearer-authenticated outbound gateway (standing in
// for the Cloud), admits a source-free Values Run from typed run materials,
// and runs it in a separate executor holder. The executor entry count is
// read from a synced evidence file, never from transport logs.
import assert from 'node:assert/strict';
import test from 'node:test';
import {execFileSync, spawn} from 'node:child_process';
import {createHash, generateKeyPairSync, X509Certificate} from 'node:crypto';
import {once} from 'node:events';
import {request as httpsRequest} from 'node:https';
import {chmod, mkdir, mkdtemp, open, readdir, readFile, rm, rmdir, stat, writeFile} from
  'node:fs/promises';
import {existsSync} from 'node:fs';
import {createServer} from 'node:net';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {createRequire} from 'node:module';
import {residentSourceEnvironment, sourceProgram, sourceRows,
  sourceRef, sourceContractCid, retainedSourceProgram, retainedSourceRows,
  retainedSourceSchemaCid} from './fixtures/resident-source.mjs';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from
  '../adapters/host-node/client-program-preparation.mjs';
import {startHttpsOutboundSiteGateway} from
  '../adapters/host-node/outbound-site-gateway.mjs';
import {openSqliteCoordinatorDispatchJournal} from
  '../adapters/host-node/sqlite-coordinator-journal.mjs';
import {createRemoteSiteCoordinator} from
  '../adapters/host-node/remote-site-coordinator.mjs';
import {allowAllAuthorization} from '../adapters/host-node/authorization-fixture.mjs';
import {observationAckLossProxy} from './fixtures/observation-ack-loss-proxy.mjs';
import {signRemoteRuntimeBundle} from
  '../adapters/site-node/remote-bundle-signature.mjs';
import {pinnedEngineContracts} from
  '../adapters/connectors/duckdb/node/test/pinned-engine-contracts.mjs';
import {startHttpsDirectTransferReceiver} from
  '../adapters/site-node/https-direct-transfer.mjs';
import {openSqliteTransferJournal} from
  '../adapters/site-node/sqlite-transfer-journal.mjs';
import {createLocalRetainedStore} from '../adapters/store-local/files.mjs';

const repository = fileURLToPath(new URL('../', import.meta.url));
const retainedConsumerMode = process.argv.includes('--retained-consumer-only') ||
  process.env.ACTQL_TEST_RESIDENT_RETAINED_CONSUMER_ONLY === '1';
const retainedCoordinatorReconstruction =
  process.env.ACTQL_TEST_RESIDENT_RETAINED_COORDINATOR_RECONSTRUCTION === '1';
const retainedCancelBeforeConsumer =
  process.env.ACTQL_TEST_RESIDENT_RETAINED_CANCEL_BEFORE_CONSUMER === '1';
if ((retainedCoordinatorReconstruction || retainedCancelBeforeConsumer) && !retainedConsumerMode) {
  throw new Error('retained fault selection requires the retained consumer case');
}
const sourceMode = process.argv.includes('--source-only') || retainedConsumerMode;
const cancelMode = process.argv.includes('--cancel-only') ||
  process.env.ACTQL_TEST_RESIDENT_CANCEL_ONLY === '1';
const releaseMaintenanceMode = process.argv.includes('--release-maintenance-only') ||
  process.env.ACTQL_TEST_RESIDENT_RELEASE_MAINTENANCE_ONLY === '1';
const scratchRoot = process.env.ACTQL_TEST_SCRATCH_ROOT;
if (typeof scratchRoot !== 'string' || scratchRoot.length === 0) {
  throw new Error('ACTQL_TEST_SCRATCH_ROOT is required');
}
await mkdir(scratchRoot, {recursive: true});
const root = await mkdtemp(join(scratchRoot, 'native-resident-site-'));
const moon = join(process.env.MOON_HOME ?? '', 'bin', 'moon');
const sqliteLibrary = process.env.ACTQL_TEST_NATIVE_SQLITE_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libsqlite3.dylib'
    : 'libsqlite3.so.0');
const httpLibrary = process.env.ACTQL_TEST_NATIVE_HTTP_LIBRARY ??
  (process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib'
    : 'libcurl.so.4');
const cryptoLibrary = process.env.ACTQL_TEST_NATIVE_CRYPTO_LIBRARY ??
  (process.platform === 'darwin'
    ? ['/opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib',
      '/usr/local/opt/openssl@3/lib/libcrypto.3.dylib']
      .find(path => existsSync(path)) ?? 'libcrypto.3.dylib'
    : 'libcrypto.so.3');
const targetTriple = process.platform === 'darwin' && process.arch === 'arm64'
  ? 'aarch64-apple-darwin'
  : process.platform === 'linux' && process.arch === 'x64'
    ? 'x86_64-unknown-linux-gnu'
    : undefined;
if (targetTriple === undefined) {
  throw new Error(
    `unsupported native resident Site test target ${process.platform}/${process.arch}`);
}
const physicalCid = value =>
  `sha256:${createHash('sha256').update(value).digest('hex')}`;
const coordinatorAuthority = sourceMode ? physicalCid('resident-source-authority')
  : 'cloud-coordinator';
const openssl = (...args) =>
  execFileSync('openssl', args, {cwd: root, stdio: 'ignore'});

let gateway;
let receiver;
let receiverStore;
let receiverJournal;
let currentSite;
let observationStore;
let observationReceiver;
let ackLossProxy;
let crashOutputReceiver;
const observationBodies = [];
const observationFailures = [];
// A test projection through the existing durable Coordinator owner, using
// only real reports after the SQLite receiver has confirmed their custody.
// It is not another production ledger or independent execution authority.
const retainedCoordinatorRecords = new Map();
const running = new Set();
async function runAcceptance() {
try {
  // Build the resident Site and the portable owners the test drives.
  execFileSync(moon, ['build', '--target', 'native', '--strip',
    'src/cmd/native_remote_resident_site', 'src/cmd/native_runtime_bundle'],
  {cwd: repository, stdio: 'inherit'});
  execFileSync(moon, ['build', '--target', 'js', '--release',
    'src/connectors_builtin_node'], {cwd: repository, stdio: 'inherit'});
  execFileSync(process.execPath, ['scripts/build-runtime-packages.mjs',
    'coordinator-core', 'run-host-core', ...(retainedConsumerMode ? ['transfer-core'] : [])],
  {cwd: repository, stdio: 'inherit'});
  const executable = join(repository, '_build/native/debug/build/cmd/' +
    'native_remote_resident_site/native_remote_resident_site.exe');
  const bundleTool = join(repository, '_build/native/debug/build/cmd/' +
    'native_runtime_bundle/native_runtime_bundle.exe');
  const moonModule = await import(pathToFileURL(join(repository,
    '_build/js/release/build/connectors_builtin_node/' +
    'connectors_builtin_node.js')).href);
  const coordinator = await import(pathToFileURL(
    process.env.ACTQL_TEST_COORDINATOR_CORE_MODULE ?? join(repository,
      'packages/coordinator-core/index.mjs')).href);
  const runHost = await import(pathToFileURL(
    process.env.ACTQL_TEST_RUN_HOST_CORE_MODULE ??
      join(repository, 'packages/run-host-core/index.mjs')).href);
  const portable = runtimeCore(moonModule);
  const siteControl = portable.remoteSiteControl;

  // Server TLS only; the Site authenticates with a bearer credential.
  openssl('genrsa', '-out', 'ca.key', '2048');
  openssl('req', '-x509', '-new', '-key', 'ca.key', '-out', 'ca.crt',
    '-subj', '/CN=ActQL Resident Test CA', '-days', '1');
  await writeFile(join(root, 'server.ext'),
    'subjectAltName=DNS:localhost,IP:127.0.0.1\nextendedKeyUsage=serverAuth\n');
  openssl('genrsa', '-out', 'server.key', '2048');
  openssl('req', '-new', '-key', 'server.key', '-out', 'server.csr',
    '-subj', '/CN=localhost');
  openssl('x509', '-req', '-in', 'server.csr', '-CA', 'ca.crt', '-CAkey',
    'ca.key', '-CAcreateserial', '-out', 'server.crt', '-days', '1',
    '-extfile', 'server.ext');
  // The Site sends Results with its own transfer credential (mTLS here).
  await writeFile(join(root, 'client.ext'), 'extendedKeyUsage=clientAuth\n');
  openssl('genrsa', '-out', 'transfer.key', '2048');
  openssl('req', '-new', '-key', 'transfer.key', '-out', 'transfer.csr',
    '-subj', '/CN=resident-site-transfer');
  openssl('x509', '-req', '-in', 'transfer.csr', '-CA', 'ca.crt', '-CAkey',
    'ca.key', '-CAcreateserial', '-out', 'transfer.crt', '-days', '1',
    '-extfile', 'client.ext');
  const token = 'resident-site-credential-a';
  const tokenFile = join(root, 'control.token');
  await writeFile(tokenFile, `${token}\n`, {mode: 0o600});
  await chmod(tokenFile, 0o600);
  const siteKey = 'resident-site';
  const durableObservationMode = process.argv.includes('--observation-replay-only') ||
    process.argv.includes('--redelivery-only') || process.argv.includes('--output-report-only') ||
    cancelMode || retainedConsumerMode;
  const startGateway = async port => startHttpsOutboundSiteGateway({
    ...(port === undefined ? {} : {port}),
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    bearerAuthorities: new Map([[
      createHash('sha256').update(token).digest('hex'),
      {siteKey, siteGeneration: 1},
    ]]),
    control: siteControl,
    ...(retainedConsumerMode ? {retainedInput: runHost,
      receiveRetainedInput: async value => {
        const file = await open(join(root,
          `${value.operation}-${value.saved.cid.slice(7)}.json`), 'w', 0o600);
        try {
          await file.writeFile(value.saved.wire);
          await file.sync();
        } finally { await file.close(); }
      }} : {}),
    receiveObservation: async value => {
        try {
          const hint = JSON.parse(value.body);
          if (retainedConsumerMode &&
              ['actql-remote-retained-input-plan/0.1', 'actql-remote-retained-input-result/0.1']
                .includes(hint.version)) {
            // A queued duplicate can arrive after its transport waiter has
            // settled. Confirm the exact admitted report custody and current
            // authenticated Site; never ACK an unadmitted report here.
            const operation = hint.version === 'actql-remote-retained-input-plan/0.1'
              ? 'retained-plan' : 'retained-transfer';
            const saved = await readFile(join(root,
              `${operation}-${createHash('sha256').update(value.body).digest('hex')}.json`), 'utf8');
            assert.equal(saved, value.body);
            const original = retainedCoordinatorRecords.get(hint.dispatch_request_cid);
            assert.ok(original);
            const scope = siteControl.journalKey(siteControl.admitJson(
              coordinator.dispatchJson(original.request), hint.dispatch_request_cid));
            assert.equal(scope[1], value.binding.siteKey);
            assert.equal(Number(scope[2]), value.binding.siteGeneration);
            return Object.freeze({});
          }
          // Output plans are a request/response waiter, not an execution
          // observation. The Coordinator owner admits the resulting report
          // below, after the plan has been used to build its exact Output
          // record.
          if (JSON.parse(value.body).version === 'actql-remote-output-plan/0.1') {
            return Object.freeze({});
          }
          // The foundation fixture exercises direct dispatch transport. Only
          // its Output path uses the durable Coordinator receiver; the R1/R2
          // modes independently exercise durable dispatch observations.
          if (!durableObservationMode &&
              JSON.parse(value.body).version !== 'actql-remote-output-result/0.1') {
            return Object.freeze({});
          }
          if (crashOutputReceiver !== undefined &&
              JSON.parse(value.body).version === 'actql-remote-output-result/0.1') {
            const crash = crashOutputReceiver;
            crashOutputReceiver = undefined;
            await crash(value);
          }
          const receipt = await observationReceiver.receiveObservation(value);
          if (retainedConsumerMode) {
            const current = retainedCoordinatorRecords.get(hint.dispatch_request_cid);
            if (current !== undefined &&
                ['actql-remote-dispatch-status/0.1', 'actql-remote-dispatch-response/0.1']
                  .includes(hint.version)) {
              const response = coordinator.admitResponseJson(value.body, current.request,
                hint.version === 'actql-remote-dispatch-status/0.1');
              const transition = coordinator.prepareResponseObservation(current.record, response);
              const next = coordinator.responseDurableJson(coordinator.admitDurableJson(current.wire),
                transition, response);
              coordinator.admitDurableJson(next);
              coordinator.commitTransition(transition);
              current.wire = next;
            }
          }
          observationBodies.push(value.body);
          return receipt;
        } catch (error) {
          if (observationFailures.length < 4) observationFailures.push({
            code: error.code, message: error.message, cause: error.cause,
            issueCode: error.issueCode, binding: value.binding,
            observation: JSON.parse(value.body),
          });
          throw error;
        }
      },
    idlePollMilliseconds: 200,
  });
  gateway = await startGateway();

  // The Cloud's Result ingress: a direct Transfer destination.
  const transferControl = portable.remoteTransferControl;
  receiverStore = await createLocalRetainedStore({parentDirectory: root,
    // The receiver keeps every Result it gets during the whole test.
    capacityBytes: 1048576, maxFrameBytes: 65536, maxEntries: 64,
    maxReadersPerBody: 2});
  receiverJournal = openSqliteTransferJournal(join(root, 'receiver-journal'), {
    destinationSiteKey: 'cloud-results', destinationSiteGeneration: 1,
    maxChunks: 8, maxManifestBytes: 65536, maxReferencedBytes: 1048576n});
  receiver = await startHttpsDirectTransferReceiver({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    sourceAuthorities: new Map([[
      new X509Certificate(await readFile(join(root, 'transfer.crt')))
        .fingerprint256,
      Object.freeze({siteKey, siteGeneration: 1}),
    ]]),
    destinationSiteKey: 'cloud-results',
    destinationSiteGeneration: 1,
    control: transferControl,
    journal: receiverJournal,
    store: receiverStore,
    authorize: () => true,
    maxManifestBytes: 65536,
    maxChunks: 8,
    maxReferencedBytes: 1048576n,
    maxFrameBytes: 65536,
  });

  // The runtime bundle names this exact resident executable.
  const component = await readFile(executable);
  const componentCid = physicalCid(component);
  const runtimeKeys = generateKeyPairSync('ed25519');
  const manifest = portable.remoteBundleControl.prepare({
    issuerAuthority: 'bundle-authority-a',
    bundleName: 'native-resident-site',
    revision: 'native-resident/1',
    targetTriple,
    components: [{role: 'runtime_executable', cid: componentCid,
      bytes: BigInt(component.byteLength)}],
    connectorRegistration: 'local',
    connectorRevision: 'local/1',
    strategyRevision: 'strategy/1',
  });
  const envelope = signRemoteRuntimeBundle(manifest, portable.remoteBundleControl,
    {keyId: 'key-a', privateKey: runtimeKeys.privateKey});
  const bundleInput = join(root, 'bundle-input');
  const runtimeRoot = join(root, 'runtime');
  const engineRoot = join(root, 'engine');
  await Promise.all([mkdir(bundleInput), mkdir(runtimeRoot), mkdir(engineRoot),
    mkdir(join(root, 'publication'), {mode: 0o700})]);
  await writeFile(join(bundleInput, 'runtime-public.pem'),
    runtimeKeys.publicKey.export({type: 'spki', format: 'pem'}), {mode: 0o600});
  await writeFile(join(bundleInput, 'trust.json'), JSON.stringify({
    authorities: [{admit_new_bundles: true, issuer_authority: 'bundle-authority-a',
      key_id: 'key-a', public_key_name: 'runtime-public.pem'}],
    version: 'actql-native-runtime-bundle-trust/0.1',
  }), {mode: 0o600});
  await writeFile(join(bundleInput, 'manifest.json'), envelope.body,
    {mode: 0o600});
  await writeFile(join(bundleInput, 'signature.txt'), envelope.signature,
    {mode: 0o600});
  await writeFile(join(bundleInput, 'component.bin'), component, {mode: 0o700});
  const bundleCommon = ['--store-root', runtimeRoot, '--sqlite-library',
    sqliteLibrary, '--crypto-library', cryptoLibrary, '--target-triple',
    targetTriple, '--authority-root', bundleInput, '--trust-config-name',
    'trust.json', '--capacity-bytes', '268435456', '--max-bundles', '4',
    '--max-owners', '8', '--max-record-bytes', '1048576'];
  execFileSync(bundleTool, [...bundleCommon, 'install', '--install-id',
    'resident-install', '--signature-key-id', 'key-a', '--bundle-cid',
    envelope.runtimeBundleCid, '--input-root', bundleInput, '--manifest-name',
    'manifest.json', '--signature-name', 'signature.txt', '--component-name',
    'component.bin'], {stdio: 'inherit'});
  execFileSync(bundleTool, [...bundleCommon, 'activate', '--bundle-cid',
    envelope.runtimeBundleCid], {stdio: 'inherit'});
  const [registry, values, fragment] = await pinnedEngineContracts(repository);
  await writeFile(join(engineRoot, 'registry.json'), registry);
  await writeFile(join(engineRoot, 'values.json'), values);
  await writeFile(join(engineRoot, 'fragment.json'), fragment);

  // The issuing side (the Cloud's role) prepares and authorizes the Run.
  const programText = retainedConsumerMode ? retainedSourceProgram : sourceMode ? sourceProgram : await readFile(join(repository,
    'packages/sdk/fixtures/values.json'), 'utf8');
  const environmentWire = sourceMode ? (await residentSourceEnvironment(repository)).wire
    : (await readFile(join(repository,
      'packages/sdk/fixtures/values.environment.json'), 'utf8')).trimEnd();
  const environmentCid = JSON.parse(environmentWire).evidence_bundle_cid;
  const checkEnvironment = moonModule.clientProgramCheckEnvironment(
    environmentWire, environmentCid, false, false, true, false, false, false,
    false);
  assert.ok(checkEnvironment);
  const program = installNodeClientProgramPreparation({moon: moonModule,
    environment: checkEnvironment})({kind: 'aql',
    input: {text: programText, format: 'json'}, parameters: null});
  const now = Date.now();
  const createdAt = new Date(now - 60_000).toISOString();
  const validUntil = new Date(now + 3_600_000).toISOString();
  const sourcePrepared = sourceMode ? runHost.prepare(programText, 'json',
    runHost.admitEnvironment(environmentWire, environmentCid, {rela: true})) : undefined;
  const sourceCompilation = sourceMode ? runHost.compileTasks(sourcePrepared) : undefined;
  const sourceAllowed = sourceMode ? runHost.issueAllowedTaskRun(sourcePrepared, sourceCompilation, {
    executionContextCid: physicalCid('resident-execution-context'),
    hostPolicyCid: physicalCid('resident-host-policy'), expiresAt: validUntil,
  }) : undefined;
  const compiled = sourceMode ? {
    preparedEvidence: {wire: sourceAllowed.preparedInvocationWire},
    authorization: {wire: sourceAllowed.authorizationWire},
    compiledPlan: {wire: runHost.privateTaskCompilationWires(sourceCompilation).compiledPlan},
  } : portable.publicationControl.prepareCheckedClientCompiledRun(
    program, 'values', {
      executionContextCid: physicalCid('resident-execution-context'),
      hostPolicyCid: physicalCid('resident-host-policy'),
      expiresAt: validUntil,
    });
  const sourceDefinition = sourceMode ? runHost.privateRunDefinition(runHost.issueTaskRunDefinition(
    sourcePrepared, sourceCompilation, sourceAllowed.admission,
    'resident-scope', 'resident-run-1', createdAt, validUntil)) : undefined;
  const definition = sourceMode ? {wire: sourceDefinition.wire, identity: sourceDefinition.cid}
    : portable.publicationControl.defineCheckedClientCompiledRun(
    compiled, {namespaceId: 'resident-scope', runId: 'resident-run-1',
      createdAt, validUntil});
  // Restore the original owners from retained evidence. The new issuer only
  // projects them: it cannot authorize, recompile or issue a replacement Run.
  const retainedEnvironment = runHost.admitEnvironment(environmentWire,
    environmentCid, {rela: true});
  const retainedPrepared = runHost.prepare(programText, 'json', retainedEnvironment);
  const retainedCompilation = sourceMode ? runHost.compileTasks(retainedPrepared)
    : runHost.compileValues(retainedPrepared);
  const retainedAdmission = (sourceMode ? runHost.admitTaskRun : runHost.admitRun)(retainedPrepared, retainedCompilation,
    compiled.preparedEvidence.wire, compiled.authorization.wire);
  const retainedDefinition = (sourceMode ? runHost.admitTaskRunDefinition : runHost.admitSourceFreeRunDefinition)(retainedPrepared,
    retainedCompilation, retainedAdmission, definition.wire);
  const materialsIssuer = sourceMode ? runHost.issueTaskRunMaterials : runHost.issueSourceFreeRunMaterials;
  const materials = materialsIssuer(retainedPrepared,
    retainedCompilation, retainedAdmission, retainedDefinition, {
      environment: retainedEnvironment, environmentWire,
      document: programText, format: 'json',
    });
  assert.equal(runHost.privateRunDefinition(retainedDefinition).cid, definition.identity);
  const projected = JSON.parse(materials);
  assert.equal(projected.prepared_invocation, compiled.preparedEvidence.wire);
  assert.equal(projected.run_authorization, compiled.authorization.wire);
  assert.equal(projected.run_id, 'resident-run-1');
  assert.equal(projected.scope_id, 'resident-scope');
  assert.equal(projected.created_at, createdAt);
  assert.equal(projected.valid_until, validUntil);
  // Individual inputs remain valid, but quoting both makes the aggregate
  // materials exceed the cap. Exercise this through the installed issuer too.
  assert.throws(() => materialsIssuer(retainedPrepared,
    retainedCompilation, retainedAdmission, retainedDefinition, {
      environment: retainedEnvironment, environmentWire, format: 'json',
      document: '\t'.repeat(65536 - Buffer.byteLength(programText)) + programText,
      parametersWire: '\t'.repeat(65534) + '{}',
    }), {code: 'RunHostRunMaterialsRejected'});
  const operationCapability = physicalCid('resident-operation-capability');
  const issuerCapability = physicalCid('resident-issuer-capability');
  const executionBytes = sourceMode ? 134217728n : 1048576n;
  // This profile retains the bounded Transfer decoder and the checked
  // consumer together. Its declared reservation is below the unchanged Site
  // ceiling; using the one-task 1 MiB allowance would reject before start.
  const retainedBytes = retainedConsumerMode ? 16777216n : 1048576n;
  const budget = siteControl.prepareBudget({retainedBytes,
    executionBytes});
  const bindingBody = sourceMode ? runHost.taskInputBinding(retainedPrepared, 0) : '{}';
  const binding = siteControl.prepareInputBinding(bindingBody);
  const taskKey = sourceMode ? runHost.taskKeys(retainedPrepared, retainedCompilation)[0]
    : JSON.parse(compiled.compiledPlan.wire).executable_plan_cid
    === undefined ? 'values_0' : 'values_0';
  const dispatchFor = (dispatchId, attempt, overrides = {}) =>
    siteControl.prepare({
      coordinatorAuthority,
      runDefinitionCid: definition.identity,
      taskKey,
      taskAttempt: attempt,
      dispatchId,
      siteKey,
      siteGeneration: 1,
      runtimeBundleCid: envelope.runtimeBundleCid,
      connectorRegistration: 'local',
      connectorRevision: 'local/1',
      strategyRevision: 'strategy/1',
      inputBindingCid: siteControl.inputBindingIdentity(binding),
      obligationsCid: physicalCid('resident-obligations'),
      budgetCid: siteControl.budgetIdentity(budget),
      evidenceIssuerCapabilityCid: issuerCapability,
      grantCid: operationCapability,
      ...overrides,
    });
  const materialsEnvelope = dispatch => coordinator.pollDispatchMaterialsJson(
    coordinator.admitDispatchJson(siteControl.requestJson(dispatch),
      siteControl.identity(dispatch)), bindingBody, 8192, materials);
  const ensureOutputReceiver = async dispatch => {
    if (observationStore?.contains(dispatch, siteControl)) return;
    observationStore ??= openSqliteCoordinatorDispatchJournal(
      join(root, 'foundation-coordinator-output'),
      {coordinatorAuthority});
    observationStore.accept(siteControl.prepareCoordinatorIntent(
      siteControl.createCoordinatorJournal(coordinatorAuthority), dispatch),
    dispatch, siteControl);
    if (retainedConsumerMode) {
      const request = coordinator.admitDispatchJson(siteControl.requestJson(dispatch), siteControl.identity(dispatch));
      const admission = coordinator.prepareIntent(coordinator.createJournal(coordinatorAuthority), request);
      const wire = coordinator.admissionDurableJson(admission);
      retainedCoordinatorRecords.set(siteControl.identity(dispatch), {
        request, wire, record: coordinator.commitIntent(admission)});
    }
    observationReceiver = createRemoteSiteCoordinator({
      control: siteControl,
      journal: siteControl.createCoordinatorJournal(coordinatorAuthority),
      store: observationStore,
      authorization: await allowAllAuthorization(),
      output: value => gateway.output(value),
      transferControl,
    });
  };
  // The Result the Coordinator publishes, from the ordinary Client owners.
  const hostPrepared = runHost.prepare(programText, 'json',
    runHost.admitEnvironment(environmentWire, environmentCid, {rela: true}));
  const resultDefinitionCid = sourceMode ? runHost.taskResultDefinitions(hostPrepared,
    runHost.compileTasks(hostPrepared))[0].cid : runHost.resultDefinitions(hostPrepared,
      runHost.compileValues(hostPrepared))[0].cid;
  // The Coordinator queries until the execution settled and its output
  // subject is observed; an executor entry is recorded before execution.
  const settledQuery = async (dispatch, tag) => {
    for (let attempt = 0; attempt < 100; attempt += 1) {
      const answer = await within(gateway.query({dispatch}), `${tag} query`);
      if (answer.state[0] === 3 && answer.subject !== undefined) return answer;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error(`${tag} did not settle`);
  };
  // The Coordinator plans the output, has it delivered to its ingress over
  // the direct route, and releases the holder's retained output.
  const planOutput = async (dispatch, terminal, tag,
    origin = receiver.origin) => {
    await ensureOutputReceiver(dispatch);
    const intent = siteControl.prepareOutputIntent(dispatch, {
      storeAuthorityCid: physicalCid('resident-publication-store'),
      publicationAttemptCid: physicalCid(`resident-publication-${tag}`),
      resultDefinitionCid,
      orderingEvidenceCid: physicalCid('resident-ordering'),
      coordinatorAuthority,
      transferAttemptId: `resident-transfer-${tag}`,
      transferRoute: 'direct',
      destinationSite: 'cloud-results',
      destinationSiteGeneration: 1,
      transferMaxBytes: 1048576n,
      transferExpiresAtMilliseconds: 4102444800000n,
      sourceGrantCid: physicalCid('resident-source-grant'),
      destinationGrantCid: physicalCid('resident-destination-grant'),
      routeCapabilityCid: physicalCid('resident-direct-route'),
      transferOrigin: origin,
    });
    const planned = await within(gateway.plan({dispatch, intent,
      subject: terminal.subject, maxChunks: 8, maxManifestBytes: 65536,
      maxReferencedBytes: 1048576n}), `${tag} plan`);
    return {intent, planned};
  };
  const requestOutput = (dispatch, {intent, planned}) => observationReceiver.output({
    dispatch, intent, payloadRequest: planned.payloadRequest,
    transferRequest: planned.transferRequest});
  const deliverAndRelease = async (dispatch, terminal, tag) => {
    const delivered = await within(requestOutput(dispatch,
      await planOutput(dispatch, terminal, tag)), `${tag} output`);
    await within(gateway.release({dispatch}), `${tag} release`);
    return delivered;
  };

  const entryLog = join(root, 'executor-entry.log');
  const common = [
    '--sqlite-library', sqliteLibrary, '--crypto-library', cryptoLibrary,
    '--http-library', httpLibrary, '--journal', join(root, 'journal.sqlite3'),
    '--runtime-root', runtimeRoot, '--bundle-issuer', 'bundle-authority-a',
    '--bundle-key-id', 'key-a', '--bundle-public-key-root', bundleInput,
    '--bundle-public-key-file', 'runtime-public.pem', '--target-triple',
    targetTriple, '--component-cid', componentCid, '--site-key', siteKey,
    '--site-generation', '1', '--executor-slot', join(root, 'executor.slot'),
    '--ca', join(root, 'ca.crt'), '--control-bearer-file', tokenFile,
    '--poll-url',
    `${gateway.origin}/v1/sites/${siteKey}/generations/1/outbound/poll`,
    '--observation-url',
    `${gateway.origin}/v1/sites/${siteKey}/generations/1/outbound/observations`,
    '--coordinator-authority', coordinatorAuthority,
    '--runtime-bundle-cid', envelope.runtimeBundleCid,
    '--connector-registration', 'local', '--connector-revision', 'local/1',
    '--strategy-revision', 'strategy/1',
    '--operation-capability-cid', operationCapability,
    '--issuer-capability-cid', issuerCapability,
    '--budget-retained-bytes', String(retainedBytes), '--budget-execution-bytes', String(executionBytes),
    '--engine-root', engineRoot, '--executor-entry-log', entryLog,
    '--transfer-cert', join(root, 'transfer.crt'),
    '--transfer-key', join(root, 'transfer.key'),
    '--publication-root', join(root, 'publication'),
    '--publication-authority-cid', physicalCid('resident-publication-store'),
    '--idle-wait-ms', '50', '--min-backoff-ms', '50', '--max-backoff-ms', '200',
    '--shutdown-wait-ms', '10000',
  ];
  const startSite = (extra = [], {
    origin = receiver.origin,
    controlOrigin = gateway.origin,
    observationOrigin = controlOrigin,
    transferJournal = join(root, 'site-transfer.sqlite3'),
    publication = join(root, 'publication'),
    siteJournal = join(root, 'journal.sqlite3'),
  } = {}) => {
    const configured = [...common];
    configured[configured.indexOf('--publication-root') + 1] = publication;
    configured[configured.indexOf('--journal') + 1] = siteJournal;
    for (const [flag, operation] of [['--poll-url', 'poll'], ['--observation-url', 'observations']]) {
      configured[configured.indexOf(flag) + 1] =
        `${(operation === 'observations' ? observationOrigin : controlOrigin)}/v1/sites/${siteKey}/generations/1/outbound/${operation}`;
    }
    const child = spawn(executable, ['run', ...configured,
      '--transfer-origin', origin, '--transfer-journal', transferJournal,
      ...extra], {
      cwd: root, stdio: ['ignore', 'pipe', 'pipe']});
    const lines = [];
    let buffer = '';
    child.stdout.on('data', chunk => {
      buffer += chunk;
      const parts = buffer.split('\n');
      buffer = parts.pop();
      for (const line of parts) {
        if (line.length === 0) continue;
        try { lines.push(JSON.parse(line)); }
        catch { lines.push({kind: 'text', text: line}); }
      }
    });
    let stderr = '';
    child.stderr.on('data', chunk => { stderr += chunk; });
    const exited = once(child, 'exit');
    running.add(child);
    exited.then(() => running.delete(child));
    return {child, lines, exited, stderr: () => stderr};
  };
  const waitFor = async (predicate, what, milliseconds = 30_000) => {
    const deadline = Date.now() + milliseconds;
    while (Date.now() < deadline) {
      if (await predicate()) return;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    throw new Error(`timed out waiting for ${what}`);
  };
  const within = async (promise, what, milliseconds = 60_000) => {
    let timer;
    try {
      return await Promise.race([promise, new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`timed out waiting for ${what}`)),
          milliseconds);
      })]);
    } finally { clearTimeout(timer); }
  };
  const entries = async () => existsSync(entryLog)
    ? (await readFile(entryLog, 'utf8')).split('\n').filter(Boolean) : [];
  const publicationRoot = join(root, 'publication');
  const journalPath = join(root, 'journal.sqlite3');
  const reservedPayloadBytes = (publication = publicationRoot) => {
    const database = new DatabaseSync(join(publication,
      '.actql-publication.sqlite3'), {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      const row = database.prepare('SELECT COALESCE(SUM(reserved_bytes), 0) ' +
        'AS bytes FROM actql_capacity WHERE namespace = ?')
        .get('publication_payload');
      return Number(row.bytes);
    } finally { database.close(); }
  };
  const pendingIntents = (journal = journalPath) => {
    const database = new DatabaseSync(journal, {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      return database.prepare('SELECT record_key FROM actql_records ' +
        'WHERE namespace = ? AND record_key NOT IN (SELECT record_key ' +
        'FROM actql_records WHERE namespace = ?)')
        .all('site_output_intent', 'site_output_intent_done')
        .map(row => row.record_key);
    } finally { database.close(); }
  };
  // The live Site commits report and ACK records while this polls; wait out
  // a transient write lock like the other journal observers, never mask it.
  const reportState = () => {
    const database = new DatabaseSync(journalPath, {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      const reports = database.prepare('SELECT record_key, body FROM actql_records ' +
        'WHERE namespace = ?').all('site_output_report');
      const replies = database.prepare('SELECT record_key, revision, body FROM actql_records ' +
        'WHERE namespace = ?').all('site_output_report_reply');
      const accepted = new Set(replies.filter(row =>
        JSON.parse(Buffer.from(row.body).toString('utf8')).outcome === 'accepted')
        .map(row => row.record_key));
      return {reports, replies, pending: reports.filter(row => !accepted.has(row.record_key)).length};
    } finally { database.close(); }
  };
  // A real journal write failure: another connection holds the write lock
  // longer than the Site's busy timeout.
  const lockJournal = async () => {
    const database = new DatabaseSync(journalPath);
    for (let attempt = 0; ; attempt += 1) {
      try {
        database.exec('BEGIN IMMEDIATE');
        break;
      } catch (error) {
        if (attempt > 400) { database.close(); throw error; }
        await new Promise(resolve => setTimeout(resolve, 25));
      }
    }
    return () => {
      database.exec('ROLLBACK');
      database.close();
    };
  };
  let expectedEntries = 0;

  if (cancelMode) {
    const bundleHoldings = () => {
      const database = new DatabaseSync(join(runtimeRoot,
        '.actql-runtime-bundle.sqlite3'), {readOnly: true});
      try {
        database.exec('PRAGMA busy_timeout = 5000');
        const catalog = database.prepare('SELECT body FROM actql_records ' +
          'WHERE namespace=? AND record_key=?').get('runtime_bundle', 'catalog');
        return JSON.parse(Buffer.from(catalog.body).toString('utf8'))
          .entries.flatMap(entry => entry.holds);
      } finally { database.close(); }
    };
    const cancellationRecord = dispatch => {
      const database = new DatabaseSync(journalPath, {readOnly: true});
      try {
        database.exec('PRAGMA busy_timeout = 5000');
        const rows = database.prepare('SELECT body FROM actql_records WHERE namespace=?')
          .all('site_dispatch');
        return rows.map(row => JSON.parse(Buffer.from(row.body).toString('utf8')))
          .find(record => record.dispatch_request_cid === siteControl.identity(dispatch));
      } finally { database.close(); }
    };
    let expectedEntries = 0;
    // A valid envelope for the same Site is still not authorized when its
    // exact operation grant differs from the installed delegation.
    const foreign = dispatchFor('resident-cancel-foreign-grant', 399,
      {grantCid: physicalCid('foreign-operation-grant')});
    let rejected = startSite(); currentSite = rejected;
    const refused = gateway.cancel({dispatch: foreign}).catch(error => error);
    await waitFor(() => rejected.lines.some(line => line.kind === 'cancel-refused'),
      'cancellation delegation refusal before mutation');
    gateway.withdraw({dispatch: foreign});
    assert.equal((await refused).code, 'RemoteDispatchWithdrawn');
    rejected.child.kill('SIGTERM'); await rejected.exited;
    const beforeJournal = new DatabaseSync(journalPath, {readOnly: true});
    try {
      assert.deepEqual(beforeJournal.prepare('SELECT record_key FROM actql_records ' +
        'WHERE namespace IN (?,?)').all('site_dispatch', 'site_cancel_request'), []);
    } finally { beforeJournal.close(); }
    assert.deepEqual(await entries(), []);
    assert.deepEqual(await readdir(publicationRoot), []);
    console.log(JSON.stringify({kind: 'resident-cancel-refusal',
      beforeMutation: true, executorEntries: 0, publicationEntries: 0}));
    for (const [index, mode] of ['unseen-restart', 'before-claim', 'running', 'lost-reply', 'running-restart', 'running-lost-reply'].entries()) {
      let lostReply = false;
      const cancelOffers = [];
      const dispatch = dispatchFor(`resident-cancel-${mode}`, 400 + index);
      await ensureOutputReceiver(dispatch);
      if (mode === 'lost-reply' || mode === 'running-lost-reply') {
        ackLossProxy = await observationAckLossProxy({origin: gateway.origin,
          key: await readFile(join(root, 'server.key')),
          cert: await readFile(join(root, 'server.crt')),
          ca: await readFile(join(root, 'ca.crt')),
          loseAck: body => {
            const value = JSON.parse(body);
            return !lostReply && value.dispatch_request_cid === siteControl.identity(dispatch) &&
              value.version === 'actql-remote-dispatch-status/0.1' &&
              value.state[0] === (mode === 'running-lost-reply' ? 2 : 5);
          }, allowDispatch: () => true, onAckLost: () => { lostReply = true; },
          transformReply: (_body, upstream) => {
            if (upstream.status === 200) {
              const envelope = upstream.body.toString('utf8');
              const value = JSON.parse(envelope);
              if (value.version === 'actql-remote-poll-cancel/0.1' &&
                  value.dispatch_request_cid === siteControl.identity(dispatch)) {
                cancelOffers.push(envelope);
              }
            }
            return upstream;
          }});
      }
      let site = startSite(mode === 'before-claim' ?
        ['--holder-pause-at', 'before-start', '--holder-pause-ms', '1500'] :
        mode === 'running' || mode === 'running-lost-reply' ? ['--holder-pause-ms', '5000', '--release-recovery-close-failures', '2'] :
        mode === 'running-restart' ? ['--holder-pause-ms', '2000', '--control-cancel-kill-at', 'after-save'] : [],
      {controlOrigin: ackLossProxy?.origin ?? gateway.origin});
      currentSite = site;
      let dispatched;
      if (mode === 'before-claim' || mode.startsWith('running')) {
        dispatched = gateway.dispatch({dispatch, inputBindingBody: '{}',
          dispatchEnvelope: materialsEnvelope(dispatch)}).catch(error => error);
        if (mode === 'before-claim') {
          await waitFor(() => site.lines.some(line => line.kind === 'holder-paused' &&
            line.point === 'before-start'), 'cancel before exclusive claim');
        } else {
          expectedEntries++;
          await waitFor(async () => (await entries()).length === expectedEntries, 'cancel during executor entry');
        }
      }
      const cancelling = gateway.cancel({dispatch});
      if (mode === 'running-restart') {
        assert.deepEqual(await within(site.exited, 'control killed after durable cancellation'), [null, 'SIGKILL']);
        assert.ok(site.lines.some(line => line.kind === 'control-cancel-killed'));
        const saved = cancellationRecord(dispatch);
        assert.equal(saved.execution_state, 2);
        assert.equal(saved.cleanup_state, 0);
        site = startSite(); currentSite = site;
      }
      const cancelled = await within(cancelling, `${mode} cancellation observation`);
      assert.equal(cancelled.dispatchRequestCid, siteControl.identity(dispatch));
      assert.equal(cancelled.state[2], 2, 'delivery custody ends only after formal cleanup release');
      if (mode === 'running' || mode === 'running-lost-reply') {
        const saved = observationBodies.map(body => JSON.parse(body)).find(value =>
          value.dispatch_request_cid === siteControl.identity(dispatch) &&
          value.version === 'actql-remote-dispatch-status/0.1' && value.state[0] === 2);
        assert.ok(saved, 'the initial saved cancellation status is independently observed');
        assert.equal(saved.state[2], 0, 'saving cancellation cannot release active resources');
        await waitFor(() => site.lines.some(line => line.kind === 'cancel-cleanup-pending'),
          'bundle close failure keeps cleanup responsibility');
      }
      if (mode === 'lost-reply' || mode === 'running-lost-reply') {
        await waitFor(() => lostReply, 'cancellation observation ACK lost');
        await waitFor(() => site.lines.some(line => line.kind === 'cancel-unreported'),
          'Site reports unconfirmed cancellation reply');
      }
      if (mode === 'unseen-restart' || mode === 'lost-reply') {
        site.child.kill('SIGTERM'); await site.exited;
        site = startSite(); currentSite = site;
      }
      await waitFor(() => {
        const saved = cancellationRecord(dispatch);
        return (saved?.execution_state === 5 ||
          (mode === 'running-restart' && saved?.execution_state === 3)) && saved.cleanup_state === 2;
      }, `${mode} formal cancellation and release`);
      // Redelivery after reconstruction uses the original envelope. No new
      // attempt, source-free computation, or holder may be created.
      if (dispatched) { gateway.withdraw({dispatch}); await dispatched; }
      const late = await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
        dispatchEnvelope: materialsEnvelope(dispatch)}), `${mode} delayed dispatch`);
      if (mode === 'running-restart') {
        assert.equal(late.state[0], 3, 'a completed execution is not rewritten as unexecuted');
        assert.equal(late.state[2], 2);
      } else {
        assert.deepEqual(late.state, [5, 0, 2, 0, 0]);
      }
      const revision = late.revision;
      for (let retry = 0; retry < 2; retry++) {
        const repeated = await within(gateway.cancel({dispatch}), `${mode} duplicate cancellation`);
        assert.deepEqual(repeated.state, late.state);
        assert.equal(repeated.revision, revision);
      }
      const coordinatorRecord = observationStore.recoverJournal(
        siteControl.createCoordinatorJournal(coordinatorAuthority), siteControl)
        .find(value => siteControl.identity(value.request) === siteControl.identity(dispatch)).record;
      const coordinatorState = siteControl.coordinatorRecordStatus(coordinatorRecord);
      assert.equal(coordinatorState[3], String(late.state[0]), 'the common Coordinator owner must admit the original execution disposition');
      assert.equal(coordinatorState[5], '2', 'the common Coordinator owner must admit released cleanup');
      site.child.kill('SIGTERM'); await site.exited;
      assert.equal((await entries()).length, expectedEntries);
      assert.equal(pendingIntents().length, 0);
      if (mode === 'unseen-restart' && index === 0) {
        assert.equal(existsSync(join(publicationRoot, '.actql-publication.sqlite3')), false,
          'cancellation before dispatch must never open publication custody');
        assert.deepEqual(await readdir(publicationRoot), [],
          'cancellation before dispatch must acquire no payload resources');
      } else {
        assert.equal(reservedPayloadBytes(), 0);
      }
      assert.deepEqual(bundleHoldings(), []);
      if (mode === 'running-lost-reply') {
        assert.ok(cancelOffers.length >= 2, 'lost nonterminal response must cause exact Cancel redelivery');
        assert.ok(cancelOffers.every(body => body === cancelOffers[0]));
      }
      console.log(JSON.stringify({kind: 'resident-cancel-case', mode,
        dispatchCid: siteControl.identity(dispatch), revision,
        executorEntries: mode.startsWith('running') ? 1 : 0,
        execution: late.state[0], cleanup: 2,
        pendingIntents: 0, reservedPayloadBytes: 0, bundleHoldings: 0}));
      if (ackLossProxy) { await ackLossProxy.close(); ackLossProxy = undefined; }
    }
  } else if (sourceMode) {
    const duckdbLibrary = process.env.ACTQL_TEST_DUCKDB_LIBRARY ?? join(repository,
      'adapters/connectors/duckdb/node/node_modules/@duckdb',
      `node-bindings-${process.platform}-${process.arch}`,
      process.platform === 'darwin' ? 'libduckdb.dylib' : 'libduckdb.so');
    assert.ok(existsSync(duckdbLibrary), 'Source acceptance requires the actual DuckDB library');
    const require = createRequire(join(repository, 'adapters/connectors/duckdb/node/package.json'));
    const {DuckDBInstance} = require('@duckdb/node-api');
    const databasePath = join(root, 'source.duckdb');
    const instance = await DuckDBInstance.create(databasePath);
    const connection = await instance.connect();
    try {
      await connection.run('CREATE TABLE records(id DOUBLE)');
      await connection.run('INSERT INTO records VALUES (3), (1), (2)');
    } finally { connection.closeSync(); instance.closeSync(); }
    for (const [name, contract] of [
      ['query-contract.json', 'actql-query-acquisition.json'],
      ['query-evidence-contract.json', 'actql-query-process-evidence.json'],
      ['query-two-receipt-contract.json', 'actql-query-two-receipt.json'],
    ]) {
      await writeFile(join(engineRoot, name), await readFile(join(repository, 'spec/contracts', contract)));
    }
    const extra = ['--duckdb-library', duckdbLibrary, '--source-ref', sourceRef,
      '--source-contract-cid', sourceContractCid, '--source-database', databasePath,
      '--source-schema', 'main', '--source-table', 'records'];
    const configured = (changes = {}) => {
      const args = [...extra];
      for (const [flag, value] of Object.entries(changes)) args[args.indexOf(flag) + 1] = value;
      return args;
    };
    if (retainedConsumerMode) {
      assert.deepEqual(runHost.taskExecutionShape(retainedPrepared, retainedCompilation),
        {taskCount: 2, acquisitionCount: 1});
      const sourceGrantCid = physicalCid('retained-source-grant');
      const destinationGrantCid = physicalCid('retained-destination-grant');
      const routeCapabilityCid = physicalCid('retained-route');
      const retainedRoot = join(root, 'retained-input');
      await mkdir(retainedRoot, {mode: 0o700});
      const site = startSite([...extra, '--retained-input-root', retainedRoot,
        '--retained-source-grant-cid', sourceGrantCid,
        '--retained-destination-grant-cid', destinationGrantCid,
        '--retained-route-capability-cid', routeCapabilityCid,
        '--retained-consumer-engine-bytes', '67108864']);
      currentSite = site;
      const producerDispatch = dispatchFor('retained-producer', 1);
      await ensureOutputReceiver(producerDispatch);
      await within(gateway.dispatch({dispatch: producerDispatch, inputBindingBody: bindingBody,
        dispatchEnvelope: materialsEnvelope(producerDispatch)}), 'retained producer');
      await settledQuery(producerDispatch, 'retained producer');
      const edge = runHost.prepareRetainedTaskInputEdge(retainedPrepared, retainedCompilation,
        retainedAdmission, retainedDefinition, 1, 0);
      const producerCurrent = () => ({
        authority: coordinatorAuthority,
        durableRecordWire: retainedCoordinatorRecords.get(siteControl.identity(producerDispatch)).wire,
      });
      let producer = runHost.prepareRetainedInputProducer(edge, producerCurrent);
      const current = {
        siteBindingCurrent: (key, generation, bundle) => key === siteKey && generation === 1 &&
          bundle === envelope.runtimeBundleCid && site.child.exitCode === null && site.child.signalCode === null,
        authority: () => coordinatorAuthority, nowUnixMs: () => BigInt(Date.now()),
        authorized: (dispatchCid, wire) => dispatchCid === siteControl.identity(producerDispatch) &&
          JSON.parse(wire).source_grant_cid === sourceGrantCid &&
          JSON.parse(wire).destination_grant_cid === destinationGrantCid &&
          JSON.parse(wire).route_capability_cid === routeCapabilityCid,
      };
      const limits = {maxChunks: 8, maxManifestBytes: 65536,
        maxReferencedBytes: 1048576n, maxBindingBytes: 1048576};
      let intent = runHost.prepareRetainedInputIntent(producer, {
        sourceGrantCid, destinationGrantCid, routeCapabilityCid,
        transferAttempt: 'retained-input-1', transferMaxBytes: 1048576n,
        transferExpiresUnixMs: BigInt(Date.parse(validUntil)),
      });
      let plan = await within(gateway.retainedPlan({dispatch: producerDispatch,
        intent, current, limits: {maxChunks: limits.maxChunks,
          maxManifestBytes: limits.maxManifestBytes,
          maxReferencedBytes: limits.maxReferencedBytes}}), 'retained input plan');
      let result = await within(gateway.retainedTransfer({dispatch: producerDispatch, plan}),
        'physical retained input transfer');
      if (retainedCoordinatorReconstruction) {
        assert.equal(gateway.pending(), 0);
        const origin = gateway.origin;
        await within(gateway.close(), 'retained Coordinator listener stop');
        // The SQLite owner remains authoritative. This synchronized snapshot
        // records its already-admitted common ABI projection for the test's
        // fresh Coordinator handles; it is not a production recovery ledger.
        const original = retainedCoordinatorRecords.get(siteControl.identity(producerDispatch));
        const intentSaved = runHost.retainedInputIntentFacts(intent);
        const planSaved = runHost.retainedInputPlanFacts(plan);
        const resultSaved = runHost.retainedInputResultFacts(result);
        const snapshotPath = join(root, 'retained-coordinator-projection.json');
        const snapshot = await open(snapshotPath, 'wx', 0o600);
        try {
          await snapshot.writeFile(JSON.stringify({durableWire: original.wire, intent: intentSaved}));
          await snapshot.sync();
        } finally { await snapshot.close(); }
        observationStore.close();
        observationReceiver = undefined;
        retainedCoordinatorRecords.clear();
        observationStore = openSqliteCoordinatorDispatchJournal(
          join(root, 'foundation-coordinator-output'), {coordinatorAuthority});
        const physicalRecords = observationStore.recoverJournal(
          siteControl.createCoordinatorJournal(coordinatorAuthority), siteControl);
        assert.equal(physicalRecords.length, 1);
        assert.equal(siteControl.identity(physicalRecords[0].request), siteControl.identity(producerDispatch));
        const saved = JSON.parse(await readFile(snapshotPath, 'utf8'));
        const durable = coordinator.admitDurableJson(saved.durableWire);
        assert.equal(coordinator.durableDispatchCid(durable), siteControl.identity(producerDispatch));
        const record = coordinator.restoreDurable(coordinator.createJournal(coordinatorAuthority), durable);
        retainedCoordinatorRecords.set(coordinator.durableDispatchCid(durable), {
          request: coordinator.durableRequest(durable), record, wire: saved.durableWire});
        observationReceiver = createRemoteSiteCoordinator({control: siteControl,
          journal: siteControl.createCoordinatorJournal(coordinatorAuthority), store: observationStore,
          authorization: await allowAllAuthorization(), output: value => gateway.output(value), transferControl});
        gateway = await startGateway(Number(new URL(origin).port));
        assert.equal(gateway.origin, origin);
        // Saved generation is insufficient. A fresh authenticated query to
        // the still-live original Site proves exact current output custody.
        const live = await settledQuery(producerDispatch, 'reconstructed retained producer');
        assert.equal(live.state[3], 1);
        assert.equal(siteControl.evidenceIdentity(live.evidence),
          coordinator.acceptedSiteOutput(durable).evidenceCid);
        producer = runHost.prepareRetainedInputProducer(edge, producerCurrent);
        intent = runHost.admitRetainedInputIntent(producer, saved.intent);
        assert.deepEqual(runHost.retainedInputIntentFacts(intent), intentSaved);
        const planWire = await readFile(join(root,
          `retained-plan-${planSaved.cid.slice(7)}.json`), 'utf8');
        const planLimits = {maxChunks: limits.maxChunks, maxManifestBytes: limits.maxManifestBytes,
          maxReferencedBytes: limits.maxReferencedBytes};
        assert.throws(() => runHost.admitRetainedInputPlan(intent,
          {cid: planSaved.cid, wire: planWire}, {...current,
            siteBindingCurrent: () => false}, planLimits), {code: 'RunHostRetainedInputPlanRejected'});
        plan = runHost.admitRetainedInputPlan(intent,
          {cid: planSaved.cid, wire: planWire}, current, planLimits);
        assert.deepEqual(runHost.retainedInputPlanFacts(plan), planSaved);
        const resultWire = await readFile(join(root,
          `retained-transfer-${resultSaved.cid.slice(7)}.json`), 'utf8');
        result = runHost.admitRetainedInputResult(plan, {cid: resultSaved.cid, wire: resultWire});
        assert.deepEqual(runHost.retainedInputResultFacts(result), resultSaved);
        const replay = await within(gateway.retainedTransfer({dispatch: producerDispatch, plan}),
          'reconstructed exact physical handoff report');
        assert.deepEqual(runHost.retainedInputResultFacts(replay), resultSaved);
        assert.equal((await entries()).length, 1, 'reconstruction cannot reacquire Source or start Compute');
      }
      const receipt = runHost.retainedInputResultFacts(result).receipt;
      const transferCid = runHost.retainedInputPlanFacts(plan).transfer.cid;
      const input = runHost.prepareRetainedTaskInput(producer, receipt, 'direct-destination', {
        ...current,
        readTransfer: () => {
          const database = new DatabaseSync(join(root, 'site-transfer.sqlite3'), {readOnly: true});
          try {
            const rows = database.prepare('SELECT CAST(body AS TEXT) AS body FROM actql_records WHERE namespace = ?')
              .all('remote_transfer');
            const row = rows.find(row => JSON.parse(row.body).request_cid === transferCid);
            assert.ok(row, 'current actual Native receiver record must exist');
            return row.body;
          } finally { database.close(); }
        },
      }, limits);
      const consumerBinding = runHost.retainedTaskInputFacts(input).wire;
      const issued = runHost.issueRetainedTaskDispatch(retainedPrepared, retainedCompilation,
        retainedAdmission, retainedDefinition,
        runHost.prepareTaskRequest(retainedPrepared, retainedCompilation, coordinatorAuthority, 'retained-request'),
        1, {taskAttempt: 1, dispatchId: 'retained-consumer', siteKey, siteGeneration: 1,
          runtimeBundleCid: envelope.runtimeBundleCid, connectorRegistration: 'local',
          connectorRevision: 'local/1', strategyRevision: 'strategy/1',
          obligationsCid: physicalCid('resident-obligations'), budgetCid: siteControl.budgetIdentity(budget),
          evidenceIssuerCapabilityCid: issuerCapability, grantCid: operationCapability}, input);
      const consumerDispatch = siteControl.admitJson(issued.wire, issued.cid);
      await ensureOutputReceiver(consumerDispatch);
      const consumerEnvelope = coordinator.pollDispatchMaterialsJson(
        coordinator.admitDispatchJson(issued.wire, issued.cid), consumerBinding, 1048576, materials);
      let resultCid;
      if (retainedCancelBeforeConsumer) {
        const cancelled = await within(gateway.cancel({dispatch: consumerDispatch}),
          'cancel retained consumer before handout');
        assert.deepEqual(cancelled.state, [5, 0, 2, 0, 0]);
        const late = await within(gateway.dispatch({dispatch: consumerDispatch,
          inputBindingBody: consumerBinding, dispatchEnvelope: consumerEnvelope}),
          'cancelled consumer delayed exact dispatch');
        assert.deepEqual(late.state, cancelled.state);
        assert.equal(late.revision, cancelled.revision);
        for (let retry = 0; retry < 2; retry++) {
          const repeated = await within(gateway.cancel({dispatch: consumerDispatch}),
            'same cancelled consumer repeated');
          assert.deepEqual(repeated.state, cancelled.state);
          assert.equal(repeated.revision, cancelled.revision);
        }
        assert.equal((await entries()).length, 1, 'cancelled consumer must never enter its executor');
        assert.equal(reportState().reports.length, 0, 'no consumer Output may be fabricated');
      } else {
        await within(gateway.dispatch({dispatch: consumerDispatch, inputBindingBody: consumerBinding,
          dispatchEnvelope: consumerEnvelope}), 'retained consumer actual holder relay');
        const terminal = await settledQuery(consumerDispatch, 'retained consumer');
        assert.equal(siteControl.managedOutputSubjectProjection(terminal.subject)[4], retainedSourceSchemaCid);
        const output = await planOutput(consumerDispatch, terminal, 'retained-consumer');
        await within(requestOutput(consumerDispatch, output), 'retained consumer Output');
        const received = [];
        resultCid = transferControl.identity(output.planned.transferRequest);
        await receiver.consume(resultCid, () => true,
          (_index, frame) => received.push(Buffer.from(frame)));
        assert.deepEqual(JSON.parse(Buffer.concat(received).toString('utf8')), retainedSourceRows);
        assert.equal((await entries()).length, 2);
        await waitFor(() => reportState().pending === 0, 'retained consumer durable Output ACK');
        assert.equal(reportState().pending, 0, 'real typed Output ACK must be durably admitted');
        // Exact repeated delivery observes the original consumer; it must never
        // create another start claim or reacquire Source.
        await within(gateway.dispatch({dispatch: consumerDispatch, inputBindingBody: consumerBinding,
          dispatchEnvelope: consumerEnvelope}), 'retained consumer duplicate');
        assert.equal((await entries()).length, 2);
      }
      await within(gateway.release({dispatch: consumerDispatch}), 'retained consumer release');
      await within(gateway.release({dispatch: producerDispatch}), 'retained producer release');
      await waitFor(() => site.lines.some(line => line.kind === 'holder-released'), 'both task physical release');
      await waitFor(() => site.lines.some(line => line.kind === 'retained-holder-settled'),
        'both task Site reservations settled');
      const capacity = site.lines.find(line => line.kind === 'retained-holder-settled');
      for (const name of ['active_operations', 'active_transfers', 'holdings',
        'cleanup_responsibilities', 'held_bytes', 'reserved_retention_bytes',
        'reserved_execution_bytes']) assert.equal(capacity[name], '0', name);
      assert.deepEqual(await readdir(retainedRoot), [], 'receiver holding physically reclaimed');
      for (const dispatch of [producerDispatch, consumerDispatch]) {
        const released = await within(gateway.query({dispatch}), 'exact task released');
        assert.equal(released.state[2], 2);
      }
      assert.equal(reservedPayloadBytes(), 0);
      assert.equal(pendingIntents().length, 0);
      assert.equal((await entries()).length, retainedCancelBeforeConsumer ? 1 : 2);
      if (resultCid !== undefined) {
        const reread = [];
        await receiver.consume(resultCid, () => true,
          (_index, frame) => reread.push(Buffer.from(frame)));
        assert.deepEqual(JSON.parse(Buffer.concat(reread).toString('utf8')), retainedSourceRows);
      }
      site.child.kill('SIGTERM');
      await within(site.exited, 'retained consumer control shutdown');
      const database = new DatabaseSync(journalPath, {readOnly: true});
      try {
        const managed = database.prepare('SELECT CAST(body AS TEXT) AS body FROM actql_records WHERE namespace = ?')
          .all('site_managed_observation').map(row => JSON.parse(row.body));
        const sourceProofs = managed.filter(row => row.source_observation_json !== undefined);
        assert.equal(sourceProofs.length, 1, 'Source acquisition observation exactly once');
        assert.equal(JSON.parse(sourceProofs[0].source_observation_json).run_definition_cid, definition.identity);
      } finally { database.close(); }
      console.log(JSON.stringify({kind: 'native-retained-consumer-verified',
        runDefinitionCid: definition.identity, producerDispatchCid: siteControl.identity(producerDispatch),
        consumerDispatchCid: issued.cid, checkedTasks: 2, sourceAcquisitions: 1,
        producerEntries: 1, consumerEntries: retainedCancelBeforeConsumer ? 0 : 1,
        rows: retainedCancelBeforeConsumer ? [] : retainedSourceRows,
        typedOutputAck: !retainedCancelBeforeConsumer, formalRelease: true, reservedPayloadBytes: 0,
        pendingIntents: 0, siteCapacity: capacity,
        coordinatorReconstructed: retainedCoordinatorReconstruction,
        producerHolderRecreated: false,
        cancelledBeforeConsumer: retainedCancelBeforeConsumer,
        receiverHoldingReclaimed: true, resultReread: !retainedCancelBeforeConsumer,
        publicCloudAcceptance: false}));
    } else {
    // Both refusals must precede holder creation. A nonexistent physical
    // database makes an accidental acquisition observable as a different
    // failure, rather than silently reading the permitted test database.
    for (const [index, mode] of ['foreign-source', 'foreign-binding'].entries()) {
      const args = configured({'--source-database': join(root, 'not-created.duckdb'),
        ...(mode === 'foreign-source' ? {'--source-ref': 'connector://crm/main/other#v'} : {})});
      const rejecting = startSite(args);
      currentSite = rejecting;
      const foreignBody = mode === 'foreign-binding'
        ? JSON.stringify({source_contract_cid: sourceContractCid, source_ref: 'connector://crm/main/other#v'})
        : bindingBody;
      const foreignBinding = siteControl.prepareInputBinding(foreignBody);
      const dispatch = dispatchFor(`source-refusal-${mode}`, 90 + index,
        {inputBindingCid: siteControl.inputBindingIdentity(foreignBinding)});
      const envelope = coordinator.pollDispatchMaterialsJson(coordinator.admitDispatchJson(
        siteControl.requestJson(dispatch), siteControl.identity(dispatch)), foreignBody, 8192, materials);
      const outcome = gateway.dispatch({dispatch, inputBindingBody: foreignBody,
        dispatchEnvelope: envelope}).catch(error => error);
      await waitFor(() => rejecting.lines.some(line => line.kind === 'refused' &&
        line.reason === 'foreign-source'), mode);
      assert.equal(gateway.withdraw({dispatch}), true);
      assert.equal((await within(outcome, mode)).code, 'RemoteDispatchWithdrawn');
      assert.equal((await entries()).length, 0);
      assert.equal(rejecting.lines.some(line => line.kind === 'holder-started'), false);
      assert.equal(existsSync(join(root, 'not-created.duckdb')), false);
      rejecting.child.kill('SIGTERM');
      await rejecting.exited;
    }
    assert.deepEqual(runHost.taskExecutionShape(retainedPrepared, retainedCompilation),
      {taskCount: 1, acquisitionCount: 1});
    assert.deepEqual(runHost.taskResultSchema(retainedPrepared, retainedCompilation, 'answer').fields, ['id']);
    const site = startSite(extra);
    currentSite = site;
    const request = runHost.prepareTaskRequest(retainedPrepared, retainedCompilation,
      coordinatorAuthority, 'resident-source-request');
    const issued = runHost.issueTaskDispatch(retainedPrepared, retainedCompilation,
      retainedAdmission, retainedDefinition, request, 0, {
        taskAttempt: 1, dispatchId: 'resident-source-dispatch', siteKey, siteGeneration: 1,
        runtimeBundleCid: envelope.runtimeBundleCid, connectorRegistration: 'local',
        connectorRevision: 'local/1', strategyRevision: 'strategy/1',
        obligationsCid: physicalCid('resident-obligations'), budgetCid: siteControl.budgetIdentity(budget),
        evidenceIssuerCapabilityCid: issuerCapability, grantCid: operationCapability,
      });
    const dispatch = coordinator.admitDispatchJson(issued.wire, issued.cid);
    const sourceDispatch = dispatchFor('resident-source-dispatch', 1);
    assert.equal(siteControl.requestJson(sourceDispatch), issued.wire);
    await within(gateway.dispatch({dispatch: sourceDispatch, inputBindingBody: bindingBody,
      dispatchEnvelope: coordinator.pollDispatchMaterialsJson(dispatch, bindingBody, 8192, materials)}), 'Source dispatch');
    const terminal = await settledQuery(sourceDispatch, 'Source');
    const plan = await planOutput(sourceDispatch, terminal, 'source');
    const delivered = await within(requestOutput(sourceDispatch, plan), 'Source Output');
    const received = [];
    await receiver.consume(transferControl.identity(plan.planned.transferRequest),
      () => true, (_index, frame) => { received.push(Buffer.from(frame)); });
    assert.deepEqual(JSON.parse(Buffer.concat(received).toString('utf8')), sourceRows);
    assert.equal((await entries()).length, 1);
    // The common payload cleanup owner must retain the responsibility while
    // deletion is blocked; repairing permission must not execute again.
    await chmod(publicationRoot, 0o500);
    const releasing = within(gateway.release({dispatch: sourceDispatch}), 'Source release');
    try {
      await waitFor(() => site.lines.some(line => line.kind === 'cleanup-pending' &&
        line.step === 'payload'), 'Source cleanup pending');
      assert.ok(reservedPayloadBytes() > 0);
      assert.equal((await entries()).length, 1);
    } finally { await chmod(publicationRoot, 0o700); }
    await releasing;
    await waitFor(() => site.lines.some(line => line.kind === 'holder-released'), 'Source physical release');
    const released = await within(gateway.query({dispatch: sourceDispatch}), 'Source release query');
    assert.equal(released.state[2], 2);
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    assert.equal((await entries()).length, 1);
    // Physical release does not stop the control process's journal updates.
    // Confirm its exit before inspecting the final durable Source proof.
    site.child.kill('SIGTERM');
    await within(site.exited, 'Source control shutdown');
    const database = new DatabaseSync(journalPath, {readOnly: true});
    try {
      const managed = database.prepare('SELECT CAST(body AS TEXT) AS body FROM actql_records WHERE namespace = ?')
        .all('site_managed_observation').map(row => JSON.parse(row.body));
      const proof = managed.find(row => row.source_observation_json !== undefined);
      assert.ok(proof, 'physical Source observation must share the managed Output transaction');
      const observation = JSON.parse(proof.source_observation_json);
      assert.equal(observation.run_definition_cid, definition.identity);
      assert.equal(observation.dispatch_request_cid, issued.cid);
      assert.equal(observation.task_ordinal, 0);
      assert.equal(proof.source_observation_json.includes(databasePath), false);
      const checkedSource = runHost.sourceEvidenceFacts(retainedPrepared, 0, 0);
      const invocation = runHost.issueTaskInvocation(retainedPrepared, retainedCompilation,
        retainedAdmission, retainedDefinition, {
          sourceEvidenceWire: observation.source_evidence_wire,
          inputLogicalWire: observation.input_logical_wire,
          sourceRef: checkedSource.sourceRef, sourceContractCid: checkedSource.sourceContractCid,
          authorityScopeCid: coordinatorAuthority, dataPolicyCid: checkedSource.sourceDataPolicyCid,
          captureStartedAt: observation.capture_started_at,
          captureCompletedAt: observation.capture_completed_at,
        }, {maxWireBytes: 100000, maxNodes: 10000, maxDepth: 64});
      assert.equal(JSON.parse(invocation.observation.wire).source_evidence_cids.length, 1);
    } finally { database.close(); }
    console.log(JSON.stringify({kind: 'native-resident-source-verified', runDefinitionCid: definition.identity,
      dispatchRequestCid: issued.cid, checkedTasks: 1, executorEntries: 1, rows: sourceRows,
      outputDelivered: !!delivered, formalRelease: true, reservedPayloadBytes: 0, pendingIntents: 0,
      publicClientAcceptance: false}));
    // Missing physical table is an acquisition failure after the ordinary
    // exclusive start claim. Query/release never retry the provider.
    const failing = startSite(configured({'--source-table': 'not_created'}));
    currentSite = failing;
    const failed = dispatchFor('source-acquisition-failed', 3);
    await within(gateway.dispatch({dispatch: failed, inputBindingBody: bindingBody,
      dispatchEnvelope: materialsEnvelope(failed)}), 'failing Source');
    await waitFor(async () => (await within(gateway.query({dispatch: failed}), 'failed Source query')).state[0] === 4,
      'Source acquisition failure');
    assert.equal((await entries()).length, 2);
    await within(gateway.release({dispatch: failed}), 'failed Source release');
    const failureState = await within(gateway.query({dispatch: failed}), 'failed Source final state');
    assert.equal(failureState.state[0], 4);
    assert.equal(failureState.state[2], 2);
    assert.equal((await entries()).length, 2);
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    console.log(JSON.stringify({kind: 'native-resident-source-negatives-verified',
      refusalsBeforeIO: 2, acquisitionFailureEntries: 1,
      cleanupPendingRecovered: true, reservedPayloadBytes: 0, pendingIntents: 0}));
    failing.child.kill('SIGTERM');
    await failing.exited;
    }
  } else if (process.argv.includes('--release-recovery-only') || releaseMaintenanceMode) {
    // The same physical Site and journals must discharge release after a
    // bounded failure, a lost control reply, and loss of the live holder.
    const releaseModes = releaseMaintenanceMode ? ['maintenance'] :
      ['release-failure', 'lost-release', 'holder-exit', 'recovery-interrupted', 'maintenance'];
    for (const [index, mode] of releaseModes.entries()) {
      let lostRelease = false;
      if (mode === 'lost-release') {
        ackLossProxy = await observationAckLossProxy({origin: gateway.origin,
          key: await readFile(join(root, 'server.key')),
          cert: await readFile(join(root, 'server.crt')),
          ca: await readFile(join(root, 'ca.crt')),
          loseAck: () => false, allowDispatch: () => true, onAckLost: () => {},
          transformReply: (_body, upstream) => {
            if (!lostRelease && upstream.status === 200 &&
                JSON.parse(upstream.body.toString('utf8')).version === 'actql-remote-poll-release/0.1') {
              lostRelease = true;
              return {status: 204, body: ''};
            }
            return upstream;
          }});
      }
      let site = startSite(mode === 'release-failure' ? ['--holder-release-failures', '3'] :
        mode === 'maintenance' ? ['--holder-kill-at', 'report-handoff'] :
        mode === 'holder-exit' ? ['--holder-kill-at', 'report-handoff', '--release-recovery-close-failures', '1'] :
          mode === 'recovery-interrupted' ? ['--holder-kill-at', 'report-handoff', '--release-recovery-kill-at', 'after-transition'] : [],
      {controlOrigin: mode === 'lost-release' ? ackLossProxy.origin : gateway.origin});
      currentSite = site;
      const dispatch = dispatchFor(`resident-release-recovery-${mode}`, 200 + index);
      await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
        dispatchEnvelope: materialsEnvelope(dispatch)}), `${mode} dispatch`);
      await waitFor(async () => (await entries()).length === index + 1, `${mode} entry`);
      const terminal = await settledQuery(dispatch, mode);
      await within(requestOutput(dispatch, await planOutput(dispatch, terminal, mode)), `${mode} output`);
      let released = gateway.release({dispatch}).catch(error => error);
      if (mode === 'holder-exit' || mode === 'recovery-interrupted' || mode === 'maintenance') {
        await waitFor(() => site.lines.some(line => line.kind === 'holder-killed'), 'holder exit');
        await waitFor(() => pendingIntents().length === 0 && reservedPayloadBytes() === 0,
          'orphan physical cleanup');
      }
      if (mode === 'lost-release') {
        await waitFor(() => lostRelease, 'lost release response');
        gateway.withdraw({dispatch});
        await released;
        released = gateway.release({dispatch});
      }
      await within(released, `${mode} release`);
      if (mode === 'maintenance') {
        await waitFor(() => reportState().pending === 0, 'maintenance durable Output ACK');
        site.child.kill('SIGTERM');
        await site.exited;
        const savedAttempt = site.lines.find(line => line.kind === 'accepted' &&
          line.request_cid === siteControl.identity(dispatch)).attempt;
        const beforeJournal = new DatabaseSync(journalPath, {readOnly: true});
        const beforeBundles = new DatabaseSync(join(runtimeRoot, '.actql-runtime-bundle.sqlite3'), {readOnly: true});
        try {
          const saved = JSON.parse(Buffer.from(beforeJournal.prepare(
            'SELECT body FROM actql_records WHERE namespace=? AND record_key=?')
            .get('site_dispatch', savedAttempt).body).toString('utf8'));
          assert.equal(saved.cleanup_state, 0, 'operator recovery starts from CleanupActive');
          const catalog = JSON.parse(Buffer.from(beforeBundles.prepare(
            'SELECT body FROM actql_records WHERE namespace=? AND record_key=?')
            .get('runtime_bundle', 'catalog').body).toString('utf8'));
          assert.equal(catalog.entries.flatMap(entry => entry.holds).length, 2,
            'the stopped holder and original dispatch still own their bundle holdings');
        } finally { beforeJournal.close(); beforeBundles.close(); }
        // Simulate an upgraded operator binary, preserving the old installed
        // component and its exact journal identity. This operator cannot
        // enter execute without its inherited slot; cleanup acquires no
        // execution binding and does not alter executable attestation.
        const maintenanceExecutable = join(root, 'maintenance.exe');
        await writeFile(maintenanceExecutable, Buffer.concat([
          await readFile(executable), Buffer.from('\nmaintenance-test-binary\n')]), {mode: 0o700});
        assert.notEqual(physicalCid(await readFile(maintenanceExecutable)), componentCid);
        const operate = async (operation, requestCid = siteControl.identity(dispatch)) => {
          const args = operation === 'recover-release' ?
            [operation, '--attempt', savedAttempt, '--expect-dispatch', requestCid, ...common] :
            [operation, '--attempt', savedAttempt, '--claimant', 'maintenance-must-not-execute', ...common];
          const process = spawn(maintenanceExecutable, args, {cwd: root,
            stdio: ['ignore', 'pipe', 'pipe']});
          running.add(process);
          const closed = once(process, 'close');
          let stdout = '', stderr = '';
          process.stdout.on('data', chunk => { stdout += chunk; });
          process.stderr.on('data', chunk => { stderr += chunk; });
          try {
            const [code] = await within(closed, 'maintenance bounded completion');
            return {code, stdout, stderr};
          } finally {
            if (process.exitCode === null && process.signalCode === null) {
              process.kill('SIGKILL'); await closed;
            }
            running.delete(process);
          }
        };
        const mismatch = await operate('execute');
        assert.notEqual(mismatch.code, 0);
        assert.match(mismatch.stdout, /executor slot is not held/u);
        const foreign = await operate('recover-release', physicalCid('foreign-dispatch'));
        assert.notEqual(foreign.code, 0);
        assert.match(foreign.stdout, /dispatch-mismatch/u);
        const firstObservation = gateway.query({dispatch});
        const recovered = await operate('recover-release');
        assert.equal(recovered.code, 0, recovered.stderr);
        assert.match(recovered.stdout, /release-recovery-observed/u);
        const first = await within(firstObservation, 'maintenance formal observation');
        for (let retry = 0; retry < 2; retry++) {
          const nextObservation = gateway.query({dispatch});
          const repeated = await operate('recover-release');
          assert.equal(repeated.code, 0, repeated.stderr);
          const snapshot = await within(nextObservation, 'maintenance repeated observation');
          assert.equal(snapshot.state[2], 2);
          assert.equal(snapshot.revision, first.revision);
          assert.equal((await entries()).length, index + 1);
        }
        // Query/release waiters below are serviced by the ordinary control
        // process, with the unchanged original installed executable.
        site = startSite(); currentSite = site;
      }
      if (mode === 'holder-exit') {
        const pending = await within(gateway.release({dispatch}), 'recovery close failure');
        assert.equal(pending.state[2], 0, 'close failure must not publish Released');
        await within(gateway.release({dispatch}), 'recover stopped holder release');
      }
      if (mode === 'recovery-interrupted') {
        const interrupted = gateway.release({dispatch}).catch(error => error);
        assert.deepEqual(await within(site.exited, 'recovery interrupted after durable transition'), [null, 'SIGKILL']);
        assert(site.lines.some(line => line.kind === 'release-recovery-killed'));
        gateway.withdraw({dispatch});
        await interrupted;
        site = startSite();
        currentSite = site;
        await within(gateway.release({dispatch}), 'resumed recovery');
      }
      const observed = await within(gateway.query({dispatch}), `${mode} cleanup observation`);
      assert.equal(observed.state[2], 2, `${mode}: physical cleanup must have a formal Released observation`);
      assert(Number.isSafeInteger(observed.revision), 'the durable revision must be present');
      await waitFor(() => reservedPayloadBytes() === 0 && pendingIntents().length === 0,
        `${mode} resource zero`);
      for (let retry = 0; retry < 2; retry++) {
        const repeated = await within(gateway.release({dispatch}), `${mode} repeated release`);
        assert.equal(repeated.state[2], 2);
        assert.equal(repeated.revision, observed.revision, 'release retry must not advance the durable revision');
        assert.equal((await entries()).length, index + 1);
        assert.equal(reservedPayloadBytes(), 0);
        assert.equal(pendingIntents().length, 0);
      }
      const bundles = new DatabaseSync(join(runtimeRoot, '.actql-runtime-bundle.sqlite3'), {readOnly: true});
      try {
        const catalog = JSON.parse(Buffer.from(bundles.prepare(
          'SELECT body FROM actql_records WHERE namespace=? AND record_key=?').get('runtime_bundle', 'catalog').body).toString('utf8'));
        assert.deepEqual(catalog.entries.flatMap(entry => entry.holds), [], 'no dispatch, holder, or recovery bundle holding remains');
      } finally { bundles.close(); }
      console.log(JSON.stringify({kind: 'resident-release-case', mode,
        dispatchCid: siteControl.identity(dispatch), executorEntries: index + 1,
        cleanup: observed.state[2], pendingIntents: 0, reservedPayloadBytes: 0}));
      site.child.kill('SIGTERM');
      await site.exited;
      if (ackLossProxy) { await ackLossProxy.close(); ackLossProxy = undefined; }
    }
  } else if (process.argv.includes('--output-report-only')) {
    // Exercise the complete report path with the real native holder and the
    // existing Coordinator/SQLite owner. The proxy drops only the first
    // typed ACK; no receipt map or synthetic result is used.
    const coordinatorRoot = join(root, 'coordinator-output-report');
    const authorization = await allowAllAuthorization();
    let dropOutputAck = true;
    let invalidAck;
    let holdOutputReply;
    const invalidAckCases = [];
    const reportBodies = [];
    ackLossProxy = await observationAckLossProxy({
      origin: gateway.origin,
      key: await readFile(join(root, 'server.key')),
      cert: await readFile(join(root, 'server.crt')),
      ca: await readFile(join(root, 'ca.crt')),
      loseAck: body => {
        const hint = JSON.parse(body);
        return dropOutputAck && hint.version === 'actql-remote-output-result/0.1';
      },
      allowDispatch: () => true,
      onAckLost: body => {
        if (reportBodies.length === 0) reportBodies.push(body);
      },
      transformReply: async (body, upstream) => {
        if (holdOutputReply !== undefined &&
            JSON.parse(body).version === 'actql-remote-output-result/0.1') {
          return holdOutputReply(upstream);
        }
        if (invalidAck === undefined ||
            JSON.parse(body).version !== 'actql-remote-output-result/0.1') return upstream;
        invalidAckCases.push(invalidAck.name);
        return invalidAck.reply(upstream);
      },
    });
    const openOutputReceiver = () => {
      observationStore = openSqliteCoordinatorDispatchJournal(coordinatorRoot,
        {coordinatorAuthority: 'cloud-coordinator', maxDeliveryBytes: 1_048_576});
      observationReceiver = createRemoteSiteCoordinator({
        control: siteControl,
        journal: siteControl.createCoordinatorJournal('cloud-coordinator'),
        store: observationStore,
        authorization,
        send: value => gateway.dispatch(value),
        query: value => gateway.query(value),
        cancel: value => gateway.cancel(value),
        release: value => gateway.release(value),
        output: value => gateway.output(value),
        transferControl,
      });
    };
    openOutputReceiver();
    crashOutputReceiver = async value => {
      const inputPath = join(root, 'receiver-crash-input.json');
      await writeFile(inputPath, JSON.stringify(value));
      const child = spawn(process.execPath, [join(repository,
        'scripts/fixtures/output-report-receiver-crash.mjs'), join(repository,
        '_build/js/release/build/connectors_builtin_node/connectors_builtin_node.js'),
      coordinatorRoot, inputPath], {stdio: ['ignore', 'pipe', 'pipe']});
      running.add(child);
      let diagnostics = '';
      child.stderr.on('data', chunk => { diagnostics += chunk; });
      const exit = await within(once(child, 'exit'), 'durable receiver abrupt exit');
      running.delete(child);
      assert.deepEqual(exit, [null, 'SIGKILL'], diagnostics);
    };
    let site = startSite(['--holder-kill-at', 'report-handoff'], {
      controlOrigin: gateway.origin,
      observationOrigin: ackLossProxy.origin,
    });
    currentSite = site;
    const dispatch = dispatchFor('resident-output-report-custody', 1);
    const dispatched = await within(observationReceiver.dispatch({
      dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch),
    }), 'output report dispatch');
    assert.ok(dispatched);
    await waitFor(async () => (await entries()).length === 1,
      'output report executor');
    const terminal = await settledQuery(dispatch, 'output report terminal');
    const planned = await planOutput(dispatch, terminal, 'output-report-custody');
    const delivered = await within(observationReceiver.output({
      dispatch, intent: planned.intent, subject: terminal.subject,
      payloadRequest: planned.planned.payloadRequest,
      transferRequest: planned.planned.transferRequest,
    }), 'output report delivery');
    assert.ok(delivered);
    await within(observationReceiver.release({dispatch}), 'output report release');
    await waitFor(() => reportBodies.length === 1,
      'first output ACK loss');
    await waitFor(() => site.lines.some(line =>
      line.kind === 'holder-killed' && line.point === 'report-handoff'),
    'output report handoff holder exit');
    assert.equal((await entries()).length, 1);
    await waitFor(() => reservedPayloadBytes() === 0 &&
      pendingIntents().length === 0, 'output report cleanup after holder exit');
    const firstReport = reportBodies[0];
    assert.equal(reportState().pending, 1, 'physical release does not acknowledge the report');
    site.child.kill('SIGTERM');
    await site.exited;
    dropOutputAck = false;
    observationStore.close();
    openOutputReceiver();
    const originalReceiverFact = observationStore.inspectOutput(
      observationReceiver.recoveredOutputs[0].record, siteControl);
    for (const invalid of [
      {name: 'legacy-200', reply: () => ({status: 200, body: '{"accepted":true}'})},
      {name: 'empty-200', reply: () => ({status: 200, body: ''})},
      {name: 'malformed-200', reply: () => ({status: 200, body: '{'})},
      {name: 'different-report', reply: upstream => ({status: 200,
        body: upstream.body.toString('utf8').replace(
          JSON.parse(upstream.body).report_cid, physicalCid('different-report'))})},
      {name: 'unconfirmed-503', reply: upstream => ({...upstream, status: 503})},
    ]) {
      invalidAck = invalid;
      site = startSite(['--max-polls', '3'], {controlOrigin: gateway.origin,
        observationOrigin: ackLossProxy.origin});
      currentSite = site;
      assert.deepEqual(await within(site.exited, `${invalid.name} response`), [0, null]);
      assert.ok(invalidAckCases.includes(invalid.name), 'fault reached the real native client');
      assert.equal(reportState().pending, 1, `${invalid.name} must not acknowledge the report`);
      assert.equal(reservedPayloadBytes(), 0);
      assert.equal(pendingIntents().length, 0);
    }
    invalidAck = undefined;
    // A typed, exact refusal is attention, not success and not an HTTP-code
    // inference. The operator command re-enables only this original report.
    invalidAck = {name: 'checked-refusal', reply: upstream => {
      const fields = JSON.parse(upstream.body);
      fields.outcome = 'refused';
      fields.reason = 'authorization_denied';
      return {status: 409, body: JSON.stringify(fields)};
    }};
    site = startSite(['--max-polls', '3'], {controlOrigin: gateway.origin,
      observationOrigin: ackLossProxy.origin});
    currentSite = site;
    assert.deepEqual(await within(site.exited, 'checked refusal'), [0, null]);
    assert.equal(reportState().pending, 1);
    const inspection = execFileSync(executable, [...common, 'output-reports'], {encoding: 'utf8'})
      .trim().split('\n').map(line => JSON.parse(line));
    const attention = inspection.find(line => line.kind === 'output-report-state');
    assert.equal(attention.state, 'attention');
    assert.equal(attention.reason, 'authorization_denied');
    execFileSync(executable, [...common, 'retry-output-report', '--intent-cid',
      attention.intent_cid], {stdio: 'pipe'});
    invalidAck = undefined;
    const initialReportCount = observationBodies.filter(body =>
      JSON.parse(body).version === 'actql-remote-output-result/0.1').length;
    // The report is recovered from the Coordinator journal, while the Site
    // journal independently replays the exact bytes after its restart.
    site = startSite(['--control-report-kill-at', 'before-ack-save'],
      {controlOrigin: gateway.origin});
    currentSite = site;
    assert.deepEqual(await within(site.exited, 'before ACK save abrupt exit'), [null, 'SIGKILL']);
    assert.ok(site.lines.some(line => line.kind === 'control-report-killed' &&
      line.point === 'before-ack-save'));
    assert.equal(reportState().pending, 1, 'ACK received without a commit remains pending');
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    // Two real control processes recover the same saved report. Hold the
    // first ACK until the second has durably saved it, then deliver the late
    // ACK. Release is already physically complete; neither replay may reopen
    // payload custody or consume another ACK revision.
    let releaseHeldAck;
    let firstAckArrived;
    const heldAck = new Promise(resolve => { releaseHeldAck = resolve; });
    const firstAck = new Promise(resolve => { firstAckArrived = resolve; });
    let parallelReplies = 0;
    holdOutputReply = async upstream => {
      if (++parallelReplies === 1) {
        firstAckArrived();
        await heldAck;
      }
      return upstream;
    };
    const lateSite = startSite(['--control-report-kill-at', 'after-ack-save'],
      {controlOrigin: gateway.origin, observationOrigin: ackLossProxy.origin});
    currentSite = lateSite;
    await within(firstAck, 'first parallel report ACK held');
    site = startSite(['--control-report-kill-at', 'after-ack-save'],
      {controlOrigin: gateway.origin, observationOrigin: ackLossProxy.origin});
    currentSite = site;
    assert.deepEqual(await within(site.exited, 'second replay ACK save abrupt exit'), [null, 'SIGKILL']);
    assert.ok(site.lines.some(line => line.kind === 'control-report-killed' &&
      line.point === 'after-ack-save'));
    assert.equal(reportState().pending, 0, 'committed ACK survives abrupt exit');
    const savedAckState = reportState();
    releaseHeldAck();
    assert.deepEqual(await within(lateSite.exited, 'late replay ACK save abrupt exit'), [null, 'SIGKILL']);
    assert.ok(lateSite.lines.some(line => line.kind === 'control-report-killed' &&
      line.point === 'after-ack-save'));
    assert.equal(parallelReplies, 2, 'both real processes posted the original report');
    assert.deepEqual(reportState(), savedAckState, 'late ACK does not change durable custody or revision');
    holdOutputReply = undefined;
    const replayCount = observationBodies.filter(body =>
      JSON.parse(body).version === 'actql-remote-output-result/0.1').length;
    site = startSite(['--max-polls', '3'], {controlOrigin: gateway.origin});
    currentSite = site;
    assert.deepEqual(await within(site.exited, 'ACK-confirmed restart'), [0, null]);
    assert.equal(observationBodies.filter(body =>
      JSON.parse(body).version === 'actql-remote-output-result/0.1').length, replayCount,
    'confirmed ACK is not posted again after restart');
    await waitFor(() => observationBodies.filter(body =>
      JSON.parse(body).version === 'actql-remote-output-result/0.1').length >= 2,
      'replayed output report body');
    // Replay reuses the already terminal Coordinator fact and the retained
    // report; it must not start a new holder. Physical release was confirmed
    // before the first Site process was stopped.
    assert.equal(observationStore.inspectOutput(
      observationReceiver.recoveredOutputs[0].record, siteControl).progress, 2);
    assert.equal((await entries()).length, 1);
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    assert.equal(reportState().pending, 0);
    assert.deepEqual((await readdir(publicationRoot)).filter(name => name.startsWith('alloc-')), [],
      'physical allocation directories are gone independently of report custody');
    assert.deepEqual(observationStore.inspectOutput(
      observationReceiver.recoveredOutputs[0].record, siteControl), originalReceiverFact,
    'ACK-only replays do not alter receiver state or revision');
    const outputBodies = observationBodies.filter(body =>
      JSON.parse(body).version === 'actql-remote-output-result/0.1');
    assert.equal(outputBodies.length, initialReportCount + 3);
    for (const body of outputBodies) assert.equal(body, firstReport);
    assert.deepEqual(outputBodies[0], firstReport);
    console.log(JSON.stringify({kind: 'resident-output-report-custody-verified',
      runDefinitionCid: definition.identity,
      dispatchRequestCid: siteControl.identity(dispatch), executorEntries: 1,
      ackLostAfterDurableAdmission: true, coordinatorReconstructed: true,
      receiverKilledAfterDurableAdmission: true,
      invalidAckCases: [...new Set(invalidAckCases)],
      checkedRefusalAndExplicitRetry: true,
      concurrentReplayAndLateAck: true,
      releaseBeforeAck: true, reportBytesReplayedExactly: true,
      ackSaveStopPoints: ['before-ack-save', 'after-ack-save'],
      receiverFactUnchanged: true, reservedPayloadBytes: 0,
      pendingOutputIntents: 0, pendingOutputReports: 0}));
  } else if (process.argv.includes('--redelivery-only')) {
    const coordinatorRoot = join(root, 'coordinator-redelivery');
    const authorization = await allowAllAuthorization();
    let blockDispatch = false;
    let loseDispatchCid;
    let lostBody;
    let loseTerminal;
    const terminalAckLosses = [];
    const lostBodies = [];
    ackLossProxy = await observationAckLossProxy({origin: gateway.origin,
      key: await readFile(join(root, 'server.key')),
      cert: await readFile(join(root, 'server.crt')), ca: await readFile(join(root, 'ca.crt')),
      loseAck: body => {
        const hint = JSON.parse(body);
        if (hint.dispatch_request_cid === loseDispatchCid) return true;
        if (loseTerminal === undefined || hint.dispatch_request_cid !== siteControl.identity(loseTerminal)) return false;
        const admitted = siteControl.admitResponseJson(body, loseTerminal,
          hint.version === 'actql-remote-dispatch-status/0.1');
        return siteControl.responseProjection(admitted)[1] === 3;
      },
      allowDispatch: () => !blockDispatch,
      onAckLost: body => {
        if (JSON.parse(body).dispatch_request_cid !== loseDispatchCid) {
          terminalAckLosses.push(body);
          loseTerminal = undefined;
          return;
        }
        loseDispatchCid = undefined;
        lostBody = body;
        lostBodies.push(body);
        blockDispatch = true;
      }});
    const currentContext = (dispatch, body) => {
      // The existing issuer projected these immutable bytes from the original
      // admitted Run. Its Run owner, not received materials, is the expectation.
      assert.equal(JSON.parse(siteControl.requestJson(dispatch)).run_definition_cid,
        runHost.privateRunDefinition(retainedDefinition).cid);
      assert.equal(body, materialsEnvelope(dispatch));
      return {coordinatorAuthority: 'cloud-coordinator', siteKey, siteGeneration: 1,
        // Never refresh original expiry. Native receipt/start recheck the
        // admitted Run/authorization owners at their current trusted clock.
        authorizationCurrent: Date.now() < now + 3_600_000,
        cancellationRequested: false};
    };
    let beforeSend;
    let sends = 0;
    const openCoordinator = () => {
      observationStore = openSqliteCoordinatorDispatchJournal(coordinatorRoot,
        {coordinatorAuthority: 'cloud-coordinator', maxDeliveryBytes: 1_048_576});
      observationReceiver = createRemoteSiteCoordinator({control: siteControl,
        journal: siteControl.createCoordinatorJournal('cloud-coordinator'),
        store: observationStore, authorization, currentDispatchContext: currentContext,
        query: gateway.query, release: gateway.release,
        output: value => gateway.output(value), transferControl,
        send: async value => {
          assert.equal(value.dispatchEnvelope, observationStore.deliveryEnvelope(value.dispatch, siteControl));
          sends++;
          if (beforeSend !== undefined) await beforeSend(value);
          blockDispatch = false;
          return gateway.dispatch(value);
        }});
    };
    openCoordinator();
    // The Site reports a record only to an exact arrival or a query. Holding
    // the executor after it starts makes a redelivered arrival observe Running
    // and settle the recovery before execution ends, as on a slow runner; the
    // terminal record is then reported only to the Coordinator's query.
    const site = startSite(['--holder-pause-ms', '1000'],
      {controlOrigin: ackLossProxy.origin});
    currentSite = site;
    const loseAcceptance = async (dispatch, previousEntries) => {
      loseDispatchCid = siteControl.identity(dispatch);
      lostBody = undefined;
      blockDispatch = false;
      const failures = site.lines.filter(line => line.kind === 'accept-failed' &&
        line.reason === 'client-transport').length;
      const publicRequest = coordinator.admitDispatchJson(siteControl.requestJson(dispatch),
        siteControl.identity(dispatch));
      const originalEnvelope = coordinator.deliveryEnvelopeJson(publicRequest, materialsEnvelope(dispatch));
      const pending = observationReceiver.dispatch({dispatch, inputBindingBody: '{}',
        dispatchEnvelope: originalEnvelope}).catch(error => error);
      await waitFor(() => lostBody !== undefined && site.lines.filter(line =>
        line.kind === 'accept-failed' && line.reason === 'client-transport').length > failures,
      'lost durable acceptance ACK');
      assert.equal((await entries()).length, previousEntries);
      assert.equal(observationStore.inspectState(dispatch, siteControl)[3], 0);
      // Public package decisions are checked with an actual native response,
      // not hand-authored Accepted bytes or a second executor/state machine.
      const initial = coordinator.prepareIntent(coordinator.createJournal('cloud-coordinator'), publicRequest);
      const durable = coordinator.admitDurableJson(coordinator.admissionDurableJson(initial));
      const record = coordinator.commitIntent(initial);
      const response = coordinator.admitResponseJson(lostBody, publicRequest, false);
      const transition = coordinator.prepareResponseObservation(record, response);
      const observed = coordinator.admitDurableJson(coordinator.responseDurableJson(durable, transition, response));
      const restored = coordinator.restoreDurable(coordinator.createJournal('cloud-coordinator'), observed);
      assert.equal(coordinator.redeliveryEligible(restored, publicRequest, '', currentContext(dispatch, originalEnvelope)), true);
      assert.equal(gateway.withdraw({dispatch}), true);
      assert.equal((await within(pending, 'lost initial dispatch')).code, 'RemoteDispatchWithdrawn');
      return lostBody;
    };
    const first = dispatchFor('r2-ack-loss-concurrent', 1);
    const firstAccepted = await loseAcceptance(first, 0);
    observationStore.close();
    openCoordinator();
    loseTerminal = first;
    let parallelSends = 0;
    let permitParallelSend;
    const parallelSendBarrier = new Promise(resolve => { permitParallelSend = resolve; });
    beforeSend = async () => {
      if (++parallelSends === 2) permitParallelSend();
      await parallelSendBarrier;
    };
    // Both recoveries query the durable Accepted record, then exact delivery
    // converges on the same existing Site admission/start claim.
    const recovered = await within(Promise.all([
      observationReceiver.recoverDispatch({dispatch: first}),
      observationReceiver.recoverDispatch({dispatch: first}),
    ]), 'R2 concurrent exact recovery');
    assert.ok(recovered.every(value => value.action === 'redelivered'));
    assert.equal(parallelSends, 2);
    beforeSend = undefined;
    await waitFor(async () => (await entries()).length === 1, 'R2 first executor entry');
    // Whether a late arrival or this query carries the terminal record, the
    // Coordinator durably admits it and exactly that first ACK is lost. The
    // query resolves before the proxy sees the 200 it then drops.
    const firstTerminal = await settledQuery(first, 'R2 first terminal');
    await waitFor(() => terminalAckLosses.length === 1, 'R2 terminal ACK loss after execution');
    const terminalState = observationStore.inspectState(first, siteControl);
    observationReceiver.receiveObservation({body: firstAccepted, binding: {siteKey, siteGeneration: 1}});
    assert.deepEqual(observationStore.inspectState(first, siteControl), terminalState);
    assert.equal((await observationReceiver.recoverDispatch({dispatch: first})).action, 'reconciled');
    await deliverAndRelease(first, firstTerminal, 'r2-first');
    await waitFor(() => site.lines.some(line => line.kind === 'holder-released'), 'R2 first physical release');

    const second = dispatchFor('r2-start-before-redelivery', 2);
    const secondAccepted = await loseAcceptance(second, 1);
    let raced = false;
    let parallelDispatch;
    beforeSend = async value => {
      if (raced) return;
      raced = true;
      // The common owner already checked Accepted. A transport delay permits
      // another exact arrival to start the Site before this arrival reaches it.
      blockDispatch = false;
      parallelDispatch = gateway.dispatch(value);
      await waitFor(async () => (await entries()).length === 2,
        'R2 start after Accepted query before recovered delivery');
    };
    const racedRecovery = await within(observationReceiver.recoverDispatch({dispatch: second}),
      'R2 Accepted/start arrival race');
    assert.equal(racedRecovery.action, 'redelivered');
    await within(parallelDispatch, 'R2 competing exact arrival');
    beforeSend = undefined;
    const secondTerminal = await settledQuery(second, 'R2 second terminal');
    const state = observationStore.inspectState(second, siteControl);
    observationReceiver.receiveObservation({body: secondAccepted, binding: {siteKey, siteGeneration: 1}});
    assert.deepEqual(observationStore.inspectState(second, siteControl), state);
    await deliverAndRelease(second, secondTerminal, 'r2-second');
    await waitFor(() => site.lines.filter(line => line.kind === 'holder-released').length === 2,
      'R2 final physical release');
    // Physical release does not stop the control process's journal updates.
    // Close that process before inspecting the final durable occurrence counts;
    // a read-only connection otherwise races its SQLite commit lock on Linux.
    site.child.kill('SIGTERM');
    await site.exited;
    assert.equal((await entries()).length, 2);
    assert.equal(new Set((await entries()).map(line => line.split(' ').at(-1))).size, 2);
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    const nativeJournal = new DatabaseSync(journalPath, {readOnly: true});
    try {
      for (const namespace of ['site_dispatch', 'site_start_claim']) {
        assert.equal(nativeJournal.prepare('SELECT COUNT(*) AS count FROM actql_records WHERE namespace = ?')
          .get(namespace).count, 2, `${namespace}: one durable occurrence per attempt`);
      }
    } finally { nativeJournal.close(); }
    assert.equal(lostBodies.length, 2);
    assert.ok(sends >= 4);
    console.log(JSON.stringify({kind: 'resident-exact-redelivery-verified',
      runDefinitionCid: definition.identity,
      dispatches: [first, second].map(siteControl.identity),
      executorEntries: 2, acceptedAckLosses: 2, terminalAckLosses: 1,
      coordinatorRecreated: true, concurrentRedelivery: true,
      startedBetweenQueryAndArrival: true, historicalAcceptedDoesNotRewind: true,
      reservedPayloadBytes: 0, pendingOutputIntents: 0}));
  } else if (process.argv.includes('--observation-replay-only')) {
    // R1's receiver is the existing Coordinator owner/journal, not a test
    // receipt map. The retained bodies below are actual native Site reports;
    // their authority is checked again by the gateway on each HTTPS request.
    const dispatch = dispatchFor('resident-observation-replay', 1);
    const coordinatorRoot = join(root, 'coordinator-observations');
    const openObservationReceiver = () => {
      observationStore = openSqliteCoordinatorDispatchJournal(coordinatorRoot,
        {coordinatorAuthority: 'cloud-coordinator'});
      observationReceiver = createRemoteSiteCoordinator({control: siteControl,
        journal: siteControl.createCoordinatorJournal('cloud-coordinator'),
        store: observationStore});
    };
    observationStore = openSqliteCoordinatorDispatchJournal(coordinatorRoot,
      {coordinatorAuthority: 'cloud-coordinator'});
    observationStore.accept(siteControl.prepareCoordinatorIntent(
      siteControl.createCoordinatorJournal('cloud-coordinator'), dispatch),
    dispatch, siteControl);
    observationStore.close();
    openObservationReceiver();
    const site = startSite();
    currentSite = site;
    await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), 'R1 native dispatch');
    await waitFor(async () => (await entries()).length === 1, 'R1 native executor');
    await settledQuery(dispatch, 'R1 native settled');
    const savedState = observationStore.inspectState(dispatch, siteControl);
    const firstBody = observationBodies[0];
    const latestBody = observationBodies.at(-1);
    const observationCa = await readFile(join(root, 'ca.crt'));
    assert.ok(firstBody && latestBody && firstBody !== latestBody);
    const submitObservation = (body, loseAck = false) => new Promise((resolve, reject) => {
      const request = httpsRequest(new URL(
        `/v1/sites/${siteKey}/generations/1/outbound/observations`, gateway.origin),
      {method: 'POST', ca: observationCa, headers: {
        authorization: `Bearer ${token}`, 'content-type': 'application/json',
        'content-length': Buffer.byteLength(body),
      }}, response => {
        if (loseAck) {
          assert.equal(response.statusCode, 200);
          // Drop the actual HTTPS response after durable admission, not before
          // a handler or a test-only counter claims that admission occurred.
          response.destroy(new Error('R1_ACK_LOST'));
          resolve('lost');
        } else {
          response.resume();
          response.once('end', () => resolve(response.statusCode));
        }
        response.on('error', error => { if (!loseAck) reject(error); });
      });
      request.on('error', reject);
      request.end(body);
    });
    assert.equal(await submitObservation(firstBody, true), 'lost');
    assert.deepEqual(observationStore.inspectState(dispatch, siteControl), savedState);
    observationStore.close();
    openObservationReceiver();
    for (const body of [firstBody, latestBody]) {
      assert.equal(await submitObservation(body), 200);
      assert.deepEqual(observationStore.inspectState(dispatch, siteControl), savedState);
      assert.equal((await entries()).length, 1);
    }
    await within(gateway.release({dispatch}), 'R1 physical release');
    await waitFor(() => site.lines.some(line => line.kind === 'holder-released'),
      'R1 holder released');
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    assert.equal((await entries()).length, 1);
    console.log(JSON.stringify({kind: 'resident-observation-replay-verified',
      dispatchRequestCid: siteControl.identity(dispatch),
      runDefinitionCid: definition.identity,
      executorEntries: 1, historicalReplayAfterCoordinatorRestart: true,
      reservedPayloadBytes: 0, pendingOutputIntents: 0}));
    site.child.kill('SIGTERM');
    await site.exited;
  } else {

  // The focused mode reuses this exact real-process fixture and assertions;
  // CI and the default command still execute every foundation scenario.
  if (!process.argv.includes('--start-authority-only')) {

  // 1. A source-free Values Run is accepted, executed once in a holder and
  //    reported with its terminal record.
  const site = startSite();
  currentSite = site;
  const first = dispatchFor('resident-dispatch-1', 1);
  const settled = await within(gateway.dispatch({dispatch: first,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(first)}),
  'first dispatch');
  assert.ok(site.lines.some(line => line.kind === 'accepted'));
  assert.ok(site.lines.some(line => line.kind === 'holder-started'));
  assert.notEqual(settled.state[0], 0);
  await waitFor(() => site.lines.some(line => line.kind === 'executed'),
    'holder execution');
  // The Coordinator's query is answered from the durable journal.
  const terminal = await settledQuery(first, 'first');
  assert.equal(terminal.state[0], 3, 'native settled');
  assert.equal((await entries()).length, 1);
  // O4: the holder's output reaches the Cloud's ingress and is released.
  const delivered = await deliverAndRelease(first, terminal, 'first');
  assert.ok(delivered);
  assert.ok(site.lines.some(line => line.kind === 'output-relayed' &&
    line.operation === 'output'));
  await waitFor(() => site.lines.some(line => line.kind === 'holder-settled'),
    'first holder ended after release');
  assert.equal((await entries()).length, 1);

  if (process.argv.includes('--materials-only')) {
    // The exact public-package materials have traversed actual native admission
    // and execution. Release ACK alone is not evidence of physical reclamation.
    await waitFor(() => site.lines.some(line => line.kind === 'holder-released'),
      'packed materials physical release');
    const released = await within(gateway.query({dispatch: first}), 'packed release query');
    assert.equal(released.state[2], 2);
    assert.equal(reservedPayloadBytes(), 0);
    assert.equal(pendingIntents().length, 0);
    console.log(JSON.stringify({kind: 'packed-run-materials-verified',
      runDefinitionCid: definition.identity,
      dispatchRequestCid: siteControl.identity(first),
      attempt: site.lines.find(line => line.kind === 'accepted').attempt,
      executorEntries: 1, physicalCleanup: 'released',
      reservedPayloadBytes: reservedPayloadBytes(), pendingOutputIntents: 0}));
    site.child.kill('SIGTERM');
    await site.exited;
    for (const [index, mutate] of [
      body => {
        const input = JSON.parse(body.program);
        input.stages[0].steps[0].values.rows[1].id = 3;
        return {...body, program: JSON.stringify(input)};
      },
      body => { const {prepared_invocation, ...rest} = body; return rest; },
    ].entries()) {
      // One new control process per rejected offer: refusal logs deliberately
      // have no request CID, so a previous offer's log cannot satisfy this wait.
      const rejecting = startSite();
      currentSite = rejecting;
      const dispatch = dispatchFor(`packed-materials-refusal-${index}`, 90 + index);
      const envelope = JSON.parse(materialsEnvelope(dispatch));
      envelope.run_materials_json = JSON.stringify(mutate(projected));
      const outcome = gateway.dispatch({dispatch, inputBindingBody: '{}',
        dispatchEnvelope: JSON.stringify(envelope)}).catch(error => error);
      await waitFor(() => rejecting.lines.some(line => line.kind === 'refused' &&
        line.reason === 'materials-rejected'), `packed refusal ${index}`);
      assert.equal(gateway.withdraw({dispatch}), true);
      assert.equal((await within(outcome, 'withdraw rejected materials')).code,
        'RemoteDispatchWithdrawn');
      assert.equal((await within(gateway.query({dispatch}).catch(error => error),
        'rejected materials query')).code, 'RemoteDispatchNotSeen');
      assert.equal((await entries()).length, 1);
      assert.equal(rejecting.lines.some(line => line.kind === 'accepted' ||
        line.kind === 'holder-started'), false);
      rejecting.child.kill('SIGTERM');
      await rejecting.exited;
    }
    expectedEntries = 1;
  }

  if (!process.argv.includes('--materials-only')) {

  // 2. The same attempt delivered again is never started again.
  const again = await within(gateway.dispatch({dispatch: first,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(first)}),
  'redelivery');
  // Same execution outcome; only its cleanup advanced after the release.
  assert.equal(again.state[0], terminal.state[0]);
  assert.equal((await entries()).length, 1);

  // 3. Dispatches outside the Site's delegation or without run materials
  //    are refused before acceptance; nothing starts.
  const foreign = dispatchFor('resident-dispatch-foreign', 2,
    {grantCid: physicalCid('another-grant')});
  const refusedForeign = gateway.dispatch({dispatch: foreign,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(foreign)})
    .catch(error => error);
  await waitFor(() => site.lines.some(line => line.kind === 'refused' &&
    line.reason === 'foreign-grant'), 'foreign grant refusal');
  assert.equal(gateway.withdraw({dispatch: foreign}), true);
  const plain = dispatchFor('resident-dispatch-plain', 3);
  const refusedPlain = gateway.dispatch({dispatch: plain,
    inputBindingBody: '{}'}).catch(error => error);
  await waitFor(() => site.lines.some(line => line.kind === 'refused' &&
    line.reason === 'materials-missing'), 'missing materials refusal');
  assert.equal(gateway.withdraw({dispatch: plain}), true);
  // A refused dispatch was never accepted: the Site answers not-seen.
  const unseen = await within(gateway.query({dispatch: foreign})
    .catch(error => error), 'foreign query');
  assert.equal(unseen.code, 'RemoteDispatchNotSeen');
  assert.equal((await entries()).length, 1);

  // 4. A credential replaced by a shared-mode file stops the requests; the
  //    Site backs off and resumes with the same identifiers after repair.
  await writeFile(`${tokenFile}.next`, `${token}\n`, {mode: 0o644});
  await chmod(`${tokenFile}.next`, 0o644);
  execFileSync('mv', [`${tokenFile}.next`, tokenFile]);
  await waitFor(() => site.lines.some(line => line.kind === 'poll-failed' &&
    line.reason === 'credential-unavailable'), 'credential refusal');
  await chmod(tokenFile, 0o600);
  const second = dispatchFor('resident-dispatch-2', 4);
  const secondSettled = await within(gateway.dispatch({dispatch: second,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(second)}),
  'second dispatch');
  assert.notEqual(secondSettled.state[0], 0);
  await waitFor(async () => (await entries()).length === 2, 'second entry');
  const secondTerminal = await settledQuery(second, 'second');
  assert.equal(secondTerminal.state[0], 3);
  await within(gateway.release({dispatch: second}), 'second release');

  // 5. A termination request stops the control process cleanly.
  site.child.kill('SIGTERM');
  const [code] = await site.exited;
  assert.equal(code, 0, site.stderr());
  assert.ok(site.lines.some(line => line.kind === 'stopped'));
  gateway.cancelPending?.();
  void refusedForeign;
  void refusedPlain;

  // 6. The control process dies right after starting a holder. The holder
  //    keeps the slot; a restarted control process accepts new work but
  //    starts no executor until the old holder is gone, and the attempt the
  //    old holder ran is never started again.
  const dying = startSite(['--holder-pause-ms', '3000']);
  currentSite = dying;
  const third = dispatchFor('resident-dispatch-3', 5);
  const thirdSettled = within(gateway.dispatch({dispatch: third,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(third)}),
  'third dispatch').catch(error => error);
  await waitFor(() => dying.lines.some(line => line.kind === 'holder-started'),
    'third holder');
  dying.child.kill('SIGKILL');
  await dying.exited;
  const restarted = startSite();
  currentSite = restarted;
  const fourth = dispatchFor('resident-dispatch-4', 6);
  const fourthSettled = within(gateway.dispatch({dispatch: fourth,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(fourth)}),
  'fourth dispatch');
  await waitFor(() => restarted.lines.some(line => line.kind === 'slot-busy'),
    'slot held by the old holder');
  await fourthSettled;
  void thirdSettled;
  await waitFor(async () => (await entries()).length === 4, 'fourth entry');
  const thirdTerminal = await within(gateway.query({dispatch: third}),
    'third query');
  assert.equal(thirdTerminal.state[0], 3);
  const fourthTerminal = await settledQuery(fourth, 'fourth');
  assert.equal(fourthTerminal.state[0], 3);
  await within(gateway.release({dispatch: fourth}), 'fourth release');
  restarted.child.kill('SIGTERM');
  await restarted.exited;

  // 7. Two control processes of the same Site run at once; one attempt still
  //    reaches the executor once.
  const left = startSite(['--holder-pause-ms', '500']);
  const right = startSite(['--holder-pause-ms', '500']);
  currentSite = left;
  const fifth = dispatchFor('resident-dispatch-5', 7);
  await within(gateway.dispatch({dispatch: fifth, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(fifth)}), 'fifth dispatch');
  await waitFor(async () => (await entries()).length === 5, 'fifth entry');
  await new Promise(resolve => setTimeout(resolve, 1500));
  const fifthTerminal = await settledQuery(fifth, 'fifth');
  assert.equal(fifthTerminal.state[0], 3);
  await within(gateway.release({dispatch: fifth}), 'fifth release');
  assert.equal((await entries()).length, 5);
  left.child.kill('SIGTERM');
  right.child.kill('SIGTERM');
  await Promise.all([left.exited, right.exited]);

  // 8. A released output also frees its payload in the Site's Store: runs
  //    one after another never exhaust a Store sized for one payload.
  const bounded = startSite(['--publication-capacity-bytes', '40']);
  currentSite = bounded;
  expectedEntries = (await entries()).length;
  for (let run = 0; run < 5; run += 1) {
    const dispatch = dispatchFor(`resident-bounded-${run}`, 20 + run);
    await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), `bounded ${run}`);
    expectedEntries += 1;
    await waitFor(async () => (await entries()).length === expectedEntries,
      `bounded entry ${run}`);
    const terminal = await settledQuery(dispatch, `bounded ${run}`);
    await deliverAndRelease(dispatch, terminal, `bounded-${run}`);
    await waitFor(() => bounded.lines.filter(line =>
      line.kind === 'holder-released').length === run + 1,
    `bounded release ${run}`);
  }
  assert.ok(!bounded.lines.some(line => line.kind === 'output-failed'));
  bounded.child.kill('SIGTERM');
  await bounded.exited;

  // 9. The control process fails to read an accepted request three times:
  //    it keeps serving and starts the attempt once afterwards. Then the
  //    payload cannot be reclaimed at release (the Store directory is read
  //    only): the holder keeps the cleanup, retries, and finishes once the
  //    directory is writable again, without executing again.
  const retrying = startSite(['--control-envelope-read-failures', '3']);
  currentSite = retrying;
  const ninth = dispatchFor('resident-dispatch-9', 30);
  await within(gateway.dispatch({dispatch: ninth, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(ninth)}), 'ninth dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'ninth entry');
  assert.equal(retrying.lines.filter(line =>
    line.kind === 'holder-request-unavailable').length, 3);
  const ninthTerminal = await settledQuery(ninth, 'ninth');
  const ninthRelease = (async () => {
    await within(requestOutput(ninth,
      await planOutput(ninth, ninthTerminal, 'ninth')), 'ninth output');
    await chmod(publicationRoot, 0o500);
    return within(gateway.release({dispatch: ninth}), 'ninth release', 120_000);
  })();
  await waitFor(() => retrying.lines.some(line =>
    line.kind === 'cleanup-pending' && line.step === 'payload'),
  'payload reclaim pending');
  await chmod(publicationRoot, 0o700);
  await ninthRelease;
  await waitFor(() => retrying.lines.some(line =>
    line.kind === 'holder-released' && line.payloads === '1'),
  'payload reclaimed after retry');
  assert.equal((await entries()).length, expectedEntries);
  retrying.child.kill('SIGTERM');
  await retrying.exited;

  // 10. Releasing the output fails more than eight times: the holder keeps
  //     its cleanup and ends only once the release is confirmed.
  const stubborn = startSite(['--holder-release-failures', '9']);
  currentSite = stubborn;
  const tenth = dispatchFor('resident-dispatch-10', 31);
  await within(gateway.dispatch({dispatch: tenth, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(tenth)}), 'tenth dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'tenth entry');
  await settledQuery(tenth, 'tenth');
  await within(gateway.release({dispatch: tenth}), 'tenth release', 120_000);
  await waitFor(() => stubborn.lines.some(line =>
    line.kind === 'holder-released'), 'tenth released', 120_000);
  assert.equal(stubborn.lines.filter(line => line.kind === 'cleanup-pending' &&
    line.step === 'release').length, 9);
  assert.equal((await entries()).length, expectedEntries);
  stubborn.child.kill('SIGTERM');
  await stubborn.exited;

  // Payload capacity still reserved in the Site's publication Store, read
  // directly from its database.
  assert.equal(reservedPayloadBytes(), 0);
  // One more Run through a Store sized for one payload: it succeeds only if
  // no earlier payload is still reserved.
  const provesCapacityFree = async (tag, attempt) => {
    const proof = startSite(['--publication-capacity-bytes', '40']);
    currentSite = proof;
    const dispatch = dispatchFor(`resident-${tag}`, attempt);
    await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), `${tag} dispatch`);
    expectedEntries += 1;
    await waitFor(async () => (await entries()).length === expectedEntries,
      `${tag} entry`);
    await deliverAndRelease(dispatch, await settledQuery(dispatch, tag), tag);
    await waitFor(() => proof.lines.some(line =>
      line.kind === 'holder-released' && line.payloads === '1'),
    `${tag} released`);
    assert.ok(!proof.lines.some(line => line.kind === 'output-failed'));
    proof.child.kill('SIGTERM');
    await proof.exited;
    assert.equal(reservedPayloadBytes(), 0);
  };
  // An https origin nothing listens on.
  const deadOrigin = await new Promise(resolve => {
    const socket = createServer();
    socket.listen(0, '127.0.0.1', () => {
      const {port} = socket.address();
      socket.close(() => resolve(`https://127.0.0.1:${port}`));
    });
  });

  // 11. The payload is sealed but its transfer fails; then the control
  //     process dies. The holder still owns the payload: on the channel's
  //     end it reclaims it, and a Store sized for one payload takes the
  //     next Run.
  const unsent = startSite(['--publication-capacity-bytes', '40'],
    {origin: deadOrigin});
  currentSite = unsent;
  const eleventh = dispatchFor('resident-dispatch-11', 40);
  await within(gateway.dispatch({dispatch: eleventh, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(eleventh)}), 'eleventh dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'eleventh entry');
  const eleventhOutput = requestOutput(eleventh, await planOutput(eleventh,
    await settledQuery(eleventh, 'eleventh'), 'eleventh', deadOrigin))
    .catch(error => error);
  await waitFor(() => unsent.lines.some(line => line.kind === 'output-failed' &&
    line.reason === 'transfer'), 'eleventh transfer failure');
  assert.ok(reservedPayloadBytes() > 0, 'sealed payload before cleanup');
  gateway.withdraw({dispatch: eleventh});
  await eleventhOutput;
  unsent.child.kill('SIGKILL');
  await unsent.exited;
  await waitFor(() => unsent.lines.some(line =>
    line.kind === 'holder-released' && line.payloads === '1'),
  'eleventh payload reclaimed on channel end');
  assert.equal(reservedPayloadBytes(), 0);
  assert.equal((await entries()).length, expectedEntries);
  await provesCapacityFree('after-transfer-failure', 41);

  // 12. The payload cannot be kept (the Store directory is read only while
  //     the output is persisted). The holder still keeps the cleanup for
  //     that exact request, finishes it at release once the directory is
  //     writable again, and nothing stays reserved.
  const unkept = startSite(['--publication-capacity-bytes', '40']);
  currentSite = unkept;
  const twelfth = dispatchFor('resident-dispatch-12', 42);
  await within(gateway.dispatch({dispatch: twelfth, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(twelfth)}), 'twelfth dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'twelfth entry');
  const twelfthPlan = await planOutput(twelfth,
    await settledQuery(twelfth, 'twelfth'), 'twelfth');
  await chmod(publicationRoot, 0o500);
  const twelfthOutput = requestOutput(twelfth, twelfthPlan)
    .catch(error => error);
  await waitFor(() => unkept.lines.some(line => line.kind === 'output-failed'),
    'twelfth persist failure');
  assert.ok(!unkept.lines.some(line => line.kind === 'output-delivered'));
  gateway.withdraw({dispatch: twelfth});
  await twelfthOutput;
  const twelfthRelease = within(gateway.release({dispatch: twelfth}),
    'twelfth release', 120_000);
  await new Promise(resolve => setTimeout(resolve, 500));
  await chmod(publicationRoot, 0o700);
  await twelfthRelease;
  await waitFor(() => unkept.lines.some(line =>
    line.kind === 'holder-released' && line.payloads === '1'),
  'twelfth cleanup kept for the exact request');
  assert.equal(reservedPayloadBytes(), 0);
  unkept.child.kill('SIGTERM');
  await unkept.exited;
  assert.equal((await entries()).length, expectedEntries);
  await provesCapacityFree('after-persist-failure', 43);

  // 13. The payload is sent but its result is not reported (acceptance
  //     hook: the report is withheld, not failed on the wire). The holder
  //     still reclaims the payload at release.
  const unreported = startSite(['--publication-capacity-bytes', '40',
    '--holder-result-report-failures', '1']);
  currentSite = unreported;
  const thirteenth = dispatchFor('resident-dispatch-13', 44);
  await within(gateway.dispatch({dispatch: thirteenth, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(thirteenth)}), 'thirteenth dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'thirteenth entry');
  const thirteenthOutput = requestOutput(thirteenth, await planOutput(
    thirteenth, await settledQuery(thirteenth, 'thirteenth'), 'thirteenth'))
    .catch(error => error);
  await waitFor(() => unreported.lines.some(line =>
    line.kind === 'output-result-unreported' && line.reason === 'injected'),
  'thirteenth result withheld');
  gateway.withdraw({dispatch: thirteenth});
  await thirteenthOutput;
  await within(gateway.release({dispatch: thirteenth}), 'thirteenth release');
  await waitFor(() => unreported.lines.some(line =>
    line.kind === 'holder-released' && line.payloads === '1'),
  'thirteenth payload reclaimed');
  assert.equal(reservedPayloadBytes(), 0);
  unreported.child.kill('SIGTERM');
  await unreported.exited;
  assert.equal((await entries()).length, expectedEntries);

  // 14–15. A holder that cannot open the publication Store, or its Transfer
  //     journal, ends before it claims: nothing executes and nothing is
  //     reported settled. The attempt stays queued; once the resource opens
  //     it executes exactly once.
  const lockedJournalRoot = join(root, 'transfer-journal-locked');
  await mkdir(lockedJournalRoot, {mode: 0o700});
  for (const [tag, attempt, locked, options] of [
    ['store-open', 45, publicationRoot, {}],
    ['transfer-journal-open', 46, lockedJournalRoot, {transferJournal:
      join(lockedJournalRoot, 'site-transfer.sqlite3')}],
  ]) {
    await chmod(locked, 0o000);
    const blocked = startSite([], options);
    currentSite = blocked;
    const dispatch = dispatchFor(`resident-${tag}`, attempt);
    // The gateway answers the dispatch once the attempt has started.
    const started = within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), `${tag} dispatch`);
    try {
      await waitFor(() => blocked.lines.some(line => line.kind === 'accepted'),
        `${tag} accepted`);
      await waitFor(() => blocked.lines.filter(line =>
        line.kind === 'holder-unclaimed').length >= 2, `${tag} requeued`);
      assert.ok(blocked.lines.some(line => line.kind === 'setup-failed'));
      assert.ok(!blocked.lines.some(line => line.kind === 'executed'));
      assert.equal((await entries()).length, expectedEntries);
    } finally {
      await chmod(locked, 0o700);
    }
    const startedState = await started;
    assert.notEqual(startedState.state[0], 0);
    expectedEntries += 1;
    await waitFor(async () => (await entries()).length === expectedEntries,
      `${tag} entry after repair`);
    await deliverAndRelease(dispatch, await settledQuery(dispatch, tag), tag);
    await waitFor(() => blocked.lines.some(line =>
      line.kind === 'holder-released' && line.payloads === '1'),
    `${tag} released`);
    assert.equal(blocked.lines.filter(line => line.kind === 'executed').length,
      1);
    blocked.child.kill('SIGTERM');
    await blocked.exited;
    assert.equal((await entries()).length, expectedEntries);
    assert.equal(reservedPayloadBytes(), 0);
  }

  // Output intents in the Site journal whose cleanup is not recorded
  // complete, and the payload records of the Store, read from their
  // databases.
  const payloadRecords = () => {
    const database = new DatabaseSync(join(publicationRoot,
      '.actql-publication.sqlite3'), {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      return new Map(database.prepare('SELECT record_key, revision FROM ' +
        'actql_records WHERE namespace = ?').all('publication_payload')
        .map(row => [row.record_key, Number(row.revision)]));
    } finally {
      database.close();
    }
  };
  const sleep = milliseconds =>
    new Promise(resolve => setTimeout(resolve, milliseconds));

  // 16. The holder is killed with SIGKILL at each step of keeping its
  //     output: before and after the durable intent, while the payload is
  //     written, right after the seal, and after the reclaim but before the
  //     intent is completed. The Site reclaims what the dead holder left
  //     (holding the slot), completes the intent, changes no other payload
  //     record and never executes again; a Store sized for one payload then
  //     takes the next Run.
  // A staging file nobody's record owns stays untouched by every reclaim.
  const foreignStaging = join(publicationRoot,
    `stage-${'f'.repeat(64)}`);
  await writeFile(foreignStaging, 'foreign', {mode: 0o600});
  // Identity and content, not access times: the file is neither removed
  // nor replaced nor written.
  const foreignStagingState = async () => {
    const {ino, size, mtimeMs} = await stat(foreignStaging);
    return JSON.stringify({ino, size, mtimeMs,
      content: await readFile(foreignStaging, 'utf8')});
  };
  const foreignStagingBefore = await foreignStagingState();
  const killPoints = ['before-intent', 'after-intent', 'allocated', 'owned',
    'payload-written', 'sealed', 'reclaimed'];
  for (const [index, point] of killPoints.entries()) {
    const tag = `killed-${point}`;
    const killed = startSite(['--publication-capacity-bytes', '40',
      '--holder-kill-at', point]);
    currentSite = killed;
    const dispatch = dispatchFor(`resident-${tag}`, 50 + index * 2);
    await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), `${tag} dispatch`);
    expectedEntries += 1;
    await waitFor(async () => (await entries()).length === expectedEntries,
      `${tag} entry`);
    const others = payloadRecords();
    const output = requestOutput(dispatch, await planOutput(dispatch,
      await settledQuery(dispatch, tag), tag)).catch(error => error);
    let release;
    if (point === 'reclaimed') {
      await within(output, `${tag} output`);
      release = gateway.release({dispatch}).catch(error => error);
    }
    await waitFor(() => killed.lines.some(line =>
      line.kind === 'holder-killed' && line.point === point), `${tag} kill`);
    gateway.withdraw({dispatch});
    await output;
    await release;
    // The Site reports the reclaim after its database writes; the line is
    // awaited first so the checks below are not ahead of it.
    if (point !== 'before-intent') {
      await waitFor(() => killed.lines.some(line =>
        line.kind === 'orphans-reclaimed'), `${tag} reclaimed by the Site`);
    }
    await waitFor(() => pendingIntents().length === 0 &&
      reservedPayloadBytes() === 0, `${tag} reclaimed after the holder died`);
    const after = payloadRecords();
    for (const [key, revision] of others) {
      assert.equal(after.get(key), revision, `${tag} other payload unchanged`);
    }
    assert.equal(await foreignStagingState(), foreignStagingBefore,
      `${tag} foreign staging untouched`);
    // No private allocation file is left behind.
    assert.deepEqual((await readdir(publicationRoot))
      .filter(name => name.startsWith('alloc-')), [], `${tag} allocation gone`);
    assert.equal((await entries()).length, expectedEntries);
    killed.child.kill('SIGTERM');
    await killed.exited;
    await provesCapacityFree(`after-${tag}`, 51 + index * 2);
  }

  // 17. While the holder that owns an intent is alive, another control
  //     process of the Site does not reclaim it: it cannot take the slot.
  const living = startSite(['--publication-capacity-bytes', '40']);
  currentSite = living;
  const livingDispatch = dispatchFor('resident-living-holder', 70);
  await within(gateway.dispatch({dispatch: livingDispatch,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(livingDispatch)}),
  'living dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'living entry');
  await within(requestOutput(livingDispatch, await planOutput(livingDispatch,
    await settledQuery(livingDispatch, 'living'), 'living')), 'living output');
  assert.equal(pendingIntents().length, 1);
  const reservedWhileLiving = reservedPayloadBytes();
  assert.ok(reservedWhileLiving > 0);
  const bystander = startSite(['--publication-capacity-bytes', '40']);
  await waitFor(() => bystander.lines.some(line =>
    line.kind === 'orphan-reclaim-pending' && line.reason === 'slot-busy'),
  'bystander finds the slot held');
  assert.ok(!bystander.lines.some(line => line.kind === 'orphans-reclaimed'));
  assert.equal(pendingIntents().length, 1);
  assert.equal(reservedPayloadBytes(), reservedWhileLiving);
  bystander.child.kill('SIGTERM');
  await bystander.exited;
  await within(gateway.release({dispatch: livingDispatch}), 'living release');
  await waitFor(() => living.lines.some(line =>
    line.kind === 'holder-released' && line.payloads === '1'),
  'living holder released');
  assert.equal(pendingIntents().length, 0);
  assert.equal(reservedPayloadBytes(), 0);
  living.child.kill('SIGTERM');
  await living.exited;

  // 18. The holder dies right after the seal and its control process never
  //     reclaims (acceptance hook: reclaim passes skipped), then the control
  //     process is killed too. A restarted Site reclaims the payload.
  const neglecting = startSite(['--publication-capacity-bytes', '40',
    '--holder-kill-at', 'sealed', '--control-reclaim-failures', '1000000']);
  currentSite = neglecting;
  const restartDispatch = dispatchFor('resident-restart-reclaim', 72);
  await within(gateway.dispatch({dispatch: restartDispatch,
    inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(restartDispatch)}),
  'restart dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'restart entry');
  const restartOutput = requestOutput(restartDispatch, await planOutput(
    restartDispatch, await settledQuery(restartDispatch, 'restart'),
    'restart')).catch(error => error);
  await waitFor(() => neglecting.lines.some(line =>
    line.kind === 'holder-killed'), 'restart holder killed');
  gateway.withdraw({dispatch: restartDispatch});
  await restartOutput;
  await sleep(1000);
  assert.equal(pendingIntents().length, 1);
  assert.ok(reservedPayloadBytes() > 0);
  neglecting.child.kill('SIGKILL');
  await neglecting.exited;
  const restartedSite = startSite(['--publication-capacity-bytes', '40']);
  currentSite = restartedSite;
  await waitFor(() => restartedSite.lines.some(line =>
    line.kind === 'orphans-reclaimed'), 'reclaimed after restart');
  assert.equal(pendingIntents().length, 0);
  assert.equal(reservedPayloadBytes(), 0);
  assert.equal((await entries()).length, expectedEntries);
  restartedSite.child.kill('SIGTERM');
  await restartedSite.exited;
  await provesCapacityFree('after-restart-reclaim', 73);

  // 19. The intent cannot be kept (a real journal write failure: another
  //     connection holds the write lock past the busy timeout). The holder
  //     does not touch the Store for that output.
  const unrecorded = startSite(['--publication-capacity-bytes', '40',
    '--holder-pause-at', 'before-intent', '--holder-pause-ms', '3000']);
  currentSite = unrecorded;
  const intentDispatch = dispatchFor('resident-intent-failure', 75);
  await within(gateway.dispatch({dispatch: intentDispatch,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(intentDispatch)}),
  'intent dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'intent entry');
  const recordsBefore = payloadRecords();
  const intentOutput = requestOutput(intentDispatch, await planOutput(
    intentDispatch, await settledQuery(intentDispatch, 'intent'), 'intent'))
    .catch(error => error);
  await waitFor(() => unrecorded.lines.some(line =>
    line.kind === 'holder-paused' && line.point === 'before-intent'),
  'holder paused before the intent');
  const unlockForIntent = await lockJournal();
  try {
    await waitFor(() => unrecorded.lines.some(line =>
      line.kind === 'output-failed' && line.reason === 'intent'),
    'intent write failed', 60_000);
    gateway.withdraw({dispatch: intentDispatch});
    assert.equal(pendingIntents().length, 0);
    assert.equal(reservedPayloadBytes(), 0);
    assert.deepEqual([...payloadRecords()], [...recordsBefore]);
  } finally {
    unlockForIntent();
  }
  await intentOutput;
  await within(gateway.release({dispatch: intentDispatch}), 'intent release');
  // Output operations served again before the withdrawal may still reach
  // the holder after the journal recovered; each keeps its intent first.
  await waitFor(() => unrecorded.lines.some(line =>
    line.kind === 'holder-released'), 'intent holder released');
  assert.equal(pendingIntents().length, 0);
  assert.equal(reservedPayloadBytes(), 0);
  unrecorded.child.kill('SIGTERM');
  await unrecorded.exited;

  // 20. The journal fails while the runtime owns resources (a real write
  //     failure: the lock is held from the executor entry), so the start
  //     fails and so does the runtime's close. The holder keeps the slot and
  //     retries only the close; no other holder starts meanwhile. After the
  //     journal recovers, the cleanup completes, the slot is freed and the
  //     next attempt runs; the failed attempt never executes again.
  const failing = startSite(['--holder-pause-ms', '3000']);
  currentSite = failing;
  const failedStart = dispatchFor('resident-start-failure', 77);
  const failedStartSettled = within(gateway.dispatch({dispatch: failedStart,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(failedStart)}),
  'failing dispatch').catch(error => error);
  await waitFor(async () => (await entries()).length === expectedEntries + 1,
    'failing entry');
  expectedEntries += 1;
  const unlockForStart = await lockJournal();
  const nextAttempt = dispatchFor('resident-after-start-failure', 78);
  let nextSettled;
  try {
    await waitFor(() => failing.lines.some(line =>
      line.kind === 'cleanup-pending' &&
      line.step === 'runtime-after-failure'), 'runtime cleanup pending',
    60_000);
    // The primary cause is the journal failure; the pending cleanup fails on
    // the journal too.
    const failure = failing.lines.find(line => line.kind === 'execute-failed');
    assert.equal(failure?.reason, 'runtime-journal', JSON.stringify(failure));
    const pendingCleanup = failing.lines.find(line =>
      line.kind === 'cleanup-pending' && line.step === 'runtime-after-failure');
    assert.equal(pendingCleanup.reason, 'journal',
      JSON.stringify(pendingCleanup));
    nextSettled = within(gateway.dispatch({dispatch: nextAttempt,
      inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(nextAttempt)}),
    'next dispatch', 120_000);
    await sleep(2000);
    assert.equal(failing.lines.filter(line =>
      line.kind === 'holder-started').length, 1, 'no other holder started');
    assert.ok(!failing.lines.some(line => line.kind === 'runtime-cleaned'));
  } finally {
    unlockForStart();
  }
  await waitFor(() => failing.lines.some(line =>
    line.kind === 'runtime-cleaned'), 'runtime cleaned after recovery', 60_000);
  assert.equal(failing.lines.find(line =>
    line.kind === 'runtime-cleaned').reason, 'runtime-journal');
  const cleanedAt = failing.lines.findIndex(line =>
    line.kind === 'runtime-cleaned');
  await nextSettled;
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries,
    'next attempt entry');
  const nextStartedAt = failing.lines.findIndex((line, index) =>
    index > 0 && line.kind === 'holder-started' &&
    failing.lines.slice(0, index).some(earlier =>
      earlier.kind === 'holder-started'));
  assert.ok(nextStartedAt > cleanedAt, 'next holder starts after cleanup');
  void failedStartSettled;
  await within(gateway.release({dispatch: nextAttempt}), 'next release');
  failing.child.kill('SIGTERM');
  await failing.exited;

  // 21. A dispatch envelope whose run materials exceed the cap (262144
  //     bytes) is refused by the same admitter on the Cloud side before it is
  //     served: the Site never receives it, accepts nothing and records
  //     nothing. The Site's own receive-side refusal is covered by the
  //     protocol tests.
  const bounded2 = startSite();
  currentSite = bounded2;
  const oversized = dispatchFor('resident-oversized-materials', 80);
  const oversizedEnvelope = JSON.parse(materialsEnvelope(oversized));
  oversizedEnvelope.run_materials_json = 'x'.repeat(262145);
  assert.throws(() => gateway.dispatch({dispatch: oversized,
    inputBindingBody: '{}',
    dispatchEnvelope: JSON.stringify(oversizedEnvelope)}),
  {code: 'MoonBitHostFailure'});
  await sleep(1000);
  assert.ok(!bounded2.lines.some(line => line.kind === 'accepted' ||
    line.kind === 'holder-started' || line.kind === 'poll-failed'));
  const unseenOversized = await within(gateway.query({dispatch: oversized})
    .catch(error => error), 'oversized query');
  assert.equal(unseenOversized.code, 'RemoteDispatchNotSeen');
  assert.equal((await entries()).length, expectedEntries);
  bounded2.child.kill('SIGTERM');
  await bounded2.exited;

  // 22. SIGKILL after mkdir, before its ownership is durable, cannot be
  // repaired by guessing from the name. Preserve capacity, the exact intent
  // and Reclaiming state on repeated process restarts. Test both the created
  // directory and a separately owned directory replacing it at that name.
  for (const [index, kind] of ['created', 'foreign'].entries()) {
    const publication = join(root, `unconfirmed-${kind}`);
    const siteJournal = join(root, `unconfirmed-${kind}.sqlite3`);
    await mkdir(publication);
    const options = {publication, siteJournal};
    const killed = startSite(['--publication-capacity-bytes', '40',
      '--holder-kill-at', 'allocation-created',
      '--control-reclaim-failures', '1000000'], options);
    currentSite = killed;
    const dispatch = dispatchFor(`unconfirmed-${kind}`, 90 + index * 2);
    await within(gateway.dispatch({dispatch, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(dispatch)}), `${kind} dispatch`);
    expectedEntries += 1;
    await waitFor(async () => (await entries()).length === expectedEntries,
      `${kind} executor entry`);
    const output = requestOutput(dispatch, await planOutput(dispatch,
      await settledQuery(dispatch, kind), kind)).catch(error => error);
    await waitFor(() => killed.lines.some(line =>
      line.kind === 'holder-killed' && line.point === 'allocation-created'),
    `${kind} stop before ownership persistence`);
    gateway.withdraw({dispatch});
    await output;
    killed.child.kill('SIGKILL');
    await killed.exited;
    const names = (await readdir(publication))
      .filter(name => name.startsWith('alloc-'));
    assert.equal(names.length, 1);
    const area = join(publication, names[0]);
    if (kind === 'foreign') {
      // Only the test removes its known, empty fixture allocation. The Site
      // must not take ownership of the replacement at the same name.
      assert.deepEqual(await readdir(area), []);
      await rmdir(area);
      await mkdir(area);
      await writeFile(join(area, 'foreign'), 'not-owned-by-the-Site');
    }
    const directoryBefore = (await stat(area)).ino;
    const pendingBefore = pendingIntents(siteJournal);
    assert.equal(pendingBefore.length, 1);
    const capacityBefore = reservedPayloadBytes(publication);
    assert.ok(capacityBefore > 0);
    const allocationRecords = () => {
      const database = new DatabaseSync(join(publication,
        '.actql-publication.sqlite3'), {readOnly: true});
      try {
        const allocations = database.prepare('SELECT record_key, revision, CAST(body AS TEXT) AS body ' +
          'FROM actql_records WHERE namespace = ? ORDER BY record_key')
          .all('publication_payload_allocation');
        const payloads = database.prepare('SELECT record_key, revision, CAST(body AS TEXT) AS body ' +
          'FROM actql_records WHERE namespace = ? ORDER BY record_key')
          .all('publication_payload');
        return {allocations, payloads};
      } finally { database.close(); }
    };
    let durable;
    for (let restart = 0; restart < 2; restart += 1) {
      const blocked = startSite(['--publication-capacity-bytes', '40'], options);
      currentSite = blocked;
      await waitFor(() => blocked.lines.some(line =>
        line.kind === 'allocation-needs-reconciliation'),
      `${kind} durable reconciliation after restart ${restart}`);
      assert.equal(blocked.lines.filter(line =>
        line.kind === 'allocation-needs-reconciliation').length, 1);
      assert.equal((await stat(area)).ino, directoryBefore);
      assert.deepEqual(pendingIntents(siteJournal), pendingBefore);
      assert.equal(reservedPayloadBytes(publication), capacityBefore);
      const records = allocationRecords();
      assert.equal(records.allocations.length, 1);
      assert.equal(records.allocations[0].body, names[0],
        'no guessed inode or new allocation ordinal');
      assert.equal(records.payloads.length, 1);
      assert.equal(JSON.parse(records.payloads[0].body).state, 'reclaiming');
      if (durable !== undefined) assert.deepEqual(records, durable);
      durable = records;
      assert.deepEqual((await readdir(publication))
        .filter(name => name.startsWith('alloc-')), names);
      if (kind === 'foreign') {
        assert.equal(await readFile(join(area, 'foreign'), 'utf8'),
          'not-owned-by-the-Site');
      }
      // Acceptance is not execution completion: this fixture's dispatch
      // Promise stays pending until terminal status or explicit withdrawal.
      // Two separately observed acceptances prove the control loop advanced
      // through its start boundary without starting a queued executor.
      for (let pulse = 0; pulse < 2; pulse += 1) {
        const next = dispatchFor(`blocked-${kind}-${restart}-${pulse}`,
          100 + index * 4 + restart * 2 + pulse);
        const outcome = gateway.dispatch({dispatch: next,
          inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(next)})
          .catch(error => error);
        await waitFor(() => blocked.lines.some(line =>
          line.kind === 'accepted' && line.request_cid ===
            siteControl.identity(next)), `${kind} queued pulse ${pulse}`);
        // Withdraw only the stand-in transport waiter. The accepted Site
        // journal record and its queued execution are not cancelled.
        assert.equal(gateway.withdraw({dispatch: next}), true);
        assert.equal((await within(outcome, `${kind} withdraw queued dispatch`))
          .code, 'RemoteDispatchWithdrawn');
      }
      assert.equal(blocked.lines.some(line => line.kind === 'holder-started'), false);
      assert.equal((await entries()).length, expectedEntries);
      blocked.child.kill('SIGTERM');
      await blocked.exited;
      assert.deepEqual(allocationRecords(), durable);
      assert.deepEqual(pendingIntents(siteJournal), pendingBefore);
      assert.equal(reservedPayloadBytes(publication), capacityBefore);
    }
  }

  }
  }

  // 23. A locally controlled clock advances at observed boundaries, not after
  // a guessed startup sleep. The executor evidence hook is not the barrier.
  // Receipt expiry, expiry after acceptance/before rebuilding, and expiry
  // after the durable start claim all start zero physical executors.
  for (const [index, point] of ['receipt', 'before-start', 'before-physical-start'].entries()) {
    const clockRoot = join(root, `expiry-clock-${index}`);
    await mkdir(clockRoot);
    const clockPath = join(clockRoot, 'clock.txt');
    // Isolate clock-controlled cases; the durable failure checks below also
    // cover expiry after acceptance, without reviving a queued execution.
    const siteJournal = join(clockRoot, 'journal.sqlite3');
    const publication = join(clockRoot, 'publication');
    await mkdir(publication);
    await writeFile(clockPath, point === 'receipt' ? validUntil : new Date(now).toISOString());
    const expiredSite = startSite(['--test-clock-root', clockRoot,
      '--holder-pause-at', point, '--holder-pause-ms', '1000'], {
      siteJournal, publication, transferJournal: join(clockRoot, 'transfer.sqlite3'),
    });
    currentSite = expiredSite;
    const expired = dispatchFor(`resident-expiry-${index}`, 210 + index);
    const outcome = gateway.dispatch({dispatch: expired, inputBindingBody: '{}',
      dispatchEnvelope: materialsEnvelope(expired)}).catch(error => error);
    if (point === 'receipt') {
      await waitFor(() => expiredSite.lines.some(line =>
        line.kind === 'refused' && line.reason === 'not-current'), 'expired receipt refusal');
      assert.equal(expiredSite.lines.some(line => line.kind === 'accepted'), false);
      // Remove the rejected stand-in dispatch offer before querying: otherwise
      // the gateway keeps offering it at the front of its poll queue. This
      // does not cancel or alter a Site journal record.
      assert.equal(gateway.withdraw({dispatch: expired}), true);
      await outcome;
      assert.equal((await within(gateway.query({dispatch: expired}).catch(error => error),
        'expired receipt query')).code, 'RemoteDispatchNotSeen');
    } else {
      await waitFor(() => expiredSite.lines.some(line =>
        line.kind === 'holder-paused' && line.point === point), `${point} barrier`);
      const acceptance = expiredSite.lines.find(line => line.kind === 'accepted' &&
        line.request_cid === siteControl.identity(expired));
      assert.ok(acceptance);
      if (point === 'before-physical-start') {
        const database = new DatabaseSync(siteJournal, {readOnly: true});
        try {
          const claims = database.prepare('SELECT body FROM actql_records WHERE namespace = ?')
            .all('site_start_claim').map(row => JSON.parse(Buffer.from(row.body).toString('utf8')));
          assert.ok(claims.some(claim => claim.dispatch_request_cid === siteControl.identity(expired)),
            'deadline advanced only after this attempt acquired its durable claim');
        } finally { database.close(); }
      }
      await writeFile(clockPath, validUntil);
      await waitFor(() => expiredSite.lines.some(line => line.kind === 'execute-failed' &&
        line.reason === 'refused-not-current'), `${point} expiry refusal`);
      await waitFor(() => expiredSite.lines.some(line => line.kind === 'holder-exited' &&
        line.attempt === acceptance.attempt), `${point} physical holder exit`);
      // A duplicate Accepted observation can already resolve the stand-in
      // dispatch waiter. Query the durable failure/cleanup, independently
      // of whether the stand-in still accepts an unsolicited status ACK.
      const stopped = await within(gateway.query({dispatch: expired}), 'expired claimed status');
      // Failed, NoEvidence, CleanupReleased, no material, no quarantine.
      assert.deepEqual(stopped.state, [4, 0, 2, 0, 0],
        'claimed expiry is stopped-before-start, with cleanup confirmed');
    }
    gateway.withdraw({dispatch: expired});
    await outcome;
    assert.equal((await entries()).length, expectedEntries, `${point}: zero executor entries`);
    assert.equal(pendingIntents(siteJournal).length, 0);
    if (point !== 'receipt') assert.equal(reservedPayloadBytes(publication), 0);
    else assert.deepEqual(await readdir(publication), [], 'receipt refusal never opened the Store');
    assert.equal(expiredSite.lines.some(line => line.kind === 'cleanup-pending'), false);
    expiredSite.child.kill('SIGTERM');
    await expiredSite.exited;
  }

  if (!process.argv.includes('--materials-only')) {
  // 24. A pre-claim expired queue head and a longer-lived successor share
  // one Site/journal. The head must become durably failed/released through
  // exclusive claim, never start, and never prevent the successor's start.
  const queueClockRoot = join(root, 'expiry-queue-clock');
  await mkdir(queueClockRoot);
  const queueClockPath = join(queueClockRoot, 'clock.txt');
  await writeFile(queueClockPath, new Date(now).toISOString());
  const queueSite = startSite(['--test-clock-root', queueClockRoot,
    '--holder-pause-at', 'before-start', '--holder-pause-ms', '1000']);
  currentSite = queueSite;
  const expiredHead = dispatchFor('resident-expired-queue-head', 220);
  const headOutcome = gateway.dispatch({dispatch: expiredHead,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(expiredHead)})
    .catch(error => error);
  await waitFor(() => queueSite.lines.some(line => line.kind === 'holder-paused' &&
    line.point === 'before-start'), 'accepted queue head before claim');
  const headAcceptance = queueSite.lines.find(line => line.kind === 'accepted' &&
    line.request_cid === siteControl.identity(expiredHead));
  assert.ok(headAcceptance);
  const laterUntil = new Date(now + 7_200_000).toISOString();
  const laterCompiled = portable.publicationControl.prepareCheckedClientCompiledRun(program,
    'values', {executionContextCid: physicalCid('resident-execution-context'),
      hostPolicyCid: physicalCid('resident-host-policy'), expiresAt: laterUntil});
  const laterDefinition = portable.publicationControl.defineCheckedClientCompiledRun(laterCompiled,
    {namespaceId: 'resident-scope', runId: 'resident-live-successor', createdAt,
      validUntil: laterUntil});
  const laterAdmission = runHost.admitRun(retainedPrepared, retainedCompilation,
    laterCompiled.preparedEvidence.wire, laterCompiled.authorization.wire);
  const laterOwnedDefinition = runHost.admitSourceFreeRunDefinition(retainedPrepared,
    retainedCompilation, laterAdmission, laterDefinition.wire);
  const laterMaterials = runHost.issueSourceFreeRunMaterials(retainedPrepared,
    retainedCompilation, laterAdmission, laterOwnedDefinition, {
      environment: retainedEnvironment, environmentWire,
      document: programText, format: 'json',
    });
  const later = dispatchFor('resident-live-successor', 221,
    {runDefinitionCid: laterDefinition.identity});
  await writeFile(queueClockPath, validUntil);
  const laterOutcome = gateway.dispatch({dispatch: later, inputBindingBody: '{}',
    dispatchEnvelope: coordinator.pollDispatchMaterialsJson(coordinator.admitDispatchJson(
      siteControl.requestJson(later), siteControl.identity(later)), '{}', 16, laterMaterials)});
  await waitFor(() => queueSite.lines.some(line => line.kind === 'accepted' &&
    line.request_cid === siteControl.identity(later)), 'valid successor acceptance');
  await waitFor(() => queueSite.lines.some(line => line.kind === 'holder-exited' &&
    line.attempt === headAcceptance.attempt), 'expired queue head physical exit');
  gateway.withdraw({dispatch: expiredHead});
  await headOutcome;
  const headStatus = await within(gateway.query({dispatch: expiredHead}), 'expired head status');
  assert.deepEqual(headStatus.state, [4, 0, 2, 0, 0], 'expired head durably failed and reclaimed');
  await within(laterOutcome, 'live successor dispatch');
  expectedEntries += 1;
  await waitFor(async () => (await entries()).length === expectedEntries, 'only live successor enters');
  const laterStatus = await settledQuery(later, 'live successor');
  const laterAcceptance = queueSite.lines.find(line => line.kind === 'accepted' &&
    line.request_cid === siteControl.identity(later));
  assert.ok(laterAcceptance);
  const headHolder = queueSite.lines.find(line => line.kind === 'holder-started' &&
    line.attempt === headAcceptance.attempt);
  const laterHolder = queueSite.lines.find(line => line.kind === 'holder-started' &&
    line.attempt === laterAcceptance.attempt);
  assert.ok(headHolder);
  assert.ok(laterHolder);
  // The durable attempt identity is not the executor's occurrence key.
  // Match each actual entry to its OS holder's claimant instead.
  assert.equal((await entries()).filter(line => line.split(' ')[0] === headHolder.claimant).length, 0);
  assert.equal((await entries()).filter(line => line.split(' ')[0] === laterHolder.claimant).length, 1);
  await deliverAndRelease(later, laterStatus, 'live-successor');
  await waitFor(() => queueSite.lines.some(line => line.kind === 'holder-released'), 'successor cleanup');
  assert.equal(pendingIntents().length, 0);
  assert.equal(reservedPayloadBytes(), 0);
  const headStarts = queueSite.lines.filter(line => line.kind === 'holder-started' &&
    line.attempt === headAcceptance.attempt).length;
  // Redelivery is checked against the terminal record even at a restored
  // earlier test time; it cannot create another holder or executor.
  await writeFile(queueClockPath, new Date(now).toISOString());
  const replay = await within(gateway.dispatch({dispatch: expiredHead, inputBindingBody: '{}',
    dispatchEnvelope: materialsEnvelope(expiredHead)}), 'expired head redelivery');
  assert.deepEqual(replay.state, [4, 0, 2, 0, 0]);
  assert.equal((await entries()).length, expectedEntries);
  assert.equal(queueSite.lines.filter(line => line.kind === 'holder-started' &&
    line.attempt === headAcceptance.attempt).length, headStarts);
  assert.equal(headStarts, 1);
  assert.equal((await within(gateway.query({dispatch: expiredHead}), 'redelivered head status')).revision,
    headStatus.revision, 'redelivery does not mutate the terminal record');
  queueSite.child.kill('SIGTERM');
  await queueSite.exited;

  // 25. A lifetime rejection is definite, but recording it can fail. Keep
  // the runtime/slot until the real SQLite write lock is removed; retry
  // cleanup only, not execution or acceptance. This is not a new attempt.
  await writeFile(queueClockPath, new Date(now).toISOString());
  const lockedSite = startSite(['--test-clock-root', queueClockRoot,
    '--holder-pause-at', 'before-physical-start', '--holder-pause-ms', '1000']);
  currentSite = lockedSite;
  const lockedExpiry = dispatchFor('resident-expiry-persistence-failure', 222);
  const lockedOutcome = gateway.dispatch({dispatch: lockedExpiry,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(lockedExpiry)})
    .catch(error => error);
  await waitFor(() => lockedSite.lines.some(line => line.kind === 'holder-paused' &&
    line.point === 'before-physical-start'), 'expiry after claim before physical call');
  const lockedAcceptance = lockedSite.lines.find(line => line.kind === 'accepted' &&
    line.request_cid === siteControl.identity(lockedExpiry));
  assert.ok(lockedAcceptance);
  const unlockExpiry = await lockJournal();
  try {
    await writeFile(queueClockPath, validUntil);
    await waitFor(() => lockedSite.lines.some(line => line.kind === 'cleanup-pending' &&
      line.step === 'runtime-after-failure'), 'expiry journal failure retains owner', 60_000);
    assert.equal(lockedSite.lines.find(line => line.kind === 'execute-failed')?.reason,
      'runtime-journal');
    assert.equal(lockedSite.lines.find(line => line.kind === 'cleanup-pending' &&
      line.step === 'runtime-after-failure')?.reason, 'journal');
    assert.equal((await entries()).length, expectedEntries, 'expiry never entered executor');
    assert.equal(lockedSite.lines.filter(line => line.kind === 'holder-started').length, 1);
    assert.equal(lockedSite.lines.some(line => line.kind === 'holder-exited' ||
      line.kind === 'runtime-cleaned'), false, 'slot custody remains with the live holder');
    const database = new DatabaseSync(journalPath, {readOnly: true});
    try {
      const claims = database.prepare('SELECT body FROM actql_records WHERE namespace = ?')
        .all('site_start_claim').map(row => JSON.parse(Buffer.from(row.body).toString('utf8')));
      assert.ok(claims.some(claim => claim.dispatch_request_cid === siteControl.identity(lockedExpiry)),
        'failed persistence does not discard the exclusive claim');
    } finally { database.close(); }
  } finally { unlockExpiry(); }
  await waitFor(() => lockedSite.lines.some(line => line.kind === 'runtime-cleaned'),
    'expiry cleanup persisted after journal recovery', 60_000);
  await waitFor(() => lockedSite.lines.some(line => line.kind === 'holder-exited' &&
    line.attempt === lockedAcceptance.attempt), 'expiry owner physical cleanup complete');
  gateway.withdraw({dispatch: lockedExpiry});
  await lockedOutcome;
  const lockedTerminal = await within(gateway.query({dispatch: lockedExpiry}),
    'expiry failure durable cleanup');
  assert.deepEqual(lockedTerminal.state, [4, 0, 2, 0, 0]);
  assert.equal((await entries()).length, expectedEntries, 'cleanup did not retry execution');
  assert.equal(lockedSite.lines.filter(line => line.kind === 'holder-started').length, 1);
  assert.equal(reservedPayloadBytes(), 0);
  assert.equal(pendingIntents().length, 0);
  lockedSite.child.kill('SIGTERM');
  await lockedSite.exited;
  }

  }
  // Each entry names one holder claimant and one attempt key; no attempt
  // key appears twice.
  const keys = (await entries()).map(line => line.split(' ')[1]);
  assert.equal(new Set(keys).size, keys.length);
  console.log('native resident Site acceptance passed');
} catch (error) {
  console.error('resident Site test failed:', error);
  if (observationFailures.length) {
    console.error('Coordinator observation failures:', observationFailures);
  }
  if (currentSite !== undefined) {
    if (retainedConsumerMode) {
      await writeFile(join(root, 'resident-failure-lines.json'), JSON.stringify(currentSite.lines),
        {mode: 0o600});
    }
    console.error('resident Site output:', JSON.stringify(retainedConsumerMode
      ? currentSite.lines.filter(line => line.kind !== 'accepted').slice(-30)
      : currentSite.lines));
    console.error('resident Site stderr:', currentSite.stderr());
  }
  throw error;
} finally {
  // Keep ownership until each tracked control process has actually stopped;
  // resource close/removal must not race an unconfirmed child exit.
  await Promise.all([...running].map(async child => {
    if (child.exitCode !== null || child.signalCode !== null) return;
    const closed = once(child, 'close');
    child.kill('SIGKILL');
    await closed;
  }));
  if (ackLossProxy !== undefined) await ackLossProxy.close().catch(() => {});
  if (gateway !== undefined) await gateway.close().catch(() => {});
  if (receiver !== undefined) await receiver.close().catch(() => {});
  receiverJournal?.close();
  observationStore?.close();
  receiverStore?.close();
  await receiverStore?.cleanup();
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    await rm(root, {recursive: true, force: true});
  } else {
    console.error(`native resident Site scratch kept: ${root}`);
  }
}
}

if (process.env.NODE_TEST_CONTEXT) {
  await test(cancelMode ? 'Native resident cancellation and reconstruction' :
    'Native resident Site acceptance', runAcceptance);
} else {
  await runAcceptance();
}
