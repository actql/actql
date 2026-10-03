///|
fn program_sources_fixture(
  capacity_policy? : @policy.Policy = policy(),
  supplied? : @decode.Cursor? = None,
  tea? : Bool = false,
  sga? : Bool = false,
  property_graph? : Bool = false,
  calendar? : Bool = false,
  veca? : Bool = false,
  text_rank? : Bool = false,
  host_profile? : String = bound_profile(),
  expression? : String = "regex_extract($p, '(.)', $n)",
  steps? : String? = None,
  second_steps? : String? = None,
  accepted? : Bool = false,
  parameters? : String = "{\"p\":{\"type\":\"string\",\"default\":\"é😀\"},\"n\":{\"type\":\"number\",\"default\":1}}",
) -> (OperationProfileChecks, ProgramReferences, SourceBindingRequirements) {
  let patterns = bound_fixture(
    expression,
    capacity_policy~,
    supplied~,
    steps~,
    second_steps~,
    accepted~,
    parameters~,
    profile=host_profile,
  )
  let validation = pattern_context(patterns)
  let selected = expression_validation_selected(validation)
  let producer = preparation_sources_fixture(selected)
  let preparation = assemble_preparation(
    producer,
    check_text_bounds(patterns, bound_limits()).unwrap(),
    check_expression_profiles(validation, { text_time: true, veca, }, 10000000).unwrap(),
    preparation_limits(),
  ).unwrap()
  let operations = check_operation_profiles(
    preparation,
    { rela: true, sga, tea, calendar, text_rank, },
    10000000,
    property_graph~,
  ).unwrap()
  let stages = wired_stage_contexts(reconciled_wiring(policy_context(selected)))
  let bound = stage_operations(stages)
  let slots = source_request_slots(
    source_rows_requests(
      source_policy_rows(
        source_capacity_context(source_producer_capacity(producer)),
      ),
    ),
  )
  let values = reference_values_for(
    @stages.bound_operations(bound),
    @references.bound_values(@stages.bound_program_index(bound)),
    request_slots=Some(slots),
  )
  let references = attach_program_references(stages, values, max_work=10000000).unwrap()
  let bindings = collect_source_bindings(preparation, 10000000, 100).unwrap()
  (operations, references, bindings)
}

///|
test "Program source checks join exact owners and retain independently validated use" {
  let (operations, references, bindings) = program_sources_fixture()
  let result = bind_program_sources(operations, references, bindings, 10000000).unwrap()
  assert_true(physical_equal(program_sources_operations(result), operations))
  assert_true(physical_equal(program_sources_references(result), references))
  assert_true(physical_equal(program_sources_bindings(result), bindings))
  let semantics = program_sources_stage_semantics(result, 0).unwrap()
  assert_true(
    physical_equal(
      @program_refs.stage_semantics_usage(semantics),
      @program_refs.parameter_usage(program_reference_values(references)),
    ),
  )
  assert_true(program_sources_stage_semantics(result, 2) is None)
  let program = program_sources_semantics(result, {
    max_work: 10000000,
    max_stages: 2,
    max_hash_bytes: 100000,
    max_hash_nodes: 10000,
    max_depth: 100,
  }).unwrap()
  assert_true(
    physical_equal(
      @program_refs.program_semantics_usage(program),
      @program_refs.parameter_usage(program_reference_values(references)),
    ),
  )
  assert_true(@program_refs.program_semantics_stage_cid(program, 0) is Some(_))
  let work = program_sources_work(result)
  assert_eq(
    work,
    operation_profiles_work(operations) +
    program_reference_work(references) -
    stage_usage(program_reference_stages(references)).0 +
    source_bindings_work(bindings) -
    preparation_usage(operation_profiles_preparation(operations)).work +
    1,
  )
  assert_true(
    bind_program_sources(operations, references, bindings, work) is Ok(_),
  )
  assert_true(
    bind_program_sources(operations, references, bindings, work - 1)
    is Err(BudgetExceeded),
  )
  assert_true(
    bind_program_sources(operations, references, bindings, -1)
    is Err(InvalidLimits),
  )
  let (_, foreign_references, foreign_bindings) = program_sources_fixture()
  assert_true(
    bind_program_sources(operations, references, foreign_bindings, work)
    is Err(ForeignPreparation),
  )
  assert_true(
    bind_program_sources(operations, foreign_references, bindings, work)
    is Err(ForeignStages),
  )
}

///|
test "equal source-role inventories cannot replace request declaration owners" {
  let (operations, references, bindings) = program_sources_fixture()
  let stages = program_reference_stages(references)
  let bound = stage_operations(stages)
  // Re-admit the same Program's Binding declarations and role slots. Names,
  // values, source bytes and StageContexts are equal; the slots are not owned
  // by the requests validated in this preparation.
  let detached = reference_values_for(
    @stages.bound_operations(bound),
    @references.bound_values(@stages.bound_program_index(bound)),
  )
  let detached_references = attach_program_references(
    stages,
    detached,
    max_work=10000000,
  ).unwrap()
  assert_true(
    bind_program_sources(operations, detached_references, bindings, 10000000)
    is Err(ForeignRequestSlots),
  )
}
