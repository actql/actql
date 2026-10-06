///|
fn graph_composition_cleanup_fixture(
  operation : String,
  input_count : Int,
) -> Unit raise {
  // Both checked composition operations use the existing Host fixture and
  // cleanup owner. The Source/capture and driver owners are unchanged.
  let program = current_graph_relation_program("current_filter")
    .replace(
      old="{\"match_nodes\":",
      new="{\"from\":\"g\"," +
        operation +
        ",\"as\":\"combined\"},{\"from\":\"combined\",\"match_nodes\":",
    )
    .replace(
      old="\"results\":{\"source\":{\"from\":{\"stage\":\"a\",\"result\":\"r\"}}}}",
      new="\"results\":{\"published\":{\"from\":{\"stage\":\"graph\",\"result\":\"r\"}}}}",
    )
  let (run, issuer) = captured_graph_fixture(
    checked_program=Some(
      query_checked_program_fixture(
        program_text=Some(program),
        local_carrier_graph_chain=true,
      ),
    ),
    managed_publication=true,
    ledger_limits=Some({
      planning_work: 30000,
      attempts: 20,
      holdings: 20,
      transfer_bytes: 800000L,
      retained_bytes: 96000000L,
      execution_bytes: 402653184L,
    }),
  )
  let graph = @strategy.captured_dag_graph(run)
  assert_eq(@strategy.graph_task_count(graph), 8)
  assert_eq(@strategy.graph_task_input_count(graph, 3), Some(input_count))
  assert_eq(@strategy.graph_task_selected_step(graph, 3), Some(1))
  assert_true(
    @strategy.configure_captured_managed_identity_policy(
      run, true, false, false, false,
    ),
  )
  let registry = search_registry()
  let limits = dispatch_test_limits()
  let sequences = dispatch_test_generated(run)
  let attempts = Ref(0)
  let provider = delayed_cleanup_provider(
    @local_sga_provider.provider(
      {
        ..carrier_graph_storage_limits(),
        max_workspace_slots: 100000,
        max_work: 100000,
      },
      4096L,
      @execution.generated_sequence_capacity(
        sequences[1],
        limits.local_execution,
        limits.guards,
      ).unwrap(),
    ),
    attempts,
    only_owner=@execution.generated_sequence_owner(sequences[3]),
    only_step=1,
    cleanup_error=true,
  )
  let modules = @builtin.configure_compute_modules(
    @host_driver.open_dispatch_driver(run),
    registry,
    1,
    _ => @strategy.RunIssue::ForeignCandidate,
    with_local=Some(
      (
        @connector.capability_registration_at(registry, 0).unwrap(),
        {
          sequences,
          managed_providers: [provider],
          managed_capacity: limits.capacity,
          execution: limits.local_execution,
          measurement: limits.guards,
          max_work: limits.candidate_work,
        },
        _ => @strategy.RunIssue::ForeignCandidate,
        _ => @strategy.RunIssue::ForeignCandidate,
      ),
    ),
  ).unwrap()
  let installed = @builtin.configured_local_module(modules).unwrap()
  @local_driver.configure_local_retained_inputs(
    installed,
    {
      max_rows: 100,
      values: limits.local_execution.rows.input_values,
      wire: {
        ..retained_attempt_wire_limits(),
        max_bytes: 10000,
        max_nodes: 1000,
        max_depth: 20,
        max_columns: 10,
      },
      row: {
        max_bytes: 3000,
        max_nodes: 300,
        max_depth: 10,
        max_text_bytes: 3000,
      },
      max_batch_bytes: 3000,
    },
    None,
  ).unwrap()
  let values_live = Ref(true)
  let (values_ops, values) = run_local_managed_test_task(
    installed,
    run,
    1,
    [],
    [],
    1,
    values_live,
    obligations?=graph_publication_obligations(run, true),
  )
  let rows = local_managed_test_rows(values_ops)
  let (construction_ops, construction, material) = run_local_managed_carrier_test_task(
    installed,
    run,
    2,
    Array::makei(2, _ => @local_driver.local_managed_relation_output(values)),
    Array::makei(2, _ => rows),
    obligations?=graph_publication_obligations(run, true),
  )
  let (union_ops, combined, combined_material) = run_local_managed_carrier_test_task(
    installed,
    run,
    3,
    Array::makei(input_count, _ => {
      @local_driver.local_managed_carrier_output(construction, material)
    }),
    [],
    obligations?=graph_publication_obligations(run, true),
  )
  assert_eq(attempts.val, 1)
  let pending = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(pending.reserved_execution_bytes > 0L && pending.held_bytes > 0L)
  let work = (union_ops.cumulative_provider_work)().unwrap()
  assert_true(work > 0L)
  assert_false((union_ops.cleanup_refresh)())
  assert_eq(attempts.val, 2)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
    pending,
  )
  assert_true(@carrier_runtime.material_available(material))
  assert_true(
    @execution.carrier_managed_completed_output_available(construction),
  )
  assert_true(@execution.carrier_managed_completed_output_available(combined))
  assert_true(@carrier_runtime.material_available(combined_material))
  assert_eq(
    @carrier_runtime.material_storage_bytes(combined_material),
    Some(4096L),
  )
  assert_eq((union_ops.cumulative_provider_work)(), Ok(work))
  // Closing the successful task is a separate disposition boundary. Only
  // that existing owner can retire its reservation; a scratch retry alone
  // must not dispose a still-live Graph output.
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 3)
  (union_ops.close)()
  let disposed = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(disposed.reserved_execution_bytes, pending.reserved_execution_bytes)
  assert_true(@carrier_runtime.material_available(material))
  assert_true(@execution.managed_completed_output_available(values))
  (union_ops.cleanup_refresh)() |> ignore
  assert_eq(attempts.val, 3)
  let cleaned = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_true(
    cleaned.reserved_execution_bytes < disposed.reserved_execution_bytes,
  )
  // This task owns one independently configured 4096-byte Graph holding.
  // Its disposal and successful cleanup release that holding, not either
  // borrowed input generation or the VALUES output's separate allocation.
  assert_eq(cleaned.held_bytes, disposed.held_bytes - 4096L)
  assert_true(
    cleaned.reserved_retention_bytes <= disposed.reserved_retention_bytes,
  )
  assert_eq(cleaned.transferred_bytes, disposed.transferred_bytes)
  assert_true(@carrier_runtime.material_available(material))
  assert_false(@carrier_runtime.material_available(combined_material))
  assert_true(
    @execution.carrier_managed_completed_output_available(construction),
  )
  (union_ops.cleanup_refresh)() |> ignore
  assert_eq(attempts.val, 3)
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)),
    cleaned,
  )
  assert_eq((union_ops.cumulative_provider_work)(), Ok(work))
  @strategy.close_captured_task_output(run, 2)
  (construction_ops.close)()
  (construction_ops.cleanup_refresh)() |> ignore
  values_live.val = false
  @strategy.close_captured_task_output(run, 1)
  (values_ops.close)()
  (values_ops.cleanup_refresh)() |> ignore
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
  let final_usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(final_usage.reserved_execution_bytes, 0L)
  assert_eq(final_usage.reserved_retention_bytes, 0L)
  assert_eq(final_usage.held_bytes, 0L)
  assert_eq(attempts.val, 3)
  @mock.close_mock_query_issuer(issuer)
}

///|
test "Host union keeps repeated input holdings and cleanup reservation through false error and retry" {
  graph_composition_cleanup_fixture(
    "\"union_graphs\":{\"with\":[\"g\",\"g\"]}", 3,
  )
}

///|
test "Host subtraction keeps both borrowed occurrences and cleanup reservation through false error and retry" {
  graph_composition_cleanup_fixture("\"subtract_graphs\":{\"with\":\"g\"}", 2)
}
