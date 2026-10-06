import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {formatCheckOutcome, explainCheckOutcome} from './index.mjs';
import {checkOutcomeSchemaCid, checkReasonSchemaCid} from '@actql/client-wire';
const metadata = {version: 'actql-check-outcome/0.1', reason_schema_cid: checkReasonSchemaCid,
  outcome_schema_cid: checkOutcomeSchemaCid};
const report = (verdict, reasons = [], requirements = [], limits = [], unresolved = []) =>
  ({scope: {kind: 'bound_input'}, context_ref: 'ctx:fixture', verdict,
    inputs: [{document_id: 'source', kind: 'text', revision: 'rev:' + '1'.repeat(64), byte_length: 8}],
    reasons, requirements, coverage: {limits, unresolved}});
const completed = (...args) => ({...metadata, outcome: 'completed', report: report(...args)});

test('check formats keep invalid, missing and limited observations distinct', () => {
  const fixtures = [
    completed('invalid', [{code: 'query_syntax_invalid'}]),
    completed('undetermined', [], [{code: 'parameter_value_required', facts: {parameter: 'x', expected_type: 'number'}}], [{code: 'bound_values_missing'}]),
    completed('undetermined', [], [], [{code: 'analysis_budget_exhausted'}]),
    completed('undetermined', [], [], [{code: 'implementation_limit'}]),
    completed('verified'),
  ];
  for (const outcome of fixtures) {
    const json = JSON.parse(formatCheckOutcome(outcome, {format: 'json'}));
    assert.deepEqual(json.observation, explainCheckOutcome(outcome), '[check-mutation:format-verdict]');
    assert.equal(json.omittedEntries, 0);
    assert.match(formatCheckOutcome(outcome), new RegExp('^completed/' + outcome.report.verdict));
    assert.match(formatCheckOutcome(outcome, {format: 'html'}), /^<section><h2>completed\//u);
  }
  assert.equal(JSON.parse(formatCheckOutcome(fixtures[1], {format: 'json'})).entries[0].kind, 'requirement');
  assert.equal(JSON.parse(formatCheckOutcome(fixtures[2], {format: 'json'})).entries[0].kind, 'limit');
});

test('partial and unavailable formatting never invents verification or a report', () => {
  const partial = {...metadata, outcome: 'failed', correlation_ref: 'corr:a', problem: {code: 'check_internal'},
    partial_report: report('invalid', [{code: 'query_syntax_invalid'}])};
  const unavailable = {...metadata, outcome: 'unavailable', correlation_ref: 'corr:a', problem: {code: 'check_unavailable'}};
  const first = JSON.parse(formatCheckOutcome(partial, {format: 'json'}));
  assert.equal(first.observation.report.completeness, 'partial');
  assert.equal(first.observation.outcome, 'failed');
  const second = JSON.parse(formatCheckOutcome(unavailable, {format: 'json'}));
  assert.equal(Object.hasOwn(second.observation, 'report'), false);
  assert.deepEqual(second.entries, []);
  assert.equal(formatCheckOutcome({...partial, partial_report: report('verified')}), undefined);
});

test('formatting rejects malformed known facts and unknown protocol states', () => {
  for (const outcome of [completed('invalid', [{code: 'supplied_value_type_mismatch', facts: {parameter: 'x'}}]),
    {...metadata, outcome: 'future_success'}, completed('future_success'), {...completed('verified'), reason_schema_cid: 'sha256:' + '0'.repeat(64)}]) {
    assert.equal(formatCheckOutcome(outcome), undefined);
  }
  const unknown = completed('invalid', [{code: 'future_reason'}]);
  const entry = JSON.parse(formatCheckOutcome(unknown, {format: 'json'})).entries[0];
  assert.equal(entry.explanationKind, 'unknown');
  assert.equal(Object.hasOwn(entry, 'hint'), false);
});

test('display formats escape controls, bidi and markup while retaining data', () => {
  const parameter = '<img src=x onerror="run()">\u202e\u2066\u061c\u007f\u0085\u001b[2J\u009b2J\n';
  const outcome = completed('invalid', [{code: 'supplied_value_type_mismatch',
    facts: {parameter, expected_type: 'number', actual_type: 'string'}}]);
  const text = formatCheckOutcome(outcome);
  const html = formatCheckOutcome(outcome, {format: 'html'});
  const json = formatCheckOutcome(outcome, {format: 'json'});
  for (const output of [text, html, json]) assert.doesNotMatch(output, /[\u202e\u2066\u061c\u007f\u0085\u001b\u009b]/u,
    '[check-mutation:format-controls]');
  assert.doesNotMatch(html, /<img|onerror="run/u, '[check-mutation:format-markup]');
  assert.match(html, /&lt;img/u);
  assert.doesNotMatch(json, /<img/u);
  assert.equal(JSON.parse(json).entries[0].facts.parameter, parameter);
  assert.equal(text.split('\n').length, 4);
});

test('bounded formats explicitly count omitted entries without changing verdict', () => {
  const outcome = completed('invalid', Array.from({length: 30}, () => ({code: 'supplied_value_type_mismatch',
    facts: {parameter: 'é'.repeat(256), expected_type: 'number', actual_type: 'string'}})));
  for (const format of ['text', 'html', 'json']) {
    const output = formatCheckOutcome(outcome, {format, maxBytes: 1024});
    assert.ok(Buffer.byteLength(output) <= 1024);
    if (format === 'json') {
      const model = JSON.parse(output);
      assert.equal(model.observation.report.verdict, 'invalid', '[check-mutation:format-verdict]');
      assert.equal(model.omittedEntries, 30 - model.entries.length, '[check-mutation:format-omitted]');
      assert.ok(model.omittedEntries > 0, '[check-mutation:format-omitted]');
    } else assert.match(output, /Omitted entries: [1-9][0-9]*\./u, '[check-mutation:format-omitted]');
  }
  for (const options of [{format: 'future'}, {maxBytes: 0}, {maxBytes: Infinity}, {maxBytes: 1048577}])
    assert.equal(formatCheckOutcome(outcome, options), undefined);
});

test('locale callbacks cannot retarget the captured public observation', () => {
  const outcome = completed('invalid', [{code: 'query_syntax_invalid'}]);
  const output = formatCheckOutcome(outcome, {format: 'json', get locale() {
    outcome.report.verdict = 'verified'; outcome.report.reasons = []; return 'ja';
  }});
  const json = JSON.parse(output);
  assert.equal(json.observation.report.verdict, 'invalid', '[check-mutation:format-verdict]');
  assert.equal(json.entries[0].code, 'query_syntax_invalid');
  assert.equal(json.presentation.locale, 'ja');
  assert.match(json.observation.summary, /入力違反/u);
});
