///|
// Actual Core task execution with existing registered Local kernels. Account
// and physical-start ports are explicit component fixtures, not public Host,
// durable Debug admission or whole-process backing for the new hook metadata.
fn boundary_test_start(
  host : LocalComputeHost,
) -> @managed.LocalManagedDispatchOperations[Int] {
  let current = account(Allow)
  start_local_compute_task(
    host,
    compute_start(host),
    [],
    permit(host.plan.input, current),
    current,
    tuple(),
    context_cid(),
  )
  .unwrap()
  .unwrap()
}

///|
fn boundary_test_finish(
  operations : @managed.LocalManagedDispatchOperations[Int],
  available : Ref[Bool],
) -> Unit raise {
  let mut finished = false
  for _ in 0..<1000 {
    if (operations.advance)(1).unwrap().complete {
      finished = true
      break
    }
  }
  assert_true(finished)
  (operations.prepare_finalization)(0, operations.storage_bytes, () => {
    available.val
  }).unwrap()
  finished = false
  for _ in 0..<1000 {
    if (operations.advance_finalization)(1).unwrap().complete {
      finished = true
      break
    }
  }
  assert_true(finished)
  (operations.settle)().unwrap()
  (operations.complete)(0, operations.storage_bytes, () => available.val).unwrap()
  |> ignore
  assert_eq((operations.output_rows)(), 1)
  assert_eq((operations.output_row)(0).unwrap(), "{\"n\":1}")
}

///|
fn boundary_test_close(
  host : LocalComputeHost,
  operations : @managed.LocalManagedDispatchOperations[Int],
  available : Ref[Bool],
  settle_stopped? : Bool = false,
  boundary_reads? : Array[@strategy.CapturedTaskBoundary] = [],
) -> Unit raise {
  let run = local_compute_run(host)
  available.val = false
  (operations.close)()
  if settle_stopped {
    // Close requests stop; only the original execution's observed stop permits
    // settlement. Polling cleanup is not a substitute for that acknowledgement.
    assert_true((operations.execution_stopped)())
    (operations.settle)().unwrap()
  }
  @strategy.close_captured_task_output(run, 0)
  let mut closed = false
  for _ in 0..<1000 {
    if (operations.cleanup_refresh)() {
      closed = true
      break
    }
  }
  assert_true(closed)
  @strategy.stop_captured_dag(run)
  for boundary in boundary_reads {
    assert_false(@strategy.captured_task_boundary_current(run, boundary))
    @strategy.return_captured_task_boundary(boundary).unwrap()
  }
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_transfer_bytes, 0L)
}

///|
test "Normal task path emits no boundary metadata or Samples by default" {
  let host = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "normal-boundary-off"),
  )
  let run = local_compute_run(host)
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  let operations = boundary_test_start(host)
  let available = Ref(true)
  boundary_test_finish(operations, available)
  assert_true(@strategy.captured_task_boundary_hooks(run) is None)
  assert_true(
    @strategy.prepare_captured_task_boundary_hooks(
      run,
      @strategy.captured_dag_graph(run),
      @strategy.captured_dag_strategy_revision(run),
    )
    is Err(AlreadyStarted),
  )
  boundary_test_close(host, operations, available)
}

///|
test "same task hook observes original grant then successful settled output and invalidates stale read" {
  let original = plan(
    prepared(@input.Aql("SELECT 1 AS n")),
    "explicit-task-boundary",
  )
  let host = compute_host(original)
  let run = local_compute_run(host)
  let hooks = @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  ).unwrap()
  assert_true(
    physical_equal(
      @strategy.prepare_captured_task_boundary_hooks(
        run,
        @strategy.captured_dag_graph(run),
        @strategy.captured_dag_strategy_revision(run),
      ).unwrap(),
      hooks,
    ),
  )
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Before).unwrap() is None,
  )
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Settled).unwrap() is None,
  )
  let task = @strategy.next_captured_task(run).unwrap()
  // Explicit pure in-process activation coverage, not an Account permission.
  @strategy.authorize_captured_task_activation(
    run,
    task,
    @strategy.task_activation_covered(),
  ).unwrap()
  let before = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  assert_eq(@strategy.captured_task_boundary_task(before), task)
  assert_eq(@strategy.captured_task_boundary_phase(before), Before)
  assert_true(
    @strategy.captured_task_boundary_matches_graph(
      before,
      @host.prepared_client_graph(original.prepared),
    ),
  )
  assert_true(@strategy.captured_task_boundary_current(run, before))
  let operations = boundary_test_start(host)
  assert_false(@strategy.captured_task_boundary_current(run, before))
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, OutputEmitted).unwrap()
    is None,
  )
  let available = Ref(true)
  boundary_test_finish(operations, available)
  let settled = @strategy.read_captured_task_boundary(run, hooks, Settled)
    .unwrap()
    .unwrap()
  let emitted = @strategy.read_captured_task_boundary(run, hooks, OutputEmitted)
    .unwrap()
    .unwrap()
  assert_eq(@strategy.captured_task_boundary_phase(settled), Settled)
  assert_eq(@strategy.captured_task_boundary_phase(emitted), OutputEmitted)
  assert_eq(@strategy.captured_task_boundary_task(emitted), task)
  assert_eq(
    @strategy.captured_task_boundary_generation(emitted),
    @strategy.captured_dag_generation(run),
  )
  assert_eq(
    @strategy.captured_task_boundary_generation(settled),
    @strategy.captured_task_boundary_generation(emitted),
  )
  assert_true(@strategy.captured_task_boundary_current(run, emitted))
  boundary_test_close(host, operations, available, boundary_reads=[
    before, settled, emitted,
  ])
  assert_false(@strategy.captured_task_boundary_current(run, emitted))
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Settled).unwrap() is None,
  )
}

///|
test "failed original completion cannot emit a settled or output boundary" {
  let host = compute_host(
    plan(
      prepared(@input.Aql("SELECT 1 AS n")),
      "boundary-original-completion-refusal",
    ),
  )
  let run = local_compute_run(host)
  let hooks = @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  ).unwrap()
  let operations = boundary_test_start(host)
  let available = Ref(true)
  assert_true(
    (operations.complete)(0, operations.storage_bytes, () => available.val)
    is Err(@managed.Configuration(InvalidLimits)),
  )
  assert_false(@strategy.captured_task_completed(run, 0))
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, Settled).unwrap() is None,
  )
  assert_true(
    @strategy.read_captured_task_boundary(run, hooks, OutputEmitted).unwrap()
    is None,
  )
  // The original task is still active after this refused early completion.
  // Request its real stop before draining the existing cleanup continuation.
  @strategy.stop_captured_dag(run)
  boundary_test_close(host, operations, available, settle_stopped=true)
}

///|
test "boundary holders cannot cross Run owners or reconstruct after stop" {
  let first = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "first-boundary-owner"),
  )
  let second = compute_host(
    plan(prepared(@input.Aql("SELECT 1 AS n")), "second-boundary-owner"),
  )
  let run = local_compute_run(first)
  let foreign = local_compute_run(second)
  let hooks = @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  ).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let before = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  assert_true(
    @strategy.read_captured_task_boundary(foreign, hooks, Before).unwrap()
    is None,
  )
  assert_false(@strategy.captured_task_boundary_current(foreign, before))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  assert_false(@strategy.captured_task_boundary_current(run, before))
  assert_true(
    @strategy.prepare_captured_task_boundary_hooks(
      run,
      @strategy.captured_dag_graph(run),
      @strategy.captured_dag_strategy_revision(run),
    )
    is Err(Stopped),
  )
  @strategy.return_captured_task_boundary(before).unwrap()
  @strategy.refresh_captured_retention(run)
  @strategy.stop_captured_dag(foreign)
  @strategy.refresh_captured_retention(foreign)
}

///|
let boundary_single_operation_program : String =
  #|{"version":"actql/0.1","id":"boundary.single-operation","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"}],"results":{"rows":{"from":"data","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}

///|
test "actual task boundary binds only the same original logical key and expires after work or release" {
  let original = plan(
    prepared(@input.Program(boundary_single_operation_program)),
    "logical-boundary-original",
  )
  let foreign = plan(
    prepared(@input.Program(boundary_single_operation_program)),
    "logical-boundary-foreign",
  )
  let host = compute_host(original)
  let run = local_compute_run(host)
  let facts_original = @host.capture_client_structural_explanation_original(
    original.compiled,
    original.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  let hooks = @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  ).unwrap()
  @strategy.authorize_captured_task_activation(
    run,
    0,
    @strategy.task_activation_covered(),
  ).unwrap()
  let before = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  guard @host.bind_client_logical_task_boundary(
      facts_original,
      original.compiled,
      original.prepared,
      run,
      before,
      1000,
    ).unwrap()
    is Projected(bound) else {
    fail("missing genuine single-operation boundary")
  }
  let key_wire = @host.client_logical_task_boundary_key_json(
    bound,
    original.compiled,
    original.prepared,
    4096,
    128,
    16,
  ).unwrap()
  let key = @publication.parse_interactive_run_control_shape(
    "logical_step_key", key_wire, 4096, 128, 16,
  ).unwrap()
  guard @identity.object_field(key, "stage_ordinal")
    is Some(@identity.Number(0)) &&
    @identity.object_field(key, "self_cid") is Some(@identity.String(step_id)) &&
    @identity.object_field(key, "compiled_plan_cid")
    is Some(@identity.String(plan_id)) else {
    fail("foreign original key")
  }
  assert_eq(
    plan_id,
    @publication.publication_contract_identity(original.compiled.plan),
  )
  assert_eq(
    @host.client_logical_task_boundary_step_id(
      bound,
      original.compiled,
      original.prepared,
    ).unwrap(),
    step_id,
  )
  let expected_port = @publication.seal_run_evidence_value(
    "logical_port_key",
    "{\"version\":\"actql-logical-port-key/0.1\",\"compiled_plan_cid\":\"" +
    plan_id +
    "\",\"step_id\":\"" +
    step_id +
    "\",\"role\":\"output\",\"port_ordinal\":0}",
    4096,
    128,
    16,
  ).unwrap()
  assert_eq(
    @host.client_logical_task_boundary_output_port_id(
      bound,
      original.compiled,
      original.prepared,
      0,
      100,
    ).unwrap(),
    Some(@publication.run_evidence_value_identity(expected_port)),
  )
  assert_true(
    @host.client_logical_task_boundary_output_port_id(
      bound,
      original.compiled,
      original.prepared,
      1,
      100,
    ).unwrap()
    is None,
  )
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts_original,
      original.compiled,
      foreign.prepared,
      run,
      before,
      1000,
    )
    is Err(ForeignOriginal),
  )
  assert_true(
    @host.client_logical_task_boundary_key_json(
      bound,
      original.compiled,
      original.prepared,
      0,
      128,
      16,
    )
    is Err(InvalidReadLimits),
  )
  let operations = boundary_test_start(host)
  assert_false(
    @host.client_logical_task_boundary_current(
      bound,
      original.compiled,
      original.prepared,
    ),
  )
  assert_true(
    @host.client_logical_task_boundary_step_id(
      bound,
      original.compiled,
      original.prepared,
    )
    is Err(StaleBoundary),
  )
  let available = Ref(true)
  boundary_test_finish(operations, available)
  let emitted = @strategy.read_captured_task_boundary(run, hooks, OutputEmitted)
    .unwrap()
    .unwrap()
  guard @host.bind_client_logical_task_boundary(
      facts_original,
      original.compiled,
      original.prepared,
      run,
      emitted,
      1000,
    ).unwrap()
    is Projected(after) else {
    fail("missing actual emitted boundary")
  }
  assert_eq(
    @host.client_logical_task_boundary_step_id(
      after,
      original.compiled,
      original.prepared,
    ).unwrap(),
    step_id,
  )
  @host.return_client_logical_task_boundary(bound).unwrap()
  @host.return_client_logical_task_boundary(after).unwrap()
  boundary_test_close(host, operations, available, boundary_reads=[
    before, emitted,
  ])
  assert_false(
    @host.client_logical_task_boundary_current(
      after,
      original.compiled,
      original.prepared,
    ),
  )
}

///|
test "fused physical task cannot manufacture a boundary for its internal logical operations" {
  let program =
    #|{"version":"actql/0.1","id":"boundary.fused","stages":[{"id":"main","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"data"},{"from":"data","filter":"n > 0","as":"filtered"},{"from":"filtered","select":["n"],"as":"out"}],"results":{"rows":{"from":"out","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"main","result":"rows"}}}}
  let original = plan(
    prepared(@input.Program(program)),
    "fused-logical-boundary",
  )
  let host = compute_host(original)
  let run = local_compute_run(host)
  let facts_original = @host.capture_client_structural_explanation_original(
    original.compiled,
    original.prepared,
    1000000,
    100000,
    100,
  ).unwrap()
  let hooks = @strategy.prepare_captured_task_boundary_hooks(
    run,
    @strategy.captured_dag_graph(run),
    @strategy.captured_dag_strategy_revision(run),
  ).unwrap()
  let task = @strategy.next_captured_task(run).unwrap()
  assert_true(
    @strategy.graph_task_selected_step(@strategy.captured_dag_graph(run), task)
    is None,
  )
  @strategy.authorize_captured_task_activation(
    run,
    task,
    @strategy.task_activation_covered(),
  ).unwrap()
  let before = @strategy.read_captured_task_boundary(run, hooks, Before)
    .unwrap()
    .unwrap()
  assert_true(
    @host.bind_client_logical_task_boundary(
      facts_original,
      original.compiled,
      original.prepared,
      run,
      before,
      1000,
    ).unwrap()
    is NotProjected(FusedPhysicalTask),
  )
  @strategy.stop_captured_dag(run)
  @strategy.return_captured_task_boundary(before).unwrap()
  @strategy.refresh_captured_retention(run)
}
