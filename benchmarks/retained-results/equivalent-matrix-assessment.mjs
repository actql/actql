// Aggregate raw paired evidence for the registered equivalent-obligations
// comparator. This is one mandatory gate, not whole-experiment acceptance.
import {assessEquivalentSeries} from './equivalent-series-assessment.mjs';
import {retainedMatrix} from './fixtures.mjs';

export function assessEquivalentMatrix(records, expectedRevision) {
  if (!Array.isArray(records) ||
      !/^[0-9a-f]{40}$/.test(expectedRevision ?? '')) {
    throw new TypeError('InvalidEquivalentMatrixAssessment');
  }
  const fixtures = retainedMatrix();
  const registered = new Set(fixtures.map(fixture => fixture.id));
  const seen = new Map();
  const unexpected = [];
  const duplicated = [];
  for (const record of records) {
    if (!record || typeof record.caseId !== 'string' ||
        !registered.has(record.caseId)) {
      unexpected.push(record?.caseId ?? null);
      continue;
    }
    if (seen.has(record.caseId)) {
      duplicated.push(record.caseId);
      continue;
    }
    seen.set(record.caseId, record.pairs);
  }
  let runtime, releaseArtifactSha256;
  const cases = fixtures.map(fixture => {
    const assessment = assessEquivalentSeries(fixture, seen.get(fixture.id));
    if (assessment.status === 'incomplete') return assessment;
    if (assessment.revision !== expectedRevision) {
      return Object.freeze({...assessment, status: 'incomplete',
        reason: 'mixed-or-unexpected-revision'});
    }
    if (runtime !== undefined && assessment.runtime !== runtime) {
      return Object.freeze({...assessment, status: 'incomplete',
        reason: 'mixed-runtime'});
    }
    if (releaseArtifactSha256 !== undefined &&
        assessment.releaseArtifactSha256 !== releaseArtifactSha256) {
      return Object.freeze({...assessment, status: 'incomplete',
        reason: 'mixed-release-build'});
    }
    runtime = assessment.runtime;
    releaseArtifactSha256 = assessment.releaseArtifactSha256;
    return assessment;
  });
  const incomplete = cases.some(value => value.status === 'incomplete') ||
    unexpected.length > 0 || duplicated.length > 0;
  const status = incomplete ? 'incomplete' :
    cases.some(value => value.status === 'fail') ? 'fail' :
      cases.some(value => value.status === 'indeterminate')
        ? 'indeterminate' : 'pass';
  return Object.freeze({
    scope: 'equivalent-obligations-27-case-timing-only',
    wholeExperimentAcceptance: false,
    status,
    expectedRevision,
    runtime,
    releaseArtifactSha256,
    registeredCases: fixtures.length,
    receivedRecords: records.length,
    unexpected,
    duplicated,
    cases,
  });
}

export function formatEquivalentMatrix(assessment) {
  if (!assessment || assessment.scope !==
      'equivalent-obligations-27-case-timing-only') {
    throw new TypeError('InvalidEquivalentMatrixReport');
  }
  const lines = [
    '# Equivalent-obligations retained-result comparison',
    '',
    `Status: **${assessment.status}**. Scope: one comparator; ` +
      'this is not whole-experiment acceptance.',
    '',
    `Expected revision: \`${assessment.expectedRevision}\`. ` +
      `Registered cases: ${assessment.registeredCases}. ` +
      `Received records: ${assessment.receivedRecords}.`,
    `Generated release build: \`${assessment.releaseArtifactSha256 ?? 'unverified'}\`.`,
    '',
    '| Case | Status | Pairs | Gate 95% intervals | Reason |',
    '| --- | --- | ---: | --- | --- |',
  ];
  for (const entry of assessment.cases) {
    const gates = entry.gates?.map(gate =>
      gate.status === 'incomplete'
        ? `${gate.field}: incomplete (${gate.reason})`
        : `${gate.field}: ${gate.lower.toFixed(3)}–${gate.upper.toFixed(3)} ` +
          `(limit ${gate.threshold}, ${gate.status})`).join('; ') ?? '';
    lines.push(`| ${entry.caseId} | ${entry.status} | ${entry.pairs ?? ''} | ` +
      `${gates} | ${entry.reason ?? ''} |`);
  }
  if (assessment.unexpected.length || assessment.duplicated.length) {
    lines.push('', `Unexpected records: ${assessment.unexpected.length}. ` +
      `Duplicate records: ${assessment.duplicated.length}.`);
  }
  return lines.join('\n') + '\n';
}
