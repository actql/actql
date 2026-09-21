///|
fn local_module_test_provider(
  capacity : @execution.ExecutionCapacity?,
) -> @local_connector.ManagedProvider {
  @local_connector.managed_provider(_ => true, _ => capacity, fn(
    _,
    _,
    _,
    _,
    _,
  ) {
    Err(@connector.InvalidLimits)
  })
}

///|
test "Local module snapshots its owned preparations without admitting or executing input" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  let (registry, _, prepared) = synchronous_test_choice(run)
  let (_, _, foreign) = synchronous_test_choice(other)
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let foreign_request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(foreign),
  )
  let sequences = [
    query_generated(@connector.fixed_compute_request_owner(request)),
  ]
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let before = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  let installed = @local_connector.prepare_local_compute_module(
    registry,
    registration,
    sequences,
    compute_test_limits(),
    { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    100,
    1,
  ).unwrap()
  sequences[0] = query_generated(
    @connector.fixed_compute_request_owner(foreign_request),
  )
  let compute = @local_connector.prepare_local_module_compute(
    installed,
    0,
    request,
    None,
  ).unwrap()
  assert_eq(@resources.ledger_usage(@strategy.captured_dag_ledger(run)), before)
  assert_false(@strategy.captured_task_completed(run, 1))
  assert_true(
    physical_equal(
      @connector.fixed_compute_candidate_registration(
        @connector.synchronous_compute_candidate(compute),
      ),
      registration,
    ),
  )
  assert_true(
    @local_connector.prepare_local_module_compute(
      installed,
      0,
      foreign_request,
      None,
    )
    is Err(Candidate(ForeignPreparation)),
  )
  for slot in [-1, 1] {
    assert_true(
      @local_connector.prepare_local_module_compute(
        installed,
        slot,
        request,
        None,
      )
      is Err(Candidate(ForeignPreparation)),
    )
  }
  @strategy.execute_captured_synchronous_task(run, 1, compute).unwrap()
  let output = @strategy.captured_task_output(run, 1, Step(1)).unwrap()
  assert_eq(@execution.completed_row_count(output), 1)
  @connector.close_capability_registry(registry)
  assert_true(
    @local_connector.prepare_local_module_compute(installed, 0, request, None)
    is Err(Candidate(CapabilityClosed)),
  )
  // Disabling new preparation is not revocation of an independent completion.
  assert_eq(@execution.completed_row_count(output), 1)
}

///|
test "Local module rejects ambiguous or unbounded managed providers" {
  let (run, _) = captured_graph_fixture()
  let (registry, _, prepared) = synchronous_test_choice(run)
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let sequences = [
    query_generated(@connector.fixed_compute_request_owner(request)),
  ]
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  let bounded = local_module_test_provider(
    @execution.execution_capacity(0L, 0L),
  )
  assert_true(
    @local_connector.prepare_local_compute_module(
      registry,
      registration,
      sequences,
      limits,
      measurement,
      100,
      1,
      managed_providers=[bounded, bounded],
    )
    is Err(ForeignPreparation),
  )
  assert_true(
    @local_connector.prepare_local_compute_module(
      registry,
      registration,
      sequences,
      limits,
      measurement,
      100,
      1,
      managed_providers=[local_module_test_provider(None)],
    )
    is Err(ForeignPreparation),
  )
}

///|
test "Local module installation rejects foreign registration and unbounded configuration" {
  let (run, _) = captured_graph_fixture()
  let (other, _) = captured_graph_fixture()
  let (registry, _, prepared) = synchronous_test_choice(run)
  let (foreign_registry, _, _) = synchronous_test_choice(other)
  let request = @connector.fixed_compute_candidate_request(
    @connector.prepared_compute_candidate(prepared),
  )
  let sequences = [
    query_generated(@connector.fixed_compute_request_owner(request)),
  ]
  let limits = compute_test_limits()
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: 10000,
    max_bytes: 10000,
    max_nodes: 10000,
    max_depth: 100,
  }
  assert_true(
    @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(foreign_registry, 0).unwrap(),
      sequences,
      limits,
      measurement,
      100,
      1,
    )
    is Err(ForeignCapability(0)),
  )
  assert_true(
    @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      sequences,
      limits,
      measurement,
      100,
      0,
    )
    is Err(InvalidLimits),
  )
}
