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
      @source_publication.prepared_published_request_copy_geometry(
        publication, environment,
      ).unwrap(),
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
test "source-free SQL keeps loose runtime maxima and refuses actual task allocation on its original Request" {
  // Same installed standard numeric profile selected by the public Node Host.
  let (environment, publication) = request_query_publication_fixture(
    numeric_profile_cid=Some(
      "sha256:d771391b2e4f3e52a3cf48810571a09c6c272df64fbb77c245dfabcf456be5df",
    ),
  )
  // Explicit empty provider port for these Core arithmetic tasks, not public
  // runtime acceptance. Full Plan maxima remain independently checked DATA;
  // actual task allocations keep this unchanged original finite policy.
  for
    (aggregate, count, exhaust) in [
      (false, 4, false),
      (false, 9, false),
      (true, 2, false),
      (true, 6, false),
      (true, 8, false),
      (false, 4, true),
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
    prepare_request_program_module_body(
      parent,
      input,
      request_program_module_contracts(),
      manifests=request_program_module_manifests(),
      compilation_limits=@publication_host.client_standard_pure_compilation_limits(),
      retained_output=true,
      provider_factory=_ => [],
    ).unwrap()
    let plan = parent.program_source_free.unwrap()
    let available = preparation_initial_limits(parent.initial, input).unwrap()
    let ledger = parent.ledger
    assert_true(plan.limits.retained_bytes <= available.retained_bytes)
    // A tighter selected provider quote can make the whole-Run maximum fit.
    // Neither case changes admission or prepays this test's actual task. The
    // dedicated oversized-Plan adoption fixture covers an explicit loose cap;
    // this execution keeps its original rows and exhausted-budget refusal.
    assert_true(parent.phase == ProgramBodyReady)
    assert_true(plan.compilation is Some(_))
    let request = @publication_host.prepare_source_free_client_request_identity(
      prepared,
      "sha256:" + "c".repeat(64),
      "capacity-original-task",
    ).unwrap()
    let run = begin_request_program_managed_run(parent, request).unwrap()
    assert_true(
      physical_equal(require_installed_managed_run(run).unwrap(), ledger),
    )
    let setup = open_installed_managed_source_free_host(
        run,
        prepared,
        request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let before = @resources.ledger_usage(ledger)
    let block = if exhaust {
      Some(
        @resources.reserve_capacity(
          ledger,
          0L,
          available.execution_bytes - before.reserved_execution_bytes,
        ).unwrap(),
      )
    } else {
      None
    }
    let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
      true
    })
    if exhaust {
      guard execution is Err(failure) else {
        fail(
          "actual task allocation must refuse exhausted execution before Start",
        )
      }
      assert_true(failure.issue is Driver(Execution(Physical(ExecutionLimit))))
      assert_true(retry_local_values_execution_failure_cleanup(failure))
      assert_eq(@resources.ledger_usage(ledger).attempts, before.attempts)
      assert_true(retire_installed_managed_run(run) is Err(CleanupPending))
      @resources.settle_capacity(ledger, block.unwrap()).unwrap()
    } else {
      let completed = execution.unwrap()
      let expected = if aggregate {
        ["{\"v\":" + (count * (count + 1) / 2).to_string() + "}"]
      } else {
        Array::makei(count, index => "{\"x\":" + (index + 1).to_string() + "}")
      }
      assert_eq(completed.rows().unwrap(), expected)
      assert_true(completed.close())
    }
    let attempts = @resources.ledger_usage(ledger).attempts
    assert_true(
      abort_request_preparation_after_cleanup(parent) is Err(WrongPhase),
    )
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(ledger).attempts, attempts)
    assert_eq(@resources.ledger_limits(ledger), available)
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
    assert_eq(@resources.ledger_usage(ledger).reserved_retention_bytes, 0L)
    assert_eq(@resources.ledger_usage(ledger).reserved_execution_bytes, 0L)
  }
}

///|
fn request_literal_publication_fixture() -> (
  @checked.CheckEnvironment,
  @source_publication.PreparedPublishedQueryEnvironment,
) {
  let body =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[{"catalog_cid":"sha256:d9dea9f5c7de6a8b98b44908feb04bfc2144841367de6c427b4e999d5bfd8b95","commands":[],"connector_id":"crm/main","connector_version":"fixture","contracts":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"},"region":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"}],"schema":"actql.connector_catalog/0.1","source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}]}],"contract_registry":[{"body":{},"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","kind":"carrier_facts","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"id":{"nullable":false,"type":"number"}},"nullable":false,"type":"object"},"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","kind":"carrier_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{"additional_properties":false,"fields":{"glob":{"nullable":true,"type":"string"},"paths":{"items":{"nullable":false,"type":"string"},"nullable":true,"type":"array"},"region":{"nullable":false,"type":"string"}},"nullable":false,"type":"object"},"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","kind":"request_schema","schema":"actql.contract/0.1","version":"fixture"},{"body":{},"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","kind":"pushdown","schema":"actql.contract/0.1","version":"fixture"},{"body":{"classification":"unknown","source_ref":"connector://crm/main/records#v","version":"actql-source-data-policy/0.1"},"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","kind":"data_policy","schema":"actql.contract/0.1","version":"fixture"}],"evidence_bundle_cid":"sha256:e7667ed7b3fbc887713dc45b63b96660ad8c73bb2b4808d866c831e840b835e1","host_policy_profile":{},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[{"acquisition":{"authority":"read_metadata","default_mode":"snapshot","kind":"scan","modes":[{"bounded":true,"mode":"snapshot"}],"request_schema":{"cid":"sha256:7d12104e6e0846b4389a80dcfec7921f718caff0b061fb8d4cb4d1202ba3155e","id":"member-0","version":"fixture"}},"connector_id":"crm/main","connector_version":"fixture","contract_cid":"sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75","output":{"carrier":"relation","data_policy":{"cid":"sha256:87ee88c2e3c1afb3af1db36ec6a57cb43bb161b1e39c113cd523ac6451a6847b","id":"member-4","version":"fixture"},"facts":{"cid":"sha256:013b48b152bc91b471ab1d8f07eac6673a9e9c0a69fe15d684380fb39dc27bf7","id":"member-2","version":"fixture"},"schema":{"cid":"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759","id":"member-1","version":"fixture"}},"pushdown":{"contract":{"cid":"sha256:4865d8d5fedb0d1cf12f78e31bfc23fef1d487ebbaf9ea0778adc171df0bfbbc","id":"member-3","version":"fixture"},"operations":[]},"request_processing":{"mutates_business_state":false},"resource_kind":"record","schema":"actql.source_view/0.1","view_id":"v","view_version":"fixture"}],"version":"actql-check-environment/0.1"}
  let wire = @environment.read(
    @utf8.encode(body),
    "sha256:e7667ed7b3fbc887713dc45b63b96660ad8c73bb2b4808d866c831e840b835e1",
    { max_bytes: 1048576, max_nodes: 16384, max_depth: 32, max_members: 32768, },
  ).unwrap()
  let environment = @checked.checking_environment(
    wire,
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  )
  let publication = @source_publication.prepare_published_query_environment(
    environment, "{\"environmentCid\":\"sha256:e7667ed7b3fbc887713dc45b63b96660ad8c73bb2b4808d866c831e840b835e1\",\"aliases\":[{\"name\":\"records\",\"sourceRef\":\"connector://crm/main/records#v\",\"sourceViewContractCid\":\"sha256:b844b32f283ef6077deb9ffd906da53679dd41f46607dbb3e0c8a48502164e75\",\"schemaContractCid\":\"sha256:918902ad5507c91441bf69c097259f7f3498aa1046161b5eba1f433550ed7759\",\"request\":{\"paths\":null,\"glob\":null,\"region\":\"europe\"}}]}",
  ).unwrap()
  (environment, publication)
}

///|
test "Request literal copies grow the original quote before repeated alias lowering" {
  let (environment, publication) = request_literal_publication_fixture()
  let catalog = @source_publication.prepared_published_query_catalog(
    publication, environment,
  ).unwrap()
  let geometry = @source_publication.prepared_published_request_copy_geometry(
    publication, environment,
  ).unwrap()
  for retention in [true, false] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let parsed = parse_request_query_syntax(
      parent,
      input,
      "SELECT l.id AS left_id, r.id AS right_id FROM records AS l CROSS JOIN records AS r",
      @frontend.Sql,
    ).unwrap()
    let syntax = parent.query_syntax.unwrap()
    let bytes = request_query_lowering_data_bytes(
      syntax,
      None,
      catalog,
      geometry,
    ).unwrap()
    let no_request = request_query_lowering_data_bytes(
      syntax,
      None,
      catalog,
      (0, 0L),
    ).unwrap()
    let tokens = @query_syntax.token_count(@query_syntax.query_source(parsed)).to_int64()
    let copied = (geometry.0.to_int64() + geometry.1) * tokens
    assert_eq(
      bytes - no_request,
      request_query_literal_copy_bytes(geometry, tokens.to_int()).unwrap(),
    )
    assert_true(copied > geometry.0.to_int64() + geometry.1)
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
    let original = parent.query_syntax.unwrap().lowering.unwrap()
    assert_true(original.output is None && parent.held_program is None)
    assert_eq(original.quote, (base.0 + bytes, base.1 + bytes))
    let foreign = request_literal_publication_fixture()
    assert_true(
      lower_request_published_query(parent, input, foreign.1, foreign.0, None)
      is Err(Request(ForeignOriginal)),
    )
    @resources.settle_capacity(parent.ledger, blocker).unwrap()
    let (lowered, original_catalog, _) = lower_request_published_query(
      parent,
      input,
      publication,
      environment,
      None,
    ).unwrap()
    assert_true(physical_equal(original_catalog, catalog))
    assert_true(
      physical_equal(parent.held_program.unwrap(), lowered.program.unwrap()),
    )
    assert_true(
      physical_equal(parent.query_syntax.unwrap().lowering.unwrap(), original),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "original standalone expression failure ignores unrelated publication filtering without rechecking" {
  let (environment, publication) = request_query_publication_fixture()
  let visible = " {\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  // Distinct retained publication bytes isolate the disclosure gate. The
  // ordinary HTTP regression separately exercises an actually hidden Source.
  assert_true(
    !@source_publication.prepared_published_query_environment_publication_matches(
      publication, environment, visible,
    ),
  )
  for
    (document, independent) in [
      ("SELECT missing AS n", true),
      ("SELECT missing AS n FROM records", false),
      ("SELECT missing + 1 AS n", false),
      ("WITH x AS (SELECT missing AS n) SELECT n FROM x", false),
      ("SELECT n FROM (SELECT missing AS n) AS x", false),
    ] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let original = parse_request_query_syntax(
      parent,
      input,
      document,
      @frontend.Sql,
    ).unwrap()
    let terminal = match
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
        public_primary=true,
      ) {
      Err(issue) => QueryLowering(issue)
      Ok(_) => fail("the authored unresolved expression must reject")
    }
    let selected = parent.query_syntax.unwrap()
    let parse_work = selected.known_work
    let before = @resources.ledger_usage(parent.ledger)
    let report = project_request_check_outcome(
        parent,
        input,
        terminal,
        visible,
        "ctx:" + "a".repeat(64),
        "text",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
      )
      .unwrap()
      .unwrap()
    if independent {
      assert_true(report.contains("\"verdict\":\"invalid\""), msg=report)
      assert_true(report.contains("query_expression_invalid"), msg=report)
      assert_true(report.contains("unknown_reference"), msg=report)
      assert_true(!report.contains("source_resolution"), msg=report)
    } else {
      assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
      assert_true(report.contains("source_resolution"), msg=report)
      assert_true(!report.contains("query_expression_invalid"), msg=report)
    }
    assert_true(parent.phase == QueryLoweringFailed)
    assert_true(physical_equal(parent.query_syntax.unwrap(), selected))
    assert_true(physical_equal(selected.query.unwrap().unwrap(), original))
    assert_eq(selected.known_work, parse_work)
    assert_eq(
      @resources.ledger_usage(parent.ledger).planning_work,
      before.planning_work,
    )
    assert_true(
      project_request_check_outcome(
        parent,
        [1],
        terminal,
        visible,
        "ctx:" + "a".repeat(64),
        "text",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
      )
      is Err(ForeignOriginal),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "original scalar implementation refusal uses only its same Source-independent parsed projection" {
  let (environment, publication) = request_query_publication_fixture()
  let visible = " {\"environmentCid\":\"" +
    @checked.checking_environment_cid(environment) +
    "\",\"aliases\":[]}"
  // Distinct retained publication bytes isolate the disclosure gate. The
  // ordinary HTTP regression separately exercises an actually hidden Source.
  assert_true(
    !@source_publication.prepared_published_query_environment_publication_matches(
      publication, environment, visible,
    ),
  )
  for
    (document, independent) in [
      ("SELECT UNKNOWN_FUNCTION(1) AS n", true),
      ("SELECT UNKNOWN_FUNCTION(1 + 2) AS n", true),
      ("SELECT UNKNOWN_FUNCTION(missing) AS n", false),
      ("SELECT UNKNOWN_FUNCTION(1) AS n FROM records", false),
      (
        "WITH x AS (SELECT 1 AS n) SELECT UNKNOWN_FUNCTION(1) AS n FROM x", false,
      ),
      ("SELECT UNKNOWN_FUNCTION(1) AS n WHERE TRUE", false),
      ("SELECT UNKNOWN_FUNCTION(1) AS n UNION ALL SELECT 1 AS n", false),
    ] {
    let input = [1]
    let parent = begin_request_preparation(
      request_parent_fixture(input),
      input,
      client_local_resource_policy(),
    ).unwrap()
    let original = parse_request_query_syntax(
      parent,
      input,
      document,
      @frontend.Sql,
    ).unwrap()
    let terminal = match
      lower_request_published_query(
        parent,
        input,
        publication,
        environment,
        None,
        public_primary=true,
      ) {
      Err(issue) => QueryLowering(issue)
      Ok(_) => fail("the original unsupported scalar must reject")
    }
    let selected = parent.query_syntax.unwrap()
    let parse_work = selected.known_work
    let before = @resources.ledger_usage(parent.ledger)
    let report = project_request_check_outcome(
        parent,
        input,
        terminal,
        visible,
        "ctx:" + "a".repeat(64),
        "text",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
      )
      .unwrap()
      .unwrap()
    if independent {
      assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
      assert_true(report.contains("implementation_limit"), msg=report)
      assert_true(!report.contains("source_resolution"), msg=report)
    } else {
      assert_true(report.contains("\"verdict\":\"undetermined\""), msg=report)
      assert_true(report.contains("source_resolution"), msg=report)
      assert_true(!report.contains("implementation_limit"), msg=report)
    }
    assert_true(parent.phase == QueryLoweringFailed)
    assert_true(physical_equal(parent.query_syntax.unwrap(), selected))
    assert_true(physical_equal(selected.query.unwrap().unwrap(), original))
    assert_eq(selected.known_work, parse_work)
    assert_eq(
      @resources.ledger_usage(parent.ledger).planning_work,
      before.planning_work,
    )
    assert_true(
      project_request_check_outcome(
        parent,
        [1],
        terminal,
        visible,
        "ctx:" + "a".repeat(64),
        "text",
        "rev:" + "b".repeat(64),
        document.length(),
        None,
        0,
        None,
        0,
        "corr:" + "c".repeat(32),
        None,
      )
      is Err(ForeignOriginal),
    )
    abort_request_preparation_after_cleanup(parent).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}
