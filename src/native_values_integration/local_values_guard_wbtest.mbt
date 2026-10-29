///|
fn local_values_guard_environment() -> @program_check.CheckEnvironment {
  @publication_host.admit_client_check_environment(
    (
      #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
    ),
    "sha256:aa727ea3fb169143aa8b774d7ee16679166cdae133c990a128921eaad0c3d904",
    { text_time: false, veca: false, },
    { rela: true, sga: false, tea: false, calendar: false, text_rank: false, },
  ).unwrap()
}

///|
fn local_values_guard_prepared() -> @publication_host.PreparedClientProgram {
  let environment = local_values_guard_environment()
  let prepared = @publication_host.prepare_effect_free_client_program(
    (
      #|{"version":"actql/0.1","id":"local-guard-values","stages":[{"id":"seed","inputs":{},"steps":[{"values":{"schema":{"n":{"type":"number","nullable":false}},"rows":[{"n":1}]},"as":"selected"}],"results":{"rows":{"from":"selected","fields":["n"]}}}],"results":{"answer":{"from":{"stage":"seed","result":"rows"}}}}
    ),
    Json,
    environment,
    None,
    @publication_host.client_standard_program_preparation_limits(),
  ).unwrap()
  prepared
}

///|
fn local_values_guard_setup() -> @builtin.ConfiguredComputeHost[
  @strategy.RunIssue,
] raise {
  let prepared = local_values_guard_prepared()
  @client_local_host.open_source_free_local_retained_host(
    prepared,
    native_values_installed_contracts(),
    @identity.stringify_value(registered_values(), 100000, 10000, 100),
    1L,
    0L,
    0L,
    0L,
  ).unwrap()
}

///|
test "guarded Local Values preserves the independently expected row and original cleanup" {
  let setup = local_values_guard_setup()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let execution = @client_local_host.execute_source_free_values_guarded(
    setup,
    16,
    1000,
    () => true,
  ).unwrap()
  assert_eq(execution.rows().unwrap(), ["{\"n\":1}"])
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_true(execution.close())
  assert_true(execution.close())
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}

///|
test "guarded Local Values refuses the original fence before any physical attempt" {
  for denied_at in 1..<=2 {
    let setup = local_values_guard_setup()
    let run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let mut observed = 0
    let failure = @client_local_host.execute_source_free_values_guarded(
      setup,
      16,
      1000,
      () => {
        observed += 1
        observed < denied_at
      },
    ).unwrap_err()
    assert_eq(observed, denied_at)
    assert_true(
      @client_local_host.local_values_execution_failure_issue(failure)
      is @client_local_host.Fenced,
    )
    assert_false(@strategy.captured_task_completed(run, 0))
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
      0,
    )
    assert_true(
      @client_local_host.retry_local_values_execution_failure_cleanup(failure),
    )
  }
}

///|
test "guarded Local Values preserves cleanup after started work is fenced" {
  for denied_at in 3..<=4 {
    let setup = local_values_guard_setup()
    let run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let mut observed = 0
    let failure = @client_local_host.execute_source_free_values_guarded(
      setup,
      16,
      1000,
      () => {
        observed += 1
        observed < denied_at
      },
    ).unwrap_err()
    assert_eq(observed, denied_at)
    assert_true(
      @client_local_host.local_values_execution_failure_issue(failure)
      is @client_local_host.Fenced,
    )
    assert_false(@strategy.captured_task_completed(run, 0))
    assert_true(
      @client_local_host.retry_local_values_execution_failure_cleanup(failure),
    )
    assert_true(
      @client_local_host.retry_local_values_execution_failure_cleanup(failure),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      0L,
    )
  }
}

///|
test "guarded Local Values refuses loss of the fence during finite finalization" {
  for denied_at in 5..<=7 {
    let setup = local_values_guard_setup()
    let run = @host_driver.dispatch_driver_run(
      @builtin.configured_host_driver(setup),
    )
    let mut observed = 0
    let failure = @client_local_host.execute_source_free_values_guarded(
      setup,
      1,
      1000,
      () => {
        observed += 1
        observed < denied_at
      },
    ).unwrap_err()
    // The Owner may reject its own availability callback before the adapter's
    // next fence. Neither typed failure returns output or permits a new start.
    assert_false(@strategy.captured_task_completed(run, 0))
    assert_true(
      @client_local_host.retry_local_values_execution_failure_cleanup(failure),
    )
    assert_true(
      @client_local_host.retry_local_values_execution_failure_cleanup(failure),
    )
    assert_eq(
      @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
      0L,
    )
  }
}

///|
test "guarded Local Values rechecks the fence after completed-output commitment" {
  let setup = local_values_guard_setup()
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let failure = @client_local_host.execute_source_free_values_guarded(
    setup,
    16,
    1000,
    () => !@strategy.captured_task_completed(run, 0),
  ).unwrap_err()
  // Task completion is not publication or a cancelled terminal. Its rows are
  // not returned to the caller once the final current fence refuses.
  assert_true(@strategy.captured_task_completed(run, 0))
  assert_true(
    @client_local_host.local_values_execution_failure_issue(failure)
    is @client_local_host.Fenced,
  )
  assert_true(
    @client_local_host.retry_local_values_execution_failure_cleanup(failure),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).held_bytes,
    0L,
  )
}
