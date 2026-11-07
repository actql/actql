///|
// Real checked Row acquisition and Common tasks on one nominal test Ledger.
// This is not Native Files backing, Account/Journal admission or CLI coverage.
priv struct CapturedTasksFixture {
  prepared : @publication_host.PreparedClientProgram
  requirements : ClientLocalRequirements
  ledger : @resources.Ledger
  source : @row_source_host.RowRun
  capture : @row_source_host.RowSourceCapture
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue]
  verify_hook : Ref[(() -> Unit)?]
  controls_ledger : @resources.Ledger
  controls : @resources.CapacityReservation
}

///|
fn captured_tasks_prepared() -> @publication_host.PreparedClientProgram {
  single_installed_prepared(
    document=(
      #|{"version":"actql/0.1","id":"captured-common-tasks","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"captured"}],"results":{"rows":{"from":"captured","fields":["id"]}}},{"id":"compute","inputs":{"r":{"result":{"stage":"acquire","result":"rows"}}},"steps":[{"filter":"id >= 2"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}},{"id":"finish","inputs":{"r":{"result":{"stage":"compute","result":"rows"}}},"steps":[{"filter":"id < 3"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}}}],"results":{"answer":{"from":{"stage":"finish","result":"rows"}}}}
    ),
  )
}

///|
fn captured_tasks_requirements(
  prepared : @publication_host.PreparedClientProgram,
) -> ClientLocalRequirements? {
  prepare_captured_local_requirements(
    prepared,
    prepare_installed_sequence_contracts(
      source_query_original_registry,
      source_query_original_values,
      Some(source_query_original_fragment),
      None,
    ).unwrap(),
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
  )
}

///|
fn captured_tasks_fixture(
  original? : @publication_host.PreparedClientProgram? = None,
  copied_source? : Bool = false,
  foreign_ledger? : Bool = false,
  simultaneous? : Bool = false,
) -> CapturedTasksFixture raise {
  let prepared = original.unwrap_or_else(captured_tasks_prepared)
  let requirements = captured_tasks_requirements(prepared).unwrap()
  let acquisition = original_row_acquisition_fixture(
    original_row_requirement(prepared),
  )
  let maximum = if simultaneous {
    requirements.simultaneous_limits().unwrap()
  } else {
    requirements.maximum_limits()
  }
  let control_capacity = captured_local_tasks_control_capacity().unwrap()
  let controls_retained = @execution.execution_capacity_retained_bytes(
    control_capacity,
  )
  let controls_execution = @execution.execution_capacity_execution_bytes(
    control_capacity,
  )
  let limits = {
    ..maximum,
    transfer_bytes: maximum.transfer_bytes + 4096L,
    retained_bytes: maximum.retained_bytes +
    @row_source_host.row_acquisition_retained_capacity(acquisition) +
    controls_retained,
    execution_bytes: maximum.execution_bytes +
    @row_source_host.row_acquisition_execution_capacity(acquisition) +
    4096L +
    controls_execution,
  }
  let ledger = @resources.create_ledger(limits).unwrap()
  let verify_hook : Ref[(() -> Unit)?] = Ref(None)
  let source = @row_source_host.start_accounted_row_acquisition(
    acquisition,
    "captured-common-tasks",
    _ => {
      if verify_hook.val is Some(hook) {
        verify_hook.val = None
        hook()
      }
      true
    },
    ledger,
    4096L,
    4096L,
  ).unwrap()
  @row_source_host.begin_row_run(source, 4096, 3, 3).unwrap()
  @row_source_host.accept_row_run_page(
    source,
    @utf8.encode(
      "[{\"id\":3,\"amount\":null},{\"id\":1,\"amount\":null},{\"id\":2,\"amount\":null}]",
    ),
  ).unwrap()
  |> ignore
  @row_source_host.finish_row_run(source).unwrap()
  @row_source_host.begin_row_capture(source).unwrap()
  let mut complete = false
  for _ in 0..<10000 {
    if @row_source_host.advance_row_capture(source, 1).unwrap().0 {
      complete = true
      break
    }
  }
  assert_true(complete)
  let capture = @row_source_host.capture_row_run(source).unwrap()
  let captured = @row_source_host.row_capture_source(capture).unwrap()
  let supplied = if copied_source {
    @query.restrict_captured_source(captured, () => true)
  } else {
    captured
  }
  let compute_ledger = if foreign_ledger {
    @resources.create_ledger(limits).unwrap()
  } else {
    ledger
  }
  let controls = @resources.reserve_capacity(
    compute_ledger, controls_retained, controls_execution,
  ).unwrap()
  let setup = open_captured_local_retained_host_on_ledger(
    prepared,
    supplied,
    compute_ledger,
    requirements.registry,
    source_query_original_values,
    Some(source_query_original_fragment),
    None,
    requirements=Some(requirements),
  ).unwrap()
  {
    prepared,
    requirements,
    ledger,
    source,
    capture,
    setup,
    verify_hook,
    controls_ledger: compute_ledger,
    controls,
  }
}

///|
fn captured_tasks_close_source(value : CapturedTasksFixture) -> Unit raise {
  // The fixture owns the fixed control reservation until downstream cleanup.
  @resources.settle_capacity(value.controls_ledger, value.controls).unwrap()
  @row_source_host.close_accounted_row_run(value.source).unwrap()
  let usage = @resources.ledger_usage(value.ledger)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.live_reservations, 0)
}

///|
test "captured Common tail executes original Source and downstream tasks on one Ledger" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  assert_true(
    physical_equal(
      @strategy.captured_dag_graph(run),
      @publication_host.prepared_client_graph(value.prepared),
    ),
  )
  assert_true(physical_equal(@strategy.captured_dag_ledger(run), value.ledger))
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 3)
  assert_eq(@strategy.next_captured_task(run), Some(1))
  let before = @resources.ledger_usage(value.ledger)
  assert_eq(before.attempts, 1)
  let execution = execute_captured_local_tasks_guarded(
    value.setup,
    value.capture,
    value.requirements,
    1,
    100000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"id\":2}"])
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 3)
  assert_true(@strategy.captured_task_completed(run, 1))
  assert_true(@strategy.captured_task_completed(run, 2))
  assert_true((execution.tasks.unwrap().0)(0) is None)
  assert_true(execution.close())
  assert_true(execution.close())
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  captured_tasks_close_source(value)
}

///|
test "captured Common tail refuses copied source foreign Ledger and same-byte foreign original before Compute" {
  for variant in ["source", "ledger", "prepared", "capture", "closed"] {
    let value = captured_tasks_fixture(
      copied_source=variant == "source",
      foreign_ledger=variant == "ledger",
    )
    let other = captured_tasks_fixture(original=Some(value.prepared))
    let requirements = if variant == "prepared" {
      captured_tasks_requirements(captured_tasks_prepared()).unwrap()
    } else {
      value.requirements
    }
    let capture = if variant == "capture" {
      other.capture
    } else {
      value.capture
    }
    if variant == "closed" {
      @row_source_host.close_accounted_row_run(value.source).unwrap()
    }
    let before = @resources.ledger_usage(value.ledger).attempts
    guard execute_captured_local_tasks_guarded(
        value.setup,
        capture,
        requirements,
        64,
        100000,
        () => true,
      )
      is Err(failure) else {
      fail("foreign or closed original must fail")
    }
    assert_true(local_values_execution_failure_issue(failure) is Fenced)
    assert_true(retry_local_values_execution_failure_cleanup(failure))
    assert_true(retry_local_values_execution_failure_cleanup(failure))
    assert_eq(@resources.ledger_usage(value.ledger).attempts, before)
    let other_run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(other.setup),
    )
    assert_true(close_local_values_tasks(other_run, []))
    captured_tasks_close_source(other)
    captured_tasks_close_source(value)
  }
}

///|
test "captured Common tail current loss after first Compute is sticky and closes only downstream originals" {
  let value = captured_tasks_fixture()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(value.setup),
  )
  let before = @resources.ledger_usage(value.ledger)
  let current = () => !@strategy.captured_task_completed(run, 1)
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      1,
      100000,
      current,
    )
    is Err(failure) else {
    fail("current loss must stop the original tail")
  }
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 2)
  assert_false(@strategy.captured_task_completed(run, 2))
  assert_eq(@resources.ledger_usage(value.ledger).held_bytes, before.held_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      64,
      100000,
      () => true,
    )
    is Err(retry) else {
    fail("stopped original cannot resume")
  }
  assert_true(retry_local_values_execution_failure_cleanup(retry))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 2)
  captured_tasks_close_source(value)
}

///|
test "source-free entry still refuses a real captured Source before Compute" {
  let value = captured_tasks_fixture()
  guard execute_source_free_local_tasks_guarded(value.setup, 64, 100000, () => {
      true
    })
    is Err(failure) else {
    fail("source-free entry must not accept a captured prefix")
  }
  assert_true(local_values_execution_failure_issue(failure) is UnsupportedGraph)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 1)
  captured_tasks_close_source(value)
}

///|
test "captured Common tail rechecks Source custody after verifier reentry" {
  let value = captured_tasks_fixture()
  value.verify_hook.val = Some(() => {
    @row_source_host.close_accounted_row_run(value.source).unwrap()
  })
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      64,
      100000,
      () => true,
    )
    is Err(failure) else {
    fail("closed Source must not survive its original verifier callback")
  }
  assert_true(local_values_execution_failure_issue(failure) is Fenced)
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 1)
  captured_tasks_close_source(value)
}

///|
test "captured Common tail finalization exhaustion cannot retry or release Source custody" {
  let value = captured_tasks_fixture()
  let before = @resources.ledger_usage(value.ledger)
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      1,
      1,
      () => true,
    )
    is Err(failure) else {
    fail("one finalization step must not finish the retained output")
  }
  assert_true(
    local_values_execution_failure_issue(failure) is FinalizationLimit,
  )
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  let after = @resources.ledger_usage(value.ledger)
  assert_eq(after.attempts, 2)
  assert_eq(after.held_bytes, before.held_bytes)
  assert_eq(after.reserved_execution_bytes, before.reserved_execution_bytes)
  assert_true(@row_source_host.row_capture_source(value.capture) is Ok(_))
  captured_tasks_close_source(value)
}

///|
test "captured Common tail preserves adaptive selection failure and stops before Compute" {
  let value = captured_tasks_fixture()
  let limits = @resources.ledger_admission_limits(value.ledger)
  let used = @resources.ledger_usage(value.ledger).planning_work
  @resources.charge_planning(value.ledger, limits.planning_work - used).unwrap()
  guard execute_captured_local_tasks_guarded(
      value.setup,
      value.capture,
      value.requirements,
      64,
      100000,
      () => true,
    )
    is Err(failure) else {
    fail("exhausted original planning work cannot select another candidate")
  }
  assert_true(local_values_execution_failure_issue(failure) is Estimate(_))
  assert_true(retry_local_values_execution_failure_cleanup(failure))
  assert_eq(@resources.ledger_usage(value.ledger).attempts, 1)
  captured_tasks_close_source(value)
}

///|
test "captured Common requirements refuse extra Sources Model and Effect profiles" {
  let multiple = nearest_failed_prepared()
  assert_eq(@publication_host.prepared_client_acquisition_count(multiple), 2)
  assert_true(captured_tasks_requirements(multiple) is None)
  let (model, _, _, _) = original_prefix_execution_fixture(source=true)
  assert_eq(@publication_host.prepared_client_acquisition_count(model), 1)
  assert_true(captured_tasks_requirements(model) is None)
  let environment = @publication_host.admit_client_check_environment(
    source_query_original_environment,
    "sha256:05ee9059ef5f173069a3f3f1896e16ee62d34d0c842d81e9b0f8421db62e67a8",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
  let effect =
    #|{"version":"actql/0.1","id":"captured-effect-refusal","stages":[{"id":"acquire","inputs":{"remote":{"connector":"crm/main","resource":"r"}},"steps":[{"filter":"id > 0"},{"select":["id"],"as":"selected"}],"results":{"rows":{"from":"selected","fields":["id"]}},"effects":{"save":{"update":{"target":"connector://crm/account","mapping":"mapping:crm.account.v1","from":{"result":"rows"},"id":"id","set":{"Name":{"field":"id"}}}}}}],"results":{"rows":{"from":{"stage":"acquire","result":"rows"}}}}
  // Effectful preparations have a different owner/type; no pure requirements
  // or execution setup can be issued through this entrance.
  assert_true(
    @publication_host.prepare_effect_free_client_program(
      effect,
      Json,
      environment,
      None,
      @publication_host.client_standard_program_preparation_limits(),
    )
    is Err(EffectNotSupported("acquire")),
  )
}
