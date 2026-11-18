///|
// Nominal original Resource/Request/Plan and the actual installed Compute
// issuer. Physical input/module backing remains the existing fixture port;
// no Journal, public observation delivery or installed ABI is claimed here.
test "logical metadata holds SAME Request through pending delivery and original Compute stop" {
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture()
  let before = @resources.ledger_usage(parent.ledger)
  let observation = prepare_installed_logical_observation(
    run, prepared, compiled, definition, 4096, 128, 16,
  ).unwrap()
  assert_true(
    @resources.ledger_usage(parent.ledger).reserved_retention_bytes >
    before.reserved_retention_bytes,
  )
  let plan = run.source_free_preparation.unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      run.request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let captured = run.source_free_captured.unwrap()
  attach_installed_logical_observation(observation, captured).unwrap()
  assert_true(
    read_installed_logical_observation(observation, Before)
    is Err(LogicalObservationProjection(NoCurrentBoundary)),
  )
  let authorized_read = begin_installed_logical_observation(observation, Before).unwrap()
  assert_false(authorized_read.captured)
  assert_true(
    logical_observation_record_state(authorized_read)
    is Err(LogicalObservationReturned),
  )
  // A declined Host authority check can return this original pre-read loan:
  // no logical projection or fabricated NotProjected fact was constructed.
  return_logical_observation_record(authorized_read)
  assert_eq(observation.pending, 0)
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), [])
  let first = read_installed_logical_observation(observation, Settled).unwrap()
  let second = read_installed_logical_observation(observation, Settled).unwrap()
  assert_eq(logical_observation_record_state(first).unwrap(), "projected")
  assert_eq(logical_observation_record_phase(first).unwrap(), "settled")
  let wire = logical_observation_record_key(first).unwrap()
  let key = @publication.parse_interactive_run_control_shape(
    "logical_step_key", wire, 4096, 128, 16,
  ).unwrap()
  assert_true(
    @identity.object_field(key, "compiled_plan_cid")
    is Some(@identity.String(_)),
  )
  assert_eq(observation.pending, 2)
  assert_true(execution.close())
  let held = @resources.ledger_usage(parent.ledger)
  assert_true(
    return_installed_logical_observation(observation)
    is Err(LogicalObservationCleanupPending),
  )
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  assert_true(observation.original is Some(_))
  assert_eq(logical_observation_record_key(first).unwrap(), wire)
  assert_true(
    read_installed_logical_observation(observation, Settled)
    is Err(LogicalObservationForeignOriginal),
  )
  return_logical_observation_record(first)
  return_logical_observation_record(first)
  assert_eq(observation.pending, 1)
  assert_true(
    return_installed_logical_observation(observation)
    is Err(LogicalObservationCleanupPending),
  )
  return_logical_observation_record(second)
  assert_eq(observation.pending, 0)
  return_installed_logical_observation(observation).unwrap() |> ignore
  assert_true(
    observation.attached is None && observation.cleanup.original is None,
  )
  assert_true(return_installed_logical_observation(observation) is Ok(false))
  retire_installed_managed_run(run).unwrap()
  let closed = @resources.ledger_usage(parent.ledger)
  assert_eq(closed.live_reservations, 0)
  assert_eq(closed.reserved_retention_bytes, 0L)
  assert_eq(closed.reserved_execution_bytes, 0L)
}

///|
test "logical metadata refuses one-short before retention cells and foreign issued Compute without attaching" {
  for retention in [true, false] {
    let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture()
    let holder = managed_run_publication_body(run, prepared).unwrap()
    let (r, e) = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
    let controls = explanation_capture_entry_control_bytes +
      logical_observation_control_bytes
    let limits = @resources.ledger_limits(parent.ledger)
    let blocker = @resources.reserve_capacity(
      parent.ledger,
      if retention {
        limits.retained_bytes - r - controls + 1L
      } else {
        0L
      },
      if retention {
        0L
      } else {
        limits.execution_bytes - e - controls + 1L
      },
    ).unwrap()
    let result = prepare_installed_logical_observation(
      run, prepared, compiled, definition, 4096, 128, 16,
    )
    if retention {
      assert_true(
        result is Err(LogicalObservationCapacity(Resource(RetentionLimit))),
      )
    } else {
      assert_true(
        result is Err(LogicalObservationCapacity(Resource(ExecutionLimit))),
      )
    }
    assert_eq(
      @resources.preparation_body_borrow_reserved_extents(holder),
      Ok((r, e)),
    )
    assert_false(run.source_free_opening)
    @resources.settle_capacity(parent.ledger, blocker).unwrap() |> ignore
    let observation = prepare_installed_logical_observation(
      run, prepared, compiled, definition, 4096, 128, 16,
    ).unwrap()
    let (_, foreign, foreign_prepared, _, _) = original_explanation_capture_fixture()
    let plan = foreign.source_free_preparation.unwrap()
    let setup = open_installed_managed_source_free_host(
        foreign,
        foreign_prepared,
        foreign.request,
        plan.installed_contracts,
        plan.values_body,
        plan.fragment_body,
        plan.ordered_body,
        true,
      )
      .unwrap()
      .unwrap()
    let captured = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let before = @resources.ledger_usage(parent.ledger)
    assert_true(
      attach_installed_logical_observation(observation, captured)
      is Err(LogicalObservationForeignOriginal),
    )
    assert_true(observation.attached is None)
    assert_eq(@resources.ledger_usage(parent.ledger), before)
    return_installed_logical_observation(observation).unwrap() |> ignore
    ignore(reject_client_local_run(captured))
    retire_installed_managed_run(foreign).unwrap()
    retire_installed_managed_run(run).unwrap()
    assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
  }
}

///|
test "logical delivery current callback cannot refund a returned record's live getter frame" {
  let selected : Ref[
    (ClientLogicalObservation, ClientLogicalObservationRecord)?,
  ] = Ref(None)
  let armed = Ref(false)
  let attempted = Ref(0)
  let pending = Ref(false)
  let nested_blocked = Ref(false)
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture(current=() => {
      if armed.val && selected.val is Some((owner, record)) {
        armed.val = false
        attempted.val += 1
        nested_blocked.val = logical_observation_record_state(record)
          is Err(LogicalObservationWorkActive)
        return_logical_observation_record(record)
        pending.val = return_installed_logical_observation(owner)
          is Err(LogicalObservationCleanupPending)
      }
      true
    },
  )
  let observation = prepare_installed_logical_observation(
    run, prepared, compiled, definition, 4096, 128, 16,
  ).unwrap()
  let plan = run.source_free_preparation.unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      run.request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  attach_installed_logical_observation(
    observation,
    run.source_free_captured.unwrap(),
  ).unwrap()
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  let record = read_installed_logical_observation(observation, Settled).unwrap()
  assert_true(execution.close())
  selected.val = Some((observation, record))
  let held = @resources.ledger_usage(parent.ledger)
  armed.val = true
  assert_true(
    logical_observation_record_key(record) is Err(LogicalObservationReturned),
  )
  assert_eq(attempted.val, 1)
  assert_true(pending.val && nested_blocked.val)
  assert_eq(@resources.ledger_usage(parent.ledger), held)
  assert_true(observation.cleanup.original is Some(_))
  assert_eq(observation.pending, 0)
  selected.val = None
  return_installed_logical_observation(observation).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "logical installed loan preserves a fused original graph as explicit unprojected" {
  let text =
    #|{"version":"actql/0.1","id":"boundary.fused","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"},{"from":"data","filter":"n > 0","as":"filtered"},{"from":"filtered","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture(
    text~,
  )
  let observation = match
    prepare_installed_logical_observation(
      run, prepared, compiled, definition, 1000000, 100000, 64,
    ) {
    Ok(value) => value
    Err(LogicalObservationCapture(issue)) =>
      fail("Original fused capture: " + @debug.to_string(issue))
    Err(LogicalObservationCapacity(issue)) =>
      fail("Original fused capacity: " + @debug.to_string(issue))
    Err(LogicalObservationConstructionUnavailable) =>
      fail("Original fused construction unavailable")
    Err(_) => fail("Original fused observation refused before attach")
  }
  let plan = run.source_free_preparation.unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      run.request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  let captured = run.source_free_captured.unwrap()
  let graph = @strategy.captured_dag_graph(captured)
  let task = @strategy.next_captured_task(captured).unwrap()
  assert_true(@strategy.graph_task_selected_step(graph, task) is None)
  attach_installed_logical_observation(observation, captured).unwrap()
  assert_true(physical_equal(graph, @strategy.captured_dag_graph(captured)))
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}"])
  let record = read_installed_logical_observation(observation, Settled).unwrap()
  assert_eq(logical_observation_record_state(record).unwrap(), "not_projected")
  assert_true(
    logical_observation_record_key(record) is Err(LogicalObservationReturned),
  )
  assert_eq(logical_observation_record_phase(record).unwrap(), "settled")
  return_logical_observation_record(record)
  assert_true(execution.close())
  return_installed_logical_observation(observation).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}

///|
test "logical delivery peak adds to actual intervening publication quote on SAME parent" {
  let (parent, run, prepared, compiled, definition) = original_explanation_capture_fixture()
  let observation = prepare_installed_logical_observation(
    run, prepared, compiled, definition, 4096, 128, 16,
  ).unwrap()
  let plan = run.source_free_preparation.unwrap()
  let setup = open_installed_managed_source_free_host(
      run,
      prepared,
      run.request,
      plan.installed_contracts,
      plan.values_body,
      plan.fragment_body,
      plan.ordered_body,
      true,
    )
    .unwrap()
    .unwrap()
  attach_installed_logical_observation(
    observation,
    run.source_free_captured.unwrap(),
  ).unwrap()
  let execution = execute_source_free_local_tasks_guarded(setup, 64, 100000, () => {
    true
  }).unwrap()
  let first = match begin_installed_logical_observation(observation, Settled) {
    Ok(value) => value
    Err(LogicalObservationCapacity(issue)) =>
      fail("First delivery role: " + @debug.to_string(issue))
    Err(LogicalObservationCleanupPending) =>
      fail("First delivery lower cleanup pending")
    Err(_) => fail("First delivery original refused")
  }
  // This Source-free fixture has no inferred policy. Use the existing
  // authored UNKNOWN policy body, genuinely admitted by Common; it remains
  // Unknown DATA and supplies no Account/egress/publication permission.
  let admitted_policy = @publication_host.admit_source_free_result_policy_body(
    "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563", "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
    10000, 1000, 20,
  ).unwrap()
  let policy = @publication.captured_effect_dependency_body_cid(admitted_policy)
  issue_program_publication_invocation(
    run, prepared, compiled, definition, policy, 65536, 8192, 64,
  ).unwrap()
  |> ignore
  reserve_program_publication(run, prepared).unwrap() |> ignore
  let holder = managed_run_publication_body(run, prepared).unwrap()
  let (r, e) = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  let second = match begin_installed_logical_observation(observation, Settled) {
    Ok(value) => value
    Err(LogicalObservationCapacity(issue)) =>
      fail("Second delivery role: " + @debug.to_string(issue))
    Err(LogicalObservationCleanupPending) =>
      fail("Second delivery lower cleanup pending")
    Err(_) => fail("Second delivery original refused")
  }
  assert_eq(observation.record_peak, 2)
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder),
    Ok((r + observation.record_bytes, e + observation.record_bytes)),
  )
  return_logical_observation_record(first)
  return_logical_observation_record(second)
  let peak = @resources.preparation_body_borrow_reserved_extents(holder).unwrap()
  // This is an outstanding-memory peak, never lifetime issuance debt. Reuse
  // after return neither grows again nor shrinks any publication/Run holding.
  let again = begin_installed_logical_observation(observation, Settled).unwrap()
  assert_eq(
    @resources.preparation_body_borrow_reserved_extents(holder),
    Ok(peak),
  )
  return_logical_observation_record(again)
  assert_true(execution.close())
  return_installed_logical_observation(observation).unwrap() |> ignore
  retire_installed_managed_run(run).unwrap()
  assert_eq(@resources.ledger_usage(parent.ledger).live_reservations, 0)
}
