import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { checkVocabulary } from './generate-aql-text-vocabulary.mjs';
import {legacyGraphSchemas} from './graph-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url));
const json = path => JSON.parse(read(path));
const profile = json('spec/frontend/frontend-profile-r1.json');
const baseline = json('spec/frontend/baseline.json');
const index = json('spec/frontend/acceptance-index.json');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');

test('public source closure has no legacy parser or formatter dependency', () => {
  assert.equal(existsSync('src/aql_text/moon.pkg'), false);
  const pending = ['source_frontend', 'connectors_builtin_node'];
  const visited = new Set();
  while (pending.length) {
    const name = pending.pop();
    if (visited.has(name)) continue;
    visited.add(name);
    assert.notEqual(name, 'internal_structural_fixture');
    const manifest = read(`src/${name}/moon.pkg`).toString();
    for (const section of manifest.matchAll(/import\s*\{([\s\S]*?)\}(\s*for\s*"test")?/gu)) {
      if (section[2]) continue;
      for (const entry of section[1].matchAll(/"actql\/actql\/([^"]+)"/gu)) {
        pending.push(entry[1]);
      }
    }
  }
  assert.ok(visited.has('query_syntax'));
  assert.ok(visited.has('query_program'));
  assert.ok(visited.has('stage_syntax'));
});

test('retired text is distinct from retained machine input and migration completion', () => {
  assert.deepEqual(profile.retired_public_profiles, ['actql-text/0.1']);
  assert.ok(!profile.frontend_profiles.includes('actql-text/0.1'));
  const grammar = read('spec/grammar/actql-text-0.1.ebnf').toString();
  assert.match(grammar, /no accepted public structural text document/u);
  assert.doesNotMatch(grammar, /^\s*(program|stage|step|native_op)\s*=/mu);
  const effect = profile.features.find(f => f.feature_id === 'effect.declaration');
  assert.equal(effect.adoption, 'supported');
  assert.equal(effect.implementation_status, 'partial');
  assert.ok(effect.surface_forms.includes('|> EFFECT name UPDATE TARGET string MAPPING identifier FROM RESULT name ID field SET (assignments)'));
  assert.ok(profile.features.find(f => f.feature_id === 'query.pipe')
    .surface_forms.includes('|> ASSERT UNIQUE BY (fields)'));
  assert.ok(effect.surface_forms.includes('|> EFFECT name ...'));
  assert.ok(!profile.features.find(f => f.feature_id === 'effect.hidden')
    .surface_forms.includes('|> EFFECT'));
  assert.match(read('docs/design/frontend-language-migration.md').toString(),
    /Keeping machine Programs[\s\S]*not completion/u);
});

test('machine Program vocabulary matches the current closed inventory', () => {
  checkVocabulary();
  const manifest = json('spec/manifests/actql-grammar-0.1.json');
  const operations = profile.structured_total_coverage.map(x => x.operation);
  assert.equal(new Set(operations).size, 72);
  // The adopted frontend matrix is a frozen baseline, not a claim that the
  // separately selected keyed machine constructor has a frontend spelling.
  assert.deepEqual([...operations, 'property_graph'].sort(), [...manifest.operations].sort());
  // PR-0 is a frozen historical observation, not the live compilation manifest.
  const {grammar_manifest_cid: _oldCid,
    expression_contract_cid: oldExpression, ...oldBody} = baseline.grammar_manifest;
  const {grammar_manifest_cid: _newCid, structural_text_grammar_sha256: grammar,
    structural_text_rules_sha256: rules,
    query_text_grammar_sha256: queryGrammar,
    query_text_rules_sha256: queryRules, source_grammar_cid: sourceGrammar,
    operations: currentOperations, expression_contract_cid: currentExpression,
    ...unchangedBody} = manifest;
  const expressions = json('spec/contracts/actql-expressions.json');
  assert.equal(currentExpression, machineCid(expressions));
  // The adopted shared membership exception changes the current contract,
  // while the PR-0 baseline continues to identify the original law body.
  const priorExpressions = structuredClone(expressions);
  delete priorExpressions.laws.membership;
  assert.equal(oldExpression, machineCid(priorExpressions));
  const currentProgram = json('spec/contracts/actql-protocol-schemas.json')
    .artifact_schemas.executable_plan.properties.execution_material.properties.program;
  assert.equal(machineCid(currentProgram), sourceGrammar);
  const priorProgram = structuredClone(currentProgram);
  Object.assign(priorProgram.properties.steps.items.properties, legacyGraphSchemas());
  delete priorProgram.properties.steps.items.properties.property_graph;
  assert.equal(machineCid(priorProgram), oldBody.source_grammar_cid);
  unchangedBody.source_grammar_cid = machineCid(priorProgram);
  unchangedBody.operations = currentOperations.filter(name => name !== 'property_graph');
  assert.deepEqual(oldBody, unchangedBody);
  assert.equal(grammar, hash(read('spec/grammar/actql-text-0.1.ebnf')));
  assert.equal(rules, hash(read('docs/spec/structural-text.md')));
  assert.equal(queryGrammar, hash(read('spec/grammar/actql-query-0.1.ebnf')));
  assert.equal(queryRules, hash(read('docs/spec/query-text.md')));
  for (const op of profile.structured_total_coverage) {
    assert.deepEqual(op.surface, ['Program JSON', 'Program YAML']);
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
    const retired = ['text.envelope', 'text.total'].includes(feature.feature_id);
    assert.equal(feature.implementation_status, retired ? 'retired' :
      (['acquisition.infer', 'vector.nearest', 'effect.hidden', 'effect.declaration'].includes(feature.feature_id) ? 'partial' : 'not_implemented'));
    assert.deepEqual(feature.execution_evidence_ids,
      []);
    for (const evidence of feature.execution_evidence_ids) {
      assert.ok(read(profile.implementation_evidence[evidence]).length > 0);
    }
    if (feature.adoption === 'rejected') assert.equal(feature.canonical_lowering, null);
  }
  for (const item of index.cases) {
    assert.deepEqual(item.feature_ids, profile.features
      .filter(f => f.acceptance_case_ids.includes(item.id)).map(f => f.feature_id));
  }
});

test('frozen imported requirements retain their baseline, not document-check passes', () => {
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

test('INFER and NEAREST source lowering do not claim executed KEEP outcomes', () => {
  const infer = profile.features.find(f => f.feature_id === 'acquisition.infer');
  const nearest = profile.features.find(f => f.feature_id === 'vector.nearest');
  for (const feature of [infer, nearest]) {
    assert.equal(feature.implementation_status,
      'partial');
    assert.deepEqual(feature.execution_evidence_ids, []);
    assert.ok(feature.surface_forms.some(form => form.includes('KEEP')));
    assert.ok(feature.preconditions.some(rule => rule.includes('new output scope')));
  }
  assert.ok(nearest.preconditions.includes(
    'pipe input supplies queries; named candidate source supplies corpus'));
  const fx03 = index.cases.find(c => c.id === 'FX-03');
  assert.equal(fx03.imported_requirement_sha256,
    '79cd901d3319e2cb4512884d19dd4d9d016cf4f5469ac3393ddd0318f67e0ed2');
  assert.match(fx03.superseded_imported_expectation, /^Reject non-success/u);
  assert.match(fx03.expectation, /typed NULL/u);
  assert.match(fx03.expectation, /reject unknown fields/u);
});

test('independent fixtures and historical CID oracles retain their baseline bytes', () => {
  assert.match(baseline.base_sha, /^[a-f0-9]{40}$/u);
  assert.deepEqual(baseline.toolchain, json('toolchain.json'));
  for (const fixture of [...baseline.fixtures, ...baseline.existing_identity_oracles]) {
    // PR-0 remains byte-for-byte available. Active identities follow the
    // adopted String-value and common membership laws, not Frontend output.
    const historical = {
      'portability/corpus/parameter-identities.json': 'parameter-identities-pr0.json',
      'portability/corpus/stage-definition.json': 'stage-definition-pr0.json',
      'portability/corpus/local-unit-stage-body.json': 'local-unit-stage-body-pr0.json',
    }[fixture.path];
    const path = historical ? `spec/frontend/historical/${historical}` : fixture.path;
    assert.equal(hash(read(path)), fixture.sha256, fixture.path);
  }
  for (const fixture of baseline.fixtures) {
    const imported = baseline.adopted_source.files.find(
      file => file.name === fixture.path.replace('spec/frontend/fixtures/', 'examples/'));
    assert.equal(fixture.sha256, imported.sha256);
    assert.equal(fixture.execution_status, 'not_run');
  }
});

test('exact String parameter vectors preserve every unrelated historical expectation', () => {
  const old = json('spec/frontend/historical/parameter-identities-pr0.json');
  const current = json('portability/corpus/parameter-identities.json');
  assert.equal(current.version, old.version);
  const revised = new Set(['ordinary-values', 'utf16-field-order']);
  for (const [i, original] of old.cases.entries()) {
    const actual = current.cases[i];
    if (!revised.has(original.id)) {
      assert.deepEqual(actual, original, original.id);
      continue;
    }
    const {expected_canonical_json: oldBytes, expected_cid: _oldCid, ...input} = original;
    const {expected_canonical_json: bytes, expected_cid: cid, ...actualInput} = actual;
    assert.deepEqual(actualInput, input);
    // Independently selected CRLF values were formerly converted to LF.
    assert.equal(bytes, oldBytes.replaceAll('\\n', '\\r\\n'));
    assert.equal(cid, 'sha256:' + hash(Buffer.from(bytes, 'utf8')));
  }
  const strings = [
    ['CR', '\r'], ['LF', '\n'], ['CRLF', '\r\n'],
    ['composed', '\u00e9'], ['decomposed', 'e\u0301'], ['backslash-n', '\\n'],
  ];
  assert.equal(current.cases.length, old.cases.length + strings.length);
  for (const [i, [name, value]] of strings.entries()) {
    const bytes = JSON.stringify({values: {s: value}, version: 'actql-parameter-values/0.1'});
    assert.deepEqual(current.cases[old.cases.length + i], {
      id: `preserved-string-${name}`, declarations: {s: {type: 'string'}},
      supplied: {s: value}, expected_canonical_json: bytes,
      expected_cid: 'sha256:' + hash(Buffer.from(bytes, 'utf8')),
    });
  }
});
