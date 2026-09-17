import assert from 'node:assert/strict';
import {workloads} from '../../../benchmarks/retained-results/fixtures.mjs';

export const equivalentAdmissionVersion =
  'actql-retained-equivalent-obligation-admission/0.1';

const expectedStages = fixture => fixture.workload === workloads[1]
  ? [
      ['capture', fixture.cardinalities.capture],
      ['a', fixture.cardinalities.a],
      ['b', fixture.cardinalities.b],
      ['join', fixture.cardinalities.join],
      ['count', fixture.cardinalities.count],
    ]
  : [
      ['capture', fixture.cardinalities.capture],
      ['a', fixture.cardinalities.a],
      ['b', fixture.cardinalities.b],
      ['c', fixture.cardinalities.c],
    ];

const duration = (value, label) => {
  assert(Number.isFinite(value) && value >= 0,
    `InvalidEquivalentAdmissionDuration:${label}`);
};

export function admitEquivalentObligationPair({
  fixture,
  retained,
  equivalent,
  logicalAccountingEquivalent,
  acquisitionMetadataEquivalent,
  transferWorkAccountingEquivalent,
  unresolved,
}) {
  assert(fixture && retained && equivalent,
    'IncompleteEquivalentAdmissionInput');
  assert.equal(retained.status, 'completed');
  assert.equal(equivalent.status, 'diagnostic-completed');
  assert.equal(retained.report?.comparator, 'retained-actql');
  assert.equal(equivalent.report?.comparator,
    'independent-obligation-assembly');
  assert.equal(retained.report.caseId, fixture.id);
  assert.equal(equivalent.report.caseId, fixture.id);
  assert.equal(logicalAccountingEquivalent, true);
  assert.equal(acquisitionMetadataEquivalent, true);
  assert.equal(transferWorkAccountingEquivalent, true);
  assert.deepEqual(unresolved, []);

  const expected = expectedStages(fixture);
  assert.deepEqual(
    equivalent.report.stages.map(stage => [stage.stage, stage.rows]),
    expected,
  );
  assert.equal(equivalent.report.validationRows,
    fixture.cardinalities.source);
  assert.equal(equivalent.report.holding.holdings, expected.length);
  assert.equal(equivalent.report.capacity.conformance,
    'registered-fixture-bounded');
  assert(equivalent.report.capacity.execution.admittedBytes <=
    equivalent.report.capacity.execution.limitBytes);
  assert(equivalent.report.capacity.independentRetention.fileReservedBytes <=
    equivalent.report.capacity.independentRetention.limitBytes);

  const productStages = expected.slice(1);
  assert.deepEqual(
    retained.report.tasks.map(task => task.task),
    productStages.map((_, index) => index + 1),
  );
  assert.deepEqual(
    retained.report.completionDescriptors.map(descriptor => descriptor.rows),
    productStages.map(([, rows]) => rows),
  );
  const identity = fixture.identity();
  assert.equal(retained.report.expectedRowsCid, identity.rowsCid);
  assert.equal(retained.report.rows, identity.rows);
  assert.equal(equivalent.report.stages.at(-1).cid, identity.rowsCid);
  assert.equal(equivalent.report.stages.at(-1).rows, identity.rows);
  duration(retained.cleanupMs, 'retained.cleanupMs');
  duration(equivalent.cleanupMs, 'equivalent.cleanupMs');

  return Object.freeze({
    version: equivalentAdmissionVersion,
    accepted: true,
    scope: 'one registered retained-results fixture and matched fresh-process pair',
    requirements: Object.freeze([
      'immutable source and clean fixed revision',
      'complete registered task and holding boundaries',
      'finite registered expression-demand and guard conformance',
      'logical guard and comparison accounting parity',
      'acquisition evidence metadata parity',
      'transfer-domain separation and terminal resource release',
      'independent final ordered-content oracle',
    ]),
  });
}
