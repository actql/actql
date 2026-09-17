// Matched provenance/timing assembly for one retained/equivalent diagnostic
// pair. Comparator equivalence is deliberately a separate admission decision.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {promisify} from 'node:util';

const exec = promisify(execFile);

const sha256 = value =>
  createHash('sha256').update(value).digest('hex');

async function fileHash(path) {
  return sha256(await readFile(path));
}

function childFailure(error, cycleMs) {
  let report;
  try {
    report = JSON.parse(error.stdout);
  } catch {}
  return Object.freeze({
    status: 'failed',
    processCycleMs: cycleMs,
    report,
    error: Object.freeze({
      name: error.name,
      message: error.message,
      code: error.code,
      signal: error.signal,
      killed: error.killed,
      stderr: error.stderr,
    }),
  });
}

function normalize(label, value, cycleMs) {
  const report = label === 'retained-actql' ? value.report : value;
  const completed = label === 'retained-actql'
    ? report?.status === 'completed'
    : report?.status === 'diagnostic-completed';
  const cleanupMs = report?.cleanupMs;
  assert(!completed || Number.isFinite(cleanupMs) && cleanupMs >= 0,
    'CompletedChildWithoutCleanupTiming');
  assert(!completed || Number.isFinite(report.executionMs) &&
    report.executionMs >= 0, 'CompletedChildWithoutExecutionTiming');
  assert(!completed || Number.isFinite(report.warmMs) &&
    report.warmMs >= 0, 'CompletedChildWithoutWarmTiming');
  // The parent cycle covers the same fresh-child boundary for both legs.
  // Subtract only the separately measured cleanup interval; never add the
  // overlapping child execution interval to it.
  const coldMs = completed ? cycleMs - cleanupMs : undefined;
  assert(!completed || coldMs >= 0, 'InvalidColdTimingBoundary');
  return Object.freeze({
    status: completed ? report.status : value.status ?? 'failed',
    executionMs: report?.executionMs,
    warmMs: report?.warmMs,
    coldMs,
    cleanupMs,
    processCycleMs: cycleMs,
    childRevision: value.revision,
    acceptanceEligible: value.acceptanceEligible === true,
    report,
  });
}

async function defaultRunChild(label, arguments_, timeoutMs, script) {
  const started = performance.now();
  try {
    const result = await exec(process.execPath, [script, ...arguments_], {
      timeout: timeoutMs,
      maxBuffer: 16 * 1024 * 1024,
    });
    const cycleMs = performance.now() - started;
    return normalize(label, JSON.parse(result.stdout), cycleMs);
  } catch (error) {
    return childFailure(error, performance.now() - started);
  }
}

async function defaultInspectCheckout(checkout) {
  const git = async arguments_ => (await exec('git', arguments_, {
    cwd: checkout,
  })).stdout.trim();
  return Object.freeze({
    revision: await git(['rev-parse', 'HEAD']),
    dirty: Boolean(await git(['status', '--porcelain'])),
  });
}

export async function runMatchedEquivalentPair({
  fixture,
  checkout,
  database,
  directory,
  index,
  runChild = defaultRunChild,
  inspectCheckout = defaultInspectCheckout,
}) {
  if (!fixture || typeof checkout !== 'string' || !checkout.length ||
      typeof database !== 'string' || !database.length ||
      typeof directory !== 'string' || !directory.length ||
      !Number.isSafeInteger(index) || index < 0 ||
      typeof runChild !== 'function' || typeof inspectCheckout !== 'function') {
    throw new TypeError('InvalidMatchedPairArguments');
  }
  const initialCheckout = await inspectCheckout(checkout);
  if (!initialCheckout || typeof initialCheckout.revision !== 'string' ||
      !initialCheckout.revision.length ||
      typeof initialCheckout.dirty !== 'boolean') {
    throw new TypeError('InvalidCheckoutInspection');
  }
  const revision = initialCheckout.revision;
  if (initialCheckout.dirty) {
    throw new Error('MatchedPairRequiresCleanCheckout');
  }
  const registration = await readFile(join(
    checkout,
    'benchmarks/retained-results/experiment.json',
  ));
  const sourceContentHash = await fileHash(database);
  const first = index % 2 === 0
    ? 'direct-duckdb-with-identical-obligations-and-independent-holding'
    : 'retained-actql';
  const second = first === 'retained-actql'
    ? 'direct-duckdb-with-identical-obligations-and-independent-holding'
    : 'retained-actql';
  const order = Object.freeze([first, second]);
  const samples = {};
  const timeoutMs = fixture.limits.timeoutMs +
    fixture.limits.cleanupTimeoutMs;
  for (const label of order) {
    const script = join(
      checkout,
      'adapters/duckdb-node/bench',
      label === 'retained-actql'
        ? 'retained-case.mjs'
        : 'equivalent-case.mjs',
    );
    const arguments_ = label === 'retained-actql'
      ? [checkout, database, directory, fixture.workload, fixture.layout,
        String(fixture.rows), '1']
      : [database, directory, fixture.workload, fixture.layout,
        String(fixture.rows)];
    samples[label] = await runChild(label, arguments_, timeoutMs, script);
    if (await fileHash(database) !== sourceContentHash) {
      throw new Error('MatchedPairSourceChanged');
    }
    const currentCheckout = await inspectCheckout(checkout);
    if (currentCheckout.revision !== revision || currentCheckout.dirty) {
      throw new Error('MatchedPairSourcesChanged');
    }
  }
  const equivalent = samples[
    'direct-duckdb-with-identical-obligations-and-independent-holding'
  ];
  const retained = samples['retained-actql'];
  const completed = equivalent.status === 'diagnostic-completed' &&
    retained.status === 'completed';
  const closed = Object.freeze([
    'matched process/cold timing boundaries',
    'matched warm timing boundary',
  ]);
  const closedSet = new Set(closed);
  return Object.freeze({
    index,
    caseId: fixture.id,
    order,
    samples: Object.freeze(samples),
    provenance: Object.freeze({
      revision,
      registrationSha256: sha256(registration),
      sourceContentSha256: sourceContentHash,
      sourceDefinitionSha256: sha256(fixture.createSourceSql),
      programSha256: sha256(JSON.stringify(fixture.program())),
      runtime: process.version,
      initialPlacement: 'one immutable fixture database; no resident copy',
      processBoundary: 'fresh child per leg',
      coldBoundary: 'parent spawn through child exit minus child cleanup',
      executionBoundary: 'leg-owned setup through completed holdings',
      cleanupBoundary: 'leg-owned confirmed release interval',
    }),
    status: completed ? 'diagnostic-completed' : 'failed',
    acceptanceEligible: completed && equivalent.acceptanceEligible === true &&
      retained.acceptanceEligible === true,
    closed,
    missing: Object.freeze([
      ...new Set([
        ...(equivalent.report?.missing ?? []).filter(value =>
          !closedSet.has(value)),
        'equivalent-obligation admission',
      ]),
    ]),
  });
}
