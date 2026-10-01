import assert from 'node:assert/strict';
import test from 'node:test';
import {judge, probeStatus, sameRows} from
  './fixtures/dbt-compat-judge.mjs';

const columns = [
  {name: 'id', contract: {type: 'number', nullable: false}},
  {name: 'amount', contract: {type: 'number', nullable: true}},
];
const rows = [{id: 3, amount: 30}, {id: 3, amount: 30}, {id: 5, amount: null}];
const named = (all, extra = {}) => ({stage: 'named-result', all,
  streamed: all, streamState: 'complete', columns, ...extra});
const refused = {stage: 'actql-submission-refused',
  code: 'ClientProgramInvalidInput'};
const runFailed = {stage: 'actql-run-failed', state: {status: 'failed'}};
const observe = {expect: 'observe'};
const control = {expect: 'rows', rows, order: 'unordered'};

test('a submission refusal is a finding only for an observed case', () => {
  assert.equal(judge(observe, refused, columns).verdict, 'unsupported');
  assert.equal(judge(control, refused, columns).verdict, 'baseline-failed');
});

test('an admitted Run that fails is a failure whatever the case expects',
  () => {
    assert.equal(judge(observe, runFailed, columns).verdict, 'run-failed');
    assert.equal(judge(control, runFailed, columns).verdict, 'run-failed');
    for (const item of [observe, control]) {
      const outcome = {case: 'x', ...runFailed,
        ...judge(item, runFailed, columns)};
      assert.equal(probeStatus({outcomes: [outcome]}).status, 'failed');
    }
  });

test('a positive control checks rows, duplicates, schema and stream', () => {
  assert.equal(judge(control, named(rows), columns).verdict, 'passed');
  assert.equal(judge(control, named(rows.slice(1)), columns).verdict,
    'wrong-result');
  assert.equal(judge(control, named([...rows].reverse()), columns).verdict,
    'passed');
  assert.equal(judge({...control, order: 'listed'},
    named([...rows].reverse()), columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {streamState: 'prefix'}),
    columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {streamed: rows.slice(1)}),
    columns).verdict, 'wrong-result');
  assert.equal(judge(control, named(rows, {columns: [columns[0]]}),
    columns).verdict, 'wrong-result');
  assert.equal(judge({...control, columns: [columns[0]]},
    named(rows, {columns: [columns[0]]}), columns).verdict, 'passed');
  assert.equal(judge({expect: 'rows'}, named(rows), columns).verdict,
    'wrong-result');
});

test('the probe passes only without failures, compile problems or faults',
  () => {
    const passed = {case: 'a', verdict: 'passed'};
    const unsupported = {case: 'b', verdict: 'unsupported'};
    assert.equal(probeStatus({outcomes: [passed, unsupported]}).status,
      'passed');
    assert.equal(probeStatus({outcomes: [passed, {case: 'c'}]}).status,
      'failed');
    assert.equal(probeStatus({outcomes: [passed],
      compileProblems: [['project', {}]]}).status, 'failed');
    assert.equal(probeStatus({outcomes: [passed],
      fault: {message: 'x'}}).status, 'failed');
  });

test('row comparison keeps duplicate counts', () => {
  assert.equal(sameRows([{a: 1}, {a: 1}], [{a: 1}], 'unordered'), false);
  assert.equal(sameRows([{a: 1}, {a: 2}], [{a: 2}, {a: 1}], 'unordered'),
    true);
});
