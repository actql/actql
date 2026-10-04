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
/// Use the checked task inventory and the same Local import/output envelope
/// for ordinary and Effect computations. Provider capacity and Run capacity
/// are derived together, before any task starts.
fn client_local_sequence_capacity(
  sequences : Array[@execution.GeneratedSequence],
  task_count : Int,
) -> (@resources.LedgerLimits, Int64, Int64)? {
  if task_count < 1 || task_count > 32 || sequences.length() > task_count {
    return None
  }
  let (_, execution, measurement) = client_local_execution_limits()
  let mut retained_bytes = 0L
  let mut execution_bytes = 0L
  let mut total_retained_bytes = 0L
  for sequence in sequences {
    guard @execution.generated_sequence_capacity(
        sequence, execution, measurement,
      )
      is Some(required) else {
      return None
    }
    let retained = @execution.execution_capacity_retained_bytes(required)
    let executing = @execution.execution_capacity_execution_bytes(required)
    if retained < 0L || retained > 536870912L - total_retained_bytes {
      return None
    }
    total_retained_bytes += retained
    if retained > retained_bytes {
      retained_bytes = retained
    }
    if executing > execution_bytes {
      execution_bytes = executing
    }
  }
  let limits : @resources.LedgerLimits = {
    planning_work: 100000,
    attempts: task_count,
    holdings: task_count,
    // Each checked task may import one input under the existing 1 MB wire cap.
    transfer_bytes: task_count.to_int64() * 1000000L,
    retained_bytes: if total_retained_bytes > 200000000L {
      total_retained_bytes
    } else {
      200000000L
    },
    execution_bytes: 536870912L,
  }
  Some((limits, retained_bytes, execution_bytes))
}

///|
/// Keep the original checked Effect owner while sizing its Local suffix.
pub fn client_effect_local_ledger_limits(
  prepared : @publication_host.PreparedClientEffectComputation,
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.LedgerLimits? {
  let graph = @strategy.checked_effect_computation_graph(
    @publication_host.prepared_client_effect_computation_graph(prepared),
  )
  guard prepare_client_effect_local_sequences(
      prepared, registry_body, values_body, fragment_body, ordered_body,
    )
    is Some(sequences) else {
    return None
  }
  let compute = []
  for task in @strategy.graph_captured_prefix(graph)..<sequences.length() {
    compute.push(sequences[task])
  }
  client_local_sequence_capacity(compute, @strategy.graph_task_count(graph)).map(value => {
      value.0
    },
  )
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
  if acquisitions.length() != 2 {
    return None
  }
  let capacities = []
  for acquisition in acquisitions {
    guard @duckdb_host.configured_capture_capacity(acquisition)
      is Some(capacity) else {
      return None
    }
    capacities.push((capacity.retained_bytes, capacity.execution_bytes))
  }
  prepare_multi_captured_capacity_ledger_owned(
    owner, capacities, transport_bytes, transport_execution_bytes, registry_body,
    values_body, fragment_body, ordered_body,
  )
}

///|
fn prepare_multi_captured_capacity_ledger_owned(
  owner : ClientLocalSequenceOwner,
  capacities : Array[(Int64, Int64)],
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
    capacities.length() != 2 ||
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
    let (capture_retained, capture_execution) = capacities[index]
    if capture_retained < 0L ||
      capture_execution < 0L ||
      capture_retained > 9223372036854775807L - retained {
      return None
    }
    retained += capture_retained
    let bytes = transport_bytes[index]
    let scratch = transport_execution_bytes[index]
    if bytes < 0L ||
      bytes > 9223372036854775807L - transfer ||
      scratch < 0L ||
      scratch > 9223372036854775807L - capture_execution {
      return None
    }
    transfer += bytes
    let required_execution = scratch + capture_execution
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
/// An installed capture budget retains the selected acquisition's checked
/// requirement. The Host cannot supply unbound byte counts for a different
/// source occurrence.
struct ClientInstalledCaptureCapacity {
  requirement : @planning.QueryRequirement
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
pub fn installed_duckdb_capture_capacity(
  selected : @duckdb_host.CaptureConfiguration,
) -> ClientInstalledCaptureCapacity? {
  guard @duckdb_host.configured_capture_capacity(selected) is Some(capacity) else {
    return None
  }
  Some({
    requirement: @duckdb_host.configured_capture_requirement(selected),
    retained_bytes: capacity.retained_bytes,
    execution_bytes: capacity.execution_bytes,
  })
}

///|
pub fn installed_row_capture_capacity(
  selected : @row_source_host.RowAcquisition,
) -> ClientInstalledCaptureCapacity? {
  let retained = @row_source_host.row_acquisition_retained_capacity(selected)
  let execution = @row_source_host.row_acquisition_execution_capacity(selected)
  if retained < 0L || execution < retained {
    return None
  }
  Some({
    requirement: @row_source_host.row_acquisition_requirement(selected),
    retained_bytes: retained,
    execution_bytes: execution,
  })
}

///|
pub fn installed_salesforce_capture_capacity(
  requirement : @planning.QueryRequirement,
) -> ClientInstalledCaptureCapacity? {
  let (requirement, retained, execution) = @salesforce_source_host.client_salesforce_prepared_capacity(
    requirement,
  )
  if retained < 0L || execution < retained {
    return None
  }
  Some({ requirement, retained_bytes: retained, execution_bytes: execution, })
}

///|
pub fn prepare_multi_captured_local_installed_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientInstalledCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if capacities.length() != 2 {
    return None
  }
  for index in 0..<2 {
    guard prepare_local_query_requirement(
        prepared, index, 0, registry_body, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      @planning.query_requirement_cid(requirement) ==
      @planning.query_requirement_cid(capacities[index].requirement) else {
      return None
    }
  }
  prepare_multi_captured_capacity_ledger_owned(
    Pure(prepared),
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Admit capacities from the exact selected Native or Broad preparations.
/// Broad's bounded residual remains under its original acquisition owner.
pub fn prepare_multi_captured_local_acquisition_ledger(
  prepared : @publication_host.PreparedClientProgram,
  acquisitions : Array[@duckdb_host.CaptureConfiguration],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  prepare_multi_captured_local_ledger_owned(
    Pure(prepared),
    acquisitions,
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
/// Effect computation uses the same selected-configuration capacity owner.
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

///|
/// Pending Sources contribute their checked candidate envelope before any
/// physical read. Later selection must fit that same envelope; no ledger is
/// replaced or reset when a read is approved.
pub fn prepare_multi_captured_effect_capacity_ledger(
  prepared : @publication_host.PreparedClientEffectComputation,
  capacities : Array[ClientDuckDBCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if capacities.length() != 2 {
    return None
  }
  for index in 0..<2 {
    guard prepare_effect_local_query_requirement(
        prepared, index, 0, registry_body, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      client_duckdb_capture_capacity_matches_requirement(
        capacities[index],
        requirement,
      ) else {
      return None
    }
  }
  prepare_multi_captured_capacity_ledger_owned(
    Effect(prepared),
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}

///|
pub fn prepare_multi_captured_local_capacity_ledger(
  prepared : @publication_host.PreparedClientProgram,
  capacities : Array[ClientDuckDBCaptureCapacity],
  transport_bytes : Array[Int64],
  transport_execution_bytes : Array[Int64],
  registry_body : String,
  values_body : String,
  fragment_body : String?,
  ordered_body : String?,
) -> @resources.Ledger? {
  if capacities.length() != 2 {
    return None
  }
  for index in 0..<2 {
    guard prepare_local_query_requirement(
        prepared, index, 0, registry_body, values_body, fragment_body, ordered_body,
      )
      is Ok(requirement) &&
      client_duckdb_capture_capacity_matches_requirement(
        capacities[index],
        requirement,
      ) else {
      return None
    }
  }
  prepare_multi_captured_capacity_ledger_owned(
    Pure(prepared),
    capacities.map(value => (value.retained_bytes, value.execution_bytes)),
    transport_bytes,
    transport_execution_bytes,
    registry_body,
    values_body,
    fragment_body,
    ordered_body,
  )
}
