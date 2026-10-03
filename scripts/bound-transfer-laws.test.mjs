import assert from 'node:assert/strict';
import { test } from 'node:test';
import { loadTransferLaws, validateTransferLaws } from './bound-transfer-laws.mjs';

test('every public operation has exactly one closed bound transfer classification', () => {
  const { body, source } = loadTransferLaws();
  assert.equal(validateTransferLaws(body, source).operations, 73);
  assert.equal(body.operations.property_graph, 'carrier_specific');
});

test('missing, stale, and unknown classifications fail rather than infer a default', () => {
  const { body, source } = loadTransferLaws();
  for (const mutate of [
    b => { delete b.operations.time_series; },
    b => { b.operations.event_rows = 'preserve'; },
    b => { b.operations.values = 'unconditionally_bounded'; },
    b => { b.operations = []; },
    b => { b.version = 'actql-bound-transfer-laws/9.9'; },
    b => { b.extra = true; },
  ]) {
    const changed = structuredClone(body);
    mutate(changed);
    assert.throws(() => validateTransferLaws(changed, source));
  }
  const expanded = source.replace('| RelA | [`filter`](#filter)',
    '| RelA | [`new_operation`](#filter) | relation -> relation |\n| RelA | [`filter`](#filter)');
  assert.throws(() => validateTransferLaws(body, expanded));
});

test('classifications distinguish bounds from exact counts and expansion from reduction', () => {
  const { body: { operations: o } } = loadTransferLaws();
  for (const op of ['distinct', 'dedupe_rows', 'except', 'intersect', 'top_k_by',
    'watermark_rows', 'watermark_events', 'nest', 'calendar_bucket']) assert.equal(o[op], 'preserve');
  for (const op of ['take', 'top_k']) assert.equal(o[op], 'clamp');
  for (const op of ['group', 'window_group', 'pivot', 'pool_vectors']) assert.equal(o[op], 'reduce');
  for (const op of ['unpivot', 'unnest', 'row_window', 'nearest']) assert.equal(o[op], 'multiply');
  for (const op of ['append', 'merge_rankings']) assert.equal(o[op], 'add');
  assert.equal(o.sequence, 'explicitly_unknown_requires_ceiling');
  for (const op of ['values', 'graph_bounds', 'graphs_equal', 'graph_diff', 'time_series',
    'calendar_series', 'text_rank', 'search_candidates', 'cross_join']) assert.equal(o[op], 'carrier_specific');
});
