import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFile} from 'node:child_process';
import {mkdir, readFile, rm} from 'node:fs/promises';
import {join, resolve} from 'node:path';
import {performance} from 'node:perf_hooks';
import {isDeepStrictEqual, promisify} from 'node:util';
import {releaseArtifactDigest, sha256File as fileHash} from './release-artifacts.mjs';
import {retainedCase} from './fixtures.mjs';
import {admitNativeEstimateProfile} from './native-estimate-profile.mjs';
import {admitNativeResidentEstimateProfile, assertNativeMeasuredOffers} from './native-resident-estimate-profile.mjs';
import {admitNativeEquivalentPair} from './native-equivalent-admission.mjs';
import {prepareNativeDirectProduct, executeNativeDirectProduct,
  admitNativeDirectProduct} from './native-direct-product.mjs';

const exec = promisify(execFile);

async function checkoutState(root) {
  const git = async args => (await exec('git', args, {cwd: root})).stdout.trim();
  return {revision: await git(['rev-parse', 'HEAD']),
    dirty: Boolean(await git(['status', '--porcelain']))};
}

// Runs the actual single-process Native Host and the independent assembly on
// one immutable source. This records the performance decision; formal matrix
// admission still requires the complete Native obligation/accounting report.
export async function runNativeDirectPair({checkout, fixture, database,
  directory, index = 0, nativeRates, localRates, nativeEstimateProfile,
  nativeResidentEstimateProfile}) {
  assert(Number.isSafeInteger(index) && index >= 0, 'InvalidNativePairIndex');
  assert(!(nativeEstimateProfile && nativeResidentEstimateProfile), 'ConflictingNativeProfiles');
  assert(!(nativeEstimateProfile || nativeResidentEstimateProfile) || !nativeRates && !localRates,
    'NativePairConflictingRates');
  const root = resolve(checkout);
  const initial = await checkoutState(root);
  assert.equal(initial.dirty, false, 'NativePairRequiresCleanCheckout');
  const artifactDigest = await releaseArtifactDigest(root);
  const sourceSha256 = await fileHash(database);
  const registrationSha256 = createHash('sha256').update(await readFile(
    join(root, 'benchmarks/retained-results/experiment.json'))).digest('hex');
  const sourceDefinitionSha256 = createHash('sha256').update(
    fixture.createSourceSql).digest('hex');
  const programSha256 = createHash('sha256').update(JSON.stringify(
    fixture.program())).digest('hex');
  const nativeRoot = join(directory, `native-${index}`);
  const independentRoot = join(directory, `independent-${index}`);
  const samples = {};
  let admittedProfile;
  const profileAdmissionStart = performance.now();
  if (nativeResidentEstimateProfile) admittedProfile = admitNativeResidentEstimateProfile({
    profile: nativeResidentEstimateProfile, trainingFixture: retainedCase(fixture.workload, fixture.layout, 1000),
    targetFixture: fixture, revision: initial.revision,
    binaryDigest: `sha256:${await fileHash(join(root,
      '_build/native/release/build/cmd/native_retained_case_probe/native_retained_case_probe.exe'))}`});
  const residentProfileAdmissionMs = nativeResidentEstimateProfile
    ? performance.now() - profileAdmissionStart : 0;
  await mkdir(nativeRoot);
  await mkdir(independentRoot);
  const labels = index % 2
    ? ['independent', 'native'] : ['native', 'independent'];
  try {
    for (const label of labels) {
      if (label === 'native') {
        const started = performance.now();
        const invocation = await prepareNativeDirectProduct({root, fixture,
          database, directory: nativeRoot,
          nativeMs: nativeResidentEstimateProfile?.rates.fresh[0] ?? nativeEstimateProfile?.nativeTaskMilliseconds[0] ??
            nativeRates?.[0] ?? '1000',
          nativeRates: nativeResidentEstimateProfile?.rates.fresh ?? nativeEstimateProfile?.nativeTaskMilliseconds ?? nativeRates,
          ...(nativeEstimateProfile ? {residentPolicy: false} : {}),
          ...(nativeResidentEstimateProfile ? {residentPolicy: true,
            residentEstimates: nativeResidentEstimateProfile.residentEstimates} : {}),
          localRates: nativeResidentEstimateProfile?.rates.local ?? nativeEstimateProfile?.localTaskMilliseconds ?? localRates});
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
        if (nativeResidentEstimateProfile) assert.equal(`sha256:${await fileHash(invocation.binary)}`,
          admittedProfile.binaryDigest, 'NativePairQualifiedBinaryChanged');
        const execution = await executeNativeDirectProduct(invocation,
          {root, timeoutMs: fixture.limits.timeoutMs});
        const cycleMs = performance.now() - started;
        const product = admitNativeDirectProduct(fixture, invocation, execution);
        if (nativeResidentEstimateProfile) {
          assert.deepEqual(product.ownerCorrespondence.observations.choices.map(choice =>
            choice.resident ? 'resident' : choice.name), admittedProfile.selected,
          'NativePairMeasuredRealizationChanged');
          assertNativeMeasuredOffers(product.ownerCorrespondence, admittedProfile.rates,
            admittedProfile.residentEstimates);
        } else if (admittedProfile) {
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
    const stageContentsEqual = isDeepStrictEqual(
      native.taskHoldings.map(value => [value.rowsCid, value.bytes]),
      independent.stages.slice(1).map(value => [value.cid, value.bytes]));
    const selectionProfile = admittedProfile ? {
      admitted: true, estimateSource: admittedProfile.estimateSource,
      trainingCaseId: admittedProfile.trainingCaseId,
      targetCaseId: admittedProfile.targetCaseId,
    } : {admitted: false};
    const nativeObligationAdmission = admittedProfile && identityEqual &&
      metadataEqual && stageRowsEqual && stageContentsEqual
      ? admitNativeEquivalentPair({fixture, native, equivalent: independent,
        selectionProfile}) : undefined;
    const equivalentLabel =
      'direct-duckdb-with-identical-obligations-and-independent-holding';
    const retainedLabel = 'retained-actql';
    return {caseId: fixture.id, index, labels,
      productProfile: 'native-direct',
      order: labels.map(label => label === 'native'
        ? retainedLabel : equivalentLabel),
      samples: {
        [equivalentLabel]: {status: 'diagnostic-completed',
          coldMs: samples.independent.coldMs,
          warmMs: samples.independent.warmMs,
          executionMs: samples.independent.executionMs,
          cleanupMs: samples.independent.cleanupMs},
        [retainedLabel]: {status: 'completed',
          acceptanceEligible: nativeObligationAdmission?.accepted === true,
          coldMs: samples.native.coldMs,
          warmMs: samples.native.warmMs,
          executionMs: samples.native.executionMs,
          cleanupMs: samples.native.cleanupMs},
      },
      status: identityEqual && metadataEqual && stageRowsEqual &&
        stageContentsEqual
        ? 'diagnostic-completed' : 'failed',
      acceptanceEligible: nativeObligationAdmission?.accepted === true,
      missing: nativeObligationAdmission ? [] :
        ['Native selection and equivalent-obligation admission'],
      provenance: {revision: initial.revision,
        releaseArtifactSha256: artifactDigest,
        sourceSha256, sourceContentSha256: sourceSha256,
        registrationSha256, sourceDefinitionSha256, programSha256,
        runtime: process.version,
        productRuntime: `native-${process.platform}-${process.arch}`,
        processBoundary: 'fresh native process and independent Node process',
        coldBoundary: 'parent spawn through child exit minus child cleanup',
        executionBoundary: 'leg-owned setup through completed holdings',
        cleanupBoundary: 'leg-owned confirmed release interval'},
      native: {coldMs: samples.native.coldMs,
        warmMs: samples.native.warmMs,
        executionMs: samples.native.executionMs,
        cleanupMs: samples.native.cleanupMs,
        selected: native.selected,
        host: 'native',
        acquisitionChoice: native.acquisitionChoice,
        acquisitionEvidenceMetadata: native.acquisitionEvidenceMetadata,
        ownerCorrespondence: native.ownerCorrespondence,
        taskHoldings: native.taskHoldings,
        taskUsages: native.taskUsages,
        usage: native.record.usage,
        acquisition: native.record.acquisition},
      selectionProfile,
      residentProfileAdmissionMs,
      nativeObligationAdmission,
      independent: {coldMs: samples.independent.coldMs,
        warmMs: samples.independent.warmMs,
        executionMs: samples.independent.executionMs,
        cleanupMs: samples.independent.cleanupMs},
      identityEqual, metadataEqual, stageRowsEqual, stageContentsEqual};
  } finally {
    await rm(nativeRoot, {recursive: true, force: true});
    await rm(independentRoot, {recursive: true, force: true});
  }
}
