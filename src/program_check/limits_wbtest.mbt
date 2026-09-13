///|
fn source_limits_fixture(stage_count : Int) -> SourceLimits {
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
