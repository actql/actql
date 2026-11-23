// Synthetic originals with independently fixed canonical preimages. These test
// structural identity only. No runtime was asked to issue a Sample.
import {cid, ref} from './interactive-run-control-vectors.mjs';

export const relationPrefix = {version: 'actql-sample-relation/0.1',
  kind: 'relation', schema_cid: cid('9'),
  columns: [{position: 0, name: 'score', value_contract_cid: cid('8'), required: true}],
  rows: [[{presence: 'present', value_contract_cid: cid('8'), value: 17}]],
  ordering_evidence_cid: null};

const prefixCid = 'sha256:d99a3579f96c2e4e42e9893971082746920e75437a2cd69e978dffe7677d2508';
const generationCid = 'sha256:e88380374921cbcaf946fdffef85bf082821812664aaf6b5aa81a35dbf401b3f';
const captureCid = 'sha256:34b2a40b0785c69e84e99af845685ba58aa95dde1a42bdee6c9fb9ec1b3eb217';
const emissionCid = 'sha256:ccef7cc55d8a62f1d15808e90563d318c3876da5ae10665c14e60cc8cb6673a6';
const referenceCid = 'sha256:acdfb48c3b78d17888ead1f6acb3bddd7907c7ea792f5118c537aa015db0f561';
const receiptCid = 'sha256:7f047ca4fb9feb49647c6b6e5a8ed2e16805bbb16c410563be8a453b1b966856';

const generation = {version: 'actql-sample-source-generation/0.1', run_ref: ref,
  compiled_plan_cid: cid('1'), logical_map_cid: cid('2'), step_id: cid('3'),
  output_port_id: cid('4'), carrier: 'relation', carrier_contract_cid: cid('5'),
  producer_occurrence: {kind: 'first_physical_start', start_revision: '2', attempt_sequence: '7'},
  committed_generation: '13'};
const capture = {version: 'actql-sample-original-capture/0.1', source_generation_cid: generationCid,
  control_admission_cid: cid('6'), resolved_profile_cid: cid('7'),
  strategy: 'execution_prefix', max_items: 50, max_bytes: '65536',
  max_artifacts: 20, ttl_seconds: 300, required: false};
const emission = {version: 'actql-sample-emission-provenance/0.1', original_capture_cid: captureCid,
  source_generation_cid: generationCid, relation_prefix_cid: prefixCid, ordering_evidence_cid: null,
  sampled_items: '1', total: {kind: 'unknown', unit: 'rows', reason: 'count_not_observed'},
  completeness: 'unknown', truncation: 'unknown'};
const reference = {version: 'actql-sample-reference/0.1', run_ref: ref, output_port_id: cid('4'),
  original_capture_cid: captureCid, emission_provenance_cid: emissionCid};
const receipt = {version: 'actql-sample-adoption-receipt/0.1', run_ref: ref,
  sample_ref_cid: referenceCid, adoption: 'retained_relation_prefix', expires_at_epoch_ms: '1795389900000'};

export const sampleIdentityVectors = [
  ['sample_source_generation', generation, generationCid],
  ['sample_original_capture', capture, captureCid],
  ['sample_emission_provenance', emission, emissionCid],
  ['sample_reference', reference, referenceCid],
  ['sample_adoption_receipt', receipt, receiptCid],
].map(([name, body, cid]) => ({name, body, cid}));

export const sampleInvalidIdentityBodies = [
  ['sample_source_generation', {...generation, carrier: 'graph'}],
  ['sample_source_generation', {...generation, producer_occurrence: {
    ...generation.producer_occurrence, attempt_sequence: '0'}}],
  ['sample_source_generation', {...generation, producer_occurrence: {
    ...generation.producer_occurrence, task_ordinal: 7}}],
  ['sample_source_generation', {...generation, committed_generation: '9223372036854775808'}],
  ['sample_original_capture', {...capture, max_bytes: '01'}],
  ['sample_adoption_receipt', {...receipt, expires_at_epoch_ms: '0'}],
];

// An earlier claim cannot authenticate a different producer occurrence.
// These reuse the original CIDs, so the identity check must refuse.
export const sampleSubstitutedCompleteValues = [
  ['sample_source_generation', generationCid, {...generation, producer_occurrence: {
    ...generation.producer_occurrence, attempt_sequence: '6'}}],
  ['sample_source_generation', generationCid, {...generation, run_ref: {
    ...ref, authorityScopeCid: cid('0')}}],
  ['sample_emission_provenance', emissionCid, {...emission, source_generation_cid: cid('0')}],
  ['sample_adoption_receipt', receiptCid, {...receipt, sample_ref_cid: cid('0')}],
];
