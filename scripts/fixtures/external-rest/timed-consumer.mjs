// Existing normal SDK/read/first-close/Saved protocol with timed input DATA.
// Nothing imports an installed product until this explicitly selected child runs.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {captureStandardRestRead, recoverStandardRestRead, observeOwnScopedStateFds} from './conformance.mjs';
import {loadExternalRestModules} from './installed-modules.mjs';
import {resolveInstalledCompletionModules} from './timed-installed-context.fixture.mjs';
import {timedValuesProgram, timedSourceProgram, assertTimedRows, wallObservation} from './timed-inputs.fixture.mjs';

const [configurationPath, phase] = process.argv.slice(2);
assert(configurationPath && ['read', 'saved'].includes(phase));
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const requestKind = configuration.requestKind;
assert(['values', 'source'].includes(requestKind));
const outputRoot = resolve(configuration.outputRoot, phase);
await mkdir(outputRoot, {recursive: true});
const save = (name, value) => writeFile(join(outputRoot, name), JSON.stringify(value, null, 2) + '\n', {flag: 'wx'});
const scalarFailure = cause => ({name: String(cause?.name ?? 'Error'),
  message: String(cause?.message ?? cause), ...(typeof cause?.code === 'string' ? {code: cause.code} : {})});
const report = {requestKind, phase, counters: {installedResolutionAttempts: 0, publicStartSource: 0,
  publicAttach: 0, publicClose: 0, secretResolutions: 0},
  compilerInvocations: {observable: false, value: null},
  internalModuleInitializationCount: {observable: false, value: null},
  generatedInstallationLoadBoundary: {required: requestKind === 'source', observed: false},
  executionWaitStatusAndResultMethodCounts: {observableThroughExistingHelper: false, value: null},
  performanceAcceptance: false};
let client, primary, observation;
try {
  let connect, publicSdk, connectorTable, productModules, loadedInstallationExports;
  report.counters.installedResolutionAttempts++;
  if (requestKind === 'source') {
    const modules = await loadExternalRestModules({consumerRoot: resolve(configuration.consumerRoot),
      connectorPackage: configuration.connectorPackage});
    ({connect, publicSdk, connectorTable, paths: productModules, loadedInstallationExports} = modules);
    report.generatedInstallationLoadBoundary = {required: true, observed: true,
      loadedInstallationExports, initializationCount: 'UNOBSERVABLE'};
  } else {
    const modules = await resolveInstalledCompletionModules(resolve(configuration.consumerRoot));
    publicSdk = createRequire(modules.node)('@actql/sdk');
    ({connect} = await import(pathToFileURL(modules.node).href));
    productModules = modules;
    assert(!Object.hasOwn(configuration.installation, 'sourceProfilePath'));
    assert(!Object.hasOwn(configuration.installation, 'sourceProfilePaths'));
  }
  await save('installation-module.json', {productModules, loadedInstallationExports,
    generatedInstallationLoadBoundary: report.generatedInstallationLoadBoundary, HostOpened: false});
  const keys = requestKind === 'source'
    ? ['authorization', 'directory', 'sourceProfilePath', 'sourceProfilePaths']
    : ['authorization', 'directory'];
  assert(configuration.installation && Object.keys(configuration.installation).every(key => keys.includes(key)));
  let original;
  if (phase === 'saved') {
    const root = resolve(configuration.outputRoot, 'read');
    const outcome = JSON.parse(await readFile(join(root, 'outcome.json'), 'utf8'));
    assert(outcome.passed && outcome.publicCloseAcknowledged && outcome.scopedStateFd0);
    original = {reference: JSON.parse(await readFile(join(root, 'original-reference.json'), 'utf8')),
      originalRows: JSON.parse(await readFile(join(root, 'original-rows.json'), 'utf8')),
      state: JSON.parse(await readFile(join(root, 'original-state.json'), 'utf8'))};
  }
  try {
    client = await connect({mode: 'local', owner: 'local', durability: 'durable', installation: {
      ...configuration.installation,
      ...(requestKind === 'source' ? {connectorTable, async resolveSourceSecret() {
        report.counters.secretResolutions++;
        return readFile(configuration.fixtureSecretPath, 'utf8');
      }} : {}),
    }});
  } catch (cause) {
    await save('connect-failure.json', {clientReturned: false, publicCloseAttempted: false,
      publicCloseAcknowledged: false, primary: scalarFailure(cause),
      ownPhysicalObservation: observeOwnScopedStateFds(configuration.stateRoots)});
    throw cause;
  }
  // Count calls at original public ports, preserving their actual receiver,
  // pending/Execution identity and returned Promise. No product hook is added.
  const startSource = client.startSource, attach = client.attach, close = client.close;
  const observedClient = Object.freeze({
    startSource(...args) {report.counters.publicStartSource++; return Reflect.apply(startSource, client, args);},
    attach(...args) {report.counters.publicAttach++; return Reflect.apply(attach, client, args);},
    close(...args) {report.counters.publicClose++; return Reflect.apply(close, client, args);},
  });
  const before = wallObservation();
  const common = {outputRoot, stateRoots: configuration.stateRoots, assertRows(rows) {
    const after = wallObservation();
    observation = {before, after, ...assertTimedRows(rows,
      {requestKind, phase, before, after, originalRows: original?.originalRows})};
  }};
  if (phase === 'read') {
    const program = requestKind === 'values' ? timedValuesProgram() : timedSourceProgram(configuration.connectorId);
    await captureStandardRestRead(observedClient, {...common, publicSdk, program});
  } else {
    await recoverStandardRestRead(observedClient, {...common, ...original});
    const saved = JSON.parse(await readFile(join(outputRoot, 'saved-state.json'), 'utf8'));
    assert.equal(typeof original.state.run_id, 'string');
    assert(original.state.run_id.length > 0);
    assert.equal(saved.run_id, original.state.run_id);
  }
  await save('clock-observation.json', observation);
  const state = JSON.parse(await readFile(join(outputRoot,
    phase === 'read' ? 'original-state.json' : 'saved-state.json'), 'utf8'));
  report.physicalStop = state.control?.physical_stop ?? 'UNOBSERVABLE';
  assert.equal(report.physicalStop, 'confirmed', 'ActualPublicPhysicalStopNotConfirmed');
  assert.equal(report.counters.publicStartSource, phase === 'read' ? 1 : 0);
  assert.equal(report.counters.publicAttach, phase === 'saved' ? 1 : 0);
  assert.equal(report.counters.publicClose, 1);
  if (phase === 'saved' || requestKind === 'values') assert.equal(report.counters.secretResolutions, 0);
  report.passed = true;
} catch (cause) {
  primary = cause; report.passed = false; report.primary = scalarFailure(cause);
} finally {
  // The helper owns its original first close. Only a failure before that
  // attempt reaches this path; never retry an attempted or pending close.
  if (client !== undefined && report.counters.publicClose === 0) {
    const close = {attempted: true, acknowledged: false, businessPassed: false};
    report.counters.publicClose++;
    try {await client.close(); close.acknowledged = true;}
    catch (cause) {close.failure = scalarFailure(cause); primary ??= cause;}
    close.fd = observeOwnScopedStateFds(configuration.stateRoots);
    await save('first-close.json', close);
    await save('outcome.json', {passed: false, primary: report.primary,
      publicCloseAcknowledged: close.acknowledged, scopedStateFd0: close.fd.scopedStateFd0});
  }
  await save('timed-consumer-report.json', report);
  await save('consumer-binding.json', {phase, requestKind,
    secretResolutions: report.counters.secretResolutions, counters: report.counters,
    generatedInstallationLoadBoundary: report.generatedInstallationLoadBoundary,
    compilerInvocations: report.compilerInvocations,
    internalModuleInitializationCount: report.internalModuleInitializationCount});
}
if (primary) throw primary;
