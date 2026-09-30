///|
/// This selected Node package installs SGA; the RelA-only package supplies a
/// different, provider-free selection without changing the common ABI body.
fn selected_sga_supported() -> Bool {
  true
}

///|
fn selected_graph_limits() -> @graph_storage.Limits {
  {
    max_input_rows: 100,
    max_nodes: 100,
    max_edges: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 10000,
    max_retained_value_bytes: 10000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn installed_client_graph_providers(
  capacity : @execution.ExecutionCapacity,
) -> Array[@local.ManagedProvider] {
  [@local_sga_provider.provider(selected_graph_limits(), 10000L, capacity)]
}

///|
fn selected_client_sga_providers(
  generated : Array[@execution.GeneratedSequence],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Array[@local.ManagedProvider]? {
  let mut retained_bytes = 0L
  let mut execution_bytes = 0L
  for sequence in generated {
    guard @execution.generated_sequence_capacity(
        sequence, execution, measurement,
      )
      is Some(sequence_capacity) else {
      return None
    }
    let retained = @execution.execution_capacity_retained_bytes(
      sequence_capacity,
    )
    let executing = @execution.execution_capacity_execution_bytes(
      sequence_capacity,
    )
    if retained > retained_bytes {
      retained_bytes = retained
    }
    if executing > execution_bytes {
      execution_bytes = executing
    }
  }
  match @execution.execution_capacity(retained_bytes, execution_bytes) {
    Some(sequence_capacity) =>
      Some([
        @local_sga_provider.provider(
          selected_graph_limits(),
          10000L,
          sequence_capacity,
        ),
      ])
    None => None
  }
}
