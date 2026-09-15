///|
fn distinct_compile_limits() -> CompileLimits {
  {
    work: 101,
    artifacts: { bytes: 102, nodes: 103, depth: 104, },
    structure: {
      stages: 105,
      steps: 106,
      results: 107,
      parameters: 108,
      bindings: 109,
      slots: 110,
      references: 111,
      requirements: 112,
      tokens: 113,
    },
    traversal: {
      nodes: 114,
      depth: 115,
      text_bytes: 116,
      string_bytes: 117,
      name_bytes: 118,
      pointer_units: 119,
      comparison_pairs: 120,
    },
    values: { nodes: 121, depth: 122, text_bytes: 123, },
    policy: { bytes: 124, nodes: 125, depth: 126, },
    patterns: { bytes: 127, nodes: 128, depth: 129, },
  }
}

///|
test "every compile control rejects negative configuration before preparation" {
  let valid = distinct_compile_limits()
  for
    invalid in [
      { ..valid, work: -1, },
      { ..valid, artifacts: { ..valid.artifacts, bytes: -1, }, },
      { ..valid, artifacts: { ..valid.artifacts, nodes: -1, }, },
      { ..valid, artifacts: { ..valid.artifacts, depth: -1, }, },
      { ..valid, structure: { ..valid.structure, stages: -1, }, },
      { ..valid, structure: { ..valid.structure, steps: -1, }, },
      { ..valid, structure: { ..valid.structure, results: -1, }, },
      { ..valid, structure: { ..valid.structure, parameters: -1, }, },
      { ..valid, structure: { ..valid.structure, bindings: -1, }, },
      { ..valid, structure: { ..valid.structure, slots: -1, }, },
      { ..valid, structure: { ..valid.structure, references: -1, }, },
      { ..valid, structure: { ..valid.structure, requirements: -1, }, },
      { ..valid, structure: { ..valid.structure, tokens: -1, }, },
      { ..valid, traversal: { ..valid.traversal, nodes: -1, }, },
      { ..valid, traversal: { ..valid.traversal, depth: -1, }, },
      { ..valid, traversal: { ..valid.traversal, text_bytes: -1, }, },
      { ..valid, traversal: { ..valid.traversal, string_bytes: -1, }, },
      { ..valid, traversal: { ..valid.traversal, name_bytes: -1, }, },
      { ..valid, traversal: { ..valid.traversal, pointer_units: -1, }, },
      { ..valid, traversal: { ..valid.traversal, comparison_pairs: -1, }, },
      { ..valid, values: { ..valid.values, nodes: -1, }, },
      { ..valid, values: { ..valid.values, depth: -1, }, },
      { ..valid, values: { ..valid.values, text_bytes: -1, }, },
      { ..valid, policy: { ..valid.policy, bytes: -1, }, },
      { ..valid, policy: { ..valid.policy, nodes: -1, }, },
      { ..valid, policy: { ..valid.policy, depth: -1, }, },
      { ..valid, patterns: { ..valid.patterns, bytes: -1, }, },
      { ..valid, patterns: { ..valid.patterns, nodes: -1, }, },
      { ..valid, patterns: { ..valid.patterns, depth: -1, }, },
    ] {
    assert_false(compile_limits_valid(invalid))
  }
}

///|
test "semantic compile meters retain every preparation cap without phase inputs" {
  let limits = distinct_compile_limits()
  assert_true(compile_limits_valid(limits))
  let p = compile_source_limits(limits)
  // Distinct independent sentinels expose accidental cross-meter substitution.
  assert_eq(
    [
      p.topology.max_work,
      p.topology.max_stages,
      p.topology.max_steps,
      p.topology.max_results,
      p.topology.max_nodes,
      p.topology.max_tokens,
      p.topology.max_text_bytes,
      p.topology.max_depth,
    ],
    [101, 105, 106, 107, 114, 113, 116, 115],
  )
  assert_eq(
    [
      p.context.stages.max_work,
      p.context.stages.max_text_bytes,
      p.context.stages.max_name_bytes,
      p.context.stages.max_input_work,
      p.context.stages.max_operand_work,
      p.context.max_policy_bytes,
      p.context.max_policy_nodes,
      p.context.max_policy_depth,
      p.context.max_local_input_nodes,
    ],
    [101, 116, 118, 101, 101, 124, 125, 126, 121],
  )
  assert_eq(
    [
      p.requests.max_work,
      p.requests.max_pairs,
      p.requests.values.max_nodes,
      p.requests.values.max_depth,
      p.requests.values.max_text_bytes,
      p.checks.work,
      p.checks.text_bytes,
      p.checks.source_value_nodes,
      p.checks.source_comparison_pairs,
      p.checks.policy_nodes,
      p.checks.local_input_nodes,
      p.checks.pattern_ast_bytes,
      p.checks.pattern_ast_nodes,
    ],
    [101, 120, 121, 122, 123, 101, 116, 121, 120, 125, 121, 127, 128],
  )
  let body = p.identity.body
  assert_eq(
    [
      body.max_work,
      body.selectors.max_nodes,
      body.selectors.max_depth,
      body.selectors.max_text_bytes,
      body.selectors.max_tokens,
      body.selectors.tree.max_nodes,
      body.selectors.tree.max_depth,
      body.selectors.tree.max_string_bytes,
      body.selectors.tree.max_total_string_bytes,
    ],
    [101, 114, 115, 116, 113, 114, 115, 117, 116],
  )
  assert_eq(
    [
      p.identity.uses.max_work,
      p.identity.uses.max_slots,
      p.identity.uses.max_references,
      p.identity.uses.max_pointer_units,
      p.identity.uses.max_direct_text_bytes,
      p.identity.references.max_work,
      p.identity.references.max_slots,
      p.identity.references.max_references,
      p.identity.references.max_pointer_units,
      p.identity.references.max_request_text_bytes,
    ],
    [101, 110, 111, 119, 116, 101, 110, 111, 119, 116],
  )
  assert_eq(
    [
      p.identity.identity.max_work,
      p.identity.identity.max_stages,
      p.identity.identity.max_hash_bytes,
      p.identity.identity.max_hash_nodes,
      p.identity.identity.max_depth,
      p.identity.max_bindings,
      p.max_parameters,
      p.max_bindings,
      p.max_slots,
      p.max_policy_depth,
      p.max_requirements,
      p.max_regex_depth,
    ],
    [101, 105, 102, 103, 104, 109, 108, 109, 110, 126, 112, 129],
  )
}
