///|
fn funded_source_program() -> @syntax.Program {
  @syntax.parse(
    (
      #|{"version":"actql/0.1","id":"p","params":{"n":{"type":"number"}},"stages":[{"id":"a","inputs":{"rows":{}},"from":"rows","steps":[{"take":{"$param":"n"}}],"results":{"r":{}}},{"id":"b","inputs":{"rows":{}},"from":"rows","steps":[{"take":{"$param":"n"}}],"results":{"r":{}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
    ),
    {
      source: { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
      tree: {
        max_nodes: 1000,
        max_depth: 100,
        max_string_bytes: 10000,
        max_total_string_bytes: 10000,
      },
      max_stages: 10,
    },
    format=Json,
  ).unwrap()
}

///|
fn funded_source_declarations(
  owner : ClientParameterDeclarationPreflight[Array[String], Array[Int]],
) -> @parameters.DeclarationReadInput {
  let original = prepare_funded_value_prefix(owner)
  while @parameters.declaration_read_phase(original) !=
        @parameters.DeclarationComplete {
    match @parameters.declaration_read_phase(original) {
      @parameters.DeclarationType =>
        prepare_parameter_declaration_type(owner).unwrap()
      @parameters.DeclarationValue =>
        prepare_parameter_declaration_value(owner).unwrap()
      _ => abort("funded declaration boundary")
    }
  }
  reconcile_parameter_declarations(owner).unwrap()
  original
}

///|
test "same parent funds completed declarations Source and binding snapshot across two one-short boundaries" {
  let program = funded_source_program()
  let other_program = funded_source_program()
  let params = @decode.lookup(
    @decode.open_object(@syntax.program_body(program)).unwrap(),
    "params",
  )
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 500000L,
    execution_bytes: 500018L,
  }).unwrap()
  let input = ["SAME Program declaration Source and binding parent"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    params,
    funded_value_limits(),
  ).unwrap()
  assert_eq(parameter_preflight_initial_bytes, 11816L)
  assert_true(
    prepare_parameter_declaration_source(owner, program) is Err(WrongPhase),
  )
  let reader = funded_source_declarations(owner)
  let declarations = @parameters.finish_declaration_read(reader).unwrap()
  assert_eq(
    parameter_source_construction_bytes(program),
    Some((312L, 2416L, 8L)),
  )
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  let sibling = @resources.reserve_capacity(
    ledger,
    500000L - before.0 - 2416L + 1L,
    500000L - before.0 - 2416L + 1L,
  ).unwrap()
  assert_true(
    prepare_parameter_declaration_source(owner, program)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(owner.phase == SourceQuoted)
  assert_true(parameter_declaration_source_outcome(owner) is None)
  let quote = owner.quote
  assert_eq(quote, Some((before.0 + 2416L, before.1 + 2416L)))
  assert_true(
    prepare_parameter_declaration_source(owner, other_program)
    is Err(WrongPhase),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_declaration_source(owner, program).unwrap()
  assert_true(physical_equal(quote, owner.quote))
  let source = parameter_declaration_source_outcome(owner).unwrap().unwrap()
  assert_true(physical_equal(@stages.declarations(source), declarations))
  assert_true(physical_equal(@stages.program(source), program))
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationComplete,
  )
  assert_true(
    prepare_parameter_declaration_source(owner, program) is Err(WrongPhase),
  )
  assert_true(
    @resources.begin_preparation_phase_work64(
      capacity,
      input,
      @resources.ParameterSourceConstruction,
      8L,
    )
    is Err(AlreadyClaimed),
  )
  reconcile_parameter_declaration_source(owner).unwrap()
  let retained_source = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  assert_eq(retained_source, (before.0 + 312L, before.1 + 312L))

  let supplied = Some(funded_value_cursor("{\"n\":7}"))
  let bindings = begin_parameter_binding_preparation(
    capacity,
    input,
    declarations,
    supplied,
    binding_body_value_limits(),
  ).unwrap()
  let binding = binding_body_prefix(bindings)
  guard finish_funded_binding_body(bindings, binding)
    is Ok(@parameters.Ready(values)) else {
    fail("original value")
  }
  reconcile_parameter_bindings(bindings).unwrap()
  assert_eq(parameter_binding_initial_bytes, 10672L)
  assert_eq(parameter_source_binding_construction_bytes(), Some((96L, 192L)))
  let before_snapshot = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  let sibling = @resources.reserve_capacity(
    ledger,
    500000L - before_snapshot.0 - 192L + 1L,
    500000L - before_snapshot.0 - 192L + 1L,
  ).unwrap()
  assert_true(
    prepare_parameter_binding_source(bindings, source)
    is Err(Capacity(Resource(RetentionLimit))),
  )
  assert_true(bindings.phase == BindingSourceQuoted)
  let quote = bindings.quote
  let foreign = @stages.prepare(program, funded_value_limits()).unwrap()
  assert_true(
    prepare_parameter_binding_source(bindings, foreign) is Err(WrongPhase),
  )
  assert_true(parameter_binding_source_outcome(bindings) is None)
  @resources.settle_capacity(ledger, sibling).unwrap()
  prepare_parameter_binding_source(bindings, source).unwrap()
  assert_true(physical_equal(quote, bindings.quote))
  let final_source = parameter_binding_source_outcome(bindings)
    .unwrap()
    .unwrap()
  guard @stages.bind(final_source, supplied, binding_body_value_limits())
    is Ok(@parameters.Ready(same)) else {
    fail("original bound Source")
  }
  assert_true(physical_equal(same, values))
  reconcile_parameter_binding_source(bindings).unwrap()
  let final_extents = @resources.preparation_capacity_working_extents(
    capacity, input,
  ).unwrap()
  assert_eq(final_extents, (before_snapshot.0 + 96L, before_snapshot.1 + 96L))
  clear_parameter_binding_preparation(bindings).unwrap()
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_true(parameter_binding_source_outcome(bindings) is None)
  assert_true(parameter_declaration_source_outcome(owner) is None)
  assert_true(
    @stages.bind(final_source, supplied, binding_body_value_limits())
    is Ok(@parameters.Ready(_)),
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(final_extents),
  )
  assert_eq(
    (
      @resources.ledger_usage(ledger).attempts,
      @resources.ledger_usage(ledger).live_reservations,
    ),
    (0, 1),
  )
}

///|
test "foreign original declaration Source refusal retains error backing and cannot reconcile success" {
  let program = funded_source_program()
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 500000L,
    execution_bytes: 500018L,
  }).unwrap()
  let input = ["foreign declaration original remains typed refusal"]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    Some(funded_value_cursor("{\"n\":{\"type\":\"number\"}}")),
    funded_value_limits(),
  ).unwrap()
  ignore(funded_source_declarations(owner))
  prepare_parameter_declaration_source(owner, program).unwrap()
  assert_true(
    parameter_declaration_source_outcome(owner)
    is Some(Err(ForeignDeclarations)),
  )
  assert_true(reconcile_parameter_declaration_source(owner) is Err(WrongPhase))
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  clear_parameter_declaration_preflight(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
}
