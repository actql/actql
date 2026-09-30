///|
/// Keep the family operation and its suffix inside the original producer Stage.
fn retained_relation_family_suffix(text : String) -> String raise {
  let document = @json.parse(text)
  guard document is Object(program) &&
    program.get("stages") is Some(Array(stages)) else {
    abort("invalid family fixture")
  }
  let mut modified = 0
  for stage in stages {
    if stage is Object(fields) &&
      fields.get("id") is Some(String(id)) &&
      (id == "series" || id == "joined" || id == "matched" || id == "nested") {
      guard fields.get("steps") is Some(Array(steps)) &&
        steps.last() is Some(Object(operation)) else {
        abort("missing family producer")
      }
      operation["as"] = @json.parse("\"family\"")
      steps.push(
        @json.parse("{\"from\":\"family\",\"filter\":\"true\",\"as\":\"out\"}"),
      )
      modified += 1
    }
  }
  guard modified == 1 else { abort("ambiguous family producer") }
  document.stringify()
}

///|
test "retained Nest chain binds its exact built-in child" {
  let (run, issuer) = captured_graph_fixture(
    local_values_nest_chain=true,
    local_relation_family_suffix=true,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let generated = dispatch_test_generated(run)
  assert_eq(@execution.generated_sequence_step_count(generated[2]), 2)
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    generated.length(),
  ).unwrap()
  assert_true(
    @local_connector.local_module_bounded_nest_obligation(implementation, 2, 0),
  )
  assert_false(
    @local_connector.local_module_bounded_nest_obligation(implementation, 2, 1),
  )
  assert_false(
    @local_connector.local_module_bounded_nest_obligation(implementation, 1, 0),
  )
  let filter = @execution.select_generated_sequence_step(generated[2], 1).unwrap()
  let filter_only = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    [filter],
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    1,
  ).unwrap()
  assert_false(
    @local_connector.local_module_bounded_nest_obligation(filter_only, 0, 0),
  )
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "physical DAG retains linear Relation family chains in one task" {
  for
    (kind, task, tasks) in [
      ("series", 1, 4),
      ("interval", 3, 6),
      ("asof", 3, 6),
      ("sequence", 2, 5),
      ("nest", 3, 6),
    ] {
    let program = query_checked_program_fixture(
      dag=true,
      local_time_series_chain=kind == "series",
      local_values_interval_chain=kind == "interval",
      local_values_asof_chain=kind == "asof",
      local_values_sequence_chain=kind == "sequence",
      local_values_nest_chain=kind == "nest",
      local_relation_family_suffix=true,
    )
    let graph = @strategy.prepare_checked_dag(
      program,
      physical_graph_owners(program),
      20,
      10000,
    ).unwrap()
    assert_eq(@strategy.graph_task_count(graph), tasks)
    assert_eq(@strategy.graph_task_selected_step(graph, task), None)
    assert_eq(@strategy.graph_task_prefix_end(graph, task), None)
    assert_true(@strategy.graph_ordered_inputs_complete(graph))
  }
}

///|
fn run_relation_family_chain(cancel_after? : Int? = None) -> Unit raise {
  let (run, issuer) = captured_graph_fixture(
    local_time_series_chain=true,
    local_relation_family_suffix=true,
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let generated = dispatch_test_generated(run)
  let capacity = @execution.generated_sequence_capacity(
    generated[0],
    limits.local_execution,
    limits.guards,
  ).unwrap()
  let implementation = @local_connector.prepare_local_compute_module(
    registry,
    @connector.capability_registration_at(registry, 0).unwrap(),
    generated,
    limits.local_execution,
    limits.guards,
    limits.candidate_work,
    generated.length(),
    managed_providers=[
      @local_tea_provider.time_series_provider(
        carrier_events_storage_limits(),
        capacity,
      ),
    ],
  ).unwrap()
  let provider = @local_connector.local_module_managed_provider(
    implementation,
    generated[0],
  ).unwrap()
  let active = @local_connector.start_managed_provider_with_inputs_and_execution(
    provider,
    generated[0],
    [],
    100,
    10000,
    limits.local_execution,
  ).unwrap()
  let mut terminal = false
  let mut work = 0L
  for poll_index in 0..<1000 {
    if !terminal {
      if cancel_after == Some(poll_index) {
        assert_true(@local_connector.cancel_managed_provider(active))
      }
      match @local_connector.advance_managed_provider(active, 1).unwrap() {
        @local_connector.Continue(work=charged, ..) => {
          assert_true(charged <= 1L)
          work += charged
        }
        @local_connector.Complete(output, work=charged, ..) => {
          assert_true(cancel_after is None)
          assert_true(charged <= 1L)
          work += charged
          assert_eq(@execution.completed_row_count(output), 3)
          terminal = true
        }
        @local_connector.Stopped(work=charged, ..) => {
          assert_true(cancel_after is Some(_))
          assert_true(charged <= 1L)
          work += charged
          terminal = true
        }
        _ => fail("bounded family chain did not preserve its child execution")
      }
    }
  }
  assert_true(terminal)
  // The three-row series costs four work units and the handoff costs one.
  // Cancellation after six polls therefore reaches the following filter.
  assert_true(work >= 5L)
  assert_true(@local_connector.managed_provider_stopped(active))
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  assert_true(@local_connector.cleanup_managed_provider(active).unwrap())
  @strategy.stop_captured_dag(run)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "bounded Relation family chain advances at quantum one" {
  run_relation_family_chain()
}

///|
test "bounded Relation family chain cancels after its child handoff" {
  run_relation_family_chain(cancel_after=Some(6))
}
