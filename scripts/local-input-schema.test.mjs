import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {parameterPrograms} from './parameter-schema.mjs';
import {checkLocalInputSchemas} from './local-input-schema.mjs';
import {machineCid} from './actql-spec-family.mjs';
import {scoreContractSchema, vectorSchemas} from './vector-schema.mjs';
import {verifyIdentity} from './check-canonical-json.mjs';

test('Local input score assertions and fusion use the same closed contract', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json','utf8'));
  assert.deepEqual(snapshot.schema.properties.score_contracts.additionalProperties, scoreContractSchema());
  for (const policy of vectorSchemas().merge_rankings.oneOf.slice(0,2)) {
    assert.deepEqual(policy.properties.score_contract, scoreContractSchema());
  }
});

test('Relation presence metadata is finite and independent of value nullability', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json', 'utf8'));
  assert.deepEqual(snapshot.schema.properties.column_presence, {
    type: 'object', minProperties: 1,
    propertyNames: {pattern: snapshot.schema.properties.score_contracts.propertyNames.pattern},
    additionalProperties: {const: 'conditional'},
  });
  assert.ok(!snapshot.schema.required.includes('column_presence'));
  assert.match(snapshot.semantics.presence, /omission_is_not_null/);
  assert.match(snapshot.semantics.presence, /reject_unknown_columns_and_empty_maps/);
  assert.match(snapshot.semantics.score_projection, /column_presence/);
});

test('Local interpretation roots match pinned snapshot dependencies', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json','utf8'));
  const reference = JSON.parse(readFileSync('spec/contracts/actql-local-source-reference.json','utf8'));
  const source = readFileSync('src/pipeline_check_context/core_contracts.mbt','utf8').replace(/\s+/g,' ');
  assert.deepEqual(snapshot.dependencies, {
    checked_type: {path:'spec/contracts/actql-protocol-schemas.json',pointer:'/schemas/canonical_value_contract',cid:machineCid(registry.schemas.canonical_value_contract)},
    source_reference: {path:'spec/contracts/actql-local-source-reference.json',pointer:'',cid:machineCid(reference)},
  });
  assert.ok(source.includes(`LocalSnapshotRules => "${machineCid(snapshot)}"`));
  assert.ok(source.includes(`LocalSourceReferenceRules => "${machineCid(reference)}"`));
  assert.equal(reference.dependencies,undefined);
});

const registry = JSON.parse(readFileSync('spec/contracts/actql-protocol-schemas.json', 'utf8'));
test('current Local snapshot interpretation binds ContentRef without accepting former contract identities', () => {
  const snapshot = JSON.parse(readFileSync('spec/contracts/actql-local-relation-snapshot.json', 'utf8'));
  // Independently hashed normative bodies; these are not runtime outputs.
  verifyIdentity(snapshot, 'sha256:621725e41f803d118b749abf99a40f4c23e2bd3fb15078912c69ff7f82c6f85a');
  assert.equal(snapshot.dependencies.checked_type.cid,
    'sha256:71919bebf9a27c30c2c3ac29093aa90f983307e0d9272f9baeea891295c9cbc1');
  assert.equal(machineCid(registry.schemas.canonical_value_contract),
    snapshot.dependencies.checked_type.cid);
  assert.deepEqual(snapshot.schema.$defs,
    registry.schemas.canonical_value_contract.$defs);
  const family = JSON.parse(readFileSync('spec/spec-family.json', 'utf8'));
  const owner = family.documents.find(item =>
    item.path === 'docs/spec/protocols/contracts.md');
  const references = owner.machine_contracts.filter(ref =>
    ref.path === 'spec/contracts/actql-local-relation-snapshot.json' &&
    ref.pointer === '');
  assert.equal(references.length, 1);
  assert.equal(references[0].cid, machineCid(snapshot));
  assert.equal(references[0].version, snapshot.version);
  assert(readFileSync(owner.path, 'utf8').includes(
    `actql-local-relation-snapshot.json# ${references[0].cid}`));
  const contentRef = schema => schema.$defs.value_contract.oneOf.find(
    branch => branch.properties?.type?.const === 'content_ref');
  assert.ok(contentRef(snapshot.schema));
  assert.deepEqual(contentRef(snapshot.schema),
    contentRef(registry.schemas.canonical_value_contract));
  for (const former of [
    'sha256:b6757d1d2978133784f3b3cd464fa966e432dc0caa99b6cb05d618249ef1076c',
    'sha256:9cac11de7a617035c56e06a5a6cb28dbbefd0b6ba6ca613a5c700b90d6968200',
    'sha256:0d1b824004f4e26bf3cadbfc437d000cd1d7cc6c218c0f0fc4276b483ba46701',
  ]) assert.throws(() => verifyIdentity(snapshot, former));
});

test('both embedded Program input contracts exclude schema_ref', () => {
  checkLocalInputSchemas(registry);
  assert.equal(parameterPrograms(registry).length, 2);
});
test('each embedded input remains closed and cannot restore schema_ref', () => {
  for (let i = 0; i < 2; i++) {
    for (const mutate of [
      s => { s.properties.schema_ref = {type: 'string'}; },
      s => { s.additionalProperties = true; },
      s => { delete s.properties.schema; },
    ]) {
      const copy = structuredClone(registry);
      mutate(parameterPrograms(copy)[i].properties.inputs.additionalProperties.oneOf.find(s => s.properties?.carrier));
      assert.throws(() => checkLocalInputSchemas(copy));
    }
  }
});
