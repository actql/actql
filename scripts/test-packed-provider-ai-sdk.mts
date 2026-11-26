// Optional plugin acceptance on the same normal artifact, never a new producer.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {mkdir, copyFile, readFile, writeFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {registeredExternalPackageImages} from './initial-control-package-images.mjs';
import {prepareHealthPackages, execute} from './health-monitor-adapters.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './node-benchmark-evidence.mjs';
import {publicConsumerEnvironment, publicInstallCommand, releaseConsumerDestination,
  verifyPublicConsumer} from './release-public-install.mjs';
import {nodeReleaseIncludesProvider, verifyPackageRelease} from './package-release.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';

type ReleaseManifest = Awaited<ReturnType<typeof verifyPackageRelease>>;
type Command = typeof execute;
type ProviderOptions = {repository?: string; retained?: string; release?: string;
  publicRegistry?: boolean; cases?: readonly string[]; command?: Command};
type Observation = Record<string, unknown>;
type ObservationInput = {caseId: string; phase: string; pid: number; originalPid?: number; observation: Observation};
type PhaseRecord = {
  case: string; phase: string; status: 'unexecuted' | 'running' | 'passed' | 'failed'; reason?: string;
  pid?: number; actual?: Observation; consumer?: string; failure?: ReturnType<typeof nodeBenchmarkFailure>;
};
type Prepared = Awaited<ReturnType<typeof prepareHealthPackages>> | Awaited<ReturnType<typeof installRelease>>;
type ExternalPreparation = {archive: string; sha256: string; packageImages: ReturnType<typeof registeredExternalPackageImages>};
type Report = {
  source: string; phases: PhaseRecord[]; complete: boolean;
  preparations: (Omit<Prepared, 'publicPayload'> & {case: string;
    publicPayload?: Awaited<ReturnType<typeof verifyPublicConsumer>>;
    external?: ExternalPreparation})[];
  failures?: ReturnType<typeof nodeBenchmarkFailure>[]; cleanup?: ReturnType<typeof nodeBenchmarkFailure>[];
};

const registeredProviderCases = Object.freeze([
  'registered-project', 'registered-anthropic', 'registered-google', 'registered-mixed', 'registered-mistral',
]);
export const registeredSafetyAcceptanceCases = Object.freeze([
  'registered-openai-filter', 'registered-google-recitation', 'registered-google-blocklist',
]);
const registeredCapabilityCase = 'registered-capabilities';
const externalCase = 'registered-external';
const externalDuplicateCase = 'registered-external-double';
const externalCases: readonly string[] = [externalCase, externalDuplicateCase];
const externalAdapter = '@actql-acceptance/external-openai-adapter';
const registeredTerminalFailures = Object.freeze({
  'registered-length': 'truncated', 'registered-refusal': 'refusal',
  'registered-openai-filter': 'safety_rejected', 'registered-google-recitation': 'safety_rejected',
  'registered-google-blocklist': 'safety_rejected',
});
const registeredRefusalCases = Object.freeze([
  'registered-too-late', 'registered-invalid',
  'registered-credential-reference', 'registered-credential-header',
]);
export const registeredProviderAcceptanceCases = Object.freeze([
  ...registeredProviderCases, 'registered-length', 'registered-refusal', ...registeredRefusalCases,
]);

// Assertions over the original child report only; this issues no Run authority
// or substitute provider result. The caller still owns actual process/state
// selection, same-source software verification and independent installations.
export function checkPackedProviderObservation({caseId, phase, pid, originalPid, observation: value}: ObservationInput) {
  assert.equal(value.phase, phase);
  assert(Number.isSafeInteger(pid) && pid > 0);
  if (caseId.startsWith('registered-credential-')) {
    assert.deepEqual(value, {phase, rejected: 'RegisteredSdkCredentialMismatch',
      credentialReads: 0, tlsAttempts: 0, calls: 0});
    return;
  }
  if (caseId === 'registered-invalid') {
    assert.deepEqual(value, {phase, startupRefused: true, registrations: 0, calls: 0,
      defaultOpened: true, firstCloseReturned: true, aliveScopedFD0: true});
    return;
  }
  if (caseId === 'registered-too-late') {
    assert.deepEqual(value, {phase, startupRefused: true, registrations: 0, calls: 0});
    return;
  }
  assert.equal(value.firstCloseReturned, true); assert.equal(value.aliveScopedFD0, true);
  if (caseId === registeredCapabilityCase) {
    assert.equal(value.projectCredential, true);
    assert.equal(value.registeredSdk, true);
    assert.deepEqual(value.capabilityRoutes, ['fixture-chat', 'fixture-unsupported']);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    const journal = value.capabilityJournal as Readonly<{supported: {providerBindingCid: string; savedAttempts: number};
      refused?: {preDispatchRefusal: boolean; scopes: number}}>;
    assert.match(journal.supported.providerBindingCid, /^sha256:[0-9a-f]{64}$/u);
    assert.equal(journal.supported.savedAttempts, 1);
    if (phase === registeredCapabilityCase) {
      assert.equal(value.tasks, 2);
      for (const field of ['calls', 'requests', 'projectTlsConnects', 'originalModelStarts', 'usageCaptures']) {
        assert.equal(value[field], 1);
      }
      assert.equal(value.capabilityIssue, 'InstalledModelStructuredModelUnsupported');
      assert(Number.isSafeInteger(value.capabilityCredentialReads) && (value.capabilityCredentialReads as number) > 0);
    } else {
      assert.notEqual(pid, originalPid);
      for (const field of ['calls', 'projectTlsConnects', 'originalModelStarts', 'capabilityCredentialReads']) {
        assert.equal(value[field], 0);
      }
      if (phase === 'cold') assert.equal(value.egressChecks, 0);
    }
    assert.equal(value.deniedCredentialReads, 0);
    if (phase === 'changed-route') {
      assert.equal(value.changedIssue, 'SubmissionConflict');
      assert.equal(value.changedReason, 'model_provider_selection');
      assert.equal(value.historicalSavedAfterChange, true);
    } else {
      assert.deepEqual(journal.refused, {preDispatchRefusal: true, scopes: 0});
      assert.match(value.deniedRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
      assert.notEqual(value.deniedRunDefinitionCid, value.originalRunDefinitionCid);
      assert.equal(value.deniedModelStarts, 0);
      if (phase === 'cold') assert.equal(value.originalSavedFirst, true);
    }
    return;
  }
  if (caseId === externalDuplicateCase) {
    assert.equal(value.registeredSdk, true);
    assert.equal(value.externalTerminal, 'failed');
    assert.equal(value.externalResultIssue, 'ResultAccessDenied');
    for (const name of ['externalAdapterCid', 'externalLockCid', 'originalRunDefinitionCid']) {
      assert.match(value[name] as string, /^sha256:[a-f0-9]{64}$/u);
    }
    for (const name of ['calls', 'projectTlsConnects', 'externalTcp', 'externalCredentialReads',
      'originalModelStarts', 'usageCaptures', 'usageAuthorizations']) assert.equal(value[name], 0, name);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalFailureObserved, true);
      assert.equal(value.egressChecks, 0);
      assert.equal(value.interceptedFetches, 0);
      assert.equal(value.additionalIssue, undefined);
    } else {
      assert.equal(value.interceptedFetches, 2);
      assert.equal(value.additionalIssue, 'SdkAdditionalRequestRefused');
    }
    return;
  }
  if (caseId === externalCase) {
    assert.equal(value.registeredSdk, true);
    for (const name of ['externalAdapterCid', 'externalLockCid', 'originalRunDefinitionCid']) {
      assert.match(value[name] as string, /^sha256:[0-9a-f]{64}$/u);
    }
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalSavedFirst, true);
      for (const name of ['calls', 'projectTlsConnects', 'egressChecks', 'originalModelStarts']) assert.equal(value[name], 0);
    } else {
      for (const name of ['tasks', 'requests', 'calls', 'projectTlsConnects', 'originalModelStarts', 'usageCaptures']) {
        assert.equal(value[name], 1);
      }
      assert.equal(value.usageMode, 'reported');
    }
    return;
  }
  if (Object.hasOwn(registeredTerminalFailures, caseId)) {
    assert.equal(value.terminalFailure, registeredTerminalFailures[caseId as keyof typeof registeredTerminalFailures]);
    assert.equal(value.registeredSdk, true);
    assert.equal(value.projectCredential, true);
    assert.equal(value.maxCalls, 1);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      assert.equal(value.originalSavedFirst, true);
      for (const field of ['calls', 'egressChecks', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 0);
    } else {
      for (const field of ['tasks', 'requests', 'calls', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 1);
    }
    return;
  }
  if (caseId === 'registered-mixed') {
    assert.equal(value.registeredSdk, true); assert.equal(value.projectCredential, true);
    assert.deepEqual(value.mixedProviders, ['models/http', 'models/messages']);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
    if (phase === 'cold') {
      assert.notEqual(pid, originalPid);
      for (const field of ['calls', 'egressChecks', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 0);
      assert.equal(value.originalSavedFirst, true); assert.deepEqual(value.dispatchedProviders, []);
    } else {
      for (const field of ['calls', 'tasks', 'requests', 'projectTlsConnects', 'originalModelStarts']) assert.equal(value[field], 2);
      assert.deepEqual(value.dispatchedProviders, value.mixedProviders);
    }
    return;
  }
  const registered = registeredProviderCases.includes(caseId);
  const project = caseId === 'project-key' || registered;
  if (caseId === 'usage-reported' || project) {
    assert.equal(value.maxCalls, 1);
  }
  if (registered) assert.equal(value.registeredSdk, true);
  if (caseId === 'registered-mistral') {
    assert.equal(value.originalModelStarts, phase === 'cold' ? 0 : 1);
    assert.match(value.originalRunDefinitionCid as string, /^sha256:[0-9a-f]{64}$/u);
  }
  if (project) {
    assert.equal(value.projectCredential, true);
    assert.equal(value.projectTlsConnects, phase === 'cold' ? 0 : 1);
  }
  if (phase === 'warm') {
    assert.equal(value.tasks, 2); assert.equal(value.requests, 2); assert.equal(value.calls, 2);
  } else if (phase === 'cold') {
    assert.notEqual(pid, originalPid, 'Cold observation requires a distinct original process');
    assert.equal(value.calls, 0); assert.equal(value.egressChecks, 0);
    if (caseId.startsWith('timeout-')) {
      assert.equal(value.timeoutMode, caseId.slice('timeout-'.length));
      assert.equal(value.preserveOriginalState, true);
      assert.equal(value.originalUnknown, true); assert.equal(value.zeroResend, true);
      assert.equal(value.originalSavedFirst, undefined);
    } else assert.equal(value.originalSavedFirst, true);
  } else if (phase.startsWith('timeout-')) {
    assert.equal(value.timeoutMode, phase.slice('timeout-'.length));
    assert.equal(value.preserveOriginalState, true);
    for (const field of ['tasks', 'requests', 'calls']) assert.equal(value[field], 1);
    if (phase === 'timeout-call') {
      assert(typeof value.continuousWrites === 'number' && Number.isSafeInteger(value.continuousWrites) && value.continuousWrites >= 2 && value.continuousWrites < 128);
      assert.equal(value.responseClosedBeforeFirstClose, true);
    }
  } else if (phase === 'rate-limit') {
    for (const field of ['tasks', 'requests', 'calls']) assert.equal(value[field], 1);
  } else if (phase === 'missing-key') {
    assert.equal(value.requests, 1); assert.equal(value.calls, 0); assert.equal(value.credentialRefused, true);
  } else {
    assert.equal(value.usageMode, project ? 'reported' : phase.slice('usage-'.length));
    for (const field of ['tasks', 'requests', 'calls', 'usageCaptures']) assert.equal(value[field], 1);
  }
}

export async function runPackedProviderAI(root: string, {repository = fileURLToPath(new URL('../', import.meta.url)),
  retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES,
  release = process.env.ACTQL_PACKED_PROVIDER_RELEASE, publicRegistry = false, cases, command = execute}: ProviderOptions = {}) {
  const software = release ?? retained;
  assert(isAbsolute(root) && typeof software === 'string' && isAbsolute(software) &&
    (release === undefined || retained === undefined),
  'Require fresh external output and one original, matching package cohort');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Normal plugin acceptance refuses runtime overlays');
  const source = checkoutState(repository);
  assert(source.clean, 'Normal plugin acceptance requires clean fixed source');
  if (process.env.GITHUB_SHA) assert.equal(source.revision, process.env.GITHUB_SHA);
  const releaseSelected = release === undefined ? undefined : await readSelectedRelease(release);
  assert(!publicRegistry || releaseSelected !== undefined, 'Public Provider install requires an original release');
  if (releaseSelected !== undefined) {
    const {manifest} = releaseSelected;
    assert.equal(manifest.sourceSha, source.revision);
    assert(nodeReleaseIncludesProvider(manifest.cohort.packages), 'Provider acceptance requires the explicit five-package cohort');
  }
  root = await releaseConsumerDestination(root, [repository, software]);
  await mkdir(root);
  const raw = join(root, 'raw'), casesRoot = join(root, 'cases');
  await mkdir(raw); await mkdir(casesRoot);
  // Each timeout cold read observes its own entered original, never a Saved
  // success or a replacement request. Its state and profile stay in that case.
  const available = [['warm', 'cold'], ['missing-key'], ['project-key', 'cold'], ['rate-limit', 'cold'],
    ['usage-reported', 'cold'], ['usage-zero'], ['usage-absent'],
    ['timeout-headers', 'cold'], ['timeout-body', 'cold'], ['timeout-call', 'cold']];
  const selections = cases === undefined ? available : [...available,
    ...[...registeredProviderCases, ...externalCases].map(id => [id, 'cold']),
    [registeredCapabilityCase, 'cold', 'changed-route'],
    ...Object.keys(registeredTerminalFailures).map(id => [id, 'cold']),
    ...registeredRefusalCases.map(id => [id])].filter(([id]) => cases.includes(id));
  if (cases !== undefined) assert(cases.length > 0 && selections.length === cases.length,
    'Every selected provider case must match once');
  const report: Report = {source: source.revision, preparations: [],
    phases: selections.flatMap(phases => phases.map(phase => ({case: phases[0], phase, status: 'unexecuted',
      reason: phase === 'cold' ? 'Requires the same original case and its confirmed first close' : 'Requires a fresh verified installation'}))),
    complete: false};
  const preparedCases: Prepared[] = [], failures: unknown[] = [], cleanup: unknown[] = [];
  const env = Object.fromEntries(['PATH', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TZ', 'TMPDIR']
    .filter(key => typeof process.env[key] === 'string').map(key => [key, process.env[key]]));
  for (const phases of selections) {
    const id = phases[0], caseRoot = join(casesRoot, id), caseRaw = join(raw, id);
    await mkdir(caseRoot); await mkdir(caseRaw);
    // Every preparation retains its own exclusive install-node.* diagnostics.
    let externalArchive: string | undefined;
    const run: Command = (cmd, args, options) => command(cmd,
      externalArchive !== undefined && options?.name === 'install-node' ? [...args, externalArchive] : args,
      {...options, raw: caseRaw});
    try {
      const fixture = join(repository, 'scripts/fixtures/external-model-adapter');
      if (externalCases.includes(id)) {
        assert(releaseSelected === undefined, 'The fixture package uses the exact retained ordinary cohort');
        await run('npm', ['pack', '--pack-destination', caseRoot, '--ignore-scripts', '--json'],
          {cwd: fixture, name: 'pack-external-adapter', timeout: 60_000});
        externalArchive = join(caseRoot, 'actql-acceptance-external-openai-adapter-1.0.0.tgz');
      }
      const prepared: Prepared = releaseSelected === undefined ? await prepareHealthPackages({repository, root: caseRoot,
        source: {sha: source.revision, dirty: false}, retained: software,
        optionalProvider: join(software, 'optional-provider'), command: run, normalLifecycle: true})
        : await installRelease(caseRoot, software, releaseSelected.manifest, releaseSelected.manifestPath, run, publicRegistry);
      preparedCases.push(prepared);
      const external: ExternalPreparation | undefined = externalArchive === undefined ? undefined : {
        archive: externalArchive,
        sha256: createHash('sha256').update(await readFile(externalArchive)).digest('hex'),
        packageImages: registeredExternalPackageImages(prepared.consumer, externalAdapter),
      };
      if (external !== undefined) {
        assert.equal(external.packageImages[0].name, externalAdapter);
        for (const file of ['package.json', 'index.mjs', 'second-fetch.mjs', 'npm-shrinkwrap.json']) {
          const held: {sha256: string; bytes: number} | undefined =
            external.packageImages[0].images.find(image => image.path === file);
          const bytes = await readFile(join(fixture, file));
          assert.equal(held?.sha256, createHash('sha256').update(bytes).digest('hex'));
          assert.equal(held?.bytes, bytes.length);
        }
        await writeFile(join(prepared.consumer, 'external-package-images.fixture.json'),
          JSON.stringify(external.packageImages) + '\n', {flag: 'wx'});
      }
      report.preparations.push({case: id, consumer: prepared.consumer,
        manifestPath: prepared.manifestPath, manifest: prepared.manifest,
        ...(external === undefined ? {} : {external}),
        ...(publicRegistry && 'publicPayload' in prepared ? {publicPayload: prepared.publicPayload} : {})});
      await copyFile(join(repository, 'scripts/fixtures/normal-openai-installed.fixture.mjs'),
        join(prepared.consumer, 'fixture.mjs'));
      await copyFile(join(repository, 'scripts/fixtures/external-rest/conformance.mjs'),
        join(prepared.consumer, 'conformance.mjs'));
      await copyFile(join(repository, 'scripts/fixtures/normal-provider-diagnostics.fixture.mjs'),
        join(prepared.consumer, 'normal-provider-diagnostics.fixture.mjs'));
      await copyFile(join(repository, 'adapters/host-node/fixtures/work-observation.fixture.mjs'),
        join(prepared.consumer, 'work-observation.fixture.mjs'));
      let originalPid: number | undefined, originalRunDefinitionCid: unknown, deniedRunDefinitionCid: unknown;
      for (const phase of phases) {
        const record = report.phases.find(value => value.case === id && value.phase === phase);
        assert(record, 'Missing original phase');
        record.status = 'running'; delete record.reason;
        try {
          const actual = await run(process.execPath, ['fixture.mjs', phase],
            {cwd: prepared.consumer, env, name: phase, timeout: 120_000});
          const value = JSON.parse(actual.stdout.trim()) as Observation;
          Object.assign(record, {pid: actual.pid, actual: value, consumer: prepared.consumer});
          checkPackedProviderObservation({caseId: id, phase, pid: actual.pid, originalPid, observation: value});
          if (externalCases.includes(id)) {
            const adapterPath = id === externalDuplicateCase ? 'second-fetch.mjs' : 'index.mjs';
            for (const [field, path] of [['externalAdapterCid', adapterPath], ['externalLockCid', 'npm-shrinkwrap.json']]) {
              assert.equal(value[field], 'sha256:' + external!.packageImages[0].images.find(image => image.path === path)?.sha256);
            }
            if (id === externalCase && phase !== 'cold') {
              const usage = JSON.parse(await readFile(join(prepared.consumer, 'usage-original.json'), 'utf8'));
              assert.match(usage.raw_response_artifact_cid, /^sha256:[0-9a-f]{64}$/u);
              assert.equal(usage.input_tokens, 2); assert.equal(usage.output_tokens, 3);
            }
          }
          if (id === 'registered-mixed' || id === 'registered-mistral' || externalCases.includes(id) ||
              id === registeredCapabilityCase || Object.hasOwn(registeredTerminalFailures, id)) {
            if (phase === id) originalRunDefinitionCid = value.originalRunDefinitionCid;
            else assert.equal(value.originalRunDefinitionCid, originalRunDefinitionCid);
          }
          if (id === registeredCapabilityCase) {
            if (phase === id) deniedRunDefinitionCid = value.deniedRunDefinitionCid;
            if (phase === 'cold') assert.equal(value.deniedRunDefinitionCid, deniedRunDefinitionCid);
          }
          if (phase === id) originalPid = actual.pid;
          record.status = 'passed';
        } catch (failure) {
          record.status = 'failed'; record.failure = nodeBenchmarkFailure(failure); throw failure;
        }
      }
      if (external !== undefined) {
        assert.deepEqual(registeredExternalPackageImages(prepared.consumer, externalAdapter), external.packageImages);
        assert.equal(createHash('sha256').update(await readFile(external.archive)).digest('hex'), external.sha256);
      }
    } catch (failure) {failures.push(failure);}
  }
  for (const prepared of preparedCases) {
    try {
      if (publicRegistry) {
        assert('publicPayload' in prepared);
        assert.deepEqual(await verifyPublicConsumer(prepared.consumer, prepared.manifest, 'provider-ai-sdk'),
          prepared.publicPayload, 'Public Provider installation changed during acceptance');
      } else await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    }
    catch (failure) {cleanup.push(failure);}
  }
  try {assert.deepEqual(checkoutState(repository), source);}
  catch (failure) {cleanup.push(failure);}
  if (releaseSelected !== undefined) {
    try {
      assert.deepEqual(await readFile(releaseSelected.manifestPath), releaseSelected.manifestBytes);
      assert.deepEqual(await verifyPackageRelease(software), releaseSelected.manifest);
    } catch (failure) {cleanup.push(failure);}
  }
  report.complete = failures.length === 0 && cleanup.length === 0 && report.phases.every(value => value.status === 'passed');
  report.failures = failures.map(nodeBenchmarkFailure); report.cleanup = cleanup.map(nodeBenchmarkFailure);
  await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  if (failures.length === 1 && cleanup.length === 0) throw failures[0];
  if (failures.length) throw new AggregateError([...failures, ...cleanup],
    'OptionalProviderAcceptanceFailed', {cause: failures[0]});
  if (cleanup.length) throw new AggregateError(cleanup, 'OptionalProviderSoftwareChanged');
  assert(report.complete, 'Every original phase must complete before normal acceptance');
  return report;
}

async function readSelectedRelease(directory: string) {
  const manifest = await verifyPackageRelease(directory);
  const manifestPath = join(directory, 'release.json');
  return {manifest, manifestPath, manifestBytes: await readFile(manifestPath)};
}

async function installRelease(root: string, release: string, manifest: ReleaseManifest, manifestPath: string,
  run: Command, publicRegistry: boolean) {
  const consumer = join(root, 'consumer');
  const env = publicConsumerEnvironment(process.env, root);
  await Promise.all([consumer, env.HOME, env.TMPDIR].map(path => mkdir(path)));
  await writeFile(join(consumer, 'package.json'), '{"private":true,"type":"module"}\n');
  if (publicRegistry) {
    await writeFile(env.npm_config_userconfig, '');
    await writeFile(env.npm_config_globalconfig, '');
    await run('npm', publicInstallCommand(manifest, 'provider-ai-sdk'), {cwd: consumer, env, name: 'install-release'});
    const publicPayload = await verifyPublicConsumer(consumer, manifest, 'provider-ai-sdk');
    return {manifest, manifestPath, consumer, publicPayload};
  }
  await run('npm', ['install', '--ignore-scripts=false', '--no-audit', '--no-fund', '--no-save', '--omit=optional',
    ...manifest.packages.map(row => join(release, row.file))], {cwd: consumer, env, name: 'install-release'});
  await verifyNodeBenchmarkPackages(manifest, manifestPath, consumer);
  return {manifest, manifestPath, consumer};
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const [root, selection, ...extra] = process.argv.slice(2);
  assert(root !== undefined && [undefined, '--registered-only', '--registered-safety-only', '--registered-external-only',
    '--registered-capabilities-only'].includes(selection)
    && extra.length === 0,
  'usage: test-packed-provider-ai-sdk.mjs ABSOLUTE_FRESH_OUTPUT [--registered-only | --registered-safety-only | --registered-external-only | --registered-capabilities-only]');
  const cases = selection === '--registered-only' ? registeredProviderAcceptanceCases
    : selection === '--registered-safety-only' ? registeredSafetyAcceptanceCases
    : selection === '--registered-external-only' ? externalCases
    : selection === '--registered-capabilities-only' ? [registeredCapabilityCase] : undefined;
  process.exitCode = await runLocalCheck({root: fileURLToPath(new URL('../', import.meta.url)),
    heavy: false, timeoutSeconds: 300, graceSeconds: 5,
    steps: [{name: 'Original normal provider, usage and timeout consumers', command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runPackedProviderAI} from './scripts/test-packed-provider-ai-sdk.mjs'; await runPackedProviderAI(process.argv[1], JSON.parse(process.argv[2]));",
        root, JSON.stringify({cases})]}]});
}
