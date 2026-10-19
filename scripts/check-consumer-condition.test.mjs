import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {validCheckOutcome, checkReasonSchemaCid, checkOutcomeSchemaCid} from '../packages/client-wire/index.mjs';
const revision = 'rev:' + '1'.repeat(64);
const condition = {code: 'parameter_consumer_condition', facts: {
  argument: 'count', constraint: 'safe_integer', expected_type: 'int64', maximum: 9007199254740991,
  minimum: 1, operation: 'take', parameter: 'count', stage: 'binding'},
location: {kind: 'structured', document_id: 'parameter_declarations', revision, pointer: '/count'}};
const outcome = requirements => ({version: 'actql-check-outcome/0.1',
  reason_schema_cid: checkReasonSchemaCid, outcome_schema_cid: checkOutcomeSchemaCid,
  outcome: 'completed', report: {scope: {kind: 'template_only'}, verdict: 'verified', context_ref: 'ctx:original',
    runnable: {verdict: 'no', reasons: [{code: 'parameter_consumer_condition'}]},
    inputs: [{document_id: 'source', revision, kind: 'text', byte_length: 50},
      {document_id: 'parameter_declarations', revision, kind: 'structured', byte_length: 50}],
    requirements, reasons: [], coverage: {limits: [], unresolved: []}}});

test('Take binding conditions are closed template Requirements, independent of missing values', () => {
  assert.equal(validCheckOutcome(outcome([condition])), true);
  assert.equal(validCheckOutcome(outcome([condition, {code: 'parameter_value_required',
    facts: {parameter: 'count', expected_type: 'int64'}}])), true);
  const offset = structuredClone(condition); Object.assign(offset.facts, {argument: 'offset', minimum: 0});
  assert.equal(validCheckOutcome(outcome([offset])), true);
  for (const change of [
    value => {value.facts.minimum = 0;}, value => {value.facts.maximum = 9007199254740992;},
    value => {value.facts.argument = 'other';}, value => {value.facts.operation = 'top_k';},
    value => {value.facts.expected_type = 'decimal';}, value => {value.facts.stage = 'execution';},
    value => {value.facts.default = 0;}, value => {delete value.facts.minimum;},
    value => {value.location.document_id = 'parameters';},
  ]) {
    const bad = structuredClone(condition); change(bad);
    assert.equal(validCheckOutcome(outcome([bad])), false, JSON.stringify(bad));
  }
  const bound = outcome([condition]); bound.report.scope.kind = 'bound_input';
  assert.equal(validCheckOutcome(bound), false);
  const wrongFamily = outcome([]); wrongFamily.report.verdict = 'invalid'; wrongFamily.report.reasons = [condition];
  assert.equal(validCheckOutcome(wrongFamily), false);
  const omitted = outcome([condition]); omitted.report.omissions = {requirements: true};
  assert.equal(validCheckOutcome(omitted), false);
  const other = structuredClone(condition); other.code = 'parameter_value_required';
  assert.equal(validCheckOutcome(outcome([other])), false);
});

const canonical = v => Array.isArray(v) ? '[' + v.map(canonical).join(',') + ']'
  : v !== null && typeof v === 'object' ? '{' + Object.keys(v).sort().map(k => JSON.stringify(k)+':'+canonical(v[k])).join(',')+'}' : JSON.stringify(v);
const cid = v => 'sha256:' + createHash('sha256').update(canonical(v)).digest('hex');
test('complete historical reason/outcome bodies retain their independent original identities', () => {
  const fixture = JSON.parse(readFileSync('scripts/fixtures/check-consumer-condition-historical.json', 'utf8'));
  const historical = JSON.parse(execFileSync('git', ['show', fixture.source + ':spec/contracts/actql-protocol-schemas.json'],
    {encoding: 'utf8', maxBuffer: 16*1024*1024}));
  for (const name of ['reason', 'outcome']) {
    assert.deepEqual(fixture[name], historical.artifact_schemas['check_' + name]);
    assert.equal(cid(fixture[name]), fixture[name + '_cid']);
    assert.notEqual(fixture[name + '_cid'], name === 'reason' ? checkReasonSchemaCid : checkOutcomeSchemaCid);
  }
  const prior = outcome([{code: 'parameter_value_required', facts: {parameter: 'count', expected_type: 'int64'}}]);
  prior.report.runnable.reasons = [{code: 'parameter_value_required'}];
  assert.equal(validCheckOutcome(prior), true);
  const old = structuredClone(prior); old.reason_schema_cid = fixture.reason_cid; old.outcome_schema_cid = fixture.outcome_cid;
  assert.equal(validCheckOutcome(old), false, 'old containing identity cannot masquerade as the new schema');
});

test('current literal vectors change only independently admitted containing identities', () => {
  const fixture = JSON.parse(readFileSync('scripts/fixtures/check-consumer-condition-historical.json', 'utf8'));
  for (const entry of fixture.currentLiteralPinAdoptions) {
    const original = execFileSync('git', ['show', fixture.source + ':' + entry.path], {maxBuffer: 16*1024*1024});
    assert.equal(createHash('sha256').update(original).digest('hex'), entry.sha256);
    assert.equal(execFileSync('git', ['rev-parse', fixture.source + ':' + entry.path], {encoding: 'utf8'}).trim(), entry.gitBlob);
    let expected = original.toString('utf8');
    for (const [before, after] of Object.entries(entry.replacements)) expected = expected.replaceAll(before, after);
    assert.equal(readFileSync(entry.path, 'utf8'), expected, entry.path);
  }
  for (const name of ['reason', 'outcome']) {
    const current = fixture.checkSchemas[name];
    assert.equal(canonical(current.body), current.canonicalPreimage);
    assert.equal(cid(current.body), current.cid);
    assert.equal(current.cid, name === 'reason' ? checkReasonSchemaCid : checkOutcomeSchemaCid);
  }
});


test('Python Remote admits the same independent Take condition and refuses malformed binding demands', () => {
  const cases = [{name: 'original count', operation: 'check_outcome', valueJSON: JSON.stringify(outcome([condition])), expected: true}];
  for (const [name, change] of [
    ['wrong count minimum', value => {value.report.requirements[0].facts.minimum = 0;}],
    ['private value', value => {value.report.requirements[0].facts.value = 1;}],
    ['wrong consumer', value => {value.report.requirements[0].facts.operation = 'top_k';}],
    ['bound condition', value => {value.report.scope.kind = 'bound_input';}],
  ]) {
    const value = outcome([structuredClone(condition)]); change(value);
    cases.push({name, operation: 'check_outcome', valueJSON: JSON.stringify(value), expected: false});
  }
  const results = JSON.parse(execFileSync(process.env.ACTQL_PYTHON ?? 'python3',
    ['-I', 'scripts/fixtures/python-public-wire-vectors.py', process.cwd()], {
      encoding: 'utf8', timeout: 10000, input: JSON.stringify(cases),
    }));
  assert.equal(results.length, cases.length);
  for (const [index, actual] of results.entries()) {
    assert.equal(actual.name, cases[index].name);
    assert.equal(actual.error, undefined);
    assert.equal(actual.actual, cases[index].expected, actual.name);
  }
});
