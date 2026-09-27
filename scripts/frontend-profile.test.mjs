import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url));
const json = path => JSON.parse(read(path));
const profile = json('spec/frontend/frontend-profile-r1.json');
const baseline = json('spec/frontend/baseline.json');
const index = json('spec/frontend/acceptance-index.json');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('adopted structural vocabulary matches the current closed inventory', () => {
  const manifest = json('spec/manifests/actql-grammar-0.1.json');
  const operations = profile.structured_total_coverage.map(x => x.operation);
  assert.equal(new Set(operations).size, 72);
  assert.deepEqual([...operations].sort(), [...manifest.operations].sort());
  assert.deepEqual(baseline.grammar_manifest, manifest);
  for (const op of profile.structured_total_coverage) {
    assert.deepEqual(op.surface, ['STEP', 'OP']);
    assert.equal(op.runtime_support,
      'determined_by_existing_contract_checker_and_host');
  }
});

test('adoption decisions retain conditions and explicit case or fixture gaps', () => {
  assert.equal(profile.program_semantics, 'actql/0.1');
  assert.equal(profile.status, 'adopted_design_not_runtime_evidence');
  assert.equal(new Set(profile.features.map(f => f.feature_id)).size, 36);
  const ids = new Set(index.cases.map(c => c.id));
  for (const feature of profile.features) {
    assert.ok(['supported', 'restricted', 'rejected'].includes(feature.adoption));
    assert.ok(feature.preconditions.length > 0, feature.feature_id);
    assert.match(feature.delivery_unit, /^PR-[1-8]$/u);
    assert.ok(feature.acceptance_case_ids.length > 0 ||
      feature.additional_fixture_requirements.length > 0, feature.feature_id);
    for (const id of feature.acceptance_case_ids) assert.ok(ids.has(id), id);
    assert.equal(feature.implementation_status, 'not_implemented');
    assert.deepEqual(feature.execution_evidence_ids, []);
    if (feature.adoption === 'rejected') assert.equal(feature.canonical_lowering, null);
  }
  for (const item of index.cases) {
    assert.deepEqual(item.feature_ids, profile.features
      .filter(f => f.acceptance_case_ids.includes(item.id)).map(f => f.feature_id));
  }
});

test('all imported requirements remain pending, with no document-check passes', () => {
  assert.equal(index.case_count, 140);
  assert.equal(index.cases.length, 140);
  assert.equal(new Set(index.cases.map(c => c.id)).size, 140);
  for (const [prefix, count] of Object.entries({
    STR: 10, LEX: 12, SQL: 34, GRF: 25, VEC: 10, EVT: 20, FX: 13, SYS: 16,
  })) {
    for (let i = 1; i <= count; i++) {
      const id = `${prefix}-${String(i).padStart(2, '0')}`;
      const item = index.cases.find(c => c.id === id);
      assert.ok(item, id);
      assert.equal(item.required, true);
      assert.equal(item.status, 'not_run');
      assert.deepEqual(item.evidence, []);
      assert.ok(item.expectation.length > 20, id);
      assert.match(item.imported_requirement_sha256, /^[a-f0-9]{64}$/u);
      assert.match(item.delivery_unit, /^PR-[1-8]$/u);
    }
  }
  assert.equal(baseline.frontend_runtime_cases_executed, 0);
});

test('independent fixtures and existing CID oracles retain their baseline bytes', () => {
  assert.match(baseline.base_sha, /^[a-f0-9]{40}$/u);
  assert.deepEqual(baseline.toolchain, json('toolchain.json'));
  for (const fixture of [...baseline.fixtures, ...baseline.existing_identity_oracles]) {
    assert.equal(hash(read(fixture.path)), fixture.sha256, fixture.path);
  }
  for (const fixture of baseline.fixtures) {
    const imported = baseline.adopted_source.files.find(
      file => file.name === fixture.path.replace('spec/frontend/fixtures/', 'examples/'));
    assert.equal(fixture.sha256, imported.sha256);
    assert.equal(fixture.execution_status, 'not_run');
  }
});
