import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {gunzipSync} from 'node:zlib';
import test from 'node:test';

// Independent contract oracle; no Value parser, Host Date or product encoder.
const canonical=value=>Array.isArray(value)?'['+value.map(canonical).join(',')+']'
  :value!==null&&typeof value==='object'?'{'+Object.keys(value).sort()
    .map(key=>JSON.stringify(key)+':'+canonical(value[key])).join(',')+'}'
    :JSON.stringify(value);
const cid=value=>'sha256:'+createHash('sha256').update(canonical(value)).digest('hex');
const read=path=>JSON.parse(readFileSync(path,'utf8'));
const history=read('portability/corpus/historical/pre-exact-utc-timestamp.json');
const original=Object.fromEntries(history.contracts.map(c=>[c.id,c.body]));

test('exact UTC retains complete millisecond contracts and all original Value vectors',()=>{
  assert.equal(cid(history),'sha256:8a1ff56f7d04b54ad2446e8f2805b650a67a48630e4778d8deffe3b157530520');
  assert.equal(history.source_revision,'3356d295822d886a26ab49b286c8fabf270bc021');
  for(const item of history.contracts)assert.equal(cid(item.body),item.canonical_cid);
  const values=read('portability/corpus/value-admission.json');
  const old=original.value_admission_corpus;
  assert.equal(old.cases.length,53);
  assert.deepEqual(values.cases.slice(0,53),old.cases);
  assert.deepEqual({...values,cases:old.cases},old);
});

test('the scalar law changes only the adopted exact temporal boundary',()=>{
  const before=original.scalar_law_manifest;
  const expected={...before,time:{...before.time,
    timestamp:'canonical-exact-utc-iso8601-three-to-nine-fractional-digits-Z',
    arithmetic:'exact-instants-with-declared-fixed-utc-ms-s-m-h-d-units',
    canonical_fraction:{minimum_digits:3,maximum_digits:9,
      millisecond_aligned:'exactly_three_digits',
      finer:'remove_only_trailing_zeros_beyond_three_digits',
      unrelated_authored_spellings:'unchanged_refusal'},
    comparison_and_key:'exact_instant_order_not_variable_fraction_UTF16_order_canonical_equality_and_key_correspondence',
    legacy_value_identity:'all_previously_canonical_millisecond_Value_bytes_and_CIDs_unchanged_internal_sort_representation_is_separate',
    event_clock:'same_original_Timestamp_to_exact_rational_UTC_epoch_milliseconds_not_public_Number_or_truncating_date_diff_preserve_payload_and_numeric_clock_domain',
    millisecond_only_projection:'refuse_nonrepresentable_fraction_without_rounding_or_truncation',
    operational_clocks:'trusted_now_expiry_deadline_rollback_provenance_keep_original_millisecond_contracts_and_issuers',
    conformance_boundary:'legacy_millisecond_conformance_does_not_prove_extended_fractional_consumers',
  },conversion_truth_table:{...before.conversion_truth_table,to_timestamp:{
    ...before.conversion_truth_table.to_timestamp,
    input:'canonical-YYYY-MM-DDTHH:mm:ss-with-three-to-nine-fractional-digits-Z-no-redundant-extra-trailing-zeros',
  }}};
  const current=read('scripts/fixtures/date-add-source/predecessor.json').scalar;
  assert.deepEqual(current,expected);
  assert.equal(cid(current),'sha256:65e19916636e8d7dcf3bc7a1f8640762ef2dee048105c7b869878bd0fdf4d8fe');
  assert.equal(current.time.timestamp_date_diff,'fixed-unit-quotient-truncate-toward-zero');
  assert.equal(current.version,before.version);
  assert.equal(current.law_id,before.law_id);
});

test('the containing AoA body adopts the complete new scalar law and no other change',()=>{
  // The complete UTC-adoption body precedes the separately adopted comparison
  // extension and the later exact-duration rule. Both complete bodies remain frozen.
  const comparisonHistory=JSON.parse(gunzipSync(readFileSync('scripts/fixtures/pre-int64-comparison-literal-identities.json.gz')));
  const current=comparisonHistory.records['spec/contracts/actql-aoa.json'];
  assert.equal(read('scripts/fixtures/date-add-source/predecessor.json').aoa.rela_scalar_law_manifest_cid,current.rela_scalar_law_manifest_cid);
  const scalar=read('scripts/fixtures/date-add-source/predecessor.json').scalar;
  assert.deepEqual(current,{...original.aoa_contract,rela_scalar_law_manifest_cid:cid(scalar)});
  assert.notEqual(cid(current),cid(original.aoa_contract));
  assert.notEqual(cid(scalar),cid(original.scalar_law_manifest));
});
