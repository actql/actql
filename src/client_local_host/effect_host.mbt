///|
/// Install the existing Local managed dispatcher on this exact, unstarted
/// source-free Effect Run. The caller already owns its admitted bound Run and
/// physical Ledger; no new Run, Ledger, numeric profile or permission is issued.
/// This finite entry drives one Values task only. The opaque Effect closure
/// remains with `bound`/`captured`; it is never returned as an Effect-free
/// preparation. Current start/expiry/journal/cleanup stay with the caller.
/// A failed configuration may stop this same Run; the caller keeps its original
/// cleanup responsibility. `None` is not a physical cleanup acknowledgement.
pub fn configure_source_free_effect_local_retained_host(
  bound : @publication_host.PreparedClientEffectRun,
  captured : @strategy.CapturedEffectRunDAG,
  installed_contracts : ClientInstalledSequenceContracts,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @builtin.ConfiguredComputeHost[@strategy.RunIssue]? {
  let original = @publication_host.prepared_client_effect_run_graph(bound)
  if !physical_equal(
      @strategy.checked_effect_run_owner(original),
      @strategy.captured_effect_run_owner(captured),
    ) {
    return None
  }
  let prepared = @publication_host.prepared_client_effect_run_computation(bound)
  let graph = @strategy.checked_effect_run_graph(original)
  let run = @strategy.captured_effect_run_dag(captured)
  if !physical_equal(@strategy.captured_dag_graph(run), graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    @strategy.graph_captured_prefix(graph) != 0 ||
    @strategy.graph_task_count(graph) != 1 ||
    @strategy.graph_task_input_count(graph, 0) != Some(0) ||
    @strategy.captured_dag_strategy(run) is Some(_) ||
    @strategy.next_captured_task(run) != Some(0) ||
    @publication_host.prepared_client_effect_infer_occurrence(prepared)
    is Some(_) {
    return None
  }
  guard prepare_client_effect_local_sequences(
      prepared, installed_contracts, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == 1 else {
    return None
  }
  // Derive the same existing Effect/Local envelope from the installed bodies.
  // These are capacity checks, not physical backing or execution authority.
  let (values, execution, measurement) = client_local_execution_limits()
  let max_rows = execution.rows.max_rows
  guard client_local_sequence_capacity(
      sequences,
      1,
      retained_inputs=Some([0]),
      max_rows~,
    )
    is Some((required, retained_bytes, execution_bytes)) else {
    return None
  }
  let actual = @resources.ledger_admission_limits(
    @strategy.captured_dag_ledger(run),
  )
  if actual.planning_work < required.planning_work ||
    actual.attempts < required.attempts ||
    actual.holdings < required.holdings ||
    actual.transfer_bytes < required.transfer_bytes ||
    actual.retained_bytes < required.retained_bytes ||
    actual.execution_bytes < required.execution_bytes {
    return None
  }
  configure_client_local_run(
    run,
    graph,
    sequences,
    0,
    1,
    max_rows,
    values,
    execution,
    measurement,
    retained_bytes,
    execution_bytes,
    true,
    1L,
    0L,
    0L,
    0L,
    _ => [],
  )
}
