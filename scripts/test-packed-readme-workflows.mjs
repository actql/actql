// Required functional consumers of one exact normal artifact. No producer,
// repository runtime import, source overlay or performance campaign.
import assert from 'node:assert/strict';
import {mkdir, writeFile, copyFile, symlink, unlink, readlink} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {isAbsolute, join, resolve, dirname} from 'node:path';
import {fileURLToPath} from 'node:url';
import {checkoutState} from './packed-client-packages.mjs';
import {prepareHealthPackages, mockWorkflowMetrics, execute} from './health-monitor-adapters.mjs';
import {verifyNodeBenchmarkPackages, nodeBenchmarkFailure} from './benchmark-node-operations.mjs';

export const packedReadmeCases = Object.freeze([
  Object.freeze({template: 'churn-risk-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'readme'}),
  Object.freeze({template: 'deal-review-mock', variant: 'two-models'}),
]);

export async function runPackedReadmeWorkflows(root) {
  assert(isAbsolute(root), 'Require a fresh absolute consumer output directory');
  const retained = process.env.ACTQL_PACKED_CLIENT_PACKAGES;
  assert(typeof retained === 'string' && isAbsolute(retained),
    'Require the same-run normal Client artifact; no packing fallback');
  assert(!process.env.NODE_PATH && !process.env.NODE_OPTIONS &&
    !process.env.ACTQL_LOCAL_SOURCE_PROFILE && !process.env.ACTQL_LOCAL_EFFECT_PROFILE,
  'Packed README consumers refuse ambient runtime overlays');
  const repository = fileURLToPath(new URL('../', import.meta.url));
  const before = checkoutState(repository);
  assert(before.clean, 'Require clean fixed Source');
  if (process.env.GITHUB_SHA) assert.equal(before.revision, process.env.GITHUB_SHA);
  const source = {sha: before.revision, dirty: false,
    tree: execFileSync('git', ['rev-parse', 'HEAD^{tree}'], {cwd: repository, encoding: 'utf8'}).trim()};
  await mkdir(root);
  const raw = join(root, 'raw'); await mkdir(raw);
  const report = {source, node: process.version, platform: process.platform,
    architecture: process.arch, requiredCases: packedReadmeCases,
    cases: [], complete: false, performanceAcceptance: false,
    qualification: 'Same normal artifact, fresh state per variant; functional once each, not a latency verdict'};
  const command = (cmd, args, options) => execute(cmd, args, {...options, raw});
  let prepared, failed = false, primary;
  const cleanup = [];
  try {
    prepared = await prepareHealthPackages({repository, root, source, retained, command});
    report.manifest = prepared.manifest;
    const collection = join(root, 'collection'); await mkdir(collection);
    const members = ['scripts/fixtures/packed-result-collection.mjs',
      'scripts/fixtures/record-approval/scoped-fds.fixture.mjs'];
    for (const path of members) {
      await mkdir(dirname(join(collection, path)), {recursive: true});
      await copyFile(join(repository, path), join(collection, path));
    }
    await writeFile(join(collection, 'package.json'), '{"private":true,"type":"module"}\n');
    const software = join(prepared.consumer, 'node_modules'), alias = join(collection, 'node_modules');
    await symlink(software, alias, 'dir');
    try {
      report.collection = [];
      for (const phase of ['capture', 'saved']) {
        const args = [join(collection, members[0]), phase, join(collection, 'original.json')];
        const record = {phase, command: process.execPath, args, cwd: collection,
          startedAt: new Date().toISOString(), completed: false};
        report.collection.push(record);
        let observed;
        try {
          observed = await command(process.execPath, args,
            {cwd: collection, name: `collection-${phase}`, timeout: 120_000});
        } catch (error) {
          observed = error?.commandResult;
          record.error = nodeBenchmarkFailure(error);
          throw error;
        } finally {
          Object.assign(record, {pid: observed?.pid ?? null, wallNs: observed?.wallNs ?? null,
            exitCode: observed?.code ?? null, signal: observed?.signal ?? null,
            endedAt: new Date().toISOString()});
        }
        const actual = JSON.parse(observed.stdout.trim());
        record.actual = actual;
        assert.equal(actual.phase, phase); assert.equal(actual.pid, observed.pid);
        if (phase === 'saved') assert.notEqual(actual.pid, report.collection[0].pid);
        assert(actual.complete); assert.equal(actual.firstClose, 'returned');
        assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
        assert.equal(actual.submits, phase === 'capture' ? 4 : 0);
        if (phase === 'capture') {
          assert.deepEqual(actual.cases.map(value => value.count), [9999, 10000, 10001, 100000]);
          assert.equal(actual.originalProgramsRemovedAfterFirstClose, 4);
        } else assert.deepEqual(actual.cases, [{count: 100000, complete: true}]);
        record.completed = true;
      }
    } finally {
      assert.equal(await readlink(alias), software); await unlink(alias);
    }
    for (const selected of packedReadmeCases) {
      await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
      await mockWorkflowMetrics({prepared, root, repository, command,
        counts: {coldSamples: 1}, ...selected,
        async onMetric(metric) {
          report.cases = report.cases.filter(row => row.template !== selected.template || row.variant !== selected.variant);
          report.cases.push({...selected, metric});
          await writeFile(join(root, `${selected.template}-${selected.variant}.json`), JSON.stringify(metric, null, 2) + '\n');
        }});
    }
    assert.equal(report.cases.length, packedReadmeCases.length);
    assert(report.cases.every(row => row.metric.samples.length === 1 &&
      row.metric.samples[0].completed && row.metric.samples[0].verified));
    report.complete = true;
  } catch (error) {failed = true; primary = error; report.failure = nodeBenchmarkFailure(error);}
  finally {
    if (prepared) try {
      await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    } catch (error) {cleanup.push(error);}
    try {assert.deepEqual(checkoutState(repository), before);} catch (error) {cleanup.push(error);}
    report.cleanup = cleanup.map(nodeBenchmarkFailure);
    if (cleanup.length) report.complete = false;
    await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  }
  if (failed && cleanup.length) throw new AggregateError([primary, ...cleanup],
    'PackedReadmeCleanupUnconfirmed', {cause: primary});
  if (failed) throw primary;
  if (cleanup.length) throw new AggregateError(cleanup, 'PackedReadmeCleanupUnconfirmed');
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: test-packed-readme-workflows.mjs ABSOLUTE_FRESH_OUTPUT');
  await runPackedReadmeWorkflows(process.argv[2]);
}
