import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {
  checkResultPlanBindings, checkResultPlanSchema, resultPlanCid,
} from './result-plan-contract.mjs';
import {canonicalText, verifyIdentity} from './check-canonical-json.mjs';
import {machineCid} from './actql-spec-family.mjs';

const registry = JSON.parse(readFileSync(
  'spec/contracts/actql-protocol-schemas.json', 'utf8',
));
const a = 'sha256:' + 'a'.repeat(64);
const b = 'sha256:' + 'b'.repeat(64);
const c = 'sha256:' + 'c'.repeat(64);

function fixture() {
  const result = {
    version: 'actql-result-plan/0.1',
    result_name: 'answer',
    unit_definition_cid: a,
    unit_result_name: 'rows',
    unit_result_ordinal: 0,
    projection: [
      {input: 'id', output: 'id', value_contract_cid: b},
    ],
    order: {strategy: 'projected_fields', terms: [
      {field: 'id', direction: 'asc', nulls: 'last', authored: false},
    ]},
    typed_output_port: {
      name: 'rows', carrier: 'relation', row_contract_cid: c,
    },
  };
  result.result_plan_logical_cid = resultPlanCid(result);
  const plan = {
    nodes: [{node_id: 'result_0', output_contracts: {rows: c}}],
    root_refs: [{
      role: 'requested_result', name: 'answer',
      ref: {node_id: 'result_0', port: 'rows'},
    }],
    execution_material: {
      result_plan_logical_cids: {answer: result.result_plan_logical_cid},
    },
  };
  return {result, plan};
}

test('registered Result Plan schema and nested root refs retain pins', () => {
  checkResultPlanSchema(registry);
});

const selections = JSON.parse(readFileSync(
  'portability/corpus/effect-target-selection.json', 'utf8',
));
const publishedStore = JSON.parse(readFileSync(
  'portability/corpus/effect-target-selection-published-store.json', 'utf8',
));
test('independent DELETE and mixed selection identities retain eight fields and original environment', () => {
  const corpus = JSON.parse(readFileSync(
    'portability/corpus/effect-target-selection-delete.json', 'utf8'));
  assert.equal(corpus.version, selections.version);
  const keys = Object.keys(selections.cases[0].preimage[0]);
  for (const item of corpus.cases) {
    verifyIdentity(item.preimage, item.expected_cid, item.expected_canonical_bytes);
    for (const entry of item.preimage) assert.deepEqual(Object.keys(entry), keys);
  }
  assert.deepEqual(corpus.cases.map(item => item.preimage.map(entry => entry.effect_id)),
    [['save'], ['save'], ['remove', 'save', 'update']]);
  for (const item of corpus.environments) {
    verifyIdentity(item.preimage, item.expected_cid, item.expected_canonical_bytes);
    const {mapping_contract_cid, ...mapping} = item.preimage.mapping_contracts[0];
    verifyIdentity(mapping, mapping_contract_cid, canonicalText(mapping));
    assert(item.preimage.mapping_contracts[0].permission_rules.some(rule =>
      rule.effect_kind === 'delete' && rule.write_fields.length === 0));
  }
  assert(!corpus.environments[1].preimage.mapping_contracts[0].permission_rules
    .some(rule => rule.effect_kind === 'update'));
  const source = readFileSync(
    'src/run_publication_host/client_delete_target_selection_wbtest.mbt', 'utf8');
  const wire = JSON.parse(source.match(/^    #\|(.+)$/mu)[1]);
  const {evidence_bundle_cid, ...preimage} = wire;
  assert.equal(evidence_bundle_cid, corpus.environments[0].expected_cid);
  assert.deepEqual(preimage, corpus.environments[0].preimage);
});

test('independent published-STORE and mixed identities preserve the same eight-field schema', () => {
  const corpus = JSON.parse(readFileSync(
    'portability/corpus/effect-target-selection-published-store.json', 'utf8'));
  assert.equal(corpus.version, selections.version);
  for (const item of [...corpus.cases, ...corpus.installation_owners]) {
    verifyIdentity(item.preimage, item.expected_cid, item.expected_canonical_bytes);
  }
  const keys = Object.keys(selections.cases[0].preimage[0]);
  for (const item of corpus.cases) for (const entry of item.preimage) {
    assert.deepEqual(Object.keys(entry), keys);
  }
  assert.deepEqual(corpus.cases.map(item => item.preimage.map(entry => entry.effect_id)),
    [['save'], ['save', 'update']]);
  assert.equal(new Set(corpus.cases.map(item => item.expected_cid)).size, 2);
  // Structural schema instance bytes/pins stay unchanged; original purpose
  // admission, mixed occurrences and saved bindings execute in Common tests.
  checkResultPlanSchema(registry);
});

test('published selection fixture carries the actual explicit bounded policy, not undefined', () => {
  const source = readFileSync(
    'src/run_publication_host/client_published_store_selection_wbtest.mbt', 'utf8');
  const wire = source.match(/^    #\|(.+)$/mu)[1];
  const body = JSON.parse(wire);
  const {evidence_bundle_cid: cid, ...preimage} = body;
  verifyIdentity(preimage, cid, canonicalText(preimage));
  const original = JSON.parse(readFileSync(
    'scripts/fixtures/store-effect-lowering/environment.json', 'utf8'));
  assert.deepEqual(body.host_policy_profile, original.environment.host_policy_profile);
  assert.equal(body.host_policy_profile.capacity.max_artifact_bytes, 1000);
});

test('original UPDATE selection is optional in both closed Plan schemas', () => {
  const keys = ['check_environment_cid', 'effect_id',
    'installation_binding_cid', 'installation_owner_cid', 'mapping_cid',
    'mapping_ref', 'stage_index', 'target_ref'];
  for (const plan of [registry.artifact_schemas.executable_plan,
    registry.artifact_schemas.plan_document.properties.plan]) {
    const material = plan.properties.execution_material;
    assert.equal(material.additionalProperties, false);
    assert.ok(!material.required.includes('effect_target_selections'));
    assert.ok(!Object.hasOwn(material.properties.program.properties,
      'effect_target_selections'));
    const selection = material.properties.effect_target_selections;
    assert.equal(selection.type, 'array');
    assert.equal(selection.minItems, 1);
    assert.equal(selection.uniqueItems, true);
    assert.equal(selection.items.additionalProperties, false);
    assert.deepEqual(selection.items.required, keys);
    assert.deepEqual(Object.keys(selection.items.properties), keys);
    assert.deepEqual(selection.items.properties.stage_index,
      {type: 'integer', minimum: 0});
  }
  const currentPins = {
    executable_plan: 'sha256:661fb7d6ff04024797f7733effa16ee82cbc9cb31533425270677906017cd487',
    plan_document: 'sha256:8faa3038775b916b1446c42b8ef3a2349bed1fb9f4341a96025f668a6d199232',
  };
  const normative = readFileSync('docs/spec/protocols/contracts.md', 'utf8');
  for (const [key, current] of Object.entries(currentPins)) {
    assert(normative.includes(`actql-protocol-schemas.json#/artifact_schemas/${key} ${current}`));
    assert.equal(machineCid(registry.artifact_schemas[key]), current);
    assert.equal(registry.artifact_schema_cids[key], current);
  }
  assert.equal(registry.artifact_registry_cid, machineCid(registry.artifact_schemas));
});

test('independent original UPDATE vectors bind every selection and owner field', () => {
  assert.equal(selections.version, 'actql-effect-target-selection-vectors/0.1');
  for (const group of [selections.cases, selections.installation_owners]) {
    for (const item of group) {
      verifyIdentity(item.preimage, item.expected_cid,
        item.expected_canonical_bytes);
    }
    assert.equal(new Set(group.map(item => item.expected_cid)).size,
      group.length);
  }
  const original = selections.cases.find(item => item.id === 'original');
  assert.equal(original.preimage[0].installation_owner_cid,
    selections.installation_owners[0].expected_cid);
  assert.notEqual(original.preimage[0].installation_binding_cid,
    original.preimage[0].installation_owner_cid);
  assert.doesNotMatch(original.expected_canonical_bytes, /alias|UPDATE/u);
});

test('selection occurrence vectors use Stage then UTF-16 order', () => {
  const ordered = selections.cases.find(item =>
    item.id === 'stage then UTF-16 occurrence order').preimage;
  assert.deepEqual(ordered.map(item => [item.stage_index, item.effect_id]),
    [[0, 'a'], [0, '\u{1f600}'], [0, '\ue000'], [1, 'a']]);
  assert.deepEqual([...ordered].sort((left, right) =>
    left.stage_index - right.stage_index ||
      (left.effect_id < right.effect_id ? -1 :
        left.effect_id > right.effect_id ? 1 : 0)), ordered);
  const repeated = selections.cases.find(item =>
    item.id === 'same Effect id in another Stage').preimage;
  assert.equal(repeated[0].effect_id, repeated[1].effect_id);
  assert.notEqual(repeated[0].stage_index, repeated[1].stage_index);
  // Shape pins alone do not establish occurrence admission or saved recovery.
  assert.equal(canonicalText(repeated), selections.cases.find(item =>
    item.id === 'same Effect id in another Stage').expected_canonical_bytes);
});

test('independent Result Plan vector binds the checked semantic fields', () => {
  const {result} = fixture();
  assert.equal(result.result_plan_logical_cid,
    'sha256:d14737f136fab6a0a6f68ca87d9cae4d8af848ce7a138b8b47f8adc948a0c566');
  assert.notEqual(resultPlanCid({...result, unit_result_ordinal: 1}),
    result.result_plan_logical_cid);
  assert.notEqual(resultPlanCid({...result, typed_output_port: {
    ...result.typed_output_port, row_contract_cid: b,
  }}), result.result_plan_logical_cid);
});

test('Result names, roots and typed output ports bind one to one', () => {
  const {result, plan} = fixture();
  const checkedPort = () => ({carrier: 'relation', row_contract_cid: c});
  checkResultPlanBindings(plan, {answer: result}, checkedPort);
  assert.throws(() => checkResultPlanBindings(plan, {}, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {
    answer: {...result, result_name: 'other'},
  }, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {
    answer: {...result, typed_output_port: {
      ...result.typed_output_port, name: 'foreign',
    }},
  }, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, root_refs: [...plan.root_refs, plan.root_refs[0]],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, nodes: [{node_id: 'result_0', output_contracts: {rows: b}}],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, root_refs: [{...plan.root_refs[0],
      ref: {node_id: 'other', port: 'rows'}}],
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings({
    ...plan, execution_material: {result_plan_logical_cids: {answer: a}},
  }, {answer: result}, checkedPort));
  assert.throws(() => checkResultPlanBindings(plan, {answer: result},
    () => ({carrier: 'graph', row_contract_cid: c})));
  assert.throws(() => checkResultPlanBindings(plan, {answer: result},
    () => ({carrier: 'relation', row_contract_cid: b})));
});
