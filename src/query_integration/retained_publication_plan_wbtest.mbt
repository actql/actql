///|
/// This publication fixture retains three independent task envelopes at the
/// frontier: compute_a survives through compute_c, while b and c are sinks.
/// Preserve the captured-input allowance and quote the same installed IO policy;
/// neither the global fixture policy nor any product limit is widened.
fn native_publication_retained_local_plan(
  retained_bytes? : Int64? = None,
) -> (
  @strategy.CapturedDAG,
  @dbhost.StrategyHostDispatch,
  @mock.MockQueryIssuer,
  @strategy.StrategyDecision,
  @execution.RowWireLimits,
) raise {
  let limits = dispatch_test_limits()
  let wire : @execution.RowWireLimits = {
    max_columns: 10,
    max_order_work: 10000,
    max_bytes: 100000,
    max_nodes: 10000,
    max_depth: 32,
  }
  let imports : @local_connector.LocalImportLimits = {
    max_rows: 100,
    values: limits.local_execution.rows.input_values,
    wire,
    row: {
      max_bytes: 10000,
      max_nodes: 1000,
      max_depth: 32,
      max_text_bytes: 10000,
    },
    max_batch_bytes: 4096,
  }
  let output : @local_connector.LocalExportLimits = {
    max_rows: 100,
    values: limits.local_execution.rows.input_values,
    wire,
    max_batch_bytes: 4096,
  }
  let rows = limits.local_execution.rows
  // The original two-operation sequence retains its wiring/metadata roots,
  // output values and text. Reuse common units rather than measured output.
  let base = @execution.execution_capacity_inventory_bytes([
    {
      unit: CursorRootSlots,
      count: rows.retained_entries.to_int64() + rows.metadata_entries.to_int64(),
      copies: 1,
    },
    {
      unit: ValueNodeSlots,
      count: rows.output_values.max_nodes.to_int64(),
      copies: 1,
    },
    {
      unit: DecodedTextBytes,
      count: rows.output_values.max_text_bytes.to_int64(),
      copies: 1,
    },
  ]).unwrap()
  let task_retention = base +
    @local_connector.local_import_retention_capacity(imports).unwrap() +
    @local_connector.local_export_retention_capacity(output).unwrap()
  let captured_input_allowance = 32000000L
  let (run, issuer) = captured_graph_fixture(
    ledger_limits=Some({
      planning_work: 10000,
      attempts: 10,
      holdings: 10,
      transfer_bytes: 300000L,
      retained_bytes: retained_bytes.unwrap_or(
        captured_input_allowance + 3L * task_retention,
      ),
      execution_bytes: 134217728L,
    }),
  )
  let registry = search_registry()
  let registration = @connector.capability_registration_at(registry, 0).unwrap()
  let host = @dbhost.configure_strategy_dispatch(
    run,
    registry,
    registration,
    @connector.capability_registration_at(registry, 1).unwrap(),
    dispatch_test_generated(run),
    limits,
  ).unwrap()
  @dbhost.configure_dispatch_local_retained_output(
    host,
    imports,
    output,
    Some(1L),
  ).unwrap()
  @strategy.configure_strategy_search(run, {
    max_offers: 3,
    max_strategies: 8,
    max_work: 1000,
    max_revisions: 4,
  }).unwrap()
  let offers = Array::makei(3, index => {
    @dbhost.prepare_dispatch_local_offer(host, index + 1, Some(1L)).unwrap()
  })
  let decision = @strategy.revise_strategy(run, offers, registry, None).unwrap()
  (run, host, issuer, decision, wire)
}

///|
fn close_retained_publication_plan(
  run : @strategy.CapturedDAG,
  dispatch : @dbhost.StrategyHostDispatch,
  issuer : @mock.MockQueryIssuer,
) -> Unit raise {
  @dbhost.stop_strategy_dispatch(dispatch)
  for task in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, task)
  }
  @mock.close_mock_query_issuer(issuer)
  let usage = @resources.ledger_usage(@strategy.captured_dag_ledger(run))
  assert_eq(usage.reserved_retention_bytes, 0L)
  assert_eq(usage.reserved_execution_bytes, 0L)
  assert_eq(usage.held_bytes, 0L)
}

///|
test "retained Local publication planning rejects the unfunded three-offer envelope" {
  let (run, dispatch, issuer, decision, _) = native_publication_retained_local_plan(
    retained_bytes=Some(32000000L),
  )
  assert_true(decision is NoFeasible)
  assert_true(@strategy.captured_dag_strategy(run) is None)
  assert_eq(@strategy.strategy_history_count(run), 0)
  assert_eq(@strategy.strategy_report_count(run), 1)
  assert_eq(
    @strategy.strategy_report_at(run, 0).unwrap().rejection,
    Some(@resources.RetentionLimit),
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  for task in 1..<4 {
    assert_false(@strategy.captured_task_completed(run, task))
  }
  close_retained_publication_plan(run, dispatch, issuer)
}

///|
test "retained Local publication planning selects the same three offers under the quoted envelope" {
  let (run, dispatch, issuer, decision, _) = native_publication_retained_local_plan()
  guard decision is Selected(revision) else {
    abort("retained Local plan must select")
  }
  assert_true(
    physical_equal(@strategy.captured_dag_strategy(run).unwrap(), revision),
  )
  assert_eq(@strategy.strategy_history_count(run), 1)
  assert_eq(@strategy.strategy_report_count(run), 1)
  assert_eq(@strategy.strategy_assessment(revision).rejection, None)
  assert_true(
    @strategy.strategy_assessment(revision).retained_bytes > 32000000L,
  )
  assert_eq(
    @resources.ledger_usage(@strategy.captured_dag_ledger(run)).attempts,
    0,
  )
  for task in 1..<4 {
    assert_true(
      physical_equal(
        @strategy.strategy_registration(revision, task).unwrap(),
        @dbhost.dispatch_local_registration(dispatch),
      ),
    )
    assert_false(@strategy.captured_task_completed(run, task))
  }
  close_retained_publication_plan(run, dispatch, issuer)
}
