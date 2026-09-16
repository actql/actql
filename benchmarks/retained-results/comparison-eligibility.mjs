// Eligibility only: never a performance certificate or a timing sample.
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {retainedMatrix} from './fixtures.mjs';
import {baselineRetentionFeasibility, verifyBaselineCapacityEvidence} from './baseline-feasibility.mjs';

export const acceptanceAddendum = 'acceptance-addendum-2026-09-16';
const originalHash = '83fc5ce32f20de2492ef862726e057a03b43d46e0488023742550a25b4fff305';

export function comparisonEligibility(caseId, {retained, baseline, equivalent} = {}) {
  const registration = readFileSync(new URL('experiment.json', import.meta.url));
  if (createHash('sha256').update(registration).digest('hex') !== originalHash) {
    throw Error('OriginalRegistrationChanged');
  }
  const fixture = retainedMatrix().find(value => value.id === caseId);
  if (!fixture) throw Error('UnregisteredCase');
  const evidence = verifyBaselineCapacityEvidence();
  const capacity = baselineRetentionFeasibility(fixture.workload, fixture.layout, fixture.rows);
  const impossible = capacity.status === 'impossible-under-declared-retention';
  const complete = retained?.status === 'completed';
  // An alleged successful baseline conflicts with the pinned resource policy.
  // Investigate its configuration instead of using an invalid denominator.
  const baselineStatus = impossible
    ? baseline?.status === 'completed' ? 'conflicting-capacity-evidence' : 'ratio-not-computable'
    : complete && baseline?.status === 'completed' ? 'paired-samples-required' : 'undetermined';
  return Object.freeze({caseId, addendum: acceptanceAddendum,
    scope: 'comparison-eligibility-only', performanceAcceptance: false,
    retained: complete ? 'completion-reported-verification-required' : 'incomplete',
    baseline: {status: baselineStatus, ...(impossible ? {capacity, evidence,
      reason: 'declared-retention-lower-bound-exceeds-1-GiB',
      interpretation: complete ? 'baseline-infeasible-retained-completion-reported' : 'retained-still-incomplete'} : {})},
    equivalent: {status: complete && equivalent?.status === 'completed'
      ? 'equivalence-and-paired-samples-required' : 'undetermined'},
  });
}
