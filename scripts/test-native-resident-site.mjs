// Real-process acceptance for the outbound-only resident Site: a native
// control process polls a bearer-authenticated outbound gateway (standing in
// for the Cloud), admits a source-free Values Run from typed run materials,
// and runs it in a separate executor holder. The executor entry count is
// read from a synced evidence file, never from transport logs.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash, generateKeyPairSync, X509Certificate} from 'node:crypto';
import {once} from 'node:events';
import {chmod, mkdir, mkdtemp, readdir, readFile, rm, stat, writeFile} from
  'node:fs/promises';
import {existsSync} from 'node:fs';
import {createServer} from 'node:net';
import {join} from 'node:path';
import {DatabaseSync} from 'node:sqlite';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {runtimeCore} from '../adapters/host-common/runtime-core.mjs';
import {installNodeClientProgramPreparation} from
  '../adapters/host-node/client-program-preparation.mjs';
import {startHttpsOutboundSiteGateway} from
  '../adapters/host-node/outbound-site-gateway.mjs';
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
const openssl = (...args) =>
  execFileSync('openssl', args, {cwd: root, stdio: 'ignore'});

let gateway;
let receiver;
let receiverStore;
let receiverJournal;
let currentSite;
const running = new Set();
try {
  // Build the resident Site and the portable owners the test drives.
  execFileSync(moon, ['build', '--target', 'native',
    'src/cmd/native_remote_resident_site', 'src/cmd/native_runtime_bundle'],
  {cwd: repository, stdio: 'inherit'});
  execFileSync(moon, ['build', '--target', 'js', '--release',
    'src/connectors_builtin_node'], {cwd: repository, stdio: 'inherit'});
  execFileSync(process.execPath, ['scripts/build-runtime-packages.mjs',
    'coordinator-core', 'run-host-core'], {cwd: repository, stdio: 'inherit'});
  const executable = join(repository, '_build/native/debug/build/cmd/' +
    'native_remote_resident_site/native_remote_resident_site.exe');
  const bundleTool = join(repository, '_build/native/debug/build/cmd/' +
    'native_runtime_bundle/native_runtime_bundle.exe');
  const moonModule = await import(pathToFileURL(join(repository,
    '_build/js/release/build/connectors_builtin_node/' +
    'connectors_builtin_node.js')).href);
  const coordinator = await import(pathToFileURL(join(repository,
    'packages/coordinator-core/index.mjs')).href);
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
  gateway = await startHttpsOutboundSiteGateway({
    key: await readFile(join(root, 'server.key')),
    cert: await readFile(join(root, 'server.crt')),
    ca: await readFile(join(root, 'ca.crt')),
    bearerAuthorities: new Map([[
      createHash('sha256').update(token).digest('hex'),
      {siteKey, siteGeneration: 1},
    ]]),
    control: siteControl,
    idlePollMilliseconds: 200,
  });

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
  const [registry, values] = await pinnedEngineContracts(repository);
  await writeFile(join(engineRoot, 'registry.json'), registry);
  await writeFile(join(engineRoot, 'values.json'), values);

  // The issuing side (the Cloud's role) prepares and authorizes the Run.
  const programText = await readFile(join(repository,
    'packages/sdk/fixtures/values.json'), 'utf8');
  const environmentWire = (await readFile(join(repository,
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
  const compiled = portable.publicationControl.prepareCheckedClientCompiledRun(
    program, 'values', {
      executionContextCid: physicalCid('resident-execution-context'),
      hostPolicyCid: physicalCid('resident-host-policy'),
      expiresAt: validUntil,
    });
  const definition = portable.publicationControl.defineCheckedClientCompiledRun(
    compiled, {namespaceId: 'resident-scope', runId: 'resident-run-1',
      createdAt, validUntil});
  const materials = JSON.stringify({
    check_environment: environmentWire,
    check_environment_cid: environmentCid,
    created_at: createdAt,
    parameters: null,
    prepared_invocation: compiled.preparedEvidence.wire,
    program: programText,
    program_format: 'json',
    run_authorization: compiled.authorization.wire,
    run_id: 'resident-run-1',
    scope_id: 'resident-scope',
    valid_until: validUntil,
    version: 'actql-remote-run-materials/0.1',
  });
  const operationCapability = physicalCid('resident-operation-capability');
  const issuerCapability = physicalCid('resident-issuer-capability');
  const budget = siteControl.prepareBudget({retainedBytes: 1048576n,
    executionBytes: 1048576n});
  const binding = siteControl.prepareInputBinding('{}');
  const taskKey = JSON.parse(compiled.compiledPlan.wire).executable_plan_cid
    === undefined ? 'values_0' : 'values_0';
  const dispatchFor = (dispatchId, attempt, overrides = {}) =>
    siteControl.prepare({
      coordinatorAuthority: 'cloud-coordinator',
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
      siteControl.identity(dispatch)), '{}', 16, materials);
  // The Result the Coordinator publishes, from the ordinary Client owners.
  const runHost = await import(pathToFileURL(join(repository,
    'packages/run-host-core/index.mjs')).href);
  const hostPrepared = runHost.prepare(programText, 'json',
    runHost.admitEnvironment(environmentWire, environmentCid, {rela: true}));
  const resultDefinitionCid = runHost.resultDefinitions(hostPrepared,
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
    const intent = siteControl.prepareOutputIntent(dispatch, {
      storeAuthorityCid: physicalCid('resident-publication-store'),
      publicationAttemptCid: physicalCid(`resident-publication-${tag}`),
      resultDefinitionCid,
      orderingEvidenceCid: physicalCid('resident-ordering'),
      coordinatorAuthority: 'cloud-coordinator',
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
  const requestOutput = (dispatch, {intent, planned}) => gateway.output({
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
    '--coordinator-authority', 'cloud-coordinator',
    '--runtime-bundle-cid', envelope.runtimeBundleCid,
    '--connector-registration', 'local', '--connector-revision', 'local/1',
    '--strategy-revision', 'strategy/1',
    '--operation-capability-cid', operationCapability,
    '--issuer-capability-cid', issuerCapability,
    '--budget-retained-bytes', '1048576', '--budget-execution-bytes', '1048576',
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
    transferJournal = join(root, 'site-transfer.sqlite3'),
  } = {}) => {
    const child = spawn(executable, ['run', ...common,
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
  const within = (promise, what, milliseconds = 60_000) => Promise.race([
    promise,
    new Promise((_, reject) => setTimeout(() =>
      reject(new Error(`timed out waiting for ${what}`)), milliseconds)),
  ]);
  const entries = async () => existsSync(entryLog)
    ? (await readFile(entryLog, 'utf8')).split('\n').filter(Boolean) : [];

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
  let expectedEntries = (await entries()).length;
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
  const publicationRoot = join(root, 'publication');
  const ninthIntentTag = 'ninth';
  const ninthRelease = (async () => {
    const intent = siteControl.prepareOutputIntent(ninth, {
      storeAuthorityCid: physicalCid('resident-publication-store'),
      publicationAttemptCid: physicalCid(`resident-publication-${ninthIntentTag}`),
      resultDefinitionCid,
      orderingEvidenceCid: physicalCid('resident-ordering'),
      coordinatorAuthority: 'cloud-coordinator',
      transferAttemptId: `resident-transfer-${ninthIntentTag}`,
      transferRoute: 'direct',
      destinationSite: 'cloud-results',
      destinationSiteGeneration: 1,
      transferMaxBytes: 1048576n,
      transferExpiresAtMilliseconds: 4102444800000n,
      sourceGrantCid: physicalCid('resident-source-grant'),
      destinationGrantCid: physicalCid('resident-destination-grant'),
      routeCapabilityCid: physicalCid('resident-direct-route'),
      transferOrigin: receiver.origin,
    });
    const planned = await within(gateway.plan({dispatch: ninth, intent,
      subject: ninthTerminal.subject, maxChunks: 8, maxManifestBytes: 65536,
      maxReferencedBytes: 1048576n}), 'ninth plan');
    await within(gateway.output({dispatch: ninth, intent,
      payloadRequest: planned.payloadRequest,
      transferRequest: planned.transferRequest}), 'ninth output');
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
  const reservedPayloadBytes = () => {
    const database = new DatabaseSync(join(publicationRoot,
      '.actql-publication.sqlite3'), {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      const row = database.prepare('SELECT COALESCE(SUM(reserved_bytes), 0) ' +
        'AS bytes FROM actql_capacity WHERE namespace = ?')
        .get('publication_payload');
      return Number(row.bytes);
    } finally {
      database.close();
    }
  };
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
  const journalPath = join(root, 'journal.sqlite3');
  const pendingIntents = () => {
    const database = new DatabaseSync(journalPath, {readOnly: true});
    database.exec('PRAGMA busy_timeout = 5000');
    try {
      return database.prepare('SELECT record_key FROM actql_records ' +
        'WHERE namespace = ? AND record_key NOT IN (SELECT record_key ' +
        'FROM actql_records WHERE namespace = ?)')
        .all('site_output_intent', 'site_output_intent_done')
        .map(row => row.record_key);
    } finally {
      database.close();
    }
  };
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
  // A real journal write failure: another connection holds the write lock
  // longer than the Site's busy timeout.
  const lockJournal = async () => {
    const database = new DatabaseSync(journalPath);
    for (let attempt = 0; ; attempt += 1) {
      try {
        database.exec('BEGIN IMMEDIATE');
        break;
      } catch (error) {
        if (attempt > 400) throw error;
        await new Promise(resolve => setTimeout(resolve, 25));
      }
    }
    return () => {
      database.exec('ROLLBACK');
      database.close();
    };
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
  const foreignStagingBefore = JSON.stringify(await stat(foreignStaging));
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
    assert.equal(JSON.stringify(await stat(foreignStaging)),
      foreignStagingBefore, `${tag} foreign staging untouched`);
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

  // Each entry names one holder claimant and one attempt key; no attempt
  // key appears twice.
  const keys = (await entries()).map(line => line.split(' ')[1]);
  assert.equal(new Set(keys).size, keys.length);
  console.log('native resident Site acceptance passed');
} catch (error) {
  console.error('resident Site test failed:', error);
  if (currentSite !== undefined) {
    console.error('resident Site output:', JSON.stringify(currentSite.lines));
    console.error('resident Site stderr:', currentSite.stderr());
  }
  throw error;
} finally {
  for (const child of running) child.kill('SIGKILL');
  if (gateway !== undefined) await gateway.close().catch(() => {});
  if (receiver !== undefined) await receiver.close().catch(() => {});
  receiverJournal?.close();
  receiverStore?.close();
  await receiverStore?.cleanup();
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    await rm(root, {recursive: true, force: true});
  } else {
    console.error(`native resident Site scratch kept: ${root}`);
  }
}
