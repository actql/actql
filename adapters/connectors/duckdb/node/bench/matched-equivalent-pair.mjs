// Matched provenance/timing assembly for one retained/equivalent diagnostic
// pair. Comparator equivalence is deliberately a separate admission decision.
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {readFile} from 'node:fs/promises';
import {join} from 'node:path';
import {isDeepStrictEqual, promisify} from 'node:util';
import {admitEquivalentObligationPair} from
  './equivalent-admission.mjs';

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

const accountingDomains = Object.freeze([
  'nativeSemanticRows',
  'nativeSemanticCells',
  'nativeSemanticBytes',
  'jsMaterializedCells',
  'identityPasses',
  'identityPreimageBytes',
  'retainedStoreBytes',
  'measuredGuardWork',
  'measuredGuardBytes',
  'measuredGuardNodes',
  'reusedGuardWork',
  'reusedGuardBytes',
  'reusedGuardNodes',
  'logicalGuardWork',
  'logicalGuardBytes',
  'logicalGuardNodes',
  'comparisonWork',
  'comparisonBytes',
  'comparisonNodes',
]);

const exactLogicalDomains = Object.freeze([
  'logicalGuardWork',
  'logicalGuardBytes',
  'logicalGuardNodes',
  'comparisonWork',
  'comparisonBytes',
  'comparisonNodes',
]);

function compareAccounting(retained, equivalent) {
  const product = retained.report?.accounting;
  const direct = equivalent.report?.accounting;
  assert(product && direct, 'CompletedPairWithoutAccounting');
  return Object.freeze(Object.fromEntries(accountingDomains.map(key => {
    assert(Number.isSafeInteger(product[key]) && product[key] >= 0 &&
      Number.isSafeInteger(direct[key]) && direct[key] >= 0,
    `InvalidAccountingDomain:${key}`);
    return [key, Object.freeze({
      retained: product[key],
      equivalent: direct[key],
      difference: product[key] - direct[key],
    })];
  })));
}

const usageInteger = (value, label) => {
  const number = typeof value === 'string' && /^(0|[1-9][0-9]*)$/.test(value)
    ? BigInt(value) : typeof value === 'number' && Number.isSafeInteger(value) &&
      value >= 0 ? BigInt(value) : undefined;
  assert.notEqual(number, undefined, `InvalidResourceUsage:${label}`);
  return number;
};

const terminalUsage = (usage, label) => {
  const unresolved = [
    'uncertain_transfer_bytes',
    'reserved_transfer_bytes',
    'held_bytes',
    'reserved_retention_bytes',
    'reserved_execution_bytes',
  ];
  for (const key of unresolved) {
    assert.equal(usageInteger(usage[key], `${label}.${key}`), 0n,
      `UnsettledResourceUsage:${label}.${key}`);
  }
};

function compareTransferWork(retained, equivalent, accounting) {
  const product = retained.report?.usage;
  const directRetention = equivalent.report?.retentionLedger;
  const directExecution = equivalent.report?.executionLedger;
  const releasedRetention = equivalent.report?.releasedRetentionLedger;
  const releasedExecution = equivalent.report?.releasedExecutionLedger;
  assert(product && directRetention && directExecution && releasedRetention &&
    releasedExecution, 'CompletedPairWithoutResourceAccounting');
  terminalUsage(product, 'retained');
  terminalUsage(releasedRetention, 'equivalent.releasedRetention');
  terminalUsage(releasedExecution, 'equivalent.releasedExecution');
  for (const [label, usage] of [
    ['equivalent.retention', directRetention],
    ['equivalent.execution', directExecution],
  ]) {
    for (const key of ['planning_work', 'attempts', 'transferred_bytes']) {
      usageInteger(usage[key], `${label}.${key}`);
    }
  }
  const productAttempts = usageInteger(product.attempts,
    'retained.attempts');
  const directAttempts = usageInteger(directRetention.attempts,
    'equivalent.retention.attempts') + usageInteger(directExecution.attempts,
    'equivalent.execution.attempts');
  assert.equal(productAttempts, directAttempts,
    'LogicalAttemptBoundaryMismatch');
  const directControlTransfer = usageInteger(
    directRetention.transferred_bytes,
    'equivalent.retention.transferred_bytes',
  ) + usageInteger(
    directExecution.transferred_bytes,
    'equivalent.execution.transferred_bytes',
  );
  // The independent assembly has no child control channel. Native-to-semantic
  // bytes remain visible in the physical accounting comparison instead.
  assert.equal(directControlTransfer, 0n,
    'IndependentControlTransferMustRemainSeparate');
  const logical = Object.freeze({
    retainedWork: accounting.logicalGuardWork.retained +
      accounting.comparisonWork.retained,
    equivalentWork: accounting.logicalGuardWork.equivalent +
      accounting.comparisonWork.equivalent,
    retainedBytes: accounting.logicalGuardBytes.retained +
      accounting.comparisonBytes.retained,
    equivalentBytes: accounting.logicalGuardBytes.equivalent +
      accounting.comparisonBytes.equivalent,
    retainedNodes: accounting.logicalGuardNodes.retained +
      accounting.comparisonNodes.retained,
    equivalentNodes: accounting.logicalGuardNodes.equivalent +
      accounting.comparisonNodes.equivalent,
  });
  assert.equal(logical.retainedWork, logical.equivalentWork);
  assert.equal(logical.retainedBytes, logical.equivalentBytes);
  assert.equal(logical.retainedNodes, logical.equivalentNodes);
  return Object.freeze({
    logical,
    attempts: Object.freeze({
      retained: Number(productAttempts),
      equivalent: Number(directAttempts),
    }),
    physical: Object.freeze({
      retainedPlanningWork: Number(usageInteger(product.planning_work,
        'retained.planning_work')),
      equivalentPlanningWork: Number(usageInteger(
        directRetention.planning_work,
        'equivalent.retention.planning_work',
      ) + usageInteger(
        directExecution.planning_work,
        'equivalent.execution.planning_work',
      )),
      retainedControlTransferBytes: product.transferred_bytes,
      equivalentControlTransferBytes: directControlTransfer.toString(),
      retainedSemanticTransferBytes:
        accounting.nativeSemanticBytes.retained,
      equivalentSemanticTransferBytes:
        accounting.nativeSemanticBytes.equivalent,
      scope: 'logical work is equal; physical planner, control-channel, and semantic transfer are observed separately',
    }),
    terminalReleaseConfirmed: true,
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
      'adapters/connectors/duckdb/node/bench',
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
  const accountingComparison = completed
    ? compareAccounting(retained, equivalent)
    : undefined;
  const logicalAccountingEquivalent = completed && exactLogicalDomains.every(
    key => accountingComparison[key].difference === 0,
  );
  const acquisitionMetadataEquivalent = completed && isDeepStrictEqual(
    retained.report?.acquisitionEvidenceMetadata,
    equivalent.report?.acquisitionEvidenceMetadata,
  );
  const transferWorkComparison = completed && logicalAccountingEquivalent &&
    acquisitionMetadataEquivalent
    ? compareTransferWork(retained, equivalent, accountingComparison)
    : undefined;
  const transferWorkAccountingEquivalent = Boolean(transferWorkComparison);
  const closed = Object.freeze([
    'matched process/cold timing boundaries',
    'matched warm timing boundary',
    'finite expression-demand and negative conformance',
    ...(acquisitionMetadataEquivalent
      ? ['acquisition evidence metadata parity'] : []),
    ...(transferWorkAccountingEquivalent
      ? ['transfer and logical-work accounting equivalence'] : []),
  ]);
  const closedSet = new Set(closed);
  const unresolved = [...new Set([
    ...(equivalent.report?.missing ?? []).filter(value =>
      !closedSet.has(value)),
    ...(!logicalAccountingEquivalent
      ? ['logical guard and comparison charge parity'] : []),
    ...(!acquisitionMetadataEquivalent
      ? ['acquisition evidence metadata parity'] : []),
    ...(!transferWorkAccountingEquivalent
      ? ['transfer/work accounting equivalence'] : []),
  ])];
  let equivalentObligationAdmission;
  if (completed && unresolved.length === 0) {
    equivalentObligationAdmission = admitEquivalentObligationPair({
      fixture,
      retained,
      equivalent,
      logicalAccountingEquivalent,
      acquisitionMetadataEquivalent,
      transferWorkAccountingEquivalent,
      unresolved,
    });
  }
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
    status: completed && logicalAccountingEquivalent &&
      acquisitionMetadataEquivalent && transferWorkAccountingEquivalent
      ? 'diagnostic-completed' : 'failed',
    accountingComparison,
    logicalAccountingEquivalent,
    acquisitionMetadataEquivalent,
    transferWorkAccountingEquivalent,
    transferWorkComparison,
    equivalentObligationAdmission,
    acceptanceEligible: equivalentObligationAdmission?.accepted === true,
    closed,
    missing: Object.freeze([
      ...unresolved,
      ...(equivalentObligationAdmission ? []
        : ['equivalent-obligation admission']),
    ]),
  });
}
