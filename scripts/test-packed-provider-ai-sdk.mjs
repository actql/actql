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
  const raw = join(root, 'raw'); await mkdir(raw);
  const run = (cmd, args, options) => command(cmd, args, {...options, raw});
  const report = {source: source.revision, phases: [], complete: false};
  let prepared, primary;
  const cleanup = [];
  try {
    prepared = await prepareHealthPackages({repository, root, source: {sha: source.revision, dirty: false},
      retained, optionalProvider: join(retained, 'optional-provider'), command: run, normalLifecycle: true});
    await copyFile(join(repository, 'scripts/fixtures/normal-openai-installed.fixture.mjs'),
      join(prepared.consumer, 'fixture.mjs'));
    await copyFile(join(repository, 'scripts/fixtures/external-rest/conformance.mjs'),
      join(prepared.consumer, 'conformance.mjs'));
    const env = Object.fromEntries(Object.entries(process.env).filter(([key]) => !key.startsWith('ACTQL_')));
    for (const phase of ['warm', 'cold']) {
      const actual = await run(process.execPath, ['fixture.mjs', phase],
        {cwd: prepared.consumer, env, name: phase, timeout: 120_000});
      const value = JSON.parse(actual.stdout.trim());
      assert.equal(value.phase, phase);
      assert.equal(value.firstCloseReturned, true); assert.equal(value.aliveScopedFD0, true);
      if (phase === 'warm') {
        assert.equal(value.tasks, 2); assert.equal(value.requests, 2); assert.equal(value.calls, 2);
      } else {
        assert.equal(value.originalSavedFirst, true); assert.equal(value.calls, 0); assert.equal(value.egressChecks, 0);
      }
      report.phases.push({phase, pid: actual.pid, actual: value});
    }
    assert.notEqual(report.phases[0].pid, report.phases[1].pid, 'Cold Saved requires a distinct original process');
    report.complete = true;
  } catch (failure) {primary = failure;}
  finally {
    if (prepared) {
      try {await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);}
      catch (failure) {cleanup.push(failure);}
    }
    try {assert.deepEqual(checkoutState(repository), source);}
    catch (failure) {cleanup.push(failure);}
    if (primary !== undefined || cleanup.length) report.complete = false;
    if (primary !== undefined) report.failure = nodeBenchmarkFailure(primary);
    report.cleanup = cleanup.map(nodeBenchmarkFailure);
    await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  }
  if (primary !== undefined && cleanup.length) throw new AggregateError([primary, ...cleanup],
    'OptionalProviderAcceptanceFailed', {cause: primary});
  if (primary !== undefined) throw primary;
  if (cleanup.length) throw new AggregateError(cleanup, 'OptionalProviderSoftwareChanged');
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: test-packed-provider-ai-sdk.mjs ABSOLUTE_FRESH_OUTPUT');
  process.exitCode = await runLocalCheck({root: fileURLToPath(new URL('../', import.meta.url)),
    heavy: false, timeoutSeconds: 300, graceSeconds: 5,
    steps: [{name: 'Original normal provider warm and cold consumers', command: process.execPath,
      args: ['--input-type=module', '-e',
        "import {runPackedProviderAI} from './scripts/test-packed-provider-ai-sdk.mjs'; await runPackedProviderAI(process.argv[1]);",
        process.argv[2]]}]});
}
