///|
fn request_query_publication_fixture(
  numeric_profile_cid? : String? = None,
) -> (
  @checked.CheckEnvironment,
  @source_publication.PreparedPublishedQueryEnvironment,
) {
  let assets = @publication_host.client_local_product_assets()
  let environment = @publication_host.admit_client_check_environment(
    assets.environment,
    "sha256:2217670f3f4f54047e764878501863d4eaf37cf069ab741d7306a9d8985cc94f",
    { text_time: true, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
    numeric_profile_cid~,
  ).unwrap()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  (environment, publication)
}

///|
test "Request original Query lowers once and hands the same Program and Catalog to the checker" {
  let (environment, publication) = request_query_publication_fixture()
  for
    (document, format, declarations) in [
      ("SELECT @n AS n", @frontend.Sql, Some("{\"n\":{\"type\":\"number\"}}")),
      (
        "WITH seed AS (SELECT 1 AS n) FROM seed |> SELECT n",
        @frontend.Text,
        None,
      ),
    ] {
    let input = [1]
    let calls = Ref(0)
    let action : Ref[(() -> Unit)?] = Ref(None)
    let flags = Ref(0)
    let parent = begin_request_preparation(
      request_parent_fixture(input, current=() => {
        calls.val += 1
        if action.val is Some(run) {
          run()
        }
        true
      }),
      input,
      client_local_resource_policy(),
    ).unwrap()
    reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
    let query = parse_request_query_syntax(parent, input, document, format).unwrap()
    action.val = Some(() => {
      if lower_request_published_query(
          parent, input, publication, environment, declarations,
        )
        is Err(Request(WrongPhase)) {
        flags.val += 1
      }
      if abort_request_preparation_after_cleanup(parent) is Err(WrongPhase) {
        flags.val += 2
      }
    })
    let before = calls.val
    let original = lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      declarations,
      public_primary=true,
    ).unwrap()
    action.val = None
    assert_eq(calls.val - before, 1)
    assert_eq(flags.val, 3)
    assert_true(
      physical_equal(
        parent.query_syntax.unwrap().query.unwrap().unwrap(),
        query,
      ),
    )
    let program = original.0.program.unwrap()
    assert_true(physical_equal(parent.held_program.unwrap(), program))
    assert_true(
      physical_equal(
        prepared_request_query_lowering(parent, input).unwrap().0.program.unwrap(),
        program,
      ),
    )
    assert_eq(calls.val - before, 1)
    assert_true(
      lower_request_published_query(
        parent, input, publication, environment, declarations,
      )
      is Err(Request(WrongPhase)),
    )
    let supplied = @decode.admit_raw_json(
      @json.parse("{\"n\":7}"),
      @decode.cursor_span(@syntax.program_body(program)),
      @publication_host.client_standard_program_preparation_limits().checking.input.tree,
    ).unwrap()
    let before_check = calls.val
    let child = prepare_request_program_check_preparation(
      parent,
      input,
      environment,
      Some(supplied),
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    ).unwrap()
    assert_eq(calls.val - before_check, 1)
    assert_true(physical_equal(child.arguments.unwrap().program, program))
    assert_true(
      physical_equal(child.arguments.unwrap().supplied.unwrap(), supplied),
    )
    assert_true(
      physical_equal(
        child.arguments.unwrap().source_catalog.unwrap(),
        original.1,
      ),
    )
    prepare_program_check_input(child).unwrap()
    assert_true(physical_equal(child.check_input.unwrap().program, program))
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_true(parent.query_syntax is None && parent.held_program is None)
  }
}

///|
test "Request query lowerer keeps original quote through short grows and typed late refusal" {
  let (environment, publication) = request_query_publication_fixture()
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    parse_request_query_syntax(parent, input, "SELECT 1 AS n", @frontend.Sql).unwrap()
    |> ignore
    let catalog = @source_publication.prepared_published_query_catalog(
      publication, environment,
    ).unwrap()
    let bytes = request_query_lowering_data_bytes(
      parent.query_syntax.unwrap(),
      None,
      catalog,
    ).unwrap()
    let base = @resources.preparation_capacity_working_extents(
      parent.capacity,
      input,
    ).unwrap()
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - base.0 - bytes + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - base.1 - bytes + 1L
      },
    ).unwrap()
    assert_true(
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
      )
      is Err(Request(Capacity(_))),
    )
    let selected = parent.query_syntax.unwrap().lowering.unwrap()
    assert_true(parent.phase == QueryLoweringQuoted && selected.output is None)
    assert_true(
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        Some("{}"),
      )
      is Err(Request(ForeignOriginal)),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    lower_request_published_query(parent, input, publication, environment, None).unwrap()
    |> ignore
    assert_true(
      physical_equal(parent.query_syntax.unwrap().lowering.unwrap(), selected),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
  let input = [1]
  let parent = begin_request_preparation(
    request_parent_fixture(input),
    input,
    client_local_resource_policy(),
  ).unwrap()
  parse_request_query_syntax(
    parent,
    input,
    "SELECT id FROM unknown_input",
    @frontend.Sql,
  ).unwrap()
  |> ignore
  assert_true(
    lower_request_published_query(parent, input, publication, environment, None)
    is Err(Publication(_)),
  )
  assert_true(
    parent.phase == QueryLoweringFailed && parent.held_program is None,
  )
  assert_true(
    lower_request_published_query(parent, input, publication, environment, None)
    is Err(Request(WrongPhase)),
  )
  abort_request_preparation_after_cleanup(parent).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "Request lowered SQL keeps its original checker compiler Plan and Run through final body retirement" {
  let (environment, publication) = request_query_publication_fixture()
  let input = [1]
  let calls = Ref(0)
  let parent = begin_request_preparation(
    request_parent_fixture(input, current=() => {
      calls.val += 1
      true
    }),
    input,
    client_local_resource_policy(),
  ).unwrap()
  reserve_request_snapshot(parent, input, 100L, 100L).unwrap()
  parse_request_query_syntax(parent, input, "SELECT @n AS n", @frontend.Sql).unwrap()
  |> ignore
  let (lowered, catalog, _) = lower_request_published_query(
    parent,
    input,
    publication,
    environment,
    Some("{\"n\":{\"type\":\"number\"}}"),
    public_primary=true,
  ).unwrap()
  let program = lowered.program.unwrap()
  let supplied = @decode.admit_raw_json(
    @json.parse("{\"n\":7}"),
    @decode.cursor_span(@syntax.program_body(program)),
    @publication_host.client_standard_program_preparation_limits().checking.input.tree,
  ).unwrap()
  let child = prepare_request_program_check_preparation(
    parent,
    input,
    environment,
    Some(supplied),
    [],
    @publication_host.client_standard_program_preparation_limits().checking,
  ).unwrap()
  assert_true(
    physical_equal(child.arguments.unwrap().source_catalog.unwrap(), catalog),
  )
  prepare_program_check_input(child).unwrap()
  prepare_program_check_prelude(child).unwrap() |> ignore
  prepare_program_check_registry(child).unwrap() |> ignore
  prepare_program_check_contents(child).unwrap() |> ignore
  prepare_program_check_references(child).unwrap() |> ignore
  prepare_program_check_policies(child).unwrap() |> ignore
  prepare_program_check_values(child).unwrap() |> ignore
  prepare_program_check_views(child).unwrap() |> ignore
  prepare_program_check_carriers(child).unwrap() |> ignore
  prepare_program_check_requests(child).unwrap() |> ignore
  reconcile_program_check_requests(child).unwrap()
  guard finish_program_check_preparation(child).unwrap()
    is @checked.Checked(checked) else {
    fail("the original bound SQL must finish its existing checker")
  }
  assert_true(physical_equal(@checked.checked_source_program(checked), program))
  let prepared = compile_program_check_preparation(
    child,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  assert_true(
    physical_equal(
      continue_request_program_preparation(parent, input).unwrap(),
      prepared,
    ),
  )
  assert_true(
    compile_program_check_preparation(
      child,
      @publication_host.client_standard_program_preparation_limits(),
    )
    is Err(WrongPhase),
  )
  reserve_request_program_plan(parent, input).unwrap()
  let plan = request_program_installed_plan(prepared)
  complete_request_program_preparation(parent, input, plan).unwrap()
  let holder = borrow_request_program_preparation(parent).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "c".repeat(64),
    "original-query-request",
  ).unwrap()
  let before = calls.val
  let run = begin_request_program_managed_run(parent, request).unwrap()
  assert_eq(calls.val - before, 1)
  assert_true(
    parent.phase == Selected &&
    parent.query_syntax is None &&
    parent.held_program is None &&
    parent.input is None,
  )
  assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
  assert_true(@resources.preparation_body_retirement_started(holder))
  @resources.return_preparation_body_borrow(holder).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  let final_usage = @resources.ledger_usage(parent.ledger)
  assert_eq(final_usage.live_reservations, 0)
  assert_eq(final_usage.reserved_retention_bytes, 0L)
  assert_eq(final_usage.reserved_execution_bytes, 0L)
}

///|
test "source-free SQL capacity is refused before module completion on its original Request" {
  // Same installed standard numeric profile selected by the public Node Host.
  let (environment, publication) = request_query_publication_fixture(
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  )
  // Component fixture with an explicit empty provider port, not public runtime
  // acceptance. Keep the original policy and exact original Plan comparison.
  // Bounded leaf constructors reduce the quote: use longer same-form inputs
  // for the independent over-budget controls, not a language branch limit.
  for
    (aggregate, count, fits) in [
      (false, 4, true),
      (false, 9, false),
      (true, 2, true),
      (true, 6, false),
      (true, 8, false),
    ] {
    let branches = []
    for i in 0..<count {
      branches.push("SELECT " + (i + 1).to_string() + " AS x")
    }
    let query = "SELECT " +
      (if aggregate { "SUM(x) AS v" } else { "x" }) +
      " FROM (" +
      branches.join(" UNION ALL ") +
      ")"
    let input = [count]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    reserve_request_snapshot(parent, input, 1000L, 1000L).unwrap()
    parse_request_query_syntax(parent, input, query, @frontend.Sql).unwrap()
    |> ignore
    lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
      public_primary=true,
    ).unwrap()
    |> ignore
    let child = prepare_request_program_check_preparation(
      parent,
      input,
      environment,
      None,
      [],
      @publication_host.client_standard_program_preparation_limits().checking,
    ).unwrap()
    prepare_program_check_input(child).unwrap()
    prepare_program_check_prelude(child).unwrap() |> ignore
    prepare_program_check_registry(child).unwrap() |> ignore
    prepare_program_check_contents(child).unwrap() |> ignore
    prepare_program_check_references(child).unwrap() |> ignore
    prepare_program_check_policies(child).unwrap() |> ignore
    prepare_program_check_values(child).unwrap() |> ignore
    prepare_program_check_views(child).unwrap() |> ignore
    prepare_program_check_carriers(child).unwrap() |> ignore
    prepare_program_check_requests(child).unwrap() |> ignore
    reconcile_program_check_requests(child).unwrap()
    match finish_program_check_preparation(child).unwrap() {
      @checked.Checked(_) => ()
      @checked.NeedsInputs(_) => fail("boundary fixture needs inputs: " + query)
      @checked.Rejected(_) => fail("boundary fixture rejected: " + query)
    }
    let prepared = compile_program_check_preparation(
      child,
      @publication_host.client_standard_program_preparation_limits(),
    ).unwrap()
    continue_request_program_preparation(parent, input).unwrap() |> ignore
    let result = prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=_ => [],
    )
    let plan = parent.program_source_free.unwrap()
    let available = preparation_initial_limits(parent.initial, input).unwrap()
    println(
      "SQL_PLAN_CAPACITY aggregate=\{aggregate} branches=\{count} retained=\{plan.limits.retained_bytes} execution=\{plan.limits.execution_bytes} available=\{available.execution_bytes}",
    )
    assert_true(plan.limits.retained_bytes <= available.retained_bytes)
    if fits {
      result.unwrap()
      assert_true(plan.limits.execution_bytes <= available.execution_bytes)
      assert_true(parent.phase == ProgramBodyReady)
    } else {
      guard result is Err(CapacityExceeded(facts)) else {
        fail("the exact original over-budget Plan must have a typed refusal")
      }
      assert_eq(facts.phase, "source_free_plan")
      assert_eq(facts.dimension, "execution")
      assert_eq(facts.required_retention, plan.limits.retained_bytes)
      assert_eq(facts.required_execution, plan.limits.execution_bytes)
      assert_eq(facts.available_retention, available.retained_bytes)
      assert_eq(facts.available_execution, available.execution_bytes)
      assert_true(facts.required_execution > facts.available_execution)
      assert_false(parent.phase == ProgramBodyReady)
      assert_true(plan.compilation is None)
      let request = @publication_host.prepare_source_free_client_request_identity(
        prepared,
        "sha256:" + "c".repeat(64),
        "capacity-refused-original",
      ).unwrap()
      assert_true(
        begin_request_program_managed_run(parent, request)
        is Err(ForeignOriginal),
      )
    }
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_retention_bytes,
      0L,
    )
    assert_eq(
      @resources.ledger_usage(parent.ledger).reserved_execution_bytes,
      0L,
    )
  }
}
