///|
test "retained source-free Values chain admits the exact bounded producer" {
  let (_, environment, limits) = local_effect_export_fixture()
  let document =
    #|{"version":"actql/0.1","id":"retained-values-chain","stages":[{"id":"source","inputs":{},"steps":[{"values":{"schema":{"id":{"type":"number","nullable":false}},"rows":[{"id":3},{"id":1},{"id":2}]},"as":"seed"},{"filter":"id >= 2","as":"kept"},{"select":["id"],"as":"selected"}],"results":{"out":{"from":"selected","fields":["id"]}}}],"results":{"published":{"from":{"stage":"source","result":"out"}}}}
  let prepared = @publication_host.prepare_effect_free_client_program(
    document,
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
  let run = @publication_host.open_prepared_source_free_client_run(prepared, {
    planning_work: 100000,
    attempts: 10,
    holdings: 10,
    transfer_bytes: 500000L,
    retained_bytes: 200000000L,
    execution_bytes: 268435456L,
  }).unwrap()
  let sequence_limits : @lower.SequenceLimits = {
    max_steps: 100,
    max_rows: 100,
    max_cells: 10000,
    max_bindings: 100,
    max_name_bytes: 10000,
    expressions: {
      max_nodes: 10000,
      max_work: 100000,
      max_depth: 100,
      max_literal_nodes: 10000,
      max_literal_text_bytes: 10000,
    },
  }
  let graph = @strategy.captured_dag_graph(run)
  let sequence = prepared_sequence(
    @strategy.graph_task_owner(graph, 0).unwrap(),
  )
  let generated = @publication_host.prepare_client_task_sequence(
    prepared,
    0,
    registered_relation_contracts(),
    [sequence_fragment_context(sequence, 1, 10L)],
    sequence_limits,
    100000,
    10000,
    prepared_sequence=Some(sequence),
  ).unwrap()
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 1)
  assert_eq(@execution.generated_sequence_step_count(generated), 3)
  let registry = search_registry()
  let dispatch_limits = dispatch_test_limits()
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [generated],
    dispatch_limits.local_execution,
    dispatch_limits.guards,
    dispatch_limits.candidate_work,
    1,
  ).unwrap()
  assert_true(
    @local_connector.local_module_managed_provider(implementation, generated)
    is Some(_),
  )
  assert_true(
    @local_connector.local_module_bounded_values_obligation(
      implementation, 0, 0,
    ),
  )
  assert_false(
    @local_connector.local_module_bounded_values_obligation(
      implementation, 0, 1,
    ),
  )
  assert_false(
    @local_connector.local_module_bounded_values_obligation(
      implementation, 1, 0,
    ),
  )
  // The compatibility reader deliberately remains a single-step reader.
  assert_false(
    @local_connector.local_module_bounded_values_publication(implementation, 0),
  )
  let installed = @local_driver.prepare_local_dispatch_module(
    @host_driver.open_dispatch_driver(run),
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [generated],
    dispatch_limits.local_execution,
    dispatch_limits.guards,
    dispatch_limits.candidate_work,
  ).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: dispatch_limits.local_execution.rows.input_values,
      wire: retained_attempt_wire_limits(),
      row: { max_bytes: 100, max_nodes: 20, max_depth: 4, max_text_bytes: 100, },
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  @local_driver.configure_local_retained_output(
    installed,
    {
      max_rows: 100,
      values: dispatch_limits.local_execution.rows.output_values,
      wire: retained_attempt_wire_limits(),
      max_batch_bytes: 64,
    },
    None,
  ).unwrap()
  assert_eq(@local_driver.local_dispatch_rejection(installed, 0), None)
  assert_true(
    @local_driver.estimate_local_dispatch_offer(
      installed,
      0,
      [{ work_slots: [0, 1, 2, 3, 4], milliseconds: Some(1L), }],
      100,
    )
    is Ok(_),
  )
  @strategy.stop_captured_dag(run)
}

///|
fn retained_values_chain_source() -> String {
  "[{\"values\":{\"schema\":{\"id\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[{\"id\":3},{\"id\":1},{\"id\":2}]},\"as\":\"seed\"},{\"filter\":\"id >= 2\",\"as\":\"kept\"},{\"select\":[\"id\"],\"as\":\"selected\"}]"
}

///|
test "Values publication rejects wrong children nonlinear chains and shadowing providers" {
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let generated = task_test_generated(
    zero_input_request_owner(retained_values_chain_source()),
  )
  let values = @execution.select_generated_sequence_step(generated, 0).unwrap()
  let single = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [values],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  assert_true(
    @local_connector.local_module_bounded_values_publication(single, 0),
  )
  assert_true(
    @local_connector.local_module_bounded_values_obligation(single, 0, 0),
  )
  let shadow = @local_connector.managed_provider(
    _ => true,
    sequence => {
      @execution.generated_sequence_capacity(
        sequence,
        limits.local_execution,
        limits.guards,
      )
    },
    (_, _, _, _, _) => Err(@connector.InvalidLimits),
  )
  let cases = [
    (generated, [shadow]),
    (@execution.select_generated_sequence_step(generated, 1).unwrap(), []),
    (
      task_test_generated(
        zero_input_request_owner(
          retained_values_chain_source().replace(
            old="{\"select\":[\"id\"],\"as\":\"selected\"}",
            new="{\"from\":\"seed\",\"select\":[\"id\"],\"as\":\"selected\"}",
          ),
        ),
      ),
      [],
    ),
  ]
  for (sequence, family) in cases {
    let installed = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [sequence],
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      1,
      managed_providers=family,
    ).unwrap()
    assert_false(
      @local_connector.local_module_bounded_values_obligation(installed, 0, 0),
    )
  }
}

///|
test "source-free Values chains preserve ordered results and cancellation custody" {
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let generated = task_test_generated(
    zero_input_request_owner(retained_values_chain_source()),
  )
  let installed = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [generated],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    installed, generated,
  ).unwrap()
  for cancel in [false, true] {
    let active = @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      generated,
      [],
      100,
      10000,
      limits.local_execution,
    ).unwrap()
    let mut terminal = false
    let mut work = 0L
    let mut cancelled = false
    for _ in 0..<1000 {
      if terminal {
        break
      }
      // One name, three row/cell/commit triples and Finish consume eleven
      // steps; a handoff then precedes the first filter work unit.
      if cancel && !cancelled && work >= 13L {
        assert_true(@local_connector.cancel_managed_provider(active))
        cancelled = true
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=charged, ..) => {
          assert_true(charged <= 1L)
          work += charged
        }
        @local_connector.Complete(output, work=charged, ..) => {
          assert_false(cancel)
          assert_true(charged <= 1L)
          assert_eq(@execution.completed_row_count(output), 2)
          assert_true(
            @execution.completed_cell(output, 0, 0) is Some(Number(3.0)),
          )
          assert_true(
            @execution.completed_cell(output, 1, 0) is Some(Number(2.0)),
          )
          terminal = true
        }
        @local_connector.Stopped(work=charged, ..) => {
          assert_true(cancelled)
          assert_true(charged <= 1L)
          terminal = true
        }
        _ => fail("source-free chain did not reach its bounded completion")
      }
    }
    assert_true(terminal)
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  }
}
