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
  let graph = @publication_host.prepared_client_graph(prepared)
  if @publication_host.prepared_client_acquisition_count(prepared) != 0 ||
    @publication_host.prepared_client_uses_graph_carrier(prepared) ||
    @strategy.graph_program_has_effects(graph) ||
    !@strategy.graph_source_free_inputs_complete(graph) ||
    @strategy.graph_task_count(graph) != 1 ||
    @publication_host.prepared_client_infer_execution_occurrence(prepared, 0)
    is Some(_) {
    return None
  }
  guard prepare_client_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) &&
    sequences.length() == 1 else {
    return None
  }
  client_local_sequence_capacity(
    sequences,
    1,
    retained_inputs=Some([0]),
    max_rows=@publication_host.prepared_client_values_max_rows(prepared),
  ).map(value => value.0)
}
