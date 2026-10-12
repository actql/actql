import assert from 'node:assert/strict';
import test from 'node:test';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
import {calendarSourceIdentityOracle} from './calendar-source-identity-oracle.mjs';
const read = path => JSON.parse(readFileSync(path, 'utf8'));
const prefix = 'reviews/2026-10-13-frontend-calendar-source/';
const canonical = value => Array.isArray(value) ? value.map(canonical)
  : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(k => [k, canonical(value[k])])) : value;
const cid = value => 'sha256:' + createHash('sha256').update(JSON.stringify(canonical(value))).digest('hex');

test('Calendar source controls retain independently hashed exact selected UTC artifact and envelope', () => {
  const table = read(prefix + 'utc-table.json');
  const {evidence_bundle_cid: pin, ...body} = read(prefix + 'control-environment.json');
  assert.equal(cid(body), pin);
  assert.equal(cid(table), body.host_policy_profile.calendar.table_bytes_cid);
  assert.equal(table.tzdb_version, 'test-fixture');
  assert.deepEqual(table.zones, {UTC: {initial_offset_seconds: 0, transitions: []}});
  assert.equal(table.coverage_start_ms, -62135596800000);
  assert.equal(table.coverage_end_ms, 253402300800000);
  const expected = read(prefix + 'expected.json');
  assert.deepEqual(expected.rows, [
    {start: '2000-01-01T00:00:00.000Z', end: '2000-01-02T00:00:00.000Z'},
    {start: '2000-01-02T00:00:00.000Z', end: '2000-01-03T00:00:00.000Z'},
  ]);
  assert.deepEqual(expected.columns, ['start', 'end'].map(name =>
    ({name, contract: {type: 'timestamp', nullable: false}})));
});

test('Calendar source grammar updates containing identities while preserving parent bodies limits and Values', () => {
  const before = calendarSourceIdentityOracle({current: false});
  const after = calendarSourceIdentityOracle();
  assert.deepEqual(before, read(prefix + 'preimages/pre-values.json'));
  assert.deepEqual(after, read(prefix + 'preimages/current-values.json'));
  assert.deepEqual(after.grammar, read('spec/manifests/actql-grammar-0.1.json'));
  assert.deepEqual(after.values_dependencies, before.values_dependencies);
  assert.deepEqual(after.program_identity, before.program_identity);
  assert.deepEqual(after.run_preimages.executable.nodes, before.run_preimages.executable.nodes);
  assert.deepEqual(after.run_preimages.executable.resolved_limits, before.run_preimages.executable.resolved_limits);
  assert.notEqual(after.run_preimages.run.run_definition_cid, before.run_preimages.run.run_definition_cid);
});

test('Calendar current text documents existing optional profile and role-specific source admission', () => {
  const grammar = readFileSync('spec/grammar/actql-query-0.1.ebnf', 'utf8');
  assert.match(grammar, /relation_generator = \( "time_series" \| "calendar_series" \)/u);
  assert.ok(grammar.includes('"calendar_bucket"'));
  const profile = read('spec/frontend/frontend-profile-r1.json').features.find(f => f.feature_id === 'query.cte');
  assert.ok(profile.surface_forms.some(f => f.startsWith('|> calendar_bucket(')));
  assert.ok(profile.surface_forms.some(f => f.includes('calendar_series(')));
  assert.ok(profile.preconditions.some(f => f.startsWith('Calendar remains optional')));
  assert.deepEqual(profile.execution_evidence_ids, []);
});
