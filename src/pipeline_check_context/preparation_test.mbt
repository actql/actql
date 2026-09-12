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
  let locations = match reconciled_sourceviews(policy_context(selected)) {
    None => []
    Some(_) =>
      Array::makei(
        @stages.stage_count(
          @stages.operations_source(
            @stages.bound_operations(
              stage_operations(
                wired_stage_contexts(
                  reconciled_wiring(policy_context(selected)),
                ),
              ),
            ),
          ),
        ),
        _ => [],
      )
  }
  // These fixtures have no keyed acquisition consumers. Other Programs must
  // provide the actual row bounds and producer locations.
  let rows = Array::makei(locations.length(), _ => [])
  prepare_program_sources(
    selected,
    rows,
    locations,
    {
      max_work: 10000000,
      max_pairs: 1000,
      values: { max_nodes: 10000, max_depth: 100, max_text_bytes: 100000, },
    },
    max_bindings=100,
    max_slots=1000,
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
  let declared : PureOperationProfiles = {
    rela: true,
    sga: false,
    tea: false,
    calendar: false,
    text_rank: false,
  }
  let operations = check_operation_profiles(combined, declared, 10000000).unwrap()
  assert_true(
    physical_equal(operation_profiles_preparation(operations), combined),
  )
  assert_eq(operation_profiles_declared(operations), declared)
  assert_eq(operation_profiles_count(operations), 3)
  let operation_work = operation_profiles_work(operations)
  let full_budget = { ..used, work: operation_work, }
  let prepared = prepare_program_checks(
    sources,
    { text_time: true, veca: false, },
    declared,
    full_budget,
    max_policy_depth=100,
    max_requirements=1000,
    max_regex_depth=100,
  ).unwrap()
  let owned = operation_profiles_preparation(prepared)
  assert_true(physical_equal(preparation_sources(owned), sources))
  assert_true(
    physical_equal(
      expression_validation_selected(
        pattern_context(text_bounds_patterns(preparation_expressions(owned))),
      ),
      selected,
    ),
  )
  assert_true(
    physical_equal(
      expression_profiles_context(preparation_profiles(owned)),
      pattern_context(text_bounds_patterns(preparation_expressions(owned))),
    ),
  )
  assert_eq(preparation_usage(owned), used)
  assert_eq(operation_profiles_work(prepared), operation_work)
  assert_eq(
    operation_profiles_count(prepared),
    operation_profiles_count(operations),
  )
  for
    cap in [
      { ..full_budget, work: full_budget.work - 1, },
      { ..full_budget, text_bytes: full_budget.text_bytes - 1, },
      { ..full_budget, policy_nodes: full_budget.policy_nodes - 1, },
      { ..full_budget, local_input_nodes: full_budget.local_input_nodes - 1, },
      { ..full_budget, pattern_ast_bytes: full_budget.pattern_ast_bytes - 1, },
      { ..full_budget, pattern_ast_nodes: full_budget.pattern_ast_nodes - 1, },
    ] {
    assert_true(
      prepare_program_checks(
        sources,
        { text_time: true, veca: false, },
        declared,
        cap,
        max_policy_depth=100,
        max_requirements=1000,
        max_regex_depth=100,
      )
      is Err(_),
    )
  }
  assert_true(
    prepare_program_checks(
      sources,
      { text_time: false, veca: false, },
      declared,
      full_budget,
      max_policy_depth=100,
      max_requirements=1000,
      max_regex_depth=100,
    )
    is Err(ExpressionProfiles(UnsupportedProfile(_, "actql-text-time/0.1"))),
  )
  assert_true(
    prepare_program_checks(
      sources,
      { text_time: true, veca: false, },
      { ..declared, rela: false, },
      full_budget,
      max_policy_depth=100,
      max_requirements=1000,
      max_regex_depth=100,
    )
    is Err(OperationProfiles(UnsupportedProfile(0, 0, 0, @pipeline.RelA))),
  )
  // One constructor, two stages, three visits, three (step + profile) pairs.
  assert_eq(operation_work, used.work + 12)
  assert_true(
    check_operation_profiles(combined, declared, operation_work) is Ok(_),
  )
  assert_true(
    check_operation_profiles(combined, declared, operation_work - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    check_operation_profiles(combined, declared, -1) is Err(InvalidLimits),
  )
  assert_true(
    check_operation_profiles(
      combined,
      { ..declared, rela: false, },
      operation_work,
    )
    is Err(UnsupportedProfile(0, 0, 0, @pipeline.RelA)),
  )
  assert_eq(
    operation_profiles_diagnostic(UnsupportedProfile(0, 0, 0, @pipeline.RelA)),
    Some("ACTQL_E_PROFILE_UNSUPPORTED"),
  )
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
      prepare_program_checks(
        sources,
        { text_time: true, veca: false, },
        declared,
        caps,
        max_policy_depth=100,
        max_requirements=1000,
        max_regex_depth=100,
      )
      is Err(InvalidLimits),
    )
    assert_true(
      assemble_preparation(sources, expressions, profiles, caps)
      is Err(InvalidLimits),
    )
  }
  for
    (depth, requirements, regex_depth) in [
      (-1, 1000, 100),
      (100, -1, 100),
      (100, 1000, -1),
      (100, 1000, 1073741823),
    ] {
    assert_true(
      prepare_program_checks(
        sources,
        { text_time: true, veca: false, },
        declared,
        full_budget,
        max_policy_depth=depth,
        max_requirements=requirements,
        max_regex_depth=regex_depth,
      )
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
