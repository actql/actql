// One comparator's admission and timing gate. This is not a 27-case certificate.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {assessPairedTiming} from './paired-assessment.mjs';
import {retainedMatrix} from './fixtures.mjs';
import {workloads} from './fixtures.mjs';

const sha256 = value => createHash('sha256').update(value).digest('hex');
const registeredExperimentSha256 =
  '83fc5ce32f20de2492ef862726e057a03b43d46e0488023742550a25b4fff305';
const equivalent = 'direct-duckdb-with-identical-obligations-and-independent-holding';
const retained = 'retained-actql';

export function assessEquivalentSeries(fixture, pairs) {
  const incomplete = reason => Object.freeze({status: 'incomplete',
    scope: 'one-equivalent-comparator-only', caseId: fixture?.id, reason});
  if (!fixture || !Array.isArray(pairs) || pairs.length < 7 || pairs.length > 1000) {
    return incomplete('missing-or-invalid-pairs');
  }
  const registrationSha256 = sha256(readFileSync(new URL('experiment.json', import.meta.url)));
  const registered = retainedMatrix().find(item => item.id === fixture.id);
  if (registrationSha256 !== registeredExperimentSha256 ||
    !registered || registered.createSourceSql !== fixture.createSourceSql ||
    JSON.stringify(registered.program()) !== JSON.stringify(fixture.program()) ||
    JSON.stringify(registered.limits) !== JSON.stringify(fixture.limits) ||
    JSON.stringify(registered.cardinalities) !== JSON.stringify(fixture.cardinalities) ||
    JSON.stringify(registered.fields) !== JSON.stringify(fixture.fields) ||
    registered.minimum !== fixture.minimum) {
    return incomplete('unregistered-fixture-or-experiment');
  }
  const programSha256 = sha256(JSON.stringify(fixture.program()));
  const sourceDefinitionSha256 = sha256(fixture.createSourceSql);
  let revision, sourceContentSha256, releaseArtifactSha256, runtime;
  let productProfile, nativeEstimateSource;
  const timingPairs = [];
  for (const [index, pair] of pairs.entries()) {
    const provenance = pair?.provenance;
    const native = pair?.productProfile === 'native-direct';
    if (native && fixture.rows !== 100 && fixture.rows !== 1000 &&
        fixture.workload !== workloads[0]) {
      return incomplete(`native-profile-outside-selected-cases:${index}`);
    }
    if (pair?.index !== index || pair.caseId !== fixture.id ||
      pair.status !== 'diagnostic-completed' || pair.acceptanceEligible !== true ||
      (native
        ? pair.nativeObligationAdmission?.version !==
            'actql-native-retained-equivalent-admission/0.1' ||
          pair.nativeObligationAdmission.accepted !== true ||
          pair.selectionProfile?.admitted !== true ||
          !/^sha256:[0-9a-f]{64}$/.test(
            pair.selectionProfile.estimateSource ?? '') ||
          pair.identityEqual !== true || pair.metadataEqual !== true ||
          pair.stageRowsEqual !== true || pair.stageContentsEqual !== true
        : pair.equivalentObligationAdmission?.accepted !== true ||
          pair.transferWorkComparison?.terminalReleaseConfirmed !== true ||
          pair.logicalAccountingEquivalent !== true ||
          pair.acquisitionMetadataEquivalent !== true ||
          pair.transferWorkAccountingEquivalent !== true)) {
      return incomplete(`unadmitted-pair:${index}`);
    }
    if (productProfile !== undefined &&
        productProfile !== (native ? 'native-direct' : 'node-managed') ||
        native && nativeEstimateSource !== undefined &&
        nativeEstimateSource !== pair.selectionProfile.estimateSource) {
      return incomplete(`mixed-product-profile:${index}`);
    }
    productProfile = native ? 'native-direct' : 'node-managed';
    if (native) nativeEstimateSource = pair.selectionProfile.estimateSource;
    if (!provenance || provenance.registrationSha256 !== registrationSha256 ||
      provenance.programSha256 !== programSha256 ||
      provenance.sourceDefinitionSha256 !== sourceDefinitionSha256 ||
      !/^[0-9a-f]{40}$/.test(provenance.revision ?? '') ||
      !/^[0-9a-f]{64}$/.test(provenance.sourceContentSha256 ?? '') ||
      !/^[0-9a-f]{64}$/.test(provenance.releaseArtifactSha256 ?? '') ||
      typeof provenance.runtime !== 'string' || !provenance.runtime.length ||
      (revision !== undefined && revision !== provenance.revision) ||
      (sourceContentSha256 !== undefined && sourceContentSha256 !== provenance.sourceContentSha256) ||
      (releaseArtifactSha256 !== undefined &&
        releaseArtifactSha256 !== provenance.releaseArtifactSha256) ||
      (runtime !== undefined && runtime !== provenance.runtime)) {
      return incomplete(`unmatched-provenance:${index}`);
    }
    revision = provenance.revision;
    sourceContentSha256 = provenance.sourceContentSha256;
    releaseArtifactSha256 = provenance.releaseArtifactSha256;
    runtime = provenance.runtime;
    const a = pair.samples?.[equivalent];
    const b = pair.samples?.[retained];
    // The independent leg becomes admissible through the pair's exact
    // obligation check. The retained leg must also qualify as a normal,
    // calibrated product selection; diagnostic forced estimates do not.
    if (a?.status !== 'diagnostic-completed' || b?.status !== 'completed' ||
      b.acceptanceEligible !== true) {
      return incomplete(`unqualified-product-sample:${index}`);
    }
    if (!Number.isFinite(a.cleanupMs) || a.cleanupMs < 0 ||
      !Number.isFinite(b.cleanupMs) || b.cleanupMs < 0) {
      return incomplete(`unreleased-sample:${index}`);
    }
    timingPairs.push({index, caseId: fixture.id, order: pair.order,
      samples: {[equivalent]: {...a, status: 'completed'}, [retained]: b}});
  }
  const small = fixture.rows === 100 || fixture.rows === 1000;
  const gates = small ? [
    assessPairedTiming(timingPairs, {comparator: equivalent, field: 'warmMs',
      mode: 'difference', threshold: 10}),
    assessPairedTiming(timingPairs, {comparator: equivalent, field: 'coldMs',
      mode: 'difference', threshold: 100}),
  ] : [assessPairedTiming(timingPairs, {comparator: equivalent, field: 'executionMs',
    mode: 'ratio', threshold: 1.25})];
  const status = gates.some(gate => gate.status === 'incomplete') ? 'incomplete' :
    gates.some(gate => gate.status === 'fail') ? 'fail' :
      gates.some(gate => gate.status === 'indeterminate') ? 'indeterminate' : 'pass';
  return Object.freeze({status, scope: 'one-equivalent-comparator-only',
    caseId: fixture.id, revision, sourceContentSha256, releaseArtifactSha256,
    registrationSha256, productProfile, nativeEstimateSource,
    programSha256, runtime, pairs: pairs.length, gates});
}
