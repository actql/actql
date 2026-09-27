///|
/// One imported single-row Local materializing attempt over a retained DuckDB
/// producer, ready for its bounded provider to run.
fn provider_work_attempt() -> (
  @strategy.CapturedDAG,
  @strategy.TaskExecution,
  @strategy.TaskExecution,
  @local_connector.LocalMaterializingAttempt,
) raise {
  let (run, _) = captured_graph_fixture()
  let transport : FixedComputeTestTransport = { settled: None, }
  let producer = captured_graph_duckdb_start(run, 1, transport)
  let attempt = @duckdb_driver.captured_duckdb_attempt(producer)
  let material = receive_retained_attempt(attempt, Ref(true))
  transport.settled = Some(attempt)
  @duckdb_compute.stage_retained_duckdb_compute_material(
    attempt,
    @execution.retained_output_material(material),
  ).unwrap()
  let producer_execution = @duckdb_driver.captured_duckdb_execution(producer)
  @strategy.settle_task_execution(run, producer_execution, true).unwrap()
  @duckdb_driver.complete_captured_duckdb_task(run, producer).unwrap()
  captured_graph_local(run, 2).unwrap()
  let input = @strategy.captured_task_input(run, 3, 100, 10000).unwrap()
  let registry = @connector.prepare_capability_registry(
    [{ name: "local", acquisition: false, fixed_compute: true, effect: false, }],
    1,
    100,
  ).unwrap()
  let owner = @execution.producer_read_receiver(input)
  let request = @connector.prepare_fixed_compute_request([input], {
    contract_cid: "sha256:7d59718b965451d8a19ccf7095b92777ba0cdd8c3bb71f437ab387801fe7271f",
    max_rows: 100,
    max_value_bytes: 10000,
    common_fragment: None,
  }).unwrap()
  let limits : @local_connector.LocalImportLimits = {
    max_rows: 2,
    values: { ..fixed_compute_attempt_limits().retention, max_nodes: 1000, },
    wire: retained_attempt_wire_limits(),
    row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
    max_batch_bytes: 64,
  }
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [task_test_generated(owner)],
    compute_test_limits(),
    { max_work: 10000, max_bytes: 10000, max_nodes: 10000, max_depth: 100, },
    100,
    1,
  ).unwrap()
  let execution = @local_connector.prepare_local_module_materializing_compute(
    implementation,
    0,
    request,
    limits,
    _ => @strategy.RunIssue::Compute(InvalidLimits),
    None,
  ).unwrap()
  let (consumer, ticket) = @strategy.start_captured_materializing_execution(
    run, 3, execution,
  ).unwrap()
  @local_connector.begin_local_materializing_input(consumer, 0).unwrap()
  @strategy.charge_task_execution_transfer(run, ticket, 10L).unwrap()
  @local_connector.append_local_materializing_input(consumer, 0, "{\"id\":3}").unwrap()
  @local_connector.finish_local_materializing_input(consumer, 0).unwrap()
  (run, producer_execution, ticket, consumer)
}

///|
fn provider_work_close(
  run : @strategy.CapturedDAG,
  producer : @strategy.TaskExecution,
  ticket : @strategy.TaskExecution,
) -> Unit {
  @strategy.close_task_execution(run, ticket)
  @strategy.close_task_execution(run, producer)
}

///|
test "bounded Local provider work is the sum of its advances, counted once" {
  // Drained in one call: the reference total for this one-row input, as the
  // provider reports it.
  let (run, producer, ticket, drained) = provider_work_attempt()
  assert_true(
    @local_connector.local_materializing_provider_work(drained) is None,
  )
  @local_connector.execute_local_materializing_attempt(drained).unwrap()
  guard @local_connector.local_materializing_provider_work(drained)
    is Some(total) else {
    fail("completed attempt reports no provider work")
  }
  assert_eq(total, 23L)
  // No value measurement is produced on the bounded path.
  assert_true(@local_connector.local_materializing_guard_usage(drained) is None)
  provider_work_close(run, producer, ticket)
  // One work unit per advance: the reported total equals the sum of every
  // advance's own report, and matches the drained total exactly.
  let (run, producer, ticket, stepped) = provider_work_attempt()
  let mut summed = 0L
  let mut advances = 0
  while true {
    let step = @local_connector.advance_local_materializing_attempt(stepped, 1).unwrap()
    summed += step.work
    advances += 1
    if step.complete {
      break
    }
    assert_true(
      @local_connector.local_materializing_provider_work(stepped) is None,
    )
  }
  assert_true(advances > 1)
  assert_eq(
    @local_connector.local_materializing_provider_work(stepped),
    Some(summed),
  )
  assert_eq(summed, total)
  // Reading the total again does not add to it.
  assert_eq(
    @local_connector.local_materializing_provider_work(stepped),
    Some(total),
  )
  @local_connector.close_local_materializing_attempt(stepped)
  assert_true(
    @local_connector.local_materializing_provider_work(stepped) is None,
  )
  provider_work_close(run, producer, ticket)
}
