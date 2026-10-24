///|
// Original checked/compiled Effect admission and an explicit existing Local
// capacity recipe. This in-memory Core fixture is not a normal physical Host
// funding supplier, a journal start claim or an authorization callback.
fn local_effect_dispatch_fixture(
  empty? : Bool = false,
  short_execution? : Bool = false,
) -> (
  @publication_host.PreparedClientEffectRun,
  @strategy.CapturedEffectRunDAG,
  @client_local_host.ClientInstalledSequenceContracts,
  String,
  String?,
) raise {
  let (document, environment, limits) = local_effect_export_fixture(empty~)
  let prepared = @publication_host.prepare_client_effect_computation(
    document,
    Json,
    environment,
    None,
    [],
    limits,
  ).unwrap()
  let manifests = @publication_host.admit_client_compilation_manifests(
    @environment.compiler_grammar_manifest_wire(),
    @environment.compiler_barrier_contract_manifest_wire(),
    100000,
    10000,
    100,
  ).unwrap()
  let compiled = @publication_host.issue_prepared_client_effect_compilation(
    prepared,
    manifests,
    @publication_host.client_standard_values_sequence_limits(),
    1000,
    10000,
    1000000,
    100000,
    100,
  ).unwrap()
  let allowed = @publication_host.issue_client_effect_allowed_run(
    compiled,
    native_publication_cid("effect-local-dispatch-fixture-context"),
    native_publication_cid("effect-local-dispatch-fixture-policy"),
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let definition = @publication_host.issue_client_effect_run_definition(
    allowed, "scope", "effect-local-dispatch-fixture", "2026-09-25T00:00:00.000Z",
    "2027-01-01T00:00:00.000Z",
  ).unwrap()
  let bound = @publication_host.bind_client_effect_compiled_run(
    prepared, allowed, definition,
  ).unwrap()
  let registry = registered_installed_sequence_contracts()
  let values = @identity.stringify_value(
    registered_values(),
    100000,
    10000,
    100,
  )
  let fragment = Some(
    @identity.stringify_value(registered_fragment(), 100000, 10000, 100),
  )
  let capacity = @client_local_host.client_effect_local_ledger_limits(
    prepared,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let capacity = if short_execution {
    { ..capacity, execution_bytes: capacity.execution_bytes - 1L, }
  } else {
    capacity
  }
  let run = @publication_host.open_prepared_source_free_client_effect_run(
    bound, capacity,
  ).unwrap()
  (bound, run, registry, values, fragment)
}

///|
fn local_effect_dispatch_stop(run : @strategy.CapturedEffectRunDAG) -> Unit {
  let dag = @strategy.captured_effect_run_dag(run)
  @strategy.stop_captured_dag(dag)
  @strategy.close_captured_task_output(dag, 0)
  @strategy.refresh_captured_retention(dag)
}

///|
test "source-free Effect retains its exact Run while the normal Local dispatcher computes and captures Values" {
  for empty in [false, true] {
    let (bound, captured, registry, values, fragment) = local_effect_dispatch_fixture(
      empty~,
    )
    let original = @strategy.captured_effect_run_dag(captured)
    let checked = @publication_host.prepared_client_effect_run_graph(bound)
    assert_eq(@strategy.checked_effect_run_source_count(checked), 2)
    let setup = @client_local_host.configure_source_free_effect_local_retained_host(
      bound,
      captured,
      registry,
      values,
      fragment,
      None,
    ).unwrap()
    assert_true(
      physical_equal(
        @host_driver.dispatch_driver_run(@builtin.configured_host_driver(setup)),
        original,
      ),
    )
    assert_false(@strategy.captured_task_completed(original, 0))
    let execution = @client_local_host.execute_source_free_values_guarded(
      setup,
      64,
      1000,
      () => true,
    ).unwrap()
    // This independent row literal is not derived from the dispatcher output.
    assert_eq(
      execution.rows().unwrap(),
      if empty {
        []
      } else {
        ["{\"value\":1}"]
      },
    )
    assert_true(@strategy.captured_task_completed(original, 0))
    assert_eq(@strategy.checked_effect_run_source_count(checked), 2)
    let pins = @strategy.pin_captured_effect_sources(captured, 2).unwrap()
    assert_eq(@strategy.captured_effect_inputs_count(pins), 2)
    for index in 0..<2 {
      let input = @strategy.captured_effect_input_at(pins, index).unwrap()
      assert_true(
        @strategy.captured_any_result_borrow_matches_managed(
          @strategy.captured_effect_input_borrow(input),
          execution.completed_output(),
        ),
      )
    }
    assert_true(@strategy.release_captured_effect_inputs(pins))
    assert_true(execution.close())
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(original))
    assert_eq(usage.held_bytes, 0L)
    assert_eq(usage.reserved_retention_bytes, 0L)
    assert_eq(usage.reserved_execution_bytes, 0L)
  }
}

///|
test "source-free Effect Local configuration rejects another original Run owner without stopping either" {
  let (bound, captured, registry, values, fragment) = local_effect_dispatch_fixture()
  let (foreign, foreign_run, _, _, _) = local_effect_dispatch_fixture()
  assert_true(
    @client_local_host.configure_source_free_effect_local_retained_host(
      foreign,
      captured,
      registry,
      values,
      fragment,
      None,
    )
    is None,
  )
  for run in [captured, foreign_run] {
    let dag = @strategy.captured_effect_run_dag(run)
    assert_eq(@strategy.next_captured_task(dag), Some(0))
    assert_true(@strategy.captured_dag_strategy(dag) is None)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(dag))
    assert_eq(usage.attempts, 0)
    assert_eq(usage.held_bytes, 0L)
    local_effect_dispatch_stop(run)
  }
  // The correct original remains usable until the caller explicitly stops it.
  bound |> ignore
}

///|
test "source-free Effect refuses one-short original capacity and invalid installation before physical start" {
  for short in [false, true] {
    let (bound, captured, registry, values, fragment) = local_effect_dispatch_fixture(
      short_execution=short,
    )
    assert_true(
      @client_local_host.prepare_installed_sequence_contracts(
        "{}",
        values,
        fragment,
        None,
      )
      is Err(_),
    )
    assert_true(
      @client_local_host.configure_source_free_effect_local_retained_host(
        bound,
        captured,
        registry,
        if short {
          values
        } else {
          "{}"
        },
        fragment,
        None,
      )
      is None,
    )
    let dag = @strategy.captured_effect_run_dag(captured)
    let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(dag))
    assert_eq(usage.attempts, 0)
    assert_eq(usage.reserved_execution_bytes, 0L)
    assert_true(@strategy.captured_dag_strategy(dag) is None)
    assert_eq(@strategy.next_captured_task(dag), Some(0))
    local_effect_dispatch_stop(captured)
  }
}

///|
test "source-free Effect keeps one configured owner and honors the original managed current fence" {
  let (bound, captured, registry, values, fragment) = local_effect_dispatch_fixture()
  let setup = @client_local_host.configure_source_free_effect_local_retained_host(
    bound,
    captured,
    registry,
    values,
    fragment,
    None,
  ).unwrap()
  let dag = @strategy.captured_effect_run_dag(captured)
  let revision = @strategy.captured_dag_strategy(dag).unwrap()
  assert_true(
    @client_local_host.configure_source_free_effect_local_retained_host(
      bound,
      captured,
      registry,
      values,
      fragment,
      None,
    )
    is None,
  )
  assert_true(
    physical_equal(@strategy.captured_dag_strategy(dag).unwrap(), revision),
  )
  // This controlled fixture denies physical execution; it is not an authority
  // supplier and cannot authorize Compute/Effect/Provider work.
  let failed = @client_local_host.execute_source_free_values_guarded(
    setup,
    64,
    1000,
    () => false,
  )
  guard failed is Err(failure) else { fail("current fence was ignored") }
  assert_true(
    @client_local_host.local_values_execution_failure_issue(failure)
    is @client_local_host.Fenced,
  )
  assert_true(
    @client_local_host.retry_local_values_execution_failure_cleanup(failure),
  )
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(dag))
  assert_eq(usage.attempts, 0)
  assert_eq(usage.held_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
}
