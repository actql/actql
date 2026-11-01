// Run only after the caller has verified one coherent normal installation.
// Product imports resolve from that installation, never from checkout source.
import assert from 'node:assert/strict';
import {readFile, writeFile, mkdir} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {captureStandardRestRead, recoverStandardRestRead, observeOwnScopedStateFds} from './conformance.mjs';
import {externalRestProgram, externalRestProvider} from './provider.fixture.mjs';
import {loadExternalRestModules} from './installed-modules.mjs';

const [configurationPath, phase] = process.argv.slice(2);
assert(configurationPath && ['read', 'saved'].includes(phase),
  'Usage: consumer.mjs <fresh-own-configuration.json> read|saved');
const configuration = JSON.parse(await readFile(configurationPath, 'utf8'));
const consumerRoot = resolve(configuration.consumerRoot);
const {connect, publicSdk, connectorTable, paths: productModules,
  loadedInstallationExports} = await loadExternalRestModules({consumerRoot,
  connectorPackage: configuration.connectorPackage});
const outputRoot = resolve(configuration.outputRoot, phase);
await mkdir(outputRoot, {recursive: true});
await writeFile(join(outputRoot, 'installation-module.json'), JSON.stringify({
  productModules, loadedInstallationExports, generatedInstallationLoaded: true,
  HostOpened: false,
}, null, 2) + '\n', {flag: 'wx'});
const startedAt = new Date().toISOString(), started = performance.now();
const sourceProfileKeys = ['authorization', 'directory', 'sourceProfilePath', 'sourceProfilePaths'];
assert(configuration.installation && Object.keys(configuration.installation)
  .every(key => sourceProfileKeys.includes(key)), 'Only original public installation configuration is accepted');
const provider = externalRestProvider({mode: configuration.mode});
let original;
if (phase === 'saved') {
  const originalRoot = resolve(configuration.outputRoot, 'read');
  const outcome = JSON.parse(await readFile(join(originalRoot, 'outcome.json'), 'utf8'));
  assert.equal(outcome.passed, true);
  assert.equal(outcome.publicCloseAcknowledged, true);
  assert.equal(outcome.scopedStateFd0, true);
  original = {
    reference: JSON.parse(await readFile(join(originalRoot, 'original-reference.json'), 'utf8')),
    originalRows: JSON.parse(await readFile(join(originalRoot, 'original-rows.json'), 'utf8')),
  };
}
let secretResolutions = 0;
let client;
try {
  client = await connect({mode: 'local', owner: 'local', installation: {
    ...configuration.installation,
    connectorTable,
    // One ordinary Host secret resolver, outside all author/provider code.
    async resolveSourceSecret() {
      secretResolutions++;
      return readFile(configuration.fixtureSecretPath, 'utf8');
    },
  }});
} catch (cause) {
  await writeFile(join(outputRoot, 'connect-failure.json'), JSON.stringify({clientReturned: false,
    publicCloseAttempted: false, publicCloseAcknowledged: false,
    primary: {name: String(cause?.name ?? 'Error'), message: String(cause?.message ?? cause),
      ...(typeof cause?.code === 'string' ? {code: cause.code} : {})},
    ownPhysicalObservation: observeOwnScopedStateFds(configuration.stateRoots)}, null, 2) + '\n', {flag: 'wx'});
  throw cause;
}
const connected = performance.now();
const common = {outputRoot, stateRoots: configuration.stateRoots,
  assertRows: rows => provider.assertRows(rows)};
let outcome;
if (phase === 'read') {
  outcome = await captureStandardRestRead(client, {...common, publicSdk,
    program: externalRestProgram(configuration.connectorId)});
} else {
  // The parent must spawn this phase asynchronously while it owns TLS. It
  // uses only the successfully completed original, never a failed Run retry.
  outcome = await recoverStandardRestRead(client, {...common, ...original});
}
await writeFile(join(outputRoot, 'consumer-binding.json'), JSON.stringify({
  phase, startedAt, endedAt: new Date().toISOString(),
  connectMs: connected - started, wholeConsumerMs: performance.now() - started,
  productModules,
  secretResolutions, reference: outcome.reference,
  actualPublicCloseAndFdFacts: 'first-close.json',
  instrumentedOrPerformanceAcceptance: false,
}, null, 2) + '\n', {flag: 'wx'});
