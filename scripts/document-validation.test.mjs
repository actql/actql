import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { updateRequirements } from './update-document-metadata.mjs';
import { machineCid } from './actql-spec-family.mjs';
import { decodeYaml, programs, markdown, nodes, anchors, validateCases, validateProgramLayout, validateExamples, validateLocalLinks } from './document-validation.mjs';

test('annotation schemas preserve open metadata and all authored target kinds', () => {
  const registry = JSON.parse(readFileSync(new URL('../spec/contracts/actql-protocol-schemas.json', import.meta.url)));
  const artifacts = registry.artifact_schemas;
  const canonical = artifacts.authoring_context;
  const annotation = canonical.properties.annotations.items.properties;
  assert.deepEqual(annotation.target.properties.kind.enum,
    ['program', 'stage', 'input', 'parameter', 'binding', 'step', 'result', 'effect']);
  assert.deepEqual(annotation.meta, {
    type: 'object', minProperties: 1,
    propertyNames: { not: { pattern: '^actql_' } }, additionalProperties: true,
  });
  for (const embedded of [
    artifacts.effect_preview.properties.authoring_context,
    artifacts.plan_document.properties.authoring_context,
    artifacts.captured_run.properties.effect_context.properties.authoring_context,
  ]) assert.deepEqual(embedded, canonical);
  for (const program of [
    artifacts.executable_plan.properties.execution_material.properties.program,
    artifacts.plan_document.properties.plan.properties.execution_material.properties.program,
  ]) assert.deepEqual(program.$defs.meta, annotation.meta);
  for (const [name, schema] of Object.entries(artifacts)) {
    assert.equal(registry.artifact_schema_cids[name], machineCid(schema), name);
  }
  assert.equal(registry.artifact_registry_cid, machineCid(artifacts));
});

test('expression regex flag schemas admit exactly the portable flag strings', () => {
  const admitted = ['', 'm', 's', 'ms', 'sm'];
  for (const [name, count] of [['actql-expressions', 18], ['actql-protocol-schemas', 12]]) {
    const document = JSON.parse(readFileSync(new URL(`../spec/contracts/${name}.json`, import.meta.url)));
    let found = 0;
    function visit(value) {
      if (!value || typeof value !== 'object') return;
      const flags = value.properties?.flags;
      if (flags?.type === 'string') {
        found++;
        assert.deepEqual(flags, { type: 'string', enum: admitted });
        for (const invalid of ['mm', 'ss', 'msm', 'i', 'g', 'M', 'm\n', ' ']) {
          assert.equal(flags.enum.includes(invalid), false);
        }
      }
      for (const child of Object.values(value)) visit(child);
    }
    visit(document);
    assert.equal(found, count, name);
  }
});

test('metadata updates report changes, clear evidence and preserve explicit IDs', () => {
  const d = { spec_id: 'actql.test', path: 'test.md' };
  const source = '<a id="rule"></a>\n\n<!-- requirement-block: rule -->\nThe input MUST be finite.\n';
  const first = updateRequirements(d, source, { requirements: [] });
  assert.equal(first.changes[0].change, 'added');
  first.registry.requirements[0].status = 'verified';
  first.registry.requirements[0].evidence = ['unrelated-proof'];
  assert.equal(updateRequirements(d, source, first.registry).changes.length, 0);
  const changed = updateRequirements(d, source.replace('finite', 'nonempty'), first.registry);
  assert.equal(changed.registry.requirements[0].status, 'pending');
  assert.equal(changed.registry.requirements[0].evidence, undefined);
  assert.equal(changed.registry.requirements[0].requirement_id, 'actql.test/rule');
  assert.equal(updateRequirements(d, '', first.registry).changes[0].change, 'removed');
  assert.throws(() => updateRequirements(d, 'An input MUST be finite.', first.registry), /Unmarked/);
});

test('valid examples reject flat roots, empty stages and stage-local root fields', () => {
  const valid = { version: 'actql/0.1', id: 'demo', stages: [{ id: 'main' }] };
  validateProgramLayout(valid, 'valid');
  assert.throws(() => validateProgramLayout({ version: 'actql/0.1', inputs: {} }, 'flat'));
  assert.throws(() => validateProgramLayout({ ...valid, stages: [] }, 'empty'));
  for (const key of ['inputs', 'from', 'steps', 'effects']) assert.throws(() => validateProgramLayout({ ...valid, [key]: {} }, key));
  assert.throws(() => validateProgramLayout({ ...valid, version: 'unknown' }, 'version'));
});
test('unregistered examples fail while explicit negative fixtures remain admissible', () => {
  const discovered = new Map([['negative.aql#flat', { id: 'flat', inputs: {} }]]);
  assert.throws(() => validateExamples(discovered, []), /Unregistered/);
  const documents = [{ path: 'negative.aql', programs: [{ id: 'flat', expected_status: 'invalid', expected_diagnostic: 'ACTQL_E_STAGE_LOCAL_ROOT_FIELD' }] }];
  validateExamples(discovered, documents);
  assert.throws(() => validateExamples(discovered, [{ path: 'negative.aql', programs: [{ id: 'flat', expected_status: 'invalid' }] }]), /diagnostic/);
});
test('broken local links fail', () => {
  assert.throws(() => validateLocalLinks('README.md', '[missing](does-not-exist.md)'), /Broken link/);
});
test('broken local anchors fail and existing anchors pass', () => {
  assert.throws(() => validateLocalLinks('README.md', '[missing](README.md#not-an-existing-anchor)'), /Broken anchor/);
  const heading = [...anchors(markdown(readFileSync('README.md', 'utf8')))][0];
  assert.equal(validateLocalLinks('README.md', `[home](README.md#${encodeURIComponent(heading)})`), 1);
});

test('YAML decoding rejects duplicate keys and malformed syntax', () => {
  assert.throws(() => decodeYaml('id: a\nid: b', 'duplicate'));
  assert.throws(() => decodeYaml('items: [', 'malformed'));
});
test('Unicode business values and quoted version fields are accepted', () => {
  const p = programs('version: "actql/0.1"\nid: demo\nvalue: 日本語', 'demo.aql');
  assert.equal(p[0].value, '\u65e5\u672c\u8a9e');
});
test('Markdown code fences are not links and duplicate headings have distinct anchors', () => {
  const tree = markdown('# Hello world\n# Hello world\n[link][x]\n\n[x]: target.md\n\n```text\n[not a link](missing.md)\n```');
  assert.deepEqual([...anchors(tree)], ['hello-world', 'hello-world-1']);
  assert.equal(nodes(tree).filter(n => n.type === 'linkReference').length, 1);
  assert.equal(nodes(tree).filter(n => n.type === 'link').length, 0);
});
test('acceptance definitions can grow; duplicates and missing references fail', () => {
  const cases = { cases: ['a', 'b', 'c'].map(case_id => ({ case_id, given: 'input', when: 'action', then: 'expectation' })) };
  const trace = { decisions: [{ acceptance_cases: ['a'] }], maintained: [] };
  assert.equal(validateCases(cases, trace), 3);
  assert.throws(() => validateCases({ cases: [...cases.cases, cases.cases[0]] }, trace));
  assert.throws(() => validateCases(cases, { ...trace, additional_questions: [{ case_ids: ['missing'] }] }));
});
