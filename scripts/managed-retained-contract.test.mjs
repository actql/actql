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

test('managed profile pins quantities without weakening old evidence wire', () => {
  assert.equal(contract.profile, 'actql-managed-retained-execution/0.1');
  const dependency = contract.dependencies.fixed_compute_capacity;
  assert.equal(dependency.pointer, '');
  assert.equal(machineCid(read(dependency.path)), dependency.cid);
  for (const [name, expected] of [
    ['actql-query-acquisition', 'sha256:4bb69dfaade0a15952fe23a8202a9475ff450c9f0fab93f9dd5cef1b82045ab1'],
    ['actql-query-process-evidence', 'sha256:5cbd39d6847336c5961e222b083ca1395ab68be466ac69cadfbf7021cf617b89'],
    ['actql-query-two-receipt', 'sha256:7d9eec132b742aca27b78a801c6bea187a251b7423967950e285755c50e853d8'],
  ]) assert.equal(machineCid(read(`spec/contracts/${name}.json`)), expected, name);
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
