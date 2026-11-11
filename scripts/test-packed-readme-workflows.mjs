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

async function runCollectionConsumer({prepared, root, repository, command, report, cleanup}) {
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
    for (const record of report.collection) {
      const {phase} = record;
      const args = [join(collection, members[0]), phase, join(collection, 'original.json')];
      Object.assign(record, {command: process.execPath, args, cwd: collection,
        startedAt: new Date().toISOString(), status: 'running'});
      delete record.unexecutedReason;
      let observed;
      try {
        observed = await command(process.execPath, args,
          {cwd: collection, name: `collection-${phase}`, timeout: 120_000});
        const actual = JSON.parse(observed.stdout.trim()); record.actual = actual;
        assert.equal(actual.phase, phase); assert.equal(actual.pid, observed.pid);
        if (phase === 'saved') assert.notEqual(actual.pid, report.collection[0].pid);
        assert.equal(actual.sourceFreeMaxWork, 30000000);
        assert.deepEqual(actual.requestMemory, {retainedBytes: 1073741824, executionBytes: 1073741824});
        assert(actual.complete); assert.equal(actual.firstClose, 'returned');
        assert.deepEqual(actual.aliveScopedFD, {before: 0, after: 0});
        assert.equal(actual.submits, phase === 'capture' ? 5 : 0);
        if (phase === 'capture') {
          assert.deepEqual(actual.cases.map(value => value.count), [9999, 10000, 10001, 100000]);
          assert.deepEqual(actual.controls, {tighterRows: true, collectionBytes: true,
            wireBytes: true, rowWireBytes: true, rowBytes: true, originalChargeBeforeValidation: true,
            boundedBatches: true, batchBytes: true, earlyBreak: true, readerCancellation: true});
          assert.deepEqual(actual.oversizedRow, {rows: 1, arrayElements: 20000,
            expectedRefusal: 'ResultRowRetainedLimit', complete: true});
          assert.equal(actual.originalProgramsRemovedAfterFirstClose, 5);
        } else assert.deepEqual(actual.cases, [{count: 100000, complete: true}]);
        record.completed = true; record.status = 'passed';
      } catch (error) {
        observed ??= error?.commandResult;
        record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
        throw error;
      } finally {
        Object.assign(record, {pid: observed?.pid ?? null, wallNs: observed?.wallNs ?? null,
          exitCode: observed?.code ?? null, signal: observed?.signal ?? null,
          endedAt: new Date().toISOString()});
      }
    }
  } finally {
    try {assert.equal(await readlink(alias), software); await unlink(alias);}
    catch (error) {cleanup.push(error);}
  }
}

async function runReadmeCases({prepared, root, repository, command, report, failures}) {
  for (const record of report.cases) {
    // A shared software failure invalidates the remaining inputs. A failed
    // consumer does not mask the other fresh, independent project variants.
    await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    const {template, variant} = record;
    record.status = 'running'; delete record.unexecutedReason;
    try {
      await mockWorkflowMetrics({prepared, root, repository, command,
        counts: {coldSamples: 1}, template, variant,
        async onMetric(metric) {
          record.metric = metric;
          await writeFile(join(root, `${template}-${variant}.json`), JSON.stringify(metric, null, 2) + '\n');
        }});
      assert.equal(record.metric.samples.length, 1);
      assert(record.metric.samples[0].completed && record.metric.samples[0].verified);
      record.completed = true; record.status = 'passed';
    } catch (error) {
      failures.push(error); record.status = 'failed'; record.error = nodeBenchmarkFailure(error);
    }
  }
}

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
    collection: ['capture', 'saved'].map(phase => ({phase, completed: false, status: 'unexecuted',
      unexecutedReason: phase === 'saved' ? 'Requires successful collection capture and FIRST close' : 'Requires verified normal packages'})),
    cases: packedReadmeCases.map(selected => ({...selected, completed: false, status: 'unexecuted',
      unexecutedReason: 'Requires verified unchanged normal packages'})), complete: false, performanceAcceptance: false,
    qualification: 'Same normal artifact, fresh state per variant; functional once each, not a latency verdict'};
  const command = (cmd, args, options) => execute(cmd, args, {...options, raw});
  let prepared;
  const failures = [], cleanup = [];
  try {
    prepared = await prepareHealthPackages({repository, root, source, retained, command});
    report.manifest = prepared.manifest;
    try {
      await runCollectionConsumer({prepared, root, repository, command, report, cleanup});
    } catch (error) {failures.push(error);}
    await runReadmeCases({prepared, root, repository, command, report, failures});
    report.complete = failures.length === 0 && report.collection.every(row => row.completed) &&
      report.cases.every(row => row.completed);
  } catch (error) {failures.push(error);}
  finally {
    if (prepared) try {
      await verifyNodeBenchmarkPackages(prepared.manifest, prepared.manifestPath, prepared.consumer);
    } catch (error) {cleanup.push(error);}
    try {assert.deepEqual(checkoutState(repository), before);} catch (error) {cleanup.push(error);}
    report.failures = failures.map(nodeBenchmarkFailure);
    if (failures.length) report.failure = report.failures[0];
    report.cleanup = cleanup.map(nodeBenchmarkFailure);
    if (cleanup.length) report.complete = false;
    await writeFile(join(root, 'summary.json'), JSON.stringify(report, null, 2) + '\n');
  }
  if (failures.length && (failures.length > 1 || cleanup.length)) throw new AggregateError([...failures, ...cleanup],
    'PackedReadmeConsumersFailed', {cause: failures[0]});
  if (failures.length) throw failures[0];
  if (cleanup.length) throw new AggregateError(cleanup, 'PackedReadmeCleanupUnconfirmed');
  return report;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  assert.equal(process.argv.length, 3, 'usage: test-packed-readme-workflows.mjs ABSOLUTE_FRESH_OUTPUT');
  await runPackedReadmeWorkflows(process.argv[2]);
}
