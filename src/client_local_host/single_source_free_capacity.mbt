///|
/// Quote the existing single-task retained Values constructor before acquiring
/// its physical supplier. These are Resource admission limits, not backing,
/// permission, a Run, or a claim that every input fits the selected facility.
pub fn single_source_free_local_ledger_limits(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  if @strategy.graph_task_count(
      @publication_host.prepared_client_graph(prepared),
    ) !=
    1 {
    return None
  }
  source_free_local_ledger_limits(
    prepared, registry_body, values_body, fragment_body, ordered_body,
  )
}

///|
/// Quote all original source-free tasks and every retained input port using
/// the same installed Local provider/import/export inventory as the actual
/// retained Host. This neither flattens the graph nor creates a Ledger or a
/// physical supply original. The single-task entry above keeps its old scope.
pub fn source_free_local_ledger_limits(
  prepared : @publication_host.PreparedClientProgram,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @publication_host.prepared_client_graph(prepared)
  let count = @strategy.graph_task_count(graph)
  if @publication_host.prepared_client_acquisition_count(prepared) != 0 ||
    @publication_host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    count < 1 ||
    count > 32 {
    return None
  }
  for task in 0..<count {
    if @publication_host.prepared_client_infer_execution_occurrence(
        prepared, task,
      )
      is Some(_) {
      return None
    }
  }
  guard prepare_client_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == count else {
    return None
  }
  // Count ports, not distinct predecessor tasks: repeated edges retain their
  // own import and bridge workspace. Captures and supplied inputs were refused
  // above, so no external Source can become a source-free allowance.
  let inputs = Array::make(count, 0)
  for index in 0..<@strategy.graph_data_count(graph) {
    guard @strategy.graph_data_at(graph, index) is Some(edge) else {
      return None
    }
    let producer = @strategy.data_edge_producer(edge)
    let consumer = @strategy.data_edge_consumer(edge)
    if producer < 0 ||
      producer >= count ||
      consumer < 0 ||
      consumer >= count ||
      inputs[consumer] == 2147483647 {
      return None
    }
    inputs[consumer] += 1
  }
  client_local_sequence_capacity(
    sequences,
    count,
    retained_inputs=Some(inputs),
    max_rows=@publication_host.prepared_client_values_max_rows(prepared),
  ).map(value => value.0)
}
