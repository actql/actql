import assert from 'node:assert/strict';
import {readFileSync, writeFileSync} from 'node:fs';
import {machineCid as cid} from './actql-spec-family.mjs';

const base = {
  version: 'actql-numeric-reduction/0.1',
  operations: ['sum', 'avg'],
  input: 'admitted_finite_binary64_contributors_in_bound_sequence_order',
  demand: 'aggregate_filter_before_argument_then_exclude_null_then_distinct_if_authored',
  distinct: 'numeric_equality_retain_first_occurrence_in_contributor_sequence',
  count: 'post_filter_nonnull_post_distinct_safe_integer_count',
  empty: 'null_for_sum_and_avg',
  rounding: 'binary64_nearest_ties_even_after_each_addition_and_final_division',
  average: 'rounded_sum_divided_by_exact_binary64_count_once',
  nonfinite: 'reject_any_nonfinite_intermediate_or_final_value',
  zero: 'preserve_internal_ieee_zero_sign_normalize_final_negative_zero_to_positive_zero',
  error_law: 'exact_prescribed_binary64_operation_sequence_no_epsilon_or_reassociation',
};
const contracts = {
  left_fold: {...base, reduction: 'start_positive_zero_add_each_contributor_left_to_right'},
  adjacent_pairs: {...base, reduction: 'pair_adjacent_contributors_left_to_right_round_each_sum_carry_odd_tail_repeat_until_one_singleton_unchanged'},
};
export const profile = {
  version: 'actql-numeric-reduction-profile/0.1',
  contracts,
  contract_cids: Object.fromEntries(Object.entries(contracts).map(([name, body]) => [name, cid(body)])),
  observation_schema: {
    path: 'spec/contracts/actql-stage-contracts.json', pointer: '/schemas/numeric_observation',
    cid: cid(JSON.parse(readFileSync('spec/contracts/actql-stage-contracts.json', 'utf8')).schemas.numeric_observation),
  },
  selection: {
    static: 'slot_admits_pinned_profile_not_future_result_or_physical_parallelism',
    attempt: 'select_one_member_before_reduction_bind_contract_and_contributor_sequence_to_attempt_policy_and_accounting',
    failure: 'no_silent_algorithm_fallback_or_partial_observation',
    capture: 'durably_capture_admitted_result_before_consumers_replay_exact_observation_without_reduction',
    ownership: 'same_slot_input_artifact_contributors_group_or_window_count_demand_type_and_attempt',
    authorization: 'profile_membership_is_not_host_permission_or_backend_support',
  },
};
const path = 'spec/contracts/actql-numeric-reduction.json';
if (process.argv.includes('--write')) writeFileSync(path, JSON.stringify(profile, null, 2) + '\n');
assert.deepEqual(JSON.parse(readFileSync(path, 'utf8')), profile);
if (process.argv.includes('--print-pins')) console.log(JSON.stringify({profile: cid(profile), ...profile.contract_cids}, null, 2));
