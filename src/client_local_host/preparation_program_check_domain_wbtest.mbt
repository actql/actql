///|
fn catalog_domain_environment() -> @checked.CheckEnvironment {
  let assets = @publication_host.client_local_product_assets()
  @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn catalog_domain_fixture() -> (
  ClientProgramCheckPreparation[Array[String], Array[Int]],
  @resources.Ledger,
  @resources.PreparationCapacity[Array[String], Array[Int]],
  Array[String],
) raise {
  let wire =
    #|{"version":"actql/0.1","id":"p","stages":[{"id":"a","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[]},"as":"v"}],"results":{"r":{"from":"v","fields":["id"]}}},{"id":"b","inputs":{"rows":{"result":{"stage":"a","result":"r"}}},"steps":[{"take":1,"as":"t"}],"results":{"r":{"from":"t","fields":["id"]}}}],"results":{"out":{"from":{"stage":"b","result":"r"}}}}
  let (source, ledger, capacity, input) = structure_original_fixture(wire)
  construct_program_json_preparation(source).unwrap()
  let program = take_program_json_preparation_program(source).unwrap()
  clear_program_json_preparation(source).unwrap()
  let owner = begin_program_check_preparation(
    capacity,
    input,
    program,
    catalog_domain_environment(),
    None,
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  (owner, ledger, capacity, input)
}

///|
test "later Catalog domain preserves Source-only packet and funds every original reader on the same parent" {
  assert_eq(program_json_initial_control_bytes, 21216L)
  let initial = program_check_preparation_initial_inventory()
  assert_eq(
    (initial.record_headers, initial.reference_slots, initial.scalar_words),
    (1324L, 697L, 2634L),
  )
  assert_eq(program_check_initial_control_bytes, 47832L)
  assert_eq(program_check_input_observer_bytes, 568L)
  let (owner, ledger, capacity, input) = catalog_domain_fixture()
  let arguments = owner.arguments.unwrap()
  let original_program = arguments.program
  prepare_program_check_input(owner).unwrap()
  assert_true(owner.work is None)
  let captured = owner.check_input.unwrap()
  assert_true(physical_equal(captured.program, original_program))
  assert_true(physical_equal(captured.environment, arguments.environment))
  let (r, e) = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  // Independent two-Stage binder9248, current original input holder72,
  // actual observation568, plus the unchanged outside and later domain packet.
  assert_eq(
    (r, e),
    (
      owner.base_retained + 47832L + 9888L,
      owner.base_execution + 47832L + 9888L,
    ),
  )
  prepare_program_check_prelude(owner).unwrap() |> ignore
  let original = prepare_program_check_registry(owner).unwrap()
  for step in [0, 1, 2, 3, 4, 5, 6] {
    let actual = match step {
      0 => prepare_program_check_contents(owner).unwrap()
      1 => prepare_program_check_references(owner).unwrap()
      2 => prepare_program_check_policies(owner).unwrap()
      3 => prepare_program_check_values(owner).unwrap()
      4 => prepare_program_check_views(owner).unwrap()
      5 => prepare_program_check_carriers(owner).unwrap()
      _ => prepare_program_check_requests(owner).unwrap()
    }
    assert_true(physical_equal(original, actual))
    assert_true(owner.work is None)
  }
  reconcile_program_check_requests(owner).unwrap()
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  {
    let transferred = take_program_check_registry(owner).unwrap()
    assert_true(physical_equal(transferred, original))
    assert_true(take_program_check_registry(owner) is Err(WrongPhase))
    clear_program_check_preparation(owner).unwrap()
    assert_true(
      @checked.parsed_check_registry_remaining_work(transferred) is Ok(_),
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok(before),
    )
  }
  assert_eq(@resources.ledger_usage(ledger).planning_work, 0)
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  // Explicit Core component teardown, not backend/physical-close evidence.
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "binding one-short preserves the original observation and quote without refilling closed work" {
  for retention in [true, false] {
    let (owner, ledger, capacity, input) = catalog_domain_fixture()
    let r = owner.base_retained + 47832L + 9888L
    let e = owner.base_execution + 47832L + 9888L
    let limits = @resources.ledger_limits(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes - r + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - e + 1L
      },
    ).unwrap()
    let failed = prepare_program_check_input(owner)
    assert_true(
      if retention {
        failed is Err(Capacity(Resource(RetentionLimit)))
      } else {
        failed is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_true(owner.phase == BindingQuoted && owner.check_input is None)
    let inventory = owner.binding_inventory.unwrap()
    let quote = owner.binding_quote.unwrap()
    assert_true(owner.work is None)
    assert_true(
      @resources.begin_preparation_phase_work64(
        capacity,
        input,
        @resources.CapacityInputInspection,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    @resources.settle_capacity(ledger, blocker).unwrap()
    prepare_program_check_input(owner).unwrap()
    assert_true(physical_equal(inventory, owner.binding_inventory.unwrap()))
    assert_true(physical_equal(quote, owner.binding_quote.unwrap()))
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((r, e)),
    )
    assert_true(
      @resources.begin_preparation_phase_work64(
        capacity,
        input,
        @resources.CapacityInputInspection,
        1L,
      )
      is Err(AlreadyClaimed),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
    )
  }
}

///|
test "later domain foreign input and typed binder refusal retain the original parent and cleanup duties" {
  let (owner, ledger, capacity, input) = catalog_domain_fixture()
  owner.input = Some(input.copy())
  assert_true(
    prepare_program_check_input(owner) is Err(Capacity(ForeignOriginal)),
  )
  assert_true(owner.check_input is None && owner.work is None)
  owner.input = Some(input)
  let original = owner.arguments.unwrap()
  owner.arguments = Some({
    ..original,
    limits: {
      ..original.limits,
      compilation: { ..original.limits.compilation, work: 11, },
    },
  })
  assert_true(
    prepare_program_check_input(owner)
    is Err(Check(CapacityInputs(BudgetExceeded))),
  )
  assert_true(
    owner.phase == Failed && owner.work is None && owner.check_input is None,
  )
  assert_true(take_program_check_input(owner) is Err(WrongPhase))
  let before = @resources.preparation_capacity_working_extents(capacity, input).unwrap()
  clear_program_check_preparation(owner).unwrap()
  assert_eq(
    @resources.preparation_capacity_working_extents(capacity, input),
    Ok(before),
  )
  assert_eq(@resources.ledger_usage(ledger).attempts, 0)
  assert_true(
    @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
  )
}

///|
test "later Catalog packet one-short refuses before constructing controls and adds the packet once" {
  for retention in [true, false] {
    let wire = "{\"version\":\"actql/0.1\",\"id\":\"p\",\"stages\":[{\"id\":\"s\",\"inputs\":{},\"steps\":[],\"results\":{\"r\":{}}}],\"results\":{\"r\":{\"from\":{\"stage\":\"s\",\"result\":\"r\"}}}}"
    let (source, ledger, capacity, input) = structure_original_fixture(wire)
    construct_program_json_preparation(source).unwrap()
    let program = take_program_json_preparation_program(source).unwrap()
    clear_program_json_preparation(source).unwrap()
    let (r, e) = @resources.preparation_capacity_working_extents(
      capacity, input,
    ).unwrap()
    let limits = @resources.ledger_limits(ledger)
    let blocker = @resources.reserve_capacity(
      ledger,
      if retention {
        limits.retained_bytes - r - 47832L + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - e - 47832L + 1L
      },
    ).unwrap()
    let attempt = begin_program_check_preparation(
      capacity,
      input,
      program,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    )
    assert_true(
      if retention {
        attempt is Err(Capacity(Resource(RetentionLimit)))
      } else {
        attempt is Err(Capacity(Resource(ExecutionLimit)))
      },
    )
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((r, e)),
    )
    @resources.settle_capacity(ledger, blocker).unwrap()
    let owner = begin_program_check_preparation(
      capacity,
      input,
      program,
      catalog_domain_environment(),
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    ).unwrap()
    assert_eq(
      @resources.preparation_capacity_working_extents(capacity, input),
      Ok((r + 47832L, e + 47832L)),
    )
    clear_program_check_preparation(owner).unwrap()
    assert_true(
      @resources.abort_preparation_capacity_after_cleanup(capacity, input).unwrap(),
    )
  }
}
