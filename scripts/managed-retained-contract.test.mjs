import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {machineCid} from './actql-spec-family.mjs';
import './managed-runtime-vectors.mjs';

const read = path => JSON.parse(readFileSync(path, 'utf8'));
const contract = read('spec/contracts/actql-managed-retained-execution.json');
const corpus = read('portability/corpus/managed-retained-identity-status.json');

// Independent interpreter for precisely this schema vocabulary. Reject schema
// extensions until the test interpreter covers them; this is not a runtime
// capability verifier and does not establish authenticity of a digest string.
function matches(schema, value) {
  const supported = new Set(['$schema', 'description', 'oneOf', 'type', 'additionalProperties', 'required', 'properties', 'enum', 'const', 'minLength', 'pattern', 'minimum', 'maximum', 'items']);
  for (const key of Object.keys(schema)) assert.ok(supported.has(key), `unhandled schema keyword ${key}`);
  if (schema.oneOf) return schema.oneOf.filter(s => matches(s, value)).length === 1;
  if (Object.hasOwn(schema, 'const') && value !== schema.const) return false;
  if (schema.enum && !schema.enum.includes(value)) return false;
  if (schema.type === 'string') {
    if (typeof value !== 'string') return false;
    if ([...value].length < (schema.minLength ?? 0)) return false;
    if (schema.pattern && !new RegExp(schema.pattern).test(value)) return false;
  } else if (schema.type === 'integer') {
    if (!Number.isSafeInteger(value) || value < schema.minimum || value > schema.maximum) return false;
  } else if (schema.type === 'array') {
    if (!Array.isArray(value) || !value.every(item => matches(schema.items, item))) return false;
  } else if (schema.type === 'object') {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) return false;
    if (schema.required.some(key => !Object.hasOwn(value, key))) return false;
    for (const [key, item] of Object.entries(value)) {
      if (!Object.hasOwn(schema.properties, key)) {
        if (schema.additionalProperties === false) return false;
      } else if (!matches(schema.properties[key], item)) return false;
    }
  } else assert.equal(schema.type, undefined);
  return true;
}

test('managed identity diagnostics distinguish establishment and source availability', () => {
  assert.equal(corpus.cases.length, 12);
  for (const fixture of corpus.cases) {
    assert.equal(matches(contract.schemas.identity_status, fixture.value), fixture.accepted, fixture.id);
  }
  for (const domain of ['logical_row', 'ordered_rows', 'logical_relation']) {
    for (const source of ['retained', 'unavailable']) {
      assert.equal(matches(contract.schemas.identity_status, {domain, subject: 'fixture', state: 'unestablished', source}), true);
    }
  }
});

test('managed profile pins quantities, current evidence wire and query-time owners', () => {
  assert.equal(contract.profile, 'actql-managed-retained-execution/0.1');
  const dependency = contract.dependencies.fixed_compute_capacity;
  assert.equal(dependency.pointer, '');
  assert.equal(machineCid(read(dependency.path)), dependency.cid);
  // Fixed current contract identities bind every wire field, independently of
  // runtime output. Dependency and owner checks explain the current law without
  // requiring any former commit or reconstructing a historical schema.
  for (const [name, expected, dependencyNames] of [
    ['actql-query-acquisition', 'sha256:5a95e60847276d02229eba9550dd9808a8a8c2764decd4dad667954f020db7cc', ['canonical_value_contract', 'consumer_capacity']],
    ['actql-query-process-evidence', 'sha256:2e9959187141ac09be2f4684ac2d0dc7a2819059c6764b1a527b48e0cee6a08d', ['query_acquisition']],
    ['actql-query-two-receipt', 'sha256:dcf4b1e2c8a078d96f9160a75a9f8279047e7448ea39b3b882588e18b9ab0929', ['query_acquisition', 'process_evidence']],
  ]) {
    const current = read(`spec/contracts/${name}.json`);
    assert.equal(current.version, `${name}-contract/0.1`);
    assert.equal(machineCid(current), expected, name);
    assert.deepEqual(Object.keys(current.dependencies), dependencyNames);
    for (const [key, dependency] of Object.entries(current.dependencies)) {
      const actual = dependency.pointer.split('/').slice(1).reduce((value, part) =>
        value?.[part.replace(/~1/g, '/').replace(/~0/g, '~')], read(dependency.path));
      assert.notEqual(actual, undefined, `${name}: current dependency ${key}`);
      assert.equal(machineCid(actual), dependency.cid, `${name}: current dependency ${key}`);
    }
    const ownerSchemas = name === 'actql-query-acquisition'
      ? ['requirement', 'completed_observation']
      : name === 'actql-query-two-receipt' ? ['completed_observation'] : [];
    for (const key of ownerSchemas) {
      const owner = current.schemas[key].properties.owner;
      assert.deepEqual(owner, {
        type: 'object', additionalProperties: false,
        required: ['program_source_cid', 'stage', 'input'],
        properties: {
          program_source_cid: {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'},
          stage: {type: 'string', minLength: 1}, input: {type: 'string', minLength: 1},
          run_definition_cid: {type: 'string', pattern: '^sha256:[0-9a-f]{64}$'},
        },
      });
      const original = {program_source_cid: 'sha256:' + 'a'.repeat(64), stage: 'stage', input: 'input'};
      assert.equal(matches(owner, original), true);
      assert.equal(matches(owner, {...original, run_definition_cid: 'sha256:' + 'b'.repeat(64)}), true);
      assert.equal(matches(owner, {...original, run_definition_cid: 'unverified'}), false);
      assert.equal(matches(owner, {...original, run_definition_cid: null}), false);
      assert.equal(matches(owner, {...original, foreign_owner: true}), false);
    }
    if (name === 'actql-query-acquisition') {
      assert.equal(current.semantics.query_time_owner,
        'declared_query_time_dependency_requires_original_admitted_run_definition_cid_in_requirement_and_completed_observation_owner_with_same_nominal_context_and_saved_run_no_resample_no_grant');
    }
  }
});

test('managed contract retains agreed coverage rather than a process-local projection-only subset', () => {
  assert.deepEqual(contract.scope.included, ['one_managed_run', 'accepted_local_execution_process_delegation']);
  assert.equal(contract.scope.size_condition, 'none');
  assert.deepEqual(contract.evidence.view_rules, ['exact_view', 'projection', 'rename', 'exact_column_copy', 'checked_row_selection', 'checked_row_permutation', 'derive_unchanged_columns']);
  assert.deepEqual(contract.evidence.outcomes, ['satisfied', 'violation_with_required_diagnostic', 'insufficient']);
  assert.equal(contract.completion.portable_wire, 'none_opaque_handles_and_authenticated_delegation_not_json_authority');
  assert.deepEqual(contract.conformance.paths, ['projection_filter_derive_sort_take_multiple_consumers', 'validated_join_or_group_output_repeated_use', 'managed_delegate_hold_use_cancel_reclaim']);
});

test('physical manifest preserves ordered chunk occurrences and has no logical CID field', () => {
  const pin = 'sha256:' + 'a'.repeat(64);
  const manifest = {
    version: 'actql-managed-physical-manifest/0.1',
    schema_contract_cid: pin, view_contract_cid: pin, codec_contract_cid: pin,
    row_count: 0, chunks: [],
  };
  const schema = contract.schemas.physical_manifest;
  assert.equal(matches(schema, manifest), true);
  const a = {cid: 'sha256:' + 'b'.repeat(64), byte_length: 2, row_count: 1};
  const b = {cid: 'sha256:' + 'c'.repeat(64), byte_length: 3, row_count: 1};
  const populated = {...manifest, row_count: 3, chunks: [a, b, a]};
  assert.equal(matches(schema, populated), true);
  assert.notEqual(machineCid(populated), machineCid({...populated, chunks: [b, a, a]}));
  for (const bad of [
    {...manifest, logical_result_cid: pin},
    {...manifest, row_count: -1},
    {...manifest, chunks: [{...a, byte_length: 0.5}]},
    {...manifest, chunks: [{...a, byte_length: Number.MAX_SAFE_INTEGER + 1}]},
    {...manifest, codec_contract_cid: 'duckdb'},
    {...manifest, chunks: [{...a, path: '/untrusted/path'}]},
  ]) assert.equal(matches(schema, bad), false);
  // Deliberately shape-valid but semantically invalid: the receiver still
  // needs count, codec, integrity and conversion checks. Schema != admission.
  assert.equal(matches(schema, {...manifest, row_count: 10}), true);
  assert.equal(contract.physical_manifest.counts, 'checked_sum_chunk_row_counts_equals_manifest_row_count_verify_each_chunk_byte_length_and_row_count');
});
