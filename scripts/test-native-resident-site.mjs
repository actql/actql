// Real-process acceptance for the outbound-only resident Site: a native
// control process polls a bearer-authenticated outbound gateway (standing in
// for the Cloud), admits a source-free Values Run from typed run materials,
// and runs it in a separate executor holder. The executor entry count is
// read from a synced evidence file, never from transport logs.
import assert from 'node:assert/strict';
import {execFileSync, spawn} from 'node:child_process';
import {createHash, generateKeyPairSync} from 'node:crypto';
import {once} from 'node:events';
import {chmod, mkdir, mkdtemp, readFile, rm, writeFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
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
      .find(path => existsSync(path))
    : 'libcrypto.so.3');
const targetTriple = process.platform === 'darwin'
  ? (process.arch === 'arm64' ? 'aarch64-apple-darwin' : 'x86_64-apple-darwin')
  : (process.arch === 'arm64' ? 'aarch64-unknown-linux-gnu'
    : 'x86_64-unknown-linux-gnu');
const physicalCid = value =>
  `sha256:${createHash('sha256').update(value).digest('hex')}`;
const openssl = (...args) =>
  execFileSync('openssl', args, {cwd: root, stdio: 'ignore'});

let gateway;
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
    'coordinator-core'], {cwd: repository, stdio: 'inherit'});
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
  await Promise.all([mkdir(bundleInput), mkdir(runtimeRoot), mkdir(engineRoot)]);
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
    '--idle-wait-ms', '50', '--min-backoff-ms', '50', '--max-backoff-ms', '200',
    '--shutdown-wait-ms', '10000',
  ];
  const startSite = (extra = []) => {
    const child = spawn(executable, ['run', ...common, ...extra], {
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
  const terminal = await within(gateway.query({dispatch: first}), 'query');
  assert.equal(terminal.state[0], 3, 'native settled');
  assert.equal((await entries()).length, 1);

  // 2. The same attempt delivered again is never started again.
  const again = await within(gateway.dispatch({dispatch: first,
    inputBindingBody: '{}', dispatchEnvelope: materialsEnvelope(first)}),
  'redelivery');
  assert.deepEqual(again.state, terminal.state);
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
  const secondTerminal = await within(gateway.query({dispatch: second}),
    'second query');
  assert.equal(secondTerminal.state[0], 3);

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
  const fourthTerminal = await within(gateway.query({dispatch: fourth}),
    'fourth query');
  assert.equal(fourthTerminal.state[0], 3);
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
  const fifthTerminal = await within(gateway.query({dispatch: fifth}),
    'fifth query');
  assert.equal(fifthTerminal.state[0], 3);
  assert.equal((await entries()).length, 5);
  left.child.kill('SIGTERM');
  right.child.kill('SIGTERM');
  await Promise.all([left.exited, right.exited]);

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
  if (gateway !== undefined) await gateway.close();
  if (process.env.ACTQL_TEST_PRESERVE_SCRATCH !== '1') {
    await rm(root, {recursive: true, force: true});
  } else {
    console.error(`native resident Site scratch kept: ${root}`);
  }
}
