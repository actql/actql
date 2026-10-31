// Independently authored rows and wall-clock observations, never product output.
import assert from 'node:assert/strict';
import {externalRestProgram} from './provider.fixture.mjs';

const valueRows = Object.freeze([{id: 1, label: 'e\u0301'}, {id: 2, label: '東京'}]);
const sourceRows = Object.freeze([
  {id: 'alpha', amount: 7, note: 'e\u0301'},
  {id: 'beta', amount: 2, note: '東京'},
  {id: 'gamma', amount: 11, note: ''},
]);

export function timedValuesProgram() {
  return {version: 'actql/0.1', id: 'timed-values-read', stages: [{id: 'main', inputs: {},
    steps: [{values: {schema: {id: {type: 'number', nullable: false},
      label: {type: 'string', nullable: false}}, rows: [{id: 2, label: '東京'},
      {id: 1, label: 'e\u0301'}]}, as: 'input'},
    {from: 'input', sort: [{field: 'id', dir: 'asc', nulls: 'first'}], as: 'ordered'},
    {from: 'ordered', derive: {observed: {current_timestamp: []}}, as: 'timed'}],
    results: {rows: {from: 'timed', fields: ['id', 'label', 'observed']}}}],
    results: {rows: {from: {stage: 'main', result: 'rows'}}}};
}

export function timedSourceProgram(connectorId) {
  const program = externalRestProgram(connectorId);
  program.id = 'timed-external-rest-read';
  const stage = program.stages[0];
  stage.steps.push({from: 'selected', derive: {observed: {current_timestamp: []}}, as: 'timed'});
  stage.results.rows = {from: 'timed', fields: ['id', 'amount', 'note', 'observed']};
  return program;
}

export function wallObservation() {
  const milliseconds = Date.now();
  return {milliseconds, utc: new Date(milliseconds).toISOString(),
    sampler: 'fixture original Date.now', comparisonPrecision: 'milliseconds only'};
}

export function assertTimedRows(rows, {requestKind, phase, before, after, originalRows}) {
  assert(['values', 'source'].includes(requestKind));
  assert(['read', 'saved'].includes(phase));
  assert(Number.isSafeInteger(before.milliseconds) && Number.isSafeInteger(after.milliseconds));
  assert(after.milliseconds >= before.milliseconds, 'FixtureWallClockRegressed');
  const expected = requestKind === 'values' ? valueRows : sourceRows;
  assert(Array.isArray(rows)); assert.equal(rows.length, expected.length);
  const observed = rows[0]?.observed;
  assert.equal(typeof observed, 'string');
  assert.match(observed, /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$/u);
  const milliseconds = Date.parse(observed);
  assert(Number.isFinite(milliseconds));
  for (const [index, row] of rows.entries()) {
    assert.deepEqual(Object.keys(row).sort(), [...Object.keys(expected[index]), 'observed'].sort());
    assert.equal(row.observed, observed, 'One invocation must retain one exact original Timestamp');
    const {observed: ignored, ...business} = row; void ignored;
    assert.deepEqual(business, expected[index]);
  }
  if (phase === 'read') {
    // The normal embedded Host runs in this process; this is an independent
    // bracket, never an injected Host clock, literal Timestamp or Parameter.
    assert(milliseconds >= before.milliseconds && milliseconds <= after.milliseconds,
      'InvocationTimestampOutsideOriginalPublicSubmissionAndResultWindow');
  } else {
    assert.deepEqual(rows, originalRows, 'Cold Saved must retain the complete original rows');
    assert.equal(observed, originalRows[0].observed);
    // Do not manufacture separation with a clock override, sleep or retry.
    // A missing later boundary is incomplete evidence and fails this case.
    assert(before.milliseconds > milliseconds, 'LaterSavedWallBoundaryNotObserved');
  }
  return {observed, comparisonEpochMilliseconds: milliseconds, allRowsSameExactTimestamp: true,
    independentBusinessRowsExact: true, originalWallBracketPassed: phase === 'read',
    laterSavedBoundaryPassed: phase === 'saved', timestampPrecisionNotIncreased: true,
    directRunDefinitionCreatedAtObservation: 'UNOBSERVABLE through these public SDK ports'};
}
