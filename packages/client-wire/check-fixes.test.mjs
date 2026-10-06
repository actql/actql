import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {validCheckOutcome} from './index.mjs';

// Literal fixture for SELECT 1 AS n /*; never generated from a Host report.
const fixture = JSON.parse(readFileSync(new URL('./fixtures/check-comment-fix.json', import.meta.url)));
test('comment fix wire admits only known exact revision-bound EOF insertions', () => {
  assert.equal(validCheckOutcome(fixture), true);
  const invalid = [
    reason => {reason.code = 'future_unknown';},
    reason => {reason.facts.issue = 'invalid_escape';},
    reason => {delete reason.facts;},
    reason => {delete reason.location;},
    reason => {reason.location.precision = 'approximate';},
    reason => {reason.fixes = [];},
    reason => {reason.fixes.push(structuredClone(reason.fixes[0]));},
    reason => {reason.fixes[0].extra = 'private';},
    reason => {reason.fixes[0].code = 'run_shell';},
    reason => {reason.fixes[0].applicability = 'automatic';},
    reason => {reason.fixes[0].risk = 'none';},
    reason => {reason.fixes[0].target.document_id = 'parameters';},
    reason => {reason.fixes[0].target.revision = 'rev:' + '2'.repeat(64);},
    reason => {reason.fixes[0].edits[0].start_byte = 15;},
    reason => {reason.fixes[0].edits[0].end_byte = 17;},
    reason => {reason.fixes[0].edits[0].replacement = 'DROP SOURCE records';},
    reason => {reason.fixes[0].edits[0].start_byte = 16.5;},
    reason => {reason.fixes[0].edits.push(structuredClone(reason.fixes[0].edits[0]));},
  ];
  for (const mutate of invalid) {
    const outcome = structuredClone(fixture); mutate(outcome.report.reasons[0]);
    assert.equal(validCheckOutcome(outcome), false, '[check-mutation:fix-wire]');
  }
  const unknown = structuredClone(fixture);
  delete unknown.report.reasons[0].fixes;
  unknown.report.reasons[0] = {code: 'future_unknown'};
  assert.equal(validCheckOutcome(unknown), true);
  const previous = structuredClone(fixture);
  previous.reason_schema_cid = 'sha256:6b6f4811a1d2fd685c309769b30a796273d47a45182aff58b7398358c6770fb6';
  previous.outcome_schema_cid = 'sha256:0f7a006d18e01848f95b7d6b7204f82c1913136d148d26ebffec26bb1b587ef2';
  assert.equal(validCheckOutcome(previous), false);
});
