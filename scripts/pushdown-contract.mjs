import {readFileSync} from 'node:fs';
import {machineCid} from './actql-spec-family.mjs';

export const pushdownOperations = ['projection','filter','order_by','limit','assert_unique_by'];
export function pushdownBodyContract() {
  const pin = (path, pointer = '') => {
    const body = JSON.parse(readFileSync(path, 'utf8'));
    return {path, pointer, cid: machineCid(body)};
  };
  return {
    schema: {oneOf: [
      {type:'object',maxProperties:0},
      {type:'object',additionalProperties:false,required:['version','carrier','operations'],properties:{
        version:{const:'actql-source-view-pushdown/0.1'},
        carrier:{enum:['relation','graph','events','vectors']},
        operations:{type:'array',uniqueItems:true,items:{enum:pushdownOperations}},
      },allOf:[{if:{properties:{carrier:{enum:['graph','events','vectors']}}},then:{properties:{operations:{maxItems:0}}}}]},
    ]},
    semantics: {
      empty_body:'no_pushdown_operations_on_any_carrier',
      sourceview_agreement:'carrier_equal_when_present_and_same_operation_set_without_rewriting_either_array',
      interpretation:'advertised_capability_only_not_equivalence_proof_backend_support_or_execution_authority',
      preservation:'values_types_nulls_row_multiplicity_required_order_eager_failure_behavior_and_bounds',
      residual:'evaluate_unpushed_predicate_with_identical_canonical_semantics_or_reject',
      unsupported:'other_body_versions_and_operation_vocabularies_require_their_own_registered_interpretation',
      dependencies:'governing_contract_always_relation_laws_for_nonempty_operations_expression_contract_for_filter_no_body_ContractRef_positions',
    },
    semantic_dependencies: {
      relation_laws:pin('spec/dependencies/aoa-rela-primitive-laws.json'),
      expression_contract:pin('spec/contracts/actql-expressions.json'),
    },
  };
}
