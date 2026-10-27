///|
extern "js" fn source_current_stop() -> Unit =
  #|() => {throw new Error('SourceCurrentStopped');}

///|
fn source_current_fixture(
  current : () -> Unit,
) -> (
  ClientParameterDeclarationPreflight[Array[Int], Array[Int]],
  @syntax.Program,
) {
  let program = funded_source_program()
  let input = [1]
  // Existing real preparation-purpose Node original, not fabricated ports.
  // This is still an explicit Resource component, not a normal Host or a
  // physical first-entry supplier for the parser/borrowed Program backing.
  let original = closed_module_test_original(
    publication_test_loader(publication_test_url()),
    () => input,
    () => [7L, 2L, 0L, 0L, 500000L, 500018L],
    current,
  )
  let initial = @resources.prepare_node_local_preparation_admission(
    original, input,
  ).unwrap()
  let ledger = @resources.start_node_preparation_admission(initial).unwrap()
  let capacity : @resources.PreparationCapacity[Array[Int], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let params = @decode.lookup(
    @decode.open_object(@syntax.program_body(program)).unwrap(),
    "params",
  )
  let owner = begin_parameter_declaration_preflight(
    capacity,
    input,
    params,
    funded_value_limits(),
  ).unwrap()
  prepare_parameter_declaration_preflight(owner).unwrap()
  let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
  reconcile_parameter_declaration_preflight(owner).unwrap()
  prepare_parameter_declaration_header(owner).unwrap()
  prepare_parameter_declaration_inventory(owner).unwrap()
  reconcile_parameter_declaration_inventory(owner).unwrap()
  while @parameters.declaration_read_phase(reader) !=
        @parameters.DeclarationComplete {
    match @parameters.declaration_read_phase(reader) {
      @parameters.DeclarationType =>
        prepare_parameter_declaration_type(owner).unwrap()
      @parameters.DeclarationValue =>
        prepare_parameter_declaration_value(owner).unwrap()
      _ => abort("original declaration phase")
    }
  }
  reconcile_parameter_declarations(owner).unwrap()
  (owner, program)
}

///|
test "actual original Source current callback occurs once and synchronous reentry cannot retire or duplicate construction" {
  let calls = Ref(0)
  let flags = Ref(0)
  let action : Ref[(() -> Unit)?] = Ref(None)
  let (owner, program) = source_current_fixture(() => {
    calls.val += 1
    if action.val is Some(run) {
      run()
    }
  })
  action.val = Some(() => {
    if clear_parameter_declaration_preflight(owner) is Err(WrongPhase) {
      flags.val += 1
    }
    if prepare_parameter_declaration_source(owner, program) is Err(WrongPhase) {
      flags.val += 2
    }
    if parameter_declaration_source_outcome(owner) is None {
      flags.val += 4
    }
  })
  let before = calls.val
  prepare_parameter_declaration_source(owner, program).unwrap()
  action.val = None
  assert_eq(calls.val - before, 1)
  assert_eq(flags.val, 7)
  assert_true(parameter_declaration_source_outcome(owner) is Some(Ok(_)))
  clear_parameter_declaration_preflight(owner).unwrap()
}

///|
test "actual original stopping Source callback refuses before construction and preserves original reader and debit" {
  let calls = Ref(0)
  let stop = Ref(false)
  let (owner, program) = source_current_fixture(() => {
    calls.val += 1
    if stop.val {
      source_current_stop()
    }
  })
  let reader = parameter_declaration_preflight_outcome(owner).unwrap().0.unwrap()
  let before = @resources.preparation_capacity_working_extents(
    owner.capacity,
    owner.input.unwrap(),
  ).unwrap()
  let count = calls.val
  stop.val = true
  assert_true(
    prepare_parameter_declaration_source(owner, program)
    is Err(Capacity(Resource(ClosedReservation))),
  )
  assert_eq(calls.val - count, 1)
  assert_true(parameter_declaration_source_outcome(owner) is None)
  assert_eq(
    @parameters.declaration_read_phase(reader),
    @parameters.DeclarationComplete,
  )
  assert_eq(
    @resources.preparation_capacity_working_extents(
      owner.capacity,
      owner.input.unwrap(),
    ),
    Ok(before),
  )
  clear_parameter_declaration_preflight(owner).unwrap()
}
