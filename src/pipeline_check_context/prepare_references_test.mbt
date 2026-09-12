///|
fn prepared_reference_branch(
  operations : OperationProfileChecks,
  max_work : Int,
) -> Result[ProgramReferences, PreparedReferencesIssue] {
  let limits = source_preparation_limits()
  prepare_program_references(
    operations,
    limits.body,
    limits.uses,
    limits.references,
    max_work~,
  )
}

///|
fn source_preparation_limits() -> SourcePreparationLimits {
  {
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
    identity: identity_limits(),
    max_bindings: 100,
  }
}

///|
test "owned reference preparation preserves declaration use and shared work" {
  let (identity, _, _) = prepared_identity_fixture()
  let sources = program_identity_sources(identity)
  let operations = program_sources_operations(sources)
  let prior = program_sources_references(sources)
  let exact = program_reference_work(prior)
  let result = prepared_reference_branch(operations, exact).unwrap()
  let stages = program_reference_stages(prior)
  let bound = stage_operations(stages)
  let slots = source_request_slots(
    source_rows_requests(
      source_policy_rows(
        source_capacity_context(
          source_producer_capacity(
            preparation_sources(operation_profiles_preparation(operations)),
          ),
        ),
      ),
    ),
  )
  let independent = attach_program_references(
    stages,
    reference_values_for(
      @stages.bound_operations(bound),
      @references.bound_values(@stages.bound_program_index(bound)),
      request_slots=Some(slots),
    ),
    max_work=exact,
  ).unwrap()
  assert_eq(program_reference_work(result), program_reference_work(independent))
  assert_eq(program_reference_work(result), exact)
  assert_true(
    physical_equal(
      program_reference_stages(result),
      program_reference_stages(prior),
    ),
  )
  assert_true(
    physical_equal(
      @program_refs.parameter_values(program_reference_values(result)),
      @program_refs.parameter_values(program_reference_values(prior)),
    ),
  )
  let rebound = bind_program_sources(
    operations,
    result,
    program_sources_bindings(sources),
    10000000,
  ).unwrap()
  let rebuilt = identify_program_sources(rebound, identity_limits()).unwrap()
  assert_eq(
    program_identity_definition_cid(rebuilt),
    program_identity_definition_cid(identity),
  )
  assert_eq(
    program_identity_parameter_values_cid(rebuilt),
    program_identity_parameter_values_cid(identity),
  )
  assert_true(prepared_reference_branch(operations, exact - 1) is Err(_))
  assert_true(prepared_reference_branch(operations, 0) is Err(BudgetExceeded))
  assert_true(prepared_reference_branch(operations, -1) is Err(InvalidLimits))
}
