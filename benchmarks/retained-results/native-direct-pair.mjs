import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {createReadStream} from 'node:fs';
import {mkdir, rm} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {isDeepStrictEqual, promisify} from 'node:util';
import {releaseArtifactDigest} from './release-artifacts.mjs';
import {retainedCase} from './fixtures.mjs';
import {admitNativeEstimateProfile} from './native-estimate-profile.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct,
  admitNativeDirectProduct} from './native-direct-product.mjs';

const exec = promisify(execFile);

async function fileHash(path) {
  const hash = createHash('sha256');
  for await (const bytes of createReadStream(path)) hash.update(bytes);
  return hash.digest('hex');
}

async function checkoutState(root) {
  const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
  return {revision: await git(['rev-parse', 'HEAD']),
    dirty: Boolean(await git(['status', '--porcelain']))};
}

// Runs the actual single-process Native Host and the independent assembly on
// one immutable source. This records the performance decision; formal matrix
// admission still requires the complete Native obligation/accounting report.
export async function runNativeDirectPair({checkout, fixture, database,
  directory, index = 0, nativeRates, localRates, nativeEstimateProfile}) {
  assert(Number.isSafeInteger(index) && index >= 0, 'InvalidNativePairIndex');
  assert(!nativeEstimateProfile || !nativeRates && !localRates,
    'NativePairConflictingRates');
  const root = resolve(checkout);
  const initial = await checkoutState(root);
  assert.equal(initial.dirty, false, 'NativePairRequiresCleanCheckout');
  const artifactDigest = await releaseArtifactDigest(root);
  const sourceSha256 = await fileHash(database);
  const nativeRoot = join(directory, `native-${index}`);
  const independentRoot = join(directory, `independent-${index}`);
  await mkdir(nativeRoot);
  await mkdir(independentRoot);
  const samples = {};
  let admittedProfile;
  const labels = index % 2
    ? ['independent', 'native'] : ['native', 'independent'];
  try {
    for (const label of labels) {
      if (label === 'native') {
        const started = performance.now();
        const invocation = await prepareNativeDirectProduct({root, fixture,
          database, directory: nativeRoot,
          nativeMs: nativeEstimateProfile?.nativeTaskMilliseconds[0] ??
            nativeRates?.[0] ?? '1000',
          nativeRates: nativeEstimateProfile?.nativeTaskMilliseconds ?? nativeRates,
          localRates: nativeEstimateProfile?.localTaskMilliseconds ?? localRates});
        if (nativeEstimateProfile) {
          const [workload, layout, rowText, ...remaining] =
            nativeEstimateProfile.trainingCaseId.split('/');
          assert.equal(remaining.length, 0, 'InvalidNativePairTrainingCase');
          const trainingFixture = retainedCase(workload, layout,
            Number(rowText));
          admittedProfile = admitNativeEstimateProfile({
            profile: nativeEstimateProfile, trainingFixture,
            targetFixture: fixture, revision: initial.revision,
            binaryDigest: `sha256:${await fileHash(invocation.binary)}`,
          });
        }
        const execution = await executeNativeDirectProduct(invocation,
          {root, timeoutMs: fixture.limits.timeoutMs});
        const cycleMs = performance.now() - started;
        const product = admitNativeDirectProduct(fixture, invocation, execution);
        if (admittedProfile) {
          assert.deepEqual(product.selected,
            nativeEstimateProfile.ordinary.selected,
          'NativePairOrdinarySelectionChanged');
        }
        samples.native = {cycleMs, coldMs: cycleMs - product.cleanupMs,
          warmMs: product.warmMs, executionMs: product.executionMs,
          cleanupMs: product.cleanupMs, product};
      } else {
        const started = performance.now();
        const script = join(root,
          'adapters/connectors/duckdb/node/bench/equivalent-case.mjs');
        const {stdout} = await exec(process.execPath,
          [script, database, independentRoot, fixture.workload,
            fixture.layout, String(fixture.rows)],
          {cwd: root, timeout: fixture.limits.timeoutMs,
            maxBuffer: 16 * 1024 * 1024});
        const cycleMs = performance.now() - started;
        const report = JSON.parse(stdout.trim().split('\n').at(-1));
        assert.equal(report.status, 'diagnostic-completed');
        samples.independent = {cycleMs,
          coldMs: cycleMs - report.cleanupMs,
          warmMs: report.warmMs, executionMs: report.executionMs,
          cleanupMs: report.cleanupMs, report};
      }
      assert.equal(await fileHash(database), sourceSha256,
        'NativePairSourceChanged');
      assert.deepEqual(await checkoutState(root), initial,
        'NativePairCheckoutChanged');
      assert.equal(await releaseArtifactDigest(root), artifactDigest,
        'NativePairReleaseArtifactsChanged');
    }
    const native = samples.native.product;
    const independent = samples.independent.report;
    const identityEqual = native.record.rows_cid ===
      independent.stages.at(-1).cid;
    const metadataEqual = isDeepStrictEqual(
      native.acquisitionEvidenceMetadata,
      independent.acquisitionEvidenceMetadata);
    const stageRowsEqual = isDeepStrictEqual(
      native.taskHoldings.map(value => value.rows),
      independent.stages.slice(1).map(value => value.rows));
    return {caseId: fixture.id, index, labels,
      status: identityEqual && metadataEqual && stageRowsEqual
        ? 'diagnostic-completed' : 'failed',
      acceptanceEligible: false,
      missing: ['Native logical-work and physical-traffic obligation admission'],
      provenance: {revision: initial.revision,
        releaseArtifactSha256: artifactDigest,
        sourceSha256},
      native: {coldMs: samples.native.coldMs,
        warmMs: samples.native.warmMs,
        executionMs: samples.native.executionMs,
        cleanupMs: samples.native.cleanupMs,
        selected: native.selected,
        taskHoldings: native.taskHoldings,
        taskUsages: native.taskUsages,
        usage: native.record.usage,
        acquisition: native.record.acquisition},
      selectionProfile: admittedProfile ? {
        admitted: true, estimateSource: admittedProfile.estimateSource,
        trainingCaseId: admittedProfile.trainingCaseId,
        targetCaseId: admittedProfile.targetCaseId,
      } : {admitted: false},
      independent: {coldMs: samples.independent.coldMs,
        warmMs: samples.independent.warmMs,
        executionMs: samples.independent.executionMs,
        cleanupMs: samples.independent.cleanupMs},
      identityEqual, metadataEqual, stageRowsEqual};
  } finally {
    await rm(nativeRoot, {recursive: true, force: true});
    await rm(independentRoot, {recursive: true, force: true});
  }
}
