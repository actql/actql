import test from 'node:test';
import assert from 'node:assert/strict';
import {retainedCase, workloads} from
  '../../../../../benchmarks/retained-results/fixtures.mjs';
import {
  admitEquivalentObligationPair,
  equivalentAdmissionVersion,
} from '../bench/equivalent-admission.mjs';

function input(fixture) {
  const stages = [
    ['capture', fixture.cardinalities.capture],
    ['a', fixture.cardinalities.a],
    ['b', fixture.cardinalities.b],
    ['c', fixture.cardinalities.c],
  ];
  const identity = fixture.identity();
  return {
    fixture,
    retained: {
      status: 'completed',
      cleanupMs: 1.5,
      report: {
        comparator: 'retained-actql',
        caseId: fixture.id,
        expectedRowsCid: identity.rowsCid,
        rows: identity.rows,
        tasks: stages.slice(1).map((_, index) => ({task: index + 1})),
        completionDescriptors: stages.slice(1).map(([, rows]) => ({rows})),
      },
    },
    equivalent: {
      status: 'diagnostic-completed',
      cleanupMs: 0.75,
      report: {
        comparator: 'independent-obligation-assembly',
        caseId: fixture.id,
        validationRows: fixture.cardinalities.source,
        stages: stages.map(([stage, rows], index) => ({
          stage,
          rows,
          ...(index === stages.length - 1 ? {cid: identity.rowsCid} : {}),
        })),
        holding: {holdings: stages.length},
        capacity: {
          conformance: 'registered-fixture-bounded',
          execution: {admittedBytes: 80, limitBytes: 100},
          independentRetention: {fileReservedBytes: 20, limitBytes: 100},
        },
      },
    },
    logicalAccountingEquivalent: true,
    acquisitionMetadataEquivalent: true,
    transferWorkAccountingEquivalent: true,
    unresolved: [],
  };
}

test('equivalent admission binds every registered boundary', () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const admission = admitEquivalentObligationPair(input(fixture));
  assert.equal(admission.version, equivalentAdmissionVersion);
  assert.equal(admission.accepted, true);
  assert.equal(admission.requirements.length, 7);
});

test('equivalent admission rejects unresolved or altered evidence', () => {
  const fixture = retainedCase(workloads[0], 'narrow', 100);
  const unresolved = input(fixture);
  unresolved.unresolved = ['failure parity'];
  assert.throws(() => admitEquivalentObligationPair(unresolved));

  const altered = input(fixture);
  altered.equivalent.report.stages = altered.equivalent.report.stages.map(
    (stage, index) => index === 1 ? {...stage, rows: stage.rows + 1} : stage,
  );
  assert.throws(() => admitEquivalentObligationPair(altered));

  const extraTask = input(fixture);
  extraTask.retained.report.tasks.push({task: 4});
  assert.throws(() => admitEquivalentObligationPair(extraTask));
});
