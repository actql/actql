// Existing normal SDK/read/first-close/Saved protocol with timed input DATA.
// Product imports resolve only from the explicitly selected normal installation.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {createRequire} from 'node:module';
import {pathToFileURL} from 'node:url';
import {observeOwnScopedStateFds} from './conformance.mjs';
import {withInstalledFamilyFirstClose, assertFamilyReadState,
  installedFamilyResultOnOriginal} from './fixture-source/adapters/host-node/fixtures/installed-family-read.fixture.mjs';
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
const report = {requestKind, phase, counters: {installedResolutionAttempts: 0, publicStart: 0,
  publicStartSource: 0, publicAttach: 0, publicWait: 0, publicStatus: 0, publicResultAll: 0,
  publicClose: 0, secretResolutions: 0}, firstCloseAcknowledged: false,
  compilerInvocations: {observable: false, value: null},
  internalModuleInitializationCount: {observable: false, value: null},
  generatedInstallationLoadBoundary: {required: requestKind === 'source', observed: false},
  performanceAcceptance: false};
let client, primary, observation, countedClose;
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
  // Capture the public getter from the SAME installed namespace once, before
  // the Host awaits and before the original submission pending is produced.
  const getSubmissionInput = publicSdk.getSubmissionInput;
  assert.equal(typeof getSubmissionInput, 'function');
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
      rows: JSON.parse(await readFile(join(root, 'original-rows.json'), 'utf8')),
      state: JSON.parse(await readFile(join(root, 'original-state.json'), 'utf8'))};
    assertFamilyReadState(original.state);
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
  const close = client.close;
  countedClose = (...args) => {
    report.counters.publicClose++;
    const pending = Reflect.apply(close, client, args);
    // Observe the real public return without replacing its Promise or issuing
    // another close. A rejected original close cannot manufacture an ACK.
    Promise.resolve(pending).then(() => {report.firstCloseAcknowledged = true;},
      cause => {report.firstCloseFailure = scalarFailure(cause);});
    return pending;
  };
  await withInstalledFamilyFirstClose({close: countedClose}, join(outputRoot, 'first-close.json'), async () => {
    const before = wallObservation();
    let execution;
    if (phase === 'read') {
      const program = requestKind === 'values' ? timedValuesProgram() : timedSourceProgram(configuration.connectorId);
      let pending;
      if (requestKind === 'values') {report.counters.publicStart++; pending = client.start(program);}
      else {report.counters.publicStartSource++; pending = client.startSource(JSON.stringify(program), {format: 'json'});}
      const settled = Promise.resolve(pending).then(value => ({value}), cause => ({failed: true, cause}));
      let input;
      try {input = Reflect.apply(getSubmissionInput, publicSdk, [pending]);}
      catch (cause) {await save('original-submission-input.json', {available: false,
        projectionFailure: scalarFailure(cause)}); throw cause;}
      await save('original-submission-input.json', input === undefined ? {available: false} : {available: true, input});
      const outcome = await settled;
      if (outcome.failed) throw outcome.cause;
      assert.notEqual(input, undefined, 'OriginalTimedSubmissionInputUnavailable');
      execution = outcome.value;
      await save('original-reference.json', execution.ref);
      report.counters.publicWait++;
      const waited = await execution.wait();
      await save('original-wait.json', waited); assertFamilyReadState(waited);
    } else {
      report.counters.publicAttach++;
      execution = await client.attach(original.reference);
      assert.deepEqual(execution.ref, original.reference);
    }
    const result = installedFamilyResultOnOriginal(execution, execution.ref, 'rows');
    report.counters.publicResultAll++;
    // Preserve complete raw rows before metadata or any independent assertion.
    // In Saved this is the FIRST Result materialization before status/describe.
    const rows = await result.all();
    await save(phase === 'read' ? 'original-rows.json' : 'saved-rows.json', rows);
    const after = wallObservation();
    observation = {before, after, ...assertTimedRows(rows,
      {requestKind, phase, before, after, originalRows: original?.rows})};
    await save('clock-observation.json', observation);
    report.counters.publicStatus++;
    const state = await execution.status();
    await save(phase === 'read' ? 'original-state.json' : 'saved-state.json', state);
    if (phase === 'saved') assertFamilyReadState(state, original.state.run_id);
    else assertFamilyReadState(state);
    report.physicalStop = state.control?.physical_stop ?? 'UNOBSERVABLE';
    assert.equal(report.physicalStop, 'confirmed', 'ActualPublicPhysicalStopNotConfirmed');
  });
  assert.equal(report.counters.publicStart, phase === 'read' && requestKind === 'values' ? 1 : 0);
  assert.equal(report.counters.publicStartSource, phase === 'read' && requestKind === 'source' ? 1 : 0);
  assert.equal(report.counters.publicAttach, phase === 'saved' ? 1 : 0);
  assert.equal(report.counters.publicWait, phase === 'read' ? 1 : 0);
  assert.equal(report.counters.publicStatus, 1); assert.equal(report.counters.publicResultAll, 1);
  assert.equal(report.counters.publicClose, 1);
  if (phase === 'saved' || requestKind === 'values') assert.equal(report.counters.secretResolutions, 0);
  report.passed = true;
} catch (cause) {
  primary = cause; report.passed = false; report.primary = scalarFailure(cause);
} finally {
  // Only setup failure before the shared helper's first attempt reaches this
  // branch. Never retry an attempted, failed or pending original close.
  if (client !== undefined && report.counters.publicClose === 0) {
    try {
      if (countedClose !== undefined) await countedClose();
      else {report.counters.publicClose++; await client.close(); report.firstCloseAcknowledged = true;}
    } catch (cause) {report.firstCloseFailure = scalarFailure(cause); primary ??= cause;}
  }
  report.physicalObservationBoundary = client === undefined
    ? 'After initialization/fixture failure, no public close ACK'
    : 'After the original first public close attempt; ACK recorded separately';
  report.fdAfterFirstClose = observeOwnScopedStateFds(configuration.stateRoots);
  if (!primary && (!report.firstCloseAcknowledged || !report.fdAfterFirstClose.scopedStateFd0)) {
    primary = new Error('ActualOriginalCloseOrScopedPhysicalReleaseNotConfirmed');
    report.passed = false; report.primary = scalarFailure(primary);
  }
  await save('timed-consumer-report.json', report);
  await save('consumer-binding.json', {phase, requestKind,
    secretResolutions: report.counters.secretResolutions, counters: report.counters,
    generatedInstallationLoadBoundary: report.generatedInstallationLoadBoundary,
    compilerInvocations: report.compilerInvocations,
    internalModuleInitializationCount: report.internalModuleInitializationCount});
  await save('outcome.json', {passed: report.passed === true && primary === undefined,
    publicCloseAcknowledged: report.firstCloseAcknowledged,
    scopedStateFd0: report.fdAfterFirstClose.scopedStateFd0,
    ...(report.primary ? {primary: report.primary} : {})});
}
if (primary) throw primary;
