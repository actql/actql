///|
fn source_limits(stage_count : Int) -> @program_check.SourceLimits {
  {
    topology: {
      max_stages: stage_count,
      max_steps: stage_count,
      max_results: stage_count,
      max_work: 1000000,
      max_nodes: 100000,
      max_tokens: 10000,
      max_text_bytes: 1000000,
      max_depth: 100,
    },
    context: {
      stages: {
        max_work: 10000000,
        max_text_bytes: 10000000,
        max_name_bytes: 1000000,
        max_input_work: 1000000,
        max_operand_work: 1000000,
      },
      max_policy_bytes: 10000,
      max_policy_nodes: 100,
      max_policy_depth: 10,
      max_local_input_nodes: 100000,
    },
    requests: {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    },
    checks: {
      work: 10000000,
      text_bytes: 10000000,
      source_value_nodes: 1000000,
      source_comparison_pairs: 1000000,
      policy_nodes: 1000000,
      local_input_nodes: 1000000,
      pattern_ast_bytes: 1000000,
      pattern_ast_nodes: 1000000,
    },
    identity: {
      body: {
        max_work: 1000000,
        selectors: {
          max_nodes: 10000,
          max_depth: 100,
          max_text_bytes: 100000,
          max_tokens: 1000,
          tree: {
            max_nodes: 10000,
            max_depth: 100,
            max_string_bytes: 100000,
            max_total_string_bytes: 100000,
          },
        },
      },
      uses: {
        max_work: 1000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 100000,
        max_direct_text_bytes: 100000,
      },
      references: {
        max_work: 4000000,
        max_slots: 1000,
        max_references: 1000,
        max_pointer_units: 1000000,
        max_request_text_bytes: 100000,
      },
      identity: {
        max_work: 10000000,
        max_stages: stage_count,
        max_hash_bytes: 100000,
        max_hash_nodes: 10000,
        max_depth: 100,
      },
      max_bindings: 100,
    },
    max_parameters: 1,
    max_bindings: 100,
    max_slots: 1000,
    max_policy_depth: 100,
    max_requirements: 1000,
    max_regex_depth: 100,
  }
}

///|
// Example application wiring through the public registry and fragment verifier.
fn generate(
  owner : @lower.BoundPrepared,
  registry_json : String,
  values_json : String,
  fragment_json : String,
  filter : Bool,
) -> @execution.GeneratedSequence raise {
  let registry_limits : @execution.RegistryLimits = {
    max_body_bytes: 100000,
    max_body_nodes: 10000,
    max_body_depth: 100,
  }
  let registered = @execution.admit_relation_registry(
    contract(registry_json),
    contract(values_json),
    registry_limits,
  ).unwrap()
  let fragment = @execution.admit_fragment_contract(
    registered,
    contract(fragment_json),
    registry_limits,
  ).unwrap()
  let sequence = @lower.prepare_sequence(owner, {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }).unwrap()
  let direct_count = @lower.sequence_step(sequence, 0)
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_count_group(kernel) is Some(_)
  let direct_join = @lower.sequence_step(sequence, 0)
    is Some(@lower.JoinStep(_))
  let contexts = if filter && !direct_count && !direct_join {
    let pipeline = @lower.prepare_fragment_pipeline(sequence, 0, {
      max_roots: 100,
      max_pointer_bytes: 10000,
      max_work: 100000,
    }).unwrap()
    let request = @lower.prepare_fragment_request(pipeline, 100L, 1000L).unwrap()
    let context = @execution.prepare_runtime_fragment(
      request,
      fragment,
      {
        max_roots: 100,
        max_nodes: 1000,
        max_work: 100000,
        max_text_bytes: 100000,
        max_links: 10000,
      },
      registry_limits,
      {
        max_input_rows: 100L,
        max_value_bytes: 1000L,
        max_live_value_bytes: 10000L,
        max_work: 100000L,
      },
    ).unwrap()
    [context]
  } else {
    []
  }
  @execution.prepare_generated_sequence(
    registered,
    sequence,
    contexts,
    [
      @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @pipeline.step_count(@lower.pipeline(@lower.bound_preparation(owner))) -
          1,
        ).unwrap(),
      ),
    ],
    100000,
    10000,
  ).unwrap()
}
