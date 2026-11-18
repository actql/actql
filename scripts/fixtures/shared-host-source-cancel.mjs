// One original installed Host, its physical TLS listeners, two independent
// Source clients and the existing Native Remote cancellation operations.
import assert from 'node:assert/strict';
import {spawn} from 'node:child_process';
import {createServer} from 'node:https';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {userInfo} from 'node:os';
import {readFile, writeFile} from 'node:fs/promises';
import {join} from 'node:path';
import {setTimeout as delay} from 'node:timers/promises';

const [configurationPath] = process.argv.slice(2); assert(process.argv.length === 3);
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const root = configuration.outputRoot, records = [], flights = [];
const clientCrash = configuration.scenario === 'client-crash';
const ownerCrash = configuration.scenario === 'owner-crash';
const ownerRecover = configuration.scenario === 'owner-recover';
assert(configuration.scenario === undefined || clientCrash || ownerCrash || ownerRecover,
  'Unknown shared Source acceptance scenario');
const nativeWaitEntered = Promise.withResolvers();
const save = (name, value) => writeFile(join(root, name), JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const read = async name => JSON.parse(await readFile(join(root, name), 'utf8'));
const require = createRequire(join(configuration.consumerRoot, 'package.json'));
const {openInstalledRemoteHttpHost} = await import(pathToFileURL(require.resolve('@actql/local-node/http-host')).href);
const {createInstalledConnectorTable} = await import(pathToFileURL(require.resolve('@actql/local-node')).href);
const connector = await import(pathToFileURL(require.resolve(configuration.connectorPackage)).href);
let dispatches = 0, secretResolutions = 0;
const host = await openInstalledRemoteHttpHost({...configuration.installation,
  connectorTable: createInstalledConnectorTable(connector.installedConnectors),
  beforeDispatch() {dispatches++;},
  authenticate: header => header === 'Bearer fixture-token' ? userInfo().username : undefined,
  async resolveSourceSecret() {secretResolutions++; return readFile(configuration.fixtureSecretPath, 'utf8');},
});
const certificate = await readFile(configuration.certificate), key = await readFile(configuration.privateKey);
const server = createServer({key, cert: certificate, ca: certificate, requestCert: true, rejectUnauthorized: true}, (request, response) => {
  if (clientCrash && request.url === '/actql/client/0.1/wait') {
    nativeWaitEntered.resolve({tlsRequestArrivedAt: new Date().toISOString()});
  }
  return host.handler(request, response);
});
const sdkServer = createServer({key, cert: certificate}, host.handler);
await Promise.all([server, sdkServer].map(value => new Promise(resolve => value.listen(0, '127.0.0.1', resolve))));
await save('connection.json', {mode: 'remote', owner: 'remote', durability: 'durable', consentRefs: [], runners: []});
await writeFile(join(root, 'token.txt'), 'fixture-token\n', {mode: 0o600, flag: 'wx'});
const common = ['--endpoint', `https://127.0.0.1:${server.address().port}/`,
  '--connection-root', root, '--connection-file', 'connection.json', '--token-root', root, '--token-file', 'token.txt',
  '--http-library', process.platform === 'darwin' ? '/usr/lib/libcurl.4.dylib' : 'libcurl.so.4',
  '--ca', configuration.certificate, '--cert', configuration.certificate, '--key', configuration.privateKey];
let writes = Promise.resolve();
async function command(executable, argv, label) {
  const startedAt = new Date().toISOString();
  const record = await new Promise((resolve, reject) => {
    const child = spawn(executable, argv, {cwd: root, env: process.env, stdio: ['ignore', 'pipe', 'pipe']});
    let stdout = '', stderr = '', bytes = 0, terminationReason = null;
    const timer = setTimeout(() => {terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 30_000);
    for (const [stream, isError] of [[child.stdout, false], [child.stderr, true]]) stream.on('data', chunk => {
      bytes += chunk.length;
      if (bytes > 8 * 1024 * 1024) {terminationReason = 'output-limit'; child.kill('SIGTERM');}
      else if (isError) stderr += chunk; else stdout += chunk;
    });
    child.once('error', error => {clearTimeout(timer); reject(error);});
    child.once('close', (code, signal) => {clearTimeout(timer); resolve({label, pid: child.pid ?? null,
      startedAt, endedAt: new Date().toISOString(), code, signal, terminationReason, stdout, stderr});});
  });
  records.push(record);
  const bytes = JSON.stringify(records, null, 2) + '\n';
  writes = writes.then(() => writeFile(join(root, 'source-client-commands.json'), bytes)); await writes;
  assert.equal(record.code, 0, `${label}: ${record.stderr}`); assert.equal(record.signal, null);
  assert.equal(record.terminationReason, null); return record.stdout;
}
const native = async (...args) => JSON.parse(await command(configuration.executable, [...common, ...args], args[0]));
async function crashOriginalNativeWait() {
  // The parent verifies this installed binary through the existing complete
  // artifact/platform/ABI admission. Killing the npm launcher would leave its
  // spawnSync Native child outside this retained child handle.
  assert.equal(typeof configuration.nativeCrashExecutable, 'string');
  const startedAt = new Date().toISOString();
  const child = spawn(configuration.nativeCrashExecutable, [...common, 'wait', '--ref-file', 'source-first-run.json'],
    {cwd: root, env: process.env, stdio: ['ignore', 'pipe', 'pipe']});
  let stdout = '', stderr = '', bytes = 0, terminationReason = null, nativeExit = null;
  const timer = setTimeout(() => {terminationReason = 'original-child-timeout'; child.kill('SIGTERM');}, 30_000);
  for (const [stream, isError] of [[child.stdout, false], [child.stderr, true]]) stream.on('data', chunk => {
    bytes += chunk.length;
    if (bytes > 8 * 1024 * 1024) {terminationReason = 'output-limit'; child.kill('SIGTERM');}
    else if (isError) stderr += chunk; else stdout += chunk;
  });
  const terminal = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => {nativeExit = {at: new Date().toISOString(), code, signal};});
    child.once('close', (code, signal) => resolve({code, signal, streamsClosedAt: new Date().toISOString()}));
  });
  terminal.catch(() => undefined);
  try {
    const arrival = await Promise.race([nativeWaitEntered.promise, terminal.then(() => {throw new Error('Native wait exited before its HTTP request');})]);
    const signalSendStartedAt = new Date().toISOString();
    const signalAccepted = child.kill('SIGKILL');
    const signalSentAt = new Date().toISOString();
    assert(signalAccepted, 'Only this own spawned Native child is targeted');
    const result = await terminal;
    const record = {label: 'expected-native-client-crash', pid: child.pid,
      executable: configuration.nativeCrashExecutable, startedAt, ...arrival,
      signalSendStartedAt, signalSentAt, signalAccepted, nativeExit,
      ...result, stdout, stderr, terminationReason,
      actualTlsWaitRequestObserved: true, internalWaitAdmission: 'UNOBSERVED',
      publicCloseAttempted: false, publicOperationReturned: false};
    await save('native-client-crash.json', record);
    assert.equal(result.code, null); assert.equal(result.signal, 'SIGKILL'); assert.equal(terminationReason, null);
  } finally {clearTimeout(timer);}
}

async function marker(path) {
  const signal = AbortSignal.timeout(30_000);
  while (true) {
    signal.throwIfAborted();
    try {return JSON.parse(await readFile(path, 'utf8'));}
    catch (error) {if (error.code !== 'ENOENT') throw error;}
    await delay(10, undefined, {signal});
  }
}
const originalFailure = flight => flight.then(() => {throw new Error('Source client exited before the controlled Read boundary');});
let primary, failed = false;
const report = {passed: false, scope: 'same-Host cancellation with another original Source Read still held'};
try {
  const childInput = join(root, 'source-client-input.json');
  await writeFile(childInput, JSON.stringify({consumerRoot: configuration.consumerRoot, outputRoot: root,
    originalRefRoot: configuration.originalRefRoot,
    endpoint: `https://127.0.0.1:${sdkServer.address().port}/`, programPath: configuration.programPath}), {flag: 'wx'});
  if (ownerRecover) {
    await command(process.execPath, [configuration.clientScript, childInput, 'recover-first'], 'source-recover-first');
    await command(process.execPath, [configuration.clientScript, childInput, 'observe-second'], 'source-observe-second');
    report.scope = 'explicit owner restart: completed SAME original Saved and interrupted original status only';
    report.completedOriginalSaved = true;
    report.interruptedOriginalStatusObserved = true;
    assert.equal(dispatches, 0, 'Restart/Saved/status must not dispatch another original Source');
  } else {
  if (clientCrash || ownerCrash) {
    await command(process.execPath, [configuration.clientScript, childInput, 'first-submit'], 'source-first-submit');
    const firstClose = await read('source-first-submit-report.json');
    assert.equal(firstClose.clientCloseReturned, true);
    await marker(configuration.pageEntered.first);
    if (ownerCrash) {
      const completed = command(process.execPath, [configuration.clientScript, childInput, 'recover-first'], 'source-recover-first');
      completed.catch(() => undefined); flights.push(completed);
      await save('release-first.json', {completeOriginalBeforeOwnerCrash: true});
      await completed;
      await command(process.execPath, [configuration.clientScript, childInput, 'second-submit'], 'source-second-submit');
      await marker(configuration.pageEntered.second);
      const completedState = await native('status', '--ref-file', 'source-first-run.json');
      const interruptedState = await native('status', '--ref-file', 'source-second-run.json');
      assert.equal(completedState.status, 'succeeded'); assert.equal(completedState.result_available, true);
      assert.equal(interruptedState.status, 'running'); assert.equal(interruptedState.result_available, false);
      await save('states-before-owner-crash.json', {completed: completedState, interrupted: interruptedState});
      // The parent retains this actual Host child handle and kills it only
      // after this observed boundary. No shutdown ACK is emitted here.
      console.log(JSON.stringify({stage: 'owner-crash-ready', pid: process.pid, at: new Date().toISOString()}));
      await new Promise(() => {});
    }
    const second = command(process.execPath, [configuration.clientScript, childInput, 'second'], 'source-second');
    second.catch(() => undefined); flights.push(second);
    await Promise.race([marker(configuration.pageEntered.second), originalFailure(second)]);
    await Promise.race([marker(join(root, 'source-second-run.json')), originalFailure(second)]);
  } else {
    for (const phase of ['first', 'second']) {
      const flight = command(process.execPath, [configuration.clientScript, childInput, phase], `source-${phase}`);
      flight.catch(() => undefined); flights.push(flight);
      await Promise.race([marker(configuration.pageEntered[phase]), ...flights.map(originalFailure)]);
      await Promise.race([marker(join(root, `source-${phase}-run.json`)), ...flights.map(originalFailure)]);
    }
  }
  const firstRef = await read('source-first-run.json'), secondRef = await read('source-second-run.json');
  assert.notDeepEqual(firstRef, secondRef);
  const before = await native('status', '--ref-file', 'source-first-run.json');
  const otherBefore = await native('status', '--ref-file', 'source-second-run.json');
  await save('state-before-cancel.json', {first: before, second: otherBefore});
  for (const state of [before, otherBefore]) {
    assert.equal(state.status, 'running'); assert.equal(state.result_available, false);
    assert.equal(state.control.cancellation_requested, false); assert.equal(state.control.physical_stop, 'unknown');
  }
  if (clientCrash) {
    await crashOriginalNativeWait();
    const firstAfter = await native('status', '--ref-file', 'source-first-run.json');
    const secondAfter = await native('status', '--ref-file', 'source-second-run.json');
    await save('states-after-client-crash.json', {first: firstAfter, second: secondAfter});
    for (const state of [firstAfter, secondAfter]) {
      assert.equal(state.status, 'running'); assert.equal(state.result_available, false);
      assert.equal(state.control.cancellation_requested, false);
    }
    const recovered = command(process.execPath, [configuration.clientScript, childInput, 'recover-first'], 'source-recover-first');
    recovered.catch(() => undefined); flights.push(recovered);
    await save('release-first.json', {afterOwnNativeClientCrashAndUnchangedOriginalStates: true});
    await recovered;
    const stillRunning = await native('status', '--ref-file', 'source-second-run.json');
    assert.equal(stillRunning.status, 'running'); assert.equal(stillRunning.control.cancellation_requested, false);
    await save('other-run-after-first-recovery.json', stillRunning);
    await save('release-second.json', {firstOriginalRecoveredWithoutSubmit: true});
    await flights[0];
    const recovery = await read('source-recover-first-report.json');
    assert.equal(recovery.publicStartSource, 0); assert.equal(recovery.publicAttach, 1);
    report.scope = 'client detach/exit and own Native wait SIGKILL with two original held Reads';
    report.firstSourceSurvivedClientCrash = true; report.otherRunUnaffected = true;
  } else {
    const cancelId = 'shared-source-first-cancel', revision = String(before.control.revision);
    await save('original-cancellation-input.json', {ref: firstRef, cancelId, expectedRevision: before.control.revision});
    const answer = await native('cancel', '--ref-file', 'source-first-run.json', '--cancel-id', cancelId,
      '--expected-revision', revision, '--operation-attempt-id', 'shared-source-first-cancel-invocation');
    await save('original-cancellation-answer.json', answer);
    assert.equal(answer.kind, 'accepted'); assert.equal(answer.cancellation.kind, 'accepted');
    assert.deepEqual(answer.cancellation.ref, firstRef);
    const otherAfter = await native('status', '--ref-file', 'source-second-run.json');
    await save('other-run-after-cancel.json', otherAfter);
    assert.equal(otherAfter.status, 'running'); assert.equal(otherAfter.control.cancellation_requested, false);
    // Release only the physical fixture reply after the real public cancellation
    // returned. This marker is not a stop/cleanup receipt or Owner instruction.
    await save('release-first.json', {publicCancelReturned: true});
    await flights[0];
    const lookup = await native('lookup-cancellation', '--ref-file', 'source-first-run.json', '--cancel-id', cancelId,
      '--expected-revision', revision);
    assert.equal(lookup.kind, 'found'); assert.deepEqual(lookup.cancellation, answer.cancellation);
    await save('original-cancellation-lookup.json', lookup);
    const stillRunning = await native('status', '--ref-file', 'source-second-run.json');
    assert.equal(stillRunning.status, 'running'); assert.equal(stillRunning.control.cancellation_requested, false);
    await save('other-run-after-first-stop.json', stillRunning);
    await save('release-second.json', {firstOriginalCancelledAndPhysicalStopObserved: true});
    await flights[1];
    const first = await read('source-first-terminal.json'), second = await read('source-second-terminal.json');
    assert.equal(first.control.physical_stop, 'confirmed'); assert.equal(first.status, 'cancelled');
    assert.equal(second.status, 'succeeded'); assert.equal(second.control.cancellation_requested, false);
    report.firstCancellationAndPhysicalStop = true; report.otherRunUnaffected = true;
  }
  }
  report.passed = true; report.dispatchObservations = dispatches; report.secretResolutions = secretResolutions;
} catch (error) {
  failed = true; primary = error; report.failure = {name: error?.name, code: error?.code, message: error?.message};
} finally {
  // The parent releases its HTTP reply holds even after an unexpected failure.
  // Observe every original child before closing the SAME Host owner.
  await save('fixture-release-all.json', {cleanup: true});
  await Promise.allSettled(flights);
  for (const value of [sdkServer, server]) {
    try {await new Promise((resolve, reject) => value.close(error => error ? reject(error) : resolve()));}
    catch (error) {primary = failed ? new AggregateError([primary, error]) : error; failed = true;}
  }
  try {
    const returned = await host.close(); report.hostCloseReturned = true;
    // Record the existing public shutdown DATA, not opaque retained objects or
    // a synthesized ACK from the listener's close or the later FD observation.
    const fields = returned !== null && typeof returned === 'object'
      ? Object.getOwnPropertyDescriptors(returned) : {};
    const pendingRetention = fields.pendingRetention?.value;
    report.hostCloseReturn = {
      storeCleanupPending: fields.storeCleanupPending?.value,
      pendingRetentionCount: Array.isArray(pendingRetention) ? pendingRetention.length : null,
      authorizationCleanupPending: fields.authorizationCleanupPending?.value,
      diagnosticDeliveryPending: fields.diagnosticDeliveryPending?.value,
    };
    assert.equal(report.hostCloseReturn.storeCleanupPending, false);
    assert.equal(report.hostCloseReturn.pendingRetentionCount, 0);
    assert.equal(report.hostCloseReturn.authorizationCleanupPending, false);
    assert.equal(report.hostCloseReturn.diagnosticDeliveryPending, false);
  } catch (error) {
    report.hostCloseReturned ??= false; primary = failed ? new AggregateError([primary, error]) : error; failed = true;
    report.closeFailure = {name: error?.name, code: error?.code, message: error?.message};
  }
  report.passed = report.passed && !failed;
  await save('shared-source-cancel-result.json', report);
}
if (failed) throw primary;
console.log(JSON.stringify({stage: 'closed', pid: process.pid, clientCloseReturned: true, hostCloseReturned: true}));
const acknowledgement = await new Promise(resolve => {
  let input = ''; process.stdin.setEncoding('utf8');
  process.stdin.on('data', chunk => {input += chunk; if (input.includes('\n')) resolve(input);});
  process.stdin.once('end', () => resolve(input));
});
assert.equal(acknowledgement, 'observed\n');
console.log(JSON.stringify({stage: 'close-observation-ack', pid: process.pid}));
