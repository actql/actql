///|
let installed_query_tasks_document : String =
  #|{"version":"actql/0.1","id":"same-original-query-join","stages":[{"id":"left","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"right","inputs":{"remote":{"connector":"pure-provider","resource":"records"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"joined","inputs":{"left":{"result":{"stage":"left","result":"rows"}},"right":{"result":{"stage":"right","result":"rows"}}},"steps":[{"from":"left","join":{"with":"right","kind":"inner","on":[{"left":"id","right":"id"}],"select":{"id":"left.id"},"max_output_rows":4},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"rows":{"from":{"stage":"joined","result":"rows"}}}}

///|
// Actual Request/check/Query acquisitions and managed RowRun originals. The
// existing explicit component admission is not a physical Native/Account grant.
priv struct InstalledQueryTasksFixture {
  parent : ClientRequestPreparation[Array[Int]]
  owner : ClientInstalledManagedRun
  plan : ClientInstalledManagedCapturePlan
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  captures : Array[@row_source_host.RowSourceCapture]
  controls : @resources.CapacityReservation
  ledger : @resources.Ledger
  verify_hooks : Array[Ref[(() -> Unit)?]]
}

///|
fn installed_query_tasks_fixture(
  request_protocols? : Bool = false,
) -> InstalledQueryTasksFixture raise {
  let declaration = pure_provider_declaration()
  let environment = pure_provider_environment(declaration)
  let (parent, child, _, input) = registration_parent_fixture(
    text=installed_query_tasks_document,
    environment=Some(environment),
  )
  guard finish_program_check_preparation(child).unwrap() is @checked.Checked(_) else {
    fail("original Query fixture must check")
  }
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
  reserve_request_program_plan(parent, input).unwrap()
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "same-original-query-join",
  ).unwrap()
  let contracts = prepare_installed_sequence_contracts(
    source_query_original_registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  ).unwrap()
  let original_protocols = if request_protocols {
    let (protocols, direct) = admit_request_query_acquisition_contracts(
      parent, input, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
    ).unwrap()
    assert_eq(
      @publication_host.client_direct_acquisition_occurrence_count(direct),
      2,
    )
    assert_true(
      @publication_host.client_direct_acquisition_occurrences_match_program(
        direct, prepared,
      ),
    )
    Some(protocols)
  } else {
    None
  }
  let acquisitions = [0, 1].map(stage => {
    let requirement = prepare_local_query_requirement(
      prepared,
      stage,
      0,
      contracts,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap()
    match original_protocols {
      None =>
        @row_source_host.prepare_row_acquisition(
          declaration, requirement, original_row_query_contract_fixture, original_row_evidence_contract_fixture,
        ).unwrap()
      Some(protocols) =>
        @row_source_host.prepare_declared_row_acquisition_with_contracts(
          @row_source_host.prepare_row_source(requirement, declaration).unwrap(),
          declaration.connector_registration,
          protocols,
        ).unwrap()
    }
  })
  let plan = prepare_installed_managed_capture_plan(
    prepared,
    request,
    acquisitions.map(acquisition => {
      installed_row_capture_capacity(acquisition).unwrap()
    }),
    [4096L, 4096L],
    [4096L, 4096L],
    contracts,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    retained_output=true,
    provider_factory=_ => [],
    runtime_admission=true,
  ).unwrap()
  complete_request_capture_preparation(parent, input, plan).unwrap()
  let owner = begin_request_capture_managed_run(parent, request).unwrap()
  let captures = []
  let verify_hooks : Array[Ref[(() -> Unit)?]] = [Ref(None), Ref(None)]
  for index in 0..<2 {
    let (read, _, acquisition, _) = begin_installed_managed_capture_source_read(
      owner, prepared, request, declaration, index,
    ).unwrap()
    assert_true(physical_equal(acquisition, acquisitions[index]))
    let hook = verify_hooks[index]
    let source = start_installed_source_read_rows(
      read,
      acquisition,
      "query-original-" + index.to_string(),
      _ => {
        if hook.val is Some(call) {
          hook.val = None
          call()
        }
        true
      },
      4096L,
      4096L,
    ).unwrap()
    @row_source_host.begin_row_run(source, 4096, 3, 3).unwrap()
    @row_source_host.accept_row_run_page(
      source,
      @utf8.encode(
        if index == 0 {
          "[{\"id\":1},{\"id\":2}]"
        } else {
          "[{\"id\":2},{\"id\":3}]"
        },
      ),
    ).unwrap()
    |> ignore
    @row_source_host.finish_row_run(source).unwrap()
    @row_source_host.begin_row_capture(source).unwrap()
    let mut complete = false
    for _ in 0..<1000 {
      if @row_source_host.advance_row_capture(source, 1).unwrap().0 {
        complete = true
        break
      }
    }
    assert_true(complete)
    captures.push(@row_source_host.capture_row_run(source).unwrap())
  }
  let (setup, _, _) = open_installed_managed_capture_host(
    owner,
    prepared,
    request,
    captures.map(capture => {
      @row_source_host.row_capture_source(capture).unwrap()
    }),
  ).unwrap()
  let capacity = installed_captured_local_tasks_control_capacity(plan.graph).unwrap()
  let controls = @resources.reserve_capacity(
    parent.ledger,
    @execution.execution_capacity_retained_bytes(capacity),
    @execution.execution_capacity_execution_bytes(capacity),
  ).unwrap()
  {
    parent,
    owner,
    plan,
    setup,
    captures,
    controls,
    ledger: parent.ledger,
    verify_hooks,
  }
}

///|
fn close_installed_query_tasks_fixture(
  value : InstalledQueryTasksFixture,
) -> Unit raise {
  assert_true(physical_equal(value.parent.ledger, value.ledger))
  @resources.settle_capacity(value.ledger, value.controls).unwrap()
  for index = value.owner.reads.length() - 1; index >= 0; index = index - 1 {
    retire_installed_source_read(value.owner.reads[index].unwrap()).unwrap()
  }
  retire_installed_managed_run(value.owner).unwrap()
  let usage = @resources.ledger_usage(value.ledger)
  assert_eq(usage.live_reservations, 0)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "installed plural Query continuation joins SAME original captures exactly once" {
  let value = installed_query_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  assert_eq(@strategy.next_captured_task(run), Some(2))
  let execution = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    value.captures,
    1,
    10000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts + 1)
  assert_true(@strategy.captured_task_completed(run, 2))
  assert_true(execution.close())
  assert_true(
    value.captures.all(capture => {
      @row_source_host.row_capture_source(capture) is Ok(_)
    }),
  )
  close_installed_query_tasks_fixture(value)
}

///|
test "installed plural Query continuation refuses reordered missing and foreign originals before compute" {
  for variant in ["reordered", "missing", "request", "current"] {
    let value = installed_query_tasks_fixture()
    let captures = match variant {
      "reordered" => [value.captures[1], value.captures[0]]
      "missing" => [value.captures[0]]
      _ => value.captures
    }
    let request = if variant == "request" {
      @publication_host.prepare_source_free_client_request_identity(
        value.plan.prepared,
        "sha256:" + "a".repeat(64),
        "same-original-query-join",
      ).unwrap()
    } else {
      value.plan.request
    }
    let before = @resources.ledger_usage(value.ledger)
    let failure = execute_installed_captured_local_tasks_guarded(
      value.owner,
      value.plan.prepared,
      request,
      value.setup,
      captures,
      1,
      10000,
      () => variant != "current",
    ).unwrap_err()
    assert_true(
      local_values_execution_failure_issue(failure) is UnsupportedGraph ||
      local_values_execution_failure_issue(failure) is Fenced,
    )
    assert_true(retry_local_values_execution_failure_cleanup(failure))
    assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
    close_installed_query_tasks_fixture(value)
  }
}

///|
test "installed plural Query continuation control quote is exact and one-short refuses both dimensions" {
  let value = installed_query_tasks_fixture()
  let quote = installed_captured_local_tasks_control_capacity(value.plan.graph).unwrap()
  // Independent original vector: task loop H16+12t+2p/R32+16t+4p/W8+4t+p;
  // two seven-reference guards/options H4/R16/W2; RowRun predicates borrow.
  // Exact reference snapshot uses the independent array vector H2/R(9+2n)/W2.
  let tasks = @strategy.graph_task_count(value.plan.graph).to_int64()
  let ports = @strategy.graph_data_count(value.plan.graph).to_int64()
  let expected = @execution.preparation_representation_cost({
    record_headers: 16L + 12L * tasks + 2L * ports + 4L + 2L,
    reference_slots: 32L + 16L * tasks + 4L * ports + 16L + 9L + 4L,
    scalar_words: 8L + 4L * tasks + ports + 2L + 2L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
  assert_eq(@execution.execution_capacity_retained_bytes(quote), expected)
  assert_eq(@execution.execution_capacity_execution_bytes(quote), expected)
  for missing in ["none", "retained", "execution"] {
    let ledger = @resources.create_ledger({
      planning_work: 0,
      attempts: 0,
      holdings: 0,
      transfer_bytes: 0L,
      retained_bytes: expected - (if missing == "retained" { 1L } else { 0L }),
      execution_bytes: expected - (if missing == "execution" { 1L } else { 0L }),
    }).unwrap()
    match @resources.reserve_capacity(ledger, expected, expected) {
      Ok(reservation) => {
        assert_eq(missing, "none")
        @resources.settle_capacity(ledger, reservation).unwrap()
      }
      Err(_) => assert_true(missing != "none")
    }
    assert_eq(@resources.ledger_usage(ledger).live_reservations, 0)
  }
  close_installed_query_tasks_fixture(value)
}

///|
test "installed plural Query continuation retains its finite input snapshot across callback mutation" {
  let value = installed_query_tasks_fixture()
  let checks = Ref(0)
  let execution = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    value.captures,
    1,
    10000,
    () => {
      checks.val += 1
      value.captures.clear()
      true
    },
  ).unwrap()
  assert_true(checks.val > 0)
  assert_eq(value.captures.length(), 0)
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_true(execution.close())
  close_installed_query_tasks_fixture(value)
}

///|
test "installed plural Query continuation fences earlier reader retirement from a later Source callback" {
  let value = installed_query_tasks_fixture()
  let retired = Ref(false)
  value.verify_hooks[1].val = Some(() => {
    retire_installed_source_read(value.owner.reads[0].unwrap()).unwrap()
    retired.val = true
  })
  let before = @resources.ledger_usage(value.ledger)
  let failure = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    value.captures,
    1,
    10000,
    () => true,
  ).unwrap_err()
  assert_true(retired.val)
  assert_true(local_values_execution_failure_issue(failure) is UnsupportedGraph)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  close_installed_query_tasks_fixture(value)
}

///|
test "installed plural Query continuation fences earlier DAG port retirement from a later Source callback" {
  let value = installed_query_tasks_fixture()
  let dag = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let row_run = value.owner.reads[0].unwrap().run.unwrap()
  let retired = Ref(false)
  let row_live = Ref(false)
  value.verify_hooks[1].val = Some(() => {
    @strategy.close_captured_task_output(dag, 0)
    retired.val = true
    row_live.val = @row_source_host.check_row_query_capture_run(
      value.captures[0],
      row_run,
    )
  })
  let before = @resources.ledger_usage(value.ledger)
  let current = installed_captured_local_tasks_current(
    value.owner,
    value.plan,
    value.plan.prepared,
    value.plan.request,
    dag,
    value.captures,
  )
  assert_true(retired.val)
  assert_true(row_live.val)
  assert_false(current)
  value.verify_hooks[1].val = None
  let failure = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    value.captures,
    1,
    10000,
    () => true,
  ).unwrap_err()
  assert_true(retired.val)
  assert_true(row_live.val)
  assert_true(local_values_execution_failure_issue(failure) is UnsupportedGraph)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  close_installed_query_tasks_fixture(value)
}

///|
test "installed plural Query continuation refuses duplicate capture custody before compute" {
  let value = installed_query_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  let failure = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    [value.captures[0], value.captures[0]],
    1,
    10000,
    () => true,
  ).unwrap_err()
  assert_true(local_values_execution_failure_issue(failure) is UnsupportedGraph)
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  close_installed_query_tasks_fixture(value)
}

///|
test "installed filtered SQL read keeps its actual checked acquisition route" {
  let prepared = set_output_expression_prepared(
    text="SELECT id FROM records WHERE id > 1",
  )
  let request = @publication_host.prepare_source_free_client_request_identity(
    prepared,
    "sha256:" + "a".repeat(64),
    "actual-filtered-read-route",
  ).unwrap()
  let route = select_installed_source_input(prepared, request, 0, 0).unwrap()
  let graph = @publication_host.prepared_client_graph(prepared)
  println(
    "actual-filtered-read-route=" +
    @debug.to_string(
      (
        @strategy.graph_task_count(graph),
        @strategy.graph_captured_prefix(graph),
        @strategy.graph_result_task(graph, 0),
        route is @sourceviews.QueryRoute(_),
      ),
    ),
  )
  assert_true(route is @sourceviews.QueryRoute(_))
  assert_eq(@publication_host.prepared_client_acquisition_count(prepared), 1)
  assert_true(@strategy.graph_result_count(graph) == 1)
}

///|
test "installed Query protocols are admitted on SAME Request before complete finite captures" {
  let value = installed_query_tasks_fixture(request_protocols=true)
  let before = @resources.ledger_usage(value.ledger)
  let execution = execute_installed_captured_local_tasks_guarded(
    value.owner,
    value.plan.prepared,
    value.plan.request,
    value.setup,
    value.captures,
    1,
    10000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts + 1)
  assert_true(execution.close())
  close_installed_query_tasks_fixture(value)
}

///|
test "installed Query port-only cleanup preserves original Source custody until caller retirement" {
  let value = installed_query_tasks_fixture()
  let row = value.owner.reads[0].unwrap().run.unwrap()
  let before = @resources.ledger_usage(value.ledger)
  assert_true(
    retire_installed_query_capture_ports(
      value.owner,
      value.plan.prepared,
      value.plan.request,
    ),
  )
  assert_true(
    @row_source_host.check_row_query_capture_run(value.captures[0], row),
  )
  assert_true(@row_source_host.row_capture_source(value.captures[0]) is Ok(_))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, before.attempts)
  // Source holding and native physical cleanup are separate from DAG ports.
  assert_true(@resources.ledger_usage(value.ledger).held_bytes > 0L)
  close_installed_query_tasks_fixture(value)
}

///|
test "installed Query protocol constructor refuses one-short before contract admission on each axis" {
  for axis in 0..<2 {
    for shortage in [0L, 1L] {
      let declaration = pure_provider_declaration()
      let (parent, child, _, input) = registration_parent_fixture(
        text=installed_query_tasks_document,
        environment=Some(pure_provider_environment(declaration)),
      )
      guard finish_program_check_preparation(child).unwrap()
        is @checked.Checked(_) else {
        fail("checked original required")
      }
      let prepared = compile_program_check_preparation(
        child,
        @publication_host.client_standard_program_preparation_limits(),
      ).unwrap()
      continue_request_program_preparation(parent, input).unwrap() |> ignore
      reserve_request_program_plan(parent, input).unwrap()
      // Select the SAME checked direct Query shape. No occurrence/contract
      // is reconstructed from scalar coordinates or copied wire metadata.
      let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
      if @publication_host.client_direct_acquisition_occurrence_count(direct) ==
        0 {
        abort_request_preparation_after_cleanup(parent).unwrap()
        fail("direct Query fixture required")
      }
      let bytes = request_query_acquisition_constructor_bytes(
        prepared, direct, "{}", "{}",
      ).unwrap()
      let limits = @resources.ledger_limits(parent.ledger)
      let usage = @resources.ledger_usage(parent.ledger)
      let available = if axis == 0 {
        limits.retained_bytes -
        usage.held_bytes -
        usage.reserved_retention_bytes
      } else {
        limits.execution_bytes - usage.reserved_execution_bytes
      }
      assert_true(available >= bytes)
      let blocker = @resources.reserve_capacity(
        parent.ledger,
        if axis == 0 {
          available - bytes + shortage
        } else {
          0L
        },
        if axis == 1 {
          available - bytes + shortage
        } else {
          0L
        },
      ).unwrap()
      let result = admit_request_query_acquisition_contracts(
        parent, input, "{}", "{}",
      )
      if shortage == 0L {
        assert_true(result is Err(ModelSource(InvalidContracts)))
      } else {
        assert_true(result is Err(Preparation(Capacity(_))))
      }
      @resources.settle_capacity(parent.ledger, blocker).unwrap()
      abort_request_preparation_after_cleanup(parent).unwrap()
      assert_eq(@resources.ledger_usage(parent.ledger).held_bytes, 0L)
      assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
    }
  }
}

///|
test "installed JOIN SQL read keeps the complete checked direct acquisition prefix" {
  let prepared = set_output_expression_prepared(
    text="SELECT l.id FROM records l JOIN records r ON l.id = r.id",
  )
  let graph = @publication_host.prepared_client_graph(prepared)
  // The public selector's second argument is work, not an item count.
  // Use the SAME installed bounded selector as the actual Native caller.
  let direct = installed_direct_occurrences_owned(Pure(prepared)).unwrap()
  let count = @publication_host.client_direct_acquisition_occurrence_count(
    direct,
  )
  assert_true(count > 0)
  // Repeated aliases of one logical Source may share a capture. The actual
  // checked prefix, not SQL alias count, determines the original inventory.
  assert_eq(count, @strategy.graph_captured_prefix(graph))
  guard @strategy.graph_result_task(graph, 0) is Some(result) else {
    fail("original Result task required")
  }
  assert_true(result >= @strategy.graph_captured_prefix(graph))
  for index in 0..<count {
    guard @publication_host.client_direct_acquisition_occurrence_at(
        direct, index,
      )
      is Some((_, _, task)) else {
      fail("original direct occurrence required")
    }
    assert_eq(task, index)
  }
}
