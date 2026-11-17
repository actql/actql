// Optional plugin acceptance on the same normal artifact, never a new producer.
import assert from 'node:assert/strict';
import {mkdir, copyFile, writeFile} from 'node:fs/promises';
import {isAbsolute, join, resolve} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {prepareHealthPackages, execute} from './health-monitor-adapters.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';
import {releaseConsumerDestination} from './release-public-install.mjs';
import {runLocalCheck} from './local-checks-guard.mjs';

// Assertions over the original child report only; this issues no Run authority
// or substitute provider result. The caller still owns actual process/state
// selection, same-source software verification and independent installations.
export function checkPackedProviderObservation({caseId, phase, pid, originalPid, observation: value}) {
  assert.equal(value.phase, phase);
  assert(Number.isSafeInteger(pid) && pid > 0);
  assert.equal(value.firstCloseReturned, true); assert.equal(value.aliveScopedFD0, true);
  if (phase === 'warm') {
    assert.equal(value.tasks, 2); assert.equal(value.requests, 2); assert.equal(value.calls, 2);
  } else if (phase === 'cold') {
    assert.notEqual(pid, originalPid, 'Cold observation requires a distinct original process');
    assert.equal(value.calls, 0); assert.equal(value.egressChecks, 0);
    if (caseId.startsWith('timeout-')) {
      assert.equal(value.timeoutMode, caseId.slice('timeout-'.length));
      assert.equal(value.preserveOriginalState, true);
      assert.equal(value.originalUnknown, true); assert.equal(value.zeroResend, true);
    } else assert.equal(value.originalSavedFirst, true);
  } else if (phase.startsWith('timeout-')) {
    assert.equal(value.timeoutMode, phase.slice('timeout-'.length));
    assert.equal(value.preserveOriginalState, true);
    for (const field of ['tasks', 'requests', 'calls']) assert.equal(value[field], 1);
  } else {
    assert.equal(value.usageMode, phase.slice('usage-'.length));
    for (const field of ['tasks', 'requests', 'calls', 'usageCaptures']) assert.equal(value[field], 1);
  }
}

export async function runPackedProviderAI(root, {repository = fileURLToPath(new URL('../', import.meta.url)),
  retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES, command = execute} = {}) {
  assert(isAbsolute(root) && typeof retained === 'string' && isAbsolute(retained),
    'Require fresh external output and original same-run normal packages');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Normal plugin acceptance refuses runtime overlays');
  const source = checkoutState(repository);
  assert(source.clean, 'Normal plugin acceptance requires clean fixed source');
  if (process.env.GITHUB_SHA) assert.equal(source.revision, process.env.GITHUB_SHA);
  root = await releaseConsumerDestination(root, [repository, retained]);
  await mkdir(root);
  const raw = join(root, 'raw'), casesRoot = join(root, 'cases');
  await mkdir(raw); await mkdir(casesRoot);
  // Each timeout cold read observes its own entered original, never a Saved
  // success or a replacement request. Its state and profile stay in that case.
  const selections = [['warm', 'cold'], ['usage-reported'], ['usage-zero'], ['usage-absent'],
    ['timeout-headers', 'cold'], ['timeout-body', 'cold']];
  const report = {source: source.revision, preparations: [],
    phases: selections.flatMap(phases => phases.map(phase => ({case: phases[0], phase, status: 'unexecuted',
      reason: phase === 'cold' ? 'Requires the same original case and its confirmed first close' : 'Requires a fresh verified installation'}))),
    complete: false};
  const preparedCases = [], failures = [], cleanup = [];
  const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('ACTQL_')));
  for (const phases of selections) {
    const id = phases[0], caseRoot = join(casesRoot, id), caseRaw = join(raw, id);
    await mkdir(caseRoot); await mkdir(caseRaw);
    // Every preparation retains its own exclusive install-node.* diagnostics.
    const run = (cmd, args, options) => command(cmd, args, {...options, raw: caseRaw});
    try {
      const prepared = await prepareHealthPackages({repository, root: caseRoot,
        source: {sha: source.revision, dirty: false}, retained,
        optionalProvider: join(retained, 'optional-provider'), command: run, normalLifecycle: true});
      preparedCases.push(prepared);
      report.preparations.push({case: id, consumer: prepared.consumer,
        manifestPath: prepared.manifestPath, manifest: prepared.manifest});
      await copyFile(join(repository, 'scripts/fixtures/normal-openai-installed.fixture.mjs'),
        join(prepared.consumer, 'fixture.mjs'));
      await copyFile(join(repository, 'scripts/fixtures/external-rest/conformance.mjs'),
        join(prepared.consumer, 'conformance.mjs'));
      let originalPid;
      for (const phase of phases) {
        const record = report.phases.find(value => value.case === id && value.phase === phase);
        record.status = 'running'; delete record.reason;
        try {
          const actual = await run(process.execPath, ['fixture.mjs', phase],
            {cwd: prepared.consumer, env, name: phase, timeout: 120_000});
          const value = JSON.parse(actual.stdout.trim());
          Object.assign(record, {pid: actual.pid, actual: value, consumer: prepared.consumer});
          checkPackedProviderObservation({caseId: id, phase, pid: actual.pid, originalPid, observation: value});
          if (phase !== 'cold') originalPid = actual.pid;
          record.status = 'passed';
        } catch (failure) {
          record.status = 'failed'; record.failure = nodeBenchmarkFailure(failure); throw failure;
        }
      }
    } catch (failure) {failures.push(failure);}
  }
  for (const prepared of preparedCases) {
    try {await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);}
    catch (failure) {cleanup.push(failure);}
  }
  try {assert.deepEqual(checkoutState(repository), source);}
  catch (failure) {cleanup.push(failure);}
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

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: test-packed-provider-ai-sdk.mjs ABSOLUTE_FRESH_OUTPUT');
  process.exitCode = await runLocalCheck({root: fileURLToPath(new URL('../', import.meta.url)),
    heavy: false, timeoutSeconds: 300, graceSeconds: 5,
    steps: [{name: 'Original normal provider, usage and timeout consumers', command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runPackedProviderAI} from './scripts/test-packed-provider-ai-sdk.mjs'; await runPackedProviderAI(process.argv[1]);",
        process.argv[2]]}]});
}
