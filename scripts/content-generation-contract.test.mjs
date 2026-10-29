import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {gunzipSync} from 'node:zlib';
import {checkContentGenerationSchema, contentGenerationSchema,
  contentInputArtifactSchema} from './content-generation-contract.mjs';

test('Content migration changes the ordered derive pin only through its exact contract dependencies', () => {
  // Independently fixed current and historical vectors. This test imports no
  // product canonicalizer and never derives expectations from emitted Plans.
  // Retain the Content migration's exact reviewed successor; later schema
  // extensions cannot be undone by replacing only the Content descriptor.
  const body = JSON.parse(gunzipSync(readFileSync(
    'scripts/fixtures/native-local-scalar-reviewed-current.json.gz'))).bodies.ordered;
  const canonical = value => value === null || typeof value !== 'object' ? JSON.stringify(value)
    : Array.isArray(value) ? `[${value.map(canonical).join(',')}]`
      : `{${Object.keys(value).sort().map(key => `${JSON.stringify(key)}:${canonical(value[key])}`).join(',')}}`;
  const hash = value => createHash('sha256').update(canonical(value)).digest('hex');
  assert.equal(hash(body), "85595efff53323afd08f33d88559d3b988525613bd08c43125c85e6e74762a5e");
  const before = structuredClone(body);
  const originalDependencies = {
    expression_contract: 'bdfd03bfd57f9b3d65e0c53bc122fd86235809dc16be7cd7ec08616c18d7242d',
    expression_node: '1ad188ca11e5490876722ad99152d28922c48f1c1e8177f1a8a305b225e4eaf7',
    source_expression: 'cd1f3718042b6da202b5c0f4fe507efb9050f907cc1a1b0c1bc773cd6a04e1eb',
    value_contract: '02859499357530af0ae58e4f2958d1c8fa48f957b86b0a2976dad43bed99b551',
  };
  for (const [key, digest] of Object.entries(originalDependencies)) {
    before.dependencies[key].cid = `sha256:${digest}`;
  }
  for (const key of ['context', 'shape']) {
    const tag = before.schemas[key].$defs.value_contract.oneOf[7].properties.type;
    assert.equal(tag.const, 'content_ref');
    tag.const = 'artifact_ref';
  }
  assert.equal(hash(before), 'cd7053dd97ed3f80fd5435f2fb20e91a06c99469120f0a2db637c5a1508d4d83');
});

test('Content occurrence binding references the one existing derivation contract', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  checkContentGenerationSchema(registry);
  const profiles = JSON.parse(readFileSync('spec/contracts/actql-production-profile-schemas.json', 'utf8'));
  const evidence = profiles.schemas.content_evidence;
  assert.equal(evidence.properties.version.const, 'actql-content-derivation-evidence/0.1');
  for (const field of ['barrier_input_artifact_cid', 'content_cid', 'content_ref_cid',
    'content_issuer_evidence_cid', 'byte_count', 'row_count', 'media_type', 'name']) {
    assert.ok(evidence.required.includes(field));
    assert.ok(!Object.hasOwn(contentGenerationSchema.properties, field));
  }
  for (const field of ['content_evidence_cid', 'bound_invocation_template_cid',
    'run_definition_cid', 'node_id', 'barrier_cid', 'availability_evidence_cid',
    'content_store_cid', 'workspace_scope_cid']) {
    assert.ok(contentGenerationSchema.required.includes(field));
  }
});

test('Content input Artifact binds actual rows/schema separately from computation identity', () => {
  assert.equal(contentInputArtifactSchema.additionalProperties, false);
  assert.deepEqual(Object.keys(contentInputArtifactSchema.properties),
    contentInputArtifactSchema.required);
  for (const field of ['input_fragment_cid', 'logical_relation_cid',
    'relation_schema_cid', 'ordered_rows_cid']) {
    assert.deepEqual(contentInputArtifactSchema.properties[field],
      {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'});
  }
  assert.equal(contentInputArtifactSchema.properties.row_count.minimum, 0);
  assert.equal(contentInputArtifactSchema.properties.task_ordinal.minimum, 0);
  assert.equal(contentInputArtifactSchema.properties.step_ordinal.minimum, 0);
  assert.ok(!Object.hasOwn(contentInputArtifactSchema.properties, 'bytes'));
});

test('Content Observation remains opt-in for existing pure and Model records', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  function visit(value) {
    if (value === null || typeof value !== 'object') return 0;
    let count = 0;
    if (value.properties?.version?.const === 'actql-observation-set/0.1') {
      count++;
      assert.ok(!value.required.includes('content_generation_cids'));
      assert.equal(value.properties.content_generation_cids.uniqueItems, true);
    }
    for (const child of Object.values(value)) count += visit(child);
    return count;
  }
  assert.ok(visit(registry.artifact_schemas) >= 3);
});

test('Content capture reuses closed normative proofs without granting Ref authority', () => {
  const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
  const profiles = JSON.parse(readFileSync('spec/contracts/actql-production-profile-schemas.json', 'utf8'));
  const schema = registry.artifact_schemas.captured_run.properties.effect_context;
  assert.ok(!schema.required.includes('content_generations'));
  const records = schema.properties.content_generations;
  assert.equal(records.minItems, 1);
  assert.equal(records.items.additionalProperties, false);
  const proof = records.items.properties;
  assert.deepEqual(proof.content_generation, contentGenerationSchema);
  assert.deepEqual(proof.content_input_artifact, contentInputArtifactSchema);
  assert.deepEqual(proof.content_evidence, profiles.schemas.content_evidence);
  assert.deepEqual(proof.content_reference, registry.schemas.content_ref);
  assert.deepEqual(proof.invocation_template, registry.artifact_schemas.bound_invocation_template);
  assert.deepEqual(registry.artifact_schemas.run_receipt.properties
    .external_observation_evidence.items.properties.kind.enum,
  ['model_invocation', 'source_lookup', 'content_generation']);
});
