///|
fn preparation_limits() -> PreparationBudget {
  {
    work: 10000000,
    text_bytes: 10000000,
    source_value_nodes: 1000000,
    source_comparison_pairs: 1000000,
    policy_nodes: 1000000,
    local_input_nodes: 1000000,
    pattern_ast_bytes: 1000000,
    pattern_ast_nodes: 1000000,
  }
}

///|
fn preparation_sources_fixture(
  selected : SelectedPolicyContext,
) -> SourceProducerContext {
  let rows = source_policy_fixture(policy_context(selected))
  let joined = bind_source_policy(rows, selected, 10000000).unwrap()
  bind_source_producers(
    check_source_capacity(joined, 10000000).unwrap(),
    [],
    10000000,
  ).unwrap()
}

///|
test "preparation joins exact selected owners and counts each branch once" {
  let patterns = bound_fixture("regex_replace('abc', '(.)', '$1x')")
  let expressions = check_text_bounds(patterns, bound_limits()).unwrap()
  let selected = expression_validation_selected(pattern_context(patterns))
  let profiles = check_expression_profiles(
    pattern_context(patterns),
    { text_time: true, veca: false, },
    10000000,
  ).unwrap()
  let sources = preparation_sources_fixture(selected)
  let combined = assemble_preparation(
    sources,
    expressions,
    profiles,
    preparation_limits(),
  ).unwrap()
  assert_true(physical_equal(preparation_sources(combined), sources))
  assert_true(physical_equal(preparation_expressions(combined), expressions))
  assert_true(physical_equal(preparation_profiles(combined), profiles))
  let used = preparation_usage(combined)
  let bindings = collect_source_bindings(combined, used.work + 1, 0).unwrap()
  assert_true(physical_equal(source_bindings_preparation(bindings), combined))
  assert_eq(source_bindings_count(bindings), 0)
  assert_eq(source_bindings_work(bindings), used.work + 1)
  assert_true(source_bindings_at(bindings, 0, 0) is None)
  assert_true(
    collect_source_bindings(combined, used.work, 0) is Err(BudgetExceeded),
  )
  assert_true(collect_source_bindings(combined, -1, 0) is Err(InvalidLimits))
  assert_true(
    collect_source_bindings(combined, used.work + 1, -1) is Err(InvalidLimits),
  )
  assert_eq(
    used.work,
    source_producer_work(sources) +
    text_bounds_usage(expressions).work -
    selected_policy_usage(selected).work +
    expression_profiles_work(profiles) -
    expression_validation_usage(pattern_context(patterns)).work +
    1,
  )
  assert_eq(used.text_bytes, text_bounds_usage(expressions).text_bytes)
  assert_eq(used.pattern_ast_bytes, pattern_usage(patterns).ast_bytes)
  assert_eq(used.pattern_ast_nodes, pattern_usage(patterns).ast_nodes)
  assert_true(used.pattern_ast_bytes > 0 && used.pattern_ast_nodes > 0)
  assert_true(
    assemble_preparation(sources, expressions, profiles, used) is Ok(_),
  )
  for
    caps in [
      { ..used, work: used.work - 1, },
      { ..used, text_bytes: used.text_bytes - 1, },
      { ..used, policy_nodes: used.policy_nodes - 1, },
      { ..used, local_input_nodes: used.local_input_nodes - 1, },
      { ..used, pattern_ast_bytes: used.pattern_ast_bytes - 1, },
      { ..used, pattern_ast_nodes: used.pattern_ast_nodes - 1, },
    ] {
    assert_true(
      assemble_preparation(sources, expressions, profiles, caps)
      is Err(BudgetExceeded),
    )
  }
  for
    caps in [
      { ..used, work: -1, },
      { ..used, text_bytes: -1, },
      { ..used, source_value_nodes: -1, },
      { ..used, source_comparison_pairs: -1, },
      { ..used, policy_nodes: -1, },
      { ..used, local_input_nodes: -1, },
      { ..used, pattern_ast_bytes: -1, },
      { ..used, pattern_ast_nodes: -1, },
    ] {
    assert_true(
      assemble_preparation(sources, expressions, profiles, caps)
      is Err(InvalidLimits),
    )
  }
  // Equal Programs, values and policy identities are not a shared checked owner.
  let other = check_text_bounds(
    bound_fixture("regex_replace('abc', '(.)', '$1x')"),
    bound_limits(),
  ).unwrap()
  assert_true(
    assemble_preparation(sources, other, profiles, preparation_limits())
    is Err(ForeignExpressionProfiles),
  )
  let other_profiles = check_expression_profiles(
    pattern_context(text_bounds_patterns(other)),
    { text_time: true, veca: false, },
    10000000,
  ).unwrap()
  assert_true(
    assemble_preparation(sources, other, other_profiles, preparation_limits())
    is Err(ForeignSelectedPolicy),
  )
  // Rechecking expressions using the very same selected owner is permitted.
  let repeated = check_text_bounds(patterns, bound_limits()).unwrap()
  assert_true(assemble_preparation(sources, repeated, profiles, used) is Ok(_))
}
