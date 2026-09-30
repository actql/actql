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
test "source-free scalar chain uses independent exact work and workspace limits" {
  // Three one-column rows and filter true have no data-dependent search.
  // Values: one name + three (begin/cell/commit) + finish = 11.
  // Filter: six input steps + three retained roots + three seven-step
  // rows (begin/snapshot/two literal steps/build/check/commit) + finish = 31.
  // Select: six input steps + three four-step output rows + finish = 19.
  // Two exact child handoffs give 11 + 31 + 19 + 2 = 63, independently
  // of the execution meter. Each child's control charges fit this ceiling.
  // Filter workspace peaks at three metadata entries + three input roots
  // + one snapshot + two predicate slots = 9; Values and Select need less.
  let defaults = dispatch_test_limits()
  let registry = search_registry()
  let generated = task_test_generated(
    zero_input_request_owner(
      retained_values_chain_source().replace(old="id >= 2", new="true"),
    ),
  )
  for
    (max_work, max_entries, expected) in [
      (63, 9, "complete"),
      (62, 9, "work"),
      (63, 8, "workspace"),
    ] {
    let limits : @execution.SequenceExecutionLimits = {
      ..defaults.local_execution,
      max_work,
      rows: { ..defaults.local_execution.rows, operation_entries: max_entries, },
    }
    let installed = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      [generated],
      limits,
      defaults.guards,
      defaults.candidate_work,
      1,
    ).unwrap()
    let provider = @local_connector.local_module_managed_provider(
      installed, generated,
    ).unwrap()
    let active = @local_connector.start_managed_provider_with_inputs_and_execution(
      provider,
      generated,
      [],
      100,
      10000,
      limits,
    ).unwrap()
    let mut outcome = ""
    let mut work = 0L
    for _ in 0..<100 {
      if outcome != "" {
        break
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=charged, ..) => {
          assert_true(charged <= 1L)
          work += charged
        }
        @local_connector.Complete(output, work=charged, ..) => {
          work += charged
          assert_eq(work, 63L)
          assert_eq(@execution.completed_row_count(output), 3)
          for row, value in [3.0, 1.0, 2.0] {
            guard @execution.completed_cell(output, row, 0)
              is Some(Number(actual)) else {
              fail("scalar chain output has the wrong value type")
            }
            assert_eq(actual, value)
          }
          outcome = "complete"
        }
        @local_connector.Failed(@connector.Execution(@execution.InputLimit), ..) =>
          outcome = "work"
        @local_connector.Failed(
          @connector.Execution(@execution.Rows(_, @execution.RowLimit)),
          ..
        ) => outcome = "workspace"
        _ => fail("scalar chain failed for an unrelated reason")
      }
    }
    assert_eq(outcome, expected)
    assert_true(@local_connector.managed_provider_stopped(active))
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
    assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  }
}

///|
fn retained_values_client_preparation(
  nonlinear : Bool,
) -> @publication_host.PreparedClientProgram {
  let (_, environment, limits) = local_effect_export_fixture()
  let source = if nonlinear {
    retained_values_chain_source().replace(
      old="{\"select\":[\"id\"],\"as\":\"selected\"}",
      new="{\"from\":\"seed\",\"select\":[\"id\"],\"as\":\"selected\"}",
    )
  } else {
    retained_values_chain_source()
  }
  @publication_host.prepare_effect_free_client_program(
    "{\"version\":\"actql/0.1\",\"id\":\"retained-values-client\",\"stages\":[{\"id\":\"source\",\"inputs\":{},\"steps\":" +
    source +
    ",\"results\":{\"out\":{\"from\":\"selected\",\"fields\":[\"id\"]}}}],\"results\":{\"published\":{\"from\":{\"stage\":\"source\",\"result\":\"out\"}}}}",
    Json,
    environment,
    None,
    limits.program,
  ).unwrap()
}

///|
test "product source-free retained factory installs exact bounded chain offers" {
  let prepared = retained_values_client_preparation(false)
  let setup = @client_local_host.open_source_free_local_retained_host(
    prepared,
    @identity.stringify_value(registered_body(), 100000, 10000, 100),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
    fragment_body=Some(
      @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
    ),
  ).unwrap()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  assert_eq(@strategy.captured_compute_first_task(run), 0)
  assert_eq(@strategy.graph_task_count(@strategy.captured_dag_graph(run)), 1)
  assert_true(@strategy.captured_dag_strategy(run) is Some(_))
  assert_eq(
    @local_driver.local_dispatch_rejection(
      @builtin.configured_local_module(@builtin.configured_host_modules(setup)).unwrap(),
      0,
    ),
    None,
  )
  assert_false(@strategy.captured_task_completed(run, 0))
  @strategy.stop_captured_dag(run)
  @strategy.refresh_captured_retention(run)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}

///|
test "product retained factory refuses a nonlinear Values suffix before Compute" {
  let prepared = retained_values_client_preparation(true)
  assert_true(
    @client_local_host.open_source_free_local_retained_host(
      prepared,
      @identity.stringify_value(registered_body(), 100000, 10000, 100),
      @identity.stringify_value(registered_values(), 100000, 10000, 100),
      1L,
      0L,
      0L,
      0L,
      fragment_body=Some(
        @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
      ),
    )
    is None,
  )
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
