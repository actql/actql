///|
fn run_registered_relation_session_chain(
  quantum? : Int = 1,
  cancel_after_work? : Int64? = None,
  max_work? : Int? = None,
  output_limit? : Int64? = None,
  empty? : Bool = false,
) -> Unit raise {
  let source_owner = carrier_events_source_owner_with(
    "number",
    if empty {
      "[]"
    } else {
      "[{\"event_id\":1,\"occurred_at\":0,\"payload\":\"a\"}]"
    },
  )
  let source = carrier_events_source_output(source_owner)
  let owner = carrier_events_relation_session_owner(
    source_owner,
    suffix=",{\"filter\":\"true\"},{\"select\":[\"event_id\",\"session_end_ms\"]}",
  )
  let initial = task_test_generated(owner)
  let generated = match output_limit {
    Some(limit) =>
      @execution.constrain_generated_session_output(initial, 0, limit).unwrap()
    None => initial
  }
  let limits = dispatch_test_limits()
  let registry = search_registry()
  let family = @local_tea_provider.provider(
    carrier_events_storage_limits(),
    4096L,
    @execution.generated_sequence_capacity(
      generated,
      limits.local_execution,
      limits.guards,
    ).unwrap(),
  )
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [generated],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
    managed_providers=[family],
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    implementation, generated,
  )
  assert_true(provider is Some(_))
  assert_true(
    @local_connector.local_module_bounded_session_relation_obligation(
      implementation, 0, 0,
    ),
  )
  assert_false(
    @local_connector.local_module_bounded_session_relation_obligation(
      implementation, 0, 1,
    ),
  )
  assert_false(
    @local_connector.local_module_bounded_session_relation_obligation(
      implementation, 1, 0,
    ),
  )
  let without_family = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [generated],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  assert_true(
    @local_connector.local_module_managed_provider(without_family, generated)
    is None,
  )
  assert_false(
    @local_connector.local_module_bounded_session_relation_obligation(
      without_family, 0, 0,
    ),
  )
  let input = @execution.prepare_producer_read(
    owner,
    @execution.bind_completed_input(owner, 0, source_owner, source).unwrap(),
    100,
    1000,
  ).unwrap()
  let active = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider.unwrap(),
    generated,
    [@local_connector.managed_provider_relation_input(input)],
    100,
    10000,
    {
      ..limits.local_execution,
      max_work: max_work.unwrap_or(limits.local_execution.max_work),
    },
  ).unwrap()
  let mut output = None
  let mut terminal = false
  let mut cancelled = false
  let mut work = 0L
  for _ in 0..<1000 {
    if !terminal {
      if !cancelled && cancel_after_work is Some(bound) && work >= bound {
        assert_true(@local_connector.cancel_managed_provider(active))
        cancelled = true
      }
      match
        @local_connector.advance_managed_provider(active, quantum).unwrap() {
        @local_connector.Continue(work=charged, ..) => {
          assert_true(charged <= quantum.to_int64())
          work += charged
        }
        @local_connector.Complete(value, work=charged, ..) => {
          assert_false(cancelled)
          assert_true(max_work is None)
          assert_true(charged <= quantum.to_int64())
          work += charged
          output = Some(value)
          terminal = true
        }
        @local_connector.Stopped(work=charged, ..) => {
          assert_true(cancelled)
          assert_true(charged <= quantum.to_int64())
          terminal = true
        }
        @local_connector.Failed(
          @connector.Execution(@execution.InputLimit),
          work=charged,
          ..
        ) => {
          assert_true(max_work is Some(_))
          assert_false(cancelled)
          assert_true(charged <= quantum.to_int64())
          work += charged
          assert_true(work <= max_work.unwrap().to_int64())
          terminal = true
        }
        @local_connector.Failed(
          @connector.Execution(@execution.Rows(0, RowLimit)),
          progress~,
          work=charged
        ) => {
          assert_eq(output_limit, Some(0L))
          assert_eq(progress, 0L)
          assert_true(charged <= quantum.to_int64())
          terminal = true
        }
        _ =>
          fail("Relation session chain did not finish through bounded children")
      }
    }
  }
  assert_true(terminal)
  if cancel_after_work is None &&
    max_work is None &&
    (empty || output_limit != Some(0L)) {
    let output = output.unwrap()
    assert_eq(@execution.completed_row_count(output), if empty { 0 } else { 1 })
    if !empty {
      assert_true(@execution.completed_cell(output, 0, 0) is Some(Number(1.0)))
      assert_true(@execution.completed_cell(output, 0, 1) is Some(Number(10.0)))
    }
  } else {
    assert_true(output is None)
  }
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@execution.producer_read_available(input))
}

///|
test "registered Relation session chain preserves bounded child custody" {
  for quantum in [1, 2, 7, 1024] {
    run_registered_relation_session_chain(quantum~)
  }
  run_registered_relation_session_chain(empty=true)
}

///|
test "Relation session chain retains cancellation custody across child handoffs" {
  // Session costs 44 units and its six-field projection costs 13. The
  // additional handoff unit precedes any work in the following filter.
  for boundary in [1L, 44L, 57L, 58L, 59L] {
    run_registered_relation_session_chain(cancel_after_work=Some(boundary))
  }
}

///|
test "Relation session chain enforces cumulative work before its suffix" {
  for budget in [57, 58] {
    run_registered_relation_session_chain(max_work=Some(budget))
  }
}

///|
test "Relation session output envelope preserves its exact occurrence" {
  run_registered_relation_session_chain(output_limit=Some(1L))
  run_registered_relation_session_chain(output_limit=Some(0L))
  run_registered_relation_session_chain(output_limit=Some(0L), empty=true)
  let producer = carrier_events_source_owner()
  let owner = carrier_events_relation_session_owner(
    producer,
    suffix=",{\"filter\":\"true\"}",
  )
  let generated = task_test_generated(owner)
  assert_true(
    @execution.constrain_generated_session_output(generated, 1, 1L)
    is Err(@execution.InputSet),
  )
  assert_true(
    @execution.constrain_generated_session_output(generated, 0, -1L)
    is Err(@execution.InvalidLimits),
  )
  let narrowed = @execution.constrain_generated_session_output(generated, 0, 0L).unwrap()
  let widened = @execution.constrain_generated_session_output(narrowed, 0, 1L).unwrap()
  assert_eq(@execution.generated_session_output_ceiling(widened, 0), Some(0L))
  assert_eq(@execution.generated_session_output_ceiling(widened, 1), None)
}

///|
test "retained Relation session offer reaches its registered family child" {
  for registered in [false, true] {
    let (run, issuer) = captured_graph_fixture(
      local_carrier_events_chain=true,
      local_carrier_events_variant="session_relation_chain",
    )
    let registry = search_registry()
    let limits = dispatch_test_limits()
    let generated = dispatch_test_generated(run)
    let graph = @strategy.captured_dag_graph(run)
    assert_eq(@strategy.graph_task_count(graph), 5)
    assert_eq(@strategy.graph_task_selected_step(graph, 2), None)
    assert_eq(@strategy.graph_task_prefix_end(graph, 2), None)
    assert_eq(@execution.generated_sequence_step_count(generated[1]), 3)
    let family = @local_tea_provider.provider(
      carrier_events_storage_limits(),
      4096L,
      @execution.generated_sequence_capacity(
        generated[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    )
    let selected = @execution.select_generated_sequence_step(generated[1], 0).unwrap()
    assert_true(@local_connector.managed_provider_accepts(family, selected))
    let implementation = @local_connector.prepare_local_compute_module(
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      generated.length(),
      managed_providers=[family],
    ).unwrap()
    assert_true(
      @local_connector.local_module_bounded_session_relation_obligation(
        implementation, 1, 0,
      ),
    )
    for index in 0..<@strategy.graph_task_operation_count(graph, 2).unwrap() {
      let requirement = @strategy.graph_task_operation_at(graph, 2, index).unwrap()
      if requirement.disposition is ExecutionCheck(check) {
        match check {
          SessionExecution(_) | EventExecution(_) | EventEnvelope(_) => ()
          _ => fail("unexpected retained session execution obligation")
        }
      }
    }
    let installed = @local_driver.prepare_local_dispatch_module(
      @host_driver.open_dispatch_driver(run),
      registry,
      @connector.capability_registration_at(registry, 0).unwrap(),
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      managed_providers=if registered { [family] } else { [] },
    ).unwrap()
    let wire = {
      ..retained_attempt_wire_limits(),
      max_bytes: 10000,
      max_columns: 10,
    }
    @local_driver.configure_local_retained_inputs(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.input_values,
        wire,
        row: {
          max_bytes: 10000,
          max_nodes: 1000,
          max_depth: 10,
          max_text_bytes: 1000,
        },
        max_batch_bytes: 1024,
      },
      None,
    ).unwrap()
    @local_driver.configure_local_retained_output(
      installed,
      {
        max_rows: 100,
        values: limits.local_execution.rows.output_values,
        wire,
        max_batch_bytes: 1024,
      },
      None,
    ).unwrap()
    assert_eq(
      @local_driver.local_dispatch_rejection(installed, 2),
      if registered {
        None
      } else {
        Some("unsupported_execution_obligation")
      },
    )
    @strategy.stop_captured_dag(run)
    @mock.close_mock_query_issuer(issuer)
  }
}
