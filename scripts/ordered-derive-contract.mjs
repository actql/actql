import {readFileSync, writeFileSync} from 'node:fs';
import {pathToFileURL} from 'node:url';
import {machineCid} from './actql-spec-family.mjs';
import assert from 'node:assert/strict';

const cid = {type:'string', pattern:'^sha256:[a-f0-9]{64}$'};
const index = {type:'integer', minimum:0, maximum:9007199254740991};
const name = {type:'string', minLength:1};
const closed = properties => ({type:'object', additionalProperties:false,
  required:Object.keys(properties), properties});
const array = items => ({type:'array', items});
export const executionKey = 'REL.derive.ordered';
export const executionPointer = '/execution_contracts/REL.derive.ordered';
export const sourceParams = () => ({
  $id:'urn:actql:ordered-derive-source-params:0.1',
  ...closed({bindings:{...array(closed({name,expr:{$ref:'urn:actql:expression:0.1'}})),minItems:1}}),
});
const deriveStepConstraint = params => ({
  if:{properties:{op:{const:'REL.derive'}},required:['op']},
  then:{properties:{params}},
});

export function rowKernelSchemas(protocol) {
  const valueContract = protocol.schemas.canonical_value_contract;
  const contract = {$ref:'#/$defs/value_contract'};
  const shape = {
    $id:'urn:actql:derive-row-shape:0.1',
    ...closed({version:{const:'actql-derive-row-shape/0.1'},
      fields:{type:'object',additionalProperties:contract},
      required_fields:array(name), additional_fields:{type:'boolean'}, self_cid:cid}),
    $defs:structuredClone(valueContract.$defs),
  };
  const context = {
    $id:'urn:actql:derive-row-context:0.1',
    ...closed({version:{const:'actql-derive-row-context/0.1'},
      input_contract_cid:cid,
      prior_slots:array(closed({name, contract})), self_cid:cid}),
    $defs:structuredClone(valueContract.$defs),
  };
  const limits = {
    $id:'urn:actql:derive-row-limits:0.1',
    ...closed({version:{const:'actql-derive-row-limits/0.1'},
      max_input_rows:index, max_value_bytes:index, max_live_value_bytes:index,
      max_work:index, self_cid:cid}),
  };
  const params = {
    $schema:'https://json-schema.org/draft/2020-12/schema',
    $id:'urn:actql:ordered-derive-params:0.1',
    ...closed({row_kernel_contract_cid:cid,
      bindings:{...array(closed({name, expr:{$ref:'urn:actql:expression-node:0.1'}})),minItems:1},
      references:array(closed({at:{type:'string', pattern:'^/bindings/(0|[1-9][0-9]*)/expr(?:/.*)?$'},
        target:{oneOf:[closed({input_field:name}),closed({prior_slot:index})]}}))}),
  };
  const node_preimage = {
    $id:'urn:actql:ordered-derive-node-preimage:0.1',
    ...closed({id:name,in:{...array(name),minItems:1,maxItems:1},op:{const:'REL.derive'},
      params:{$ref:params.$id}}),
  };
  return {params, source_params:sourceParams(), node_preimage, context, limits, shape};
}

export const orderedBindingLaw = 'Ordered REL.derive uses the registered row-kernel parameter alternative, with roots at /bindings/i/expr. Bindings remain in authored order; root-list serialization still uses graph-step order then pointer UTF-16 order and does not determine evaluation order. Every field node has exactly one occurrence reference to an input field or earlier slot; literal payloads are opaque. row_kernel_evidence is required exactly when ordered nodes occur, containing their derive bindings and exactly the referenced row contexts and row limits, each once in self-CID order. Regeneration checks complete evidence, same-node/input/type ownership, exact prior-slot prefixes, limits and all self-CIDs. No root or evidence is invented for an absent node. The row-kernel contract is selected through the containing registry, not recursively pinned by this expression contract. Ordered request.pipeline step params contain exactly bindings of name and canonical source expr; parameter references remain source syntax. They contain no references, extension pin, machine nodes or evidence. Graph params contain the selected extension pin, lowered bindings and regenerated references. derive_binding.aoa_node_cid hashes the complete corresponding graph.steps entry {id,in,op,params}, with no wrapper, field omission or evidence. Step and input names are the canonical fragment graph names, not process-local handles.';

export function executionContract(expressions, stages, protocol) {
  const schemas = rowKernelSchemas(protocol);
  return {
    version:'actql-ordered-derive-execution/0.1', operation:'REL.derive',
    inputs:['relation'], output:'relation', applies_to:'ordered_parameters_only',
    dependencies:{
      expression_contract:{file:'spec/contracts/actql-expressions.json',pointer:'',cid:machineCid(expressions)},
      expression_node:{file:'spec/contracts/actql-expressions.json',pointer:'/schemas/expression_node',cid:machineCid(expressions.schemas.expression_node)},
      source_expression:{file:'spec/contracts/actql-expressions.json',pointer:'/schemas/expression',cid:machineCid(expressions.schemas.expression)},
      derive_binding:{file:'spec/contracts/actql-stage-contracts.json',pointer:'/schemas/derive_binding',cid:machineCid(stages.schemas.derive_binding)},
      value_contract:{file:'spec/contracts/actql-protocol-schemas.json',pointer:'/schemas/canonical_value_contract',cid:machineCid(protocol.schemas.canonical_value_contract)},
    },
    schemas,
    semantics:{
      dispatch:'exact_registered_extension_cid_and_closed_ordered_params_no_legacy_fallback',
      legacy:'snapshot_map_exprs_node_representation_unchanged',
      source_params:'exactly_bindings_name_and_canonical_source_expr_preserve_parameter_references_no_reference_table_extension_pin_machine_nodes_or_evidence',
      source_binding:'request_pipeline_and_graph_preserve_exact_step_ids_input_edges_and_binding_names_order_replace_only_expression_payloads_and_add_registered_pin_and_regenerated_references',
      node_identity:'canonical_CID_of_complete_corresponding_graph_steps_entry_id_in_op_params_no_wrapper_or_omissions_includes_extension_pin_references_and_lowered_expressions_excludes_external_evidence',
      names:'canonical_AuthoredFieldName_unique_in_authored_binding_order',
      references:'binding_order_then_expression_semantic_preorder_exact_field_occurrences_no_literal_traversal',
      targets:'latest_prior_slot_with_same_name_else_original_input_never_self_or_future',
      field_spelling:'field_body_matches_target_field_or_prior_slot_name_and_checked_type',
      context:'input_contract_cid_matches_derive_evidence_prior_slots_equal_exact_checked_prefix',
      evidence:'one_derive_binding_per_ordered_graph_node_with_exact_node_input_output_expression_context_limits_ownership',
      expression_identity:'checked_expression_cid_hashes_complete_corresponding_fragment_root_including_step_id_parameter_pointer_source_node_contract_demand_paths',
      row_shape_identity:'input_and_output_contract_cids_resolve_row_shape_self_cids_excluding_only_self_cid',
      row_shape:'required_fields_unique_UTF16_sorted_fields_known_subset_required_additional_fields_controls_unknown_names_no_invented_types',
      admission:'all_required_input_values_before_shadowing_preserve_admitted_unknown_fields',
      evaluation:'logical_row_then_authored_binding_then_common_expression_order_with_existing_lazy_demands',
      failure:'first_demanded_failure_no_partial_operation_publication_or_slot_elimination',
      output:'retain_input_fields_replace_only_shadowed_fields_using_rhs_type_no_coercion',
      identity:'authored_order_reference_multiplicity_and_full_params_are_semantic_no_source_spans',
      acyclic:'node_includes_extension_pin_not_evidence_self_cid_evidence_then_names_node',
      limits_identity:'limits_cid_resolves_exact_request_row_kernel_limits_for_same_step_self_cid_excluding_only_self_cid',
      limits_owner:'request_row_kernel_limits_names_exact_ordered_steps_value_and_row_caps_do_not_exceed_enclosing_request_caps_selected_host_limits_remain_required',
      context_identity:'context_contract_cid_resolves_row_context_self_cid_excluding_only_self_cid',
      rows:'max_input_rows_counts_all_input_row_occurrences_before_evaluation',
      value_bytes:'canonical_JSON_UTF8_of_typed_wire_value_for_each_input_value_demanded_root_and_complete_retained_output_row',
      live_bytes:'sum_typed_wire_bytes_of_live_input_slot_temporary_and_pending_output_value_roots_count_alias_roots_separately_release_after_last_use',
      work:'one_per_row_and_binding_and_demanded_expression_entry_plus_value_weight_for_input_admission_each_consumed_operand_each_produced_value_and_retained_output',
      value_weight:'one_per_scalar_or_container_plus_raw_UTF8_octets_of_string_values_and_object_keys_count_every_logical_occurrence_including_shared_values',
      work_scope:'logical_workload_not_instruction_count_or_heap_visits_no_discount_for_caching_or_short_circuit_scalar_comparison_additional_backend_algorithm_limits_remain_separate',
      charging:'preflight_before_traversal_or_construction_check_arithmetic_overflow_exact_caps_accepted_no_per_slot_or_row_reset',
      physical_memory:'logical_measures_not_heap_ceiling_backend_may_apply_additional_host_resource_limits',
      bounds:'no_static_capacity_proof_fabrication_no_early_projection_waiver',
      unsupported:'reject_executable_plan_if_contract_expression_or_measure_cannot_be_enforced',
    },
  };
}

// Exported preparation is deliberately separate from registration. The complete
// contract/vector checks must precede selecting this capability in a registry.
export function prepareExpressionEvidence(expressions, stages, protocol) {
  const {context, limits, shape, params} = rowKernelSchemas(protocol);
  expressions.laws.ordered_derive_binding = orderedBindingLaw;
  expressions.schemas.fragment.properties.row_kernel_evidence = closed({
    bindings:array(structuredClone(stages.schemas.derive_binding)),
    contexts:array(context), limits:array(limits), shapes:array(shape),
  });
  expressions.schemas.fragment.properties.request.properties.row_kernel_limits = {
    type:'object',additionalProperties:structuredClone(limits),
  };
  const fragment=expressions.schemas.fragment.properties;
  fragment.request.properties.pipeline.properties.steps.items.allOf=[deriveStepConstraint({oneOf:[
    closed({exprs:{type:'object',additionalProperties:{$ref:expressions.schemas.expression.$id}}}),
    sourceParams(),
  ]})];
  fragment.graph.properties.steps.items.allOf=[deriveStepConstraint({oneOf:[
    closed({exprs:{type:'object',additionalProperties:{$ref:expressions.schemas.expression_node.$id}}}),
    structuredClone(params),
  ]})];
  return expressions;
}

export function checkOrderedRegistration(aoa, expressions, stages, protocol, registry) {
  assert.deepEqual(expressions, prepareExpressionEvidence(structuredClone(expressions),stages,protocol));
  const body=executionContract(expressions,stages,protocol);
  assert.deepEqual(aoa.execution_contracts[executionKey],body);
  const extension={file:'spec/contracts/actql-aoa.json',pointer:executionPointer,cid:machineCid(body)};
  assert.deepEqual(registry['REL.derive'].execution_extensions,{ordered_bindings:extension});
  assert.deepEqual(aoa.target_registry_requirements['REL.derive'],{
    inputs:['relation'],output:'relation',execution_extensions:{ordered_bindings:extension},
  });
  assert.equal(aoa.pipeline_registry_cid,machineCid(registry));
  return body;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const read = p => JSON.parse(readFileSync(p,'utf8'));
  const ep='spec/contracts/actql-expressions.json';
  const expressions=read(ep), stages=read('spec/contracts/actql-stage-contracts.json');
  const protocol=read('spec/contracts/actql-protocol-schemas.json');
  const prepared=prepareExpressionEvidence(expressions,stages,protocol);
  const body=executionContract(prepared,stages,protocol);
  if (process.argv.includes('--write')) {
    const ap='spec/contracts/actql-aoa.json',rp='spec/dependencies/aoa-pipeline-registry.json';
    const aoa=read(ap),registry=read(rp);
    const extension={file:ap,pointer:executionPointer,cid:machineCid(body)};
    registry['REL.derive'].execution_extensions={ordered_bindings:extension};
    aoa.execution_contracts[executionKey]=body;
    aoa.target_registry_requirements['REL.derive']={inputs:['relation'],output:'relation',execution_extensions:{ordered_bindings:extension}};
    aoa.expression_contract_cid=machineCid(prepared);
    aoa.pipeline_registry_cid=machineCid(registry);
    for(const [p,v]of [[ep,prepared],[ap,aoa],[rp,registry]])writeFileSync(p,JSON.stringify(v,null,2)+'\n');
  }
  if (process.argv.includes('--write-draft')) {
    // Review artifact only; this does not mutate any selected contract or pin.
    writeFileSync('_build/ordered-derive-contract-draft.json',JSON.stringify(body,null,2)+'\n');
  }
  if(!process.argv.includes('--write-draft')){
    checkOrderedRegistration(read('spec/contracts/actql-aoa.json'),read(ep),stages,protocol,read('spec/dependencies/aoa-pipeline-registry.json'));
    console.log('Registered ordered derive contract',machineCid(body));
  } else console.log('Unregistered ordered derive contract candidate',machineCid(body));
}
