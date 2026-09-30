///|
/// This selected Node package installs all Local families; RelA-only supplies a
/// different, provider-free selection without changing the common bridge body.
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
fn selected_record_limits() -> @record_storage.Limits {
  {
    max_input_records: 100,
    max_records: 100,
    max_fields_per_record: 100,
    max_value_bytes: 10000,
    max_total_value_bytes: 100000,
    max_retained_value_bytes: 100000,
    max_value_nodes: 10000,
    max_value_depth: 100,
    max_contract_work: 10000,
    max_work: 100000,
    max_workspace_slots: 10000,
  }
}

///|
fn installed_client_family_providers(
  capacity : @execution.ExecutionCapacity,
) -> Array[@local.ManagedProvider] {
  let records = selected_record_limits()
  [
    @local_sga_provider.provider(selected_graph_limits(), 10000L, capacity),
    @local_tea_provider.provider(records, 100000L, capacity),
    @local_tea_provider.time_series_provider(records, capacity),
    @local_tea_provider.interval_join_provider(records, capacity),
    @local_tea_provider.asof_join_provider(records, capacity),
    @local_tea_provider.sequence_match_provider(records, capacity),
    @local_veca_provider.provider(records, 100000L, capacity),
  ]
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
