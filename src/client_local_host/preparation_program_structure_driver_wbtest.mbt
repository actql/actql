///|
fn structure_original_fixture(
  wire : String,
) -> (
  ClientProgramJsonPreparation[Array[String], Array[Int]],
  @resources.Ledger,
  @resources.PreparationCapacity[Array[String], Array[Int]],
  Array[String],
) raise {
  let ledger = @resources.create_ledger({
    planning_work: 7,
    attempts: 2,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 10000000L,
    execution_bytes: 10000000L,
  }).unwrap()
  let input = [wire]
  let capacity : @resources.PreparationCapacity[Array[String], Array[Int]] = @resources.reserve_preparation_capacity(
    ledger,
    input,
    73L,
    91L,
    max_borrowers=1,
  ).unwrap()
  let owner = begin_program_json_preparation(
    capacity,
    input,
    wire,
    funded_json_bounds(),
  ).unwrap()
  let _ = funded_json_ready(owner)
  finish_program_json_preparation(owner).unwrap()
  (owner, ledger, capacity, input)
}

///|
test "same original funded index constructs general Unicode Program and transfers once" {
  let wire =
    #|{"version":"actql/0.1","id":"e\u0301","params":{"nested":{"a":[1,null,"é"]}},"stages":[{"id":"parent","inputs":{"crm":"source:remote.crm"},"steps":[],"results":{"rows":{"from":"crm"}},"effects":{"save":{"update":{"set":{"field":{"literal":{"e\u0301":1}}}}}}},{"id":"child","after":"accepted","inputs":{"data":{"result":{"stage":"parent","result":"rows"}}},"steps":[],"results":{"rows":{"from":"data"}}}],"results":{"one":{"from":{"stage":"child","result":"rows"}},"two":{"from":{"stage":"parent","result":"rows"}}}}
  let (owner, ledger, capacity, input) = structure_original_fixture(wire)
  let original = owner.indexed.unwrap()
  construct_program_json_preparation(owner).unwrap()
  assert_true(physical_equal(original, owner.indexed.unwrap()))
  let observed = owner.structure.unwrap()
  assert_eq(observed.retained.stage_records, 2)
  assert_eq(observed.retained.export_tuples, 2)
  assert_true(
    observed.inspection_work <
    @syntax.program_constructor_inspection_work_bound(original),
  )
  assert_true(owner.work is None)
  assert_true(
    @resources.begin_preparation_phase_work64(
      capacity,
      input,
      @resources.ProgramStructure,
      1L,
    )
    is Err(AlreadyClaimed),
  )
  {
    let program = take_program_json_preparation_program(owner).unwrap()
    assert_eq(program.id, "é")
    assert_eq(@syntax.stage_count(program), 2)
    assert_eq(@syntax.export_count(program), 2)
    clear_program_json_preparation(owner).unwrap()
    assert_eq(@syntax.stages(program)[0].id, "parent")
    assert_true(take_program_json_preparation_program(owner) is Err(WrongPhase))
  }
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 73L)
  assert_eq(@resources.ledger_usage(ledger).planning_work, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "same Program observation survives one-short construction grow without replay or parent reset" {
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"e\\u0301\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[{}],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let (probe, _, probe_capacity, probe_input) = structure_original_fixture(wire)
  construct_program_json_preparation(probe).unwrap()
  let (required_r, required_e) = @resources.preparation_capacity_working_extents(
    probe_capacity, probe_input,
  ).unwrap()
  clear_program_json_preparation(probe).unwrap()
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(
      probe_capacity, probe_input,
    ).unwrap(),
  )
  for retention in [true, false] {
    let (owner, ledger, capacity, input) = structure_original_fixture(wire)
    let original = owner.indexed.unwrap()
    let limits = @resources.ledger_limits(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes - required_r + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - required_e + 1L
      },
    ).unwrap()
    let result = construct_program_json_preparation(owner)
    if retention {
      assert_true(result is Err(Capacity(Resource(RetentionLimit))))
    } else {
      assert_true(result is Err(Capacity(Resource(ExecutionLimit))))
    }
    assert_true(owner.phase == Inspected)
    assert_true(owner.program is None && owner.work is None)
    assert_true(physical_equal(original, owner.indexed.unwrap()))
    let observed = owner.structure.unwrap()
    let quote = owner.structure_quote.unwrap()
    @resources.settle_capacity(ledger, blocker).unwrap()
    construct_program_json_preparation(owner).unwrap()
    assert_true(physical_equal(observed, owner.structure.unwrap()))
    assert_true(physical_equal(quote, owner.structure_quote.unwrap()))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((required_r, required_e)),
    )
    assert_true(construct_program_json_preparation(owner) is Err(WrongPhase))
    clear_program_json_preparation(owner).unwrap()
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
    )
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
test "general Program constructor keeps original typed structural refusal and retired input fence" {
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[],\"results\":{}}"
  let (owner, ledger, capacity, input) = structure_original_fixture(wire)
  assert_true(
    construct_program_json_preparation(owner)
    is Err(Syntax(Structure(EmptyStages, ..))),
  )
  assert_true(
    owner.indexed is Some(_) && owner.program is None && owner.work is None,
  )
  assert_true(take_program_json_preparation_program(owner) is Err(WrongPhase))
  clear_program_json_preparation(owner).unwrap()
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
  let (stopped, _, capacity, input) = structure_original_fixture(wire)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
  assert_true(construct_program_json_preparation(stopped) is Err(Capacity(_)))
  assert_true(stopped.structure is None && stopped.work is None)
  clear_program_json_preparation(stopped).unwrap()
}

///|
test "public generic structure reconciliation keeps same original Program and one retained handoff" {
  let wire = "{\"version\":\"actql/0.1\",\"id\":\"é\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"out\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
  let (owner, ledger, capacity, input) = structure_original_fixture(wire)
  construct_program_json_preparation(owner).unwrap()
  let original = owner.program.unwrap()
  let indexed = owner.indexed.unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  reconcile_program_json_preparation_structure(owner).unwrap()
  let after = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  assert_eq(after.0, before.0)
  assert_true(after.1 < before.1)
  assert_true(physical_equal(original, owner.program.unwrap()))
  assert_true(physical_equal(indexed, owner.indexed.unwrap()))
  assert_true(owner.phase == RetainedProgram)
  assert_true(
    reconcile_program_json_preparation_structure(owner) is Err(WrongPhase),
  )
  let program = take_program_json_preparation_program(owner).unwrap()
  assert_true(physical_equal(original, program))
  assert_eq(program.id, "é")
  assert_true(take_program_json_preparation_program(owner) is Err(WrongPhase))
  clear_program_json_preparation(owner).unwrap()
  assert_true(@resources.ledger_usage(ledger).reserved_retention_bytes > 73L)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}
