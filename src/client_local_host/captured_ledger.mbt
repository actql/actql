///|
fn client_local_execution_limits() -> (
  @execution.ValueLimits,
  @execution.SequenceExecutionLimits,
  @execution.FixedInputGuardMeasureLimits,
) {
  // Value budgets over one task input: the text one acquisition captures
  // (500 KB) and a value node for every cell of 100 rows by 100 columns.
  let values : @execution.ValueLimits = {
    max_nodes: 20000,
    max_text_bytes: 500000,
    max_depth: 100,
    max_work: 20000000,
  }
  let execution : @execution.SequenceExecutionLimits = {
    rows: {
      max_rows: 100,
      metadata_entries: 10000,
      retained_entries: 10000,
      operation_entries: 10000,
      input_values: values,
      output_values: values,
    },
    max_work: values.max_work,
    max_frames: 100,
  }
  let measurement : @execution.FixedInputGuardMeasureLimits = {
    max_work: values.max_work,
    max_bytes: values.max_text_bytes,
    max_nodes: values.max_nodes,
    max_depth: values.max_depth,
  }
  (values, execution, measurement)
}

///|
/// Size the existing Run ledger before physical acquisition. Native capture
/// capacities and all downstream retained outputs contribute to this one
/// bounded inventory; no allocation is represented by a synthetic zero.
pub fn prepare_multi_captured_local_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Pure(prepared),
    acquisitions.map(@duckdb_host.native_capture_configuration),
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Use the same capacity and ledger owner while retaining the checked Effect
/// computation. Neither Source capture is copied or silently re-accounted.
pub fn prepare_multi_captured_effect_local_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.NativeHostConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Effect(prepared),
    acquisitions.map(@duckdb_host.native_capture_configuration),
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
fn prepare_multi_captured_local_ledger_owned(
  owner : ClientLocalSequenceOwner,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  let graph = match owner {
    Pure(prepared) => @publication_host.prepared_client_graph(prepared)
    Effect(prepared) =>
      @strategy.checked_effect_computation_graph(
        @publication_host.prepared_client_effect_computation_graph(prepared),
      )
  }
  let count = @strategy.graph_task_count(graph)
  if @strategy.graph_captured_prefix(graph) != 2 ||
    acquisitions.length() != 2 ||
    count < 3 ||
    count > 32 ||
    transport_bytes.length() != 2 ||
    transport_execution_bytes.length() != 2 {
    return None
  }
  guard prepare_client_local_sequences_owned(
      owner, registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) else {
    return None
  }
  let (_, execution, measurement) = client_local_execution_limits()
  let mut retained = 0L
  let mut transfer = count.to_int64() * 1000000L
  let mut execution_capacity = 536870912L
  for index in 0..<2 {
    let acquisition = acquisitions[index]
    guard @duckdb_host.configured_capture_capacity(acquisition)
      is Some(capacity) else {
      return None
    }
    if capacity.retained_bytes < 0L ||
      capacity.retained_bytes > 9223372036854775807L - retained {
      return None
    }
    retained += capacity.retained_bytes
    let bytes = transport_bytes[index]
    let scratch = transport_execution_bytes[index]
    if bytes < 0L ||
      bytes > 9223372036854775807L - transfer ||
      scratch < 0L ||
      scratch > 9223372036854775807L - capacity.execution_bytes {
      return None
    }
    transfer += bytes
    let required_execution = scratch + capacity.execution_bytes
    if required_execution > execution_capacity {
      execution_capacity = required_execution
    }
  }
  let native_retained = retained
  retained = 0L
  for task in 2..<count {
    guard @execution.generated_sequence_capacity(
        sequences[task],
        execution,
        measurement,
      )
      is Some(capacity) else {
      return None
    }
    let bytes = @execution.execution_capacity_retained_bytes(capacity)
    if bytes < 0L || bytes > 9223372036854775807L - retained {
      return None
    }
    retained += bytes
  }
  // Preserve the existing Local import/output allowance in addition to,
  // rather than underneath, the independently held native inputs.
  let compute_retained = if retained > 200000000L {
    retained
  } else {
    200000000L
  }
  if compute_retained > 9223372036854775807L - native_retained {
    return None
  }
  @resources.create_ledger({
    planning_work: 100000,
    attempts: count,
    holdings: count,
    transfer_bytes: transfer,
    retained_bytes: native_retained + compute_retained,
    execution_bytes: execution_capacity,
  }).to_option()
}

///|
/// Admit capacities from the exact selected Native or Broad preparations.
/// Broad's bounded residual remains under its original acquisition owner.
pub fn prepare_multi_captured_effect_acquisition_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Effect(prepared),
    acquisitions,
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}
