///|
/// Installed Node Host provisional content/retention handle. Only the separate
/// selected-attempt completion entry can issue common managed completion. Store
/// binding and obligation authorization are trusted wiring, not Program options.
struct ManagedNodeOutput {
  receiver : ManagedNodeReceiver
  transport : @duckdb.TransportColumnLimits
  retention : @execution.ManagedOutputRetentionPort[ManagedNodeHolding, Int]
  mut receipt : @execution.ManagedOutputValueReceipt?
  mut material : @execution.ManagedRetainedOutput[Int]?
  mut open : Bool
  valid : Ref[Bool]
}

///|
priv enum ManagedNodeReceiver {
  Values(@duckdb.ManagedPhysicalOutput)
  Compute(ComputeNodeRun, @duckdb_compute.ManagedDuckDBComputeOutput)
}

///|
#export_name("computeHostManagedPrepare")
pub fn compute_host_managed_prepare(
  run : ComputeNodeRun,
  profile : @execution.ManagedExecutionProfile,
  authorize : () -> Bool,
) -> @duckdb_compute.ManagedDuckDBCompletion[Int] raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  match
    @duckdb_compute.prepare_managed_duckdb_completion(
      run.attempt,
      profile,
      authorize,
    ) {
    Ok(port) => port
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("managedOutputCompleteCompute")
pub fn managed_output_complete_compute(
  value : ManagedNodeOutput,
  completion : @duckdb_compute.ManagedDuckDBCompletion[Int],
) -> @execution.ManagedCompletedOutput[Int] raise NodeHostFailure {
  guard value.receiver is Compute(run, receiver) &&
    !run.closed &&
    value.valid.val &&
    value.material is Some(material) else {
    raise InvalidCommand
  }
  match
    @duckdb_compute.complete_managed_duckdb_compute_attempt(
      completion, receiver, material,
    ) {
    Ok(output) => output
    Err(issue) => raise Compute(issue)
  }
}

///|
#export_name("managedCompletedAvailable")
pub fn managed_completed_available(
  value : @execution.ManagedCompletedOutput[Int],
) -> Bool {
  @execution.managed_completed_output_available(value)
}

///|
priv struct ManagedNodeHolding {
  receipt : @execution.ManagedOutputValueReceipt
  bytes : Int64
  available : () -> Bool
}

///|
#export_name("managedOutputOpen")
pub fn managed_output_open(
  values : @execution.ManagedOutputValues,
  fields : String,
  physical : @duckdb.PhysicalResultLimits,
  transport : @duckdb.TransportColumnLimits,
  max_metadata_work : Int,
) -> ManagedNodeOutput raise NodeHostFailure {
  let receiver = match
    @duckdb.prepare_managed_physical_output(
      values,
      transport_fields(transport, fields),
      physical,
      max_metadata_work,
    ) {
    Ok(value) => value
    Err(issue) => raise ManagedValues(issue)
  }
  managed_node_output(Values(receiver), values, transport)
}

///|
fn managed_node_output(
  receiver : ManagedNodeReceiver,
  values : @execution.ManagedOutputValues,
  transport : @duckdb.TransportColumnLimits,
) -> ManagedNodeOutput raise NodeHostFailure {
  let retention = match
    @execution.prepare_managed_output_retention_port(values, (
      proof : ManagedNodeHolding,
    ) => Some((proof.receipt, 1, proof.bytes, proof.available))) {
    Ok(value) => value
    Err(issue) => raise ManagedRetention(issue)
  }
  {
    receiver,
    transport,
    retention,
    receipt: None,
    material: None,
    open: true,
    valid: Ref(true),
  }
}

///|
/// Installed Host entry for the actual selected Compute, not a caller-supplied
/// value stream. Identity/profile obligation admission remains the Host's job.
#export_name("computeHostManagedOutputBegin")
pub fn compute_host_managed_output_begin(
  run : ComputeNodeRun,
  fields : String,
) -> ManagedNodeOutput raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let receiver = match
    @duckdb_compute.begin_managed_duckdb_compute_output(
      run.attempt,
      transport_fields(run.transport, fields),
    ) {
    Ok(value) => value
    Err(issue) => raise Compute(issue)
  }
  errdefer @duckdb_compute.cancel_managed_duckdb_compute_output(receiver)
  managed_node_output(
    Compute(run, receiver),
    @duckdb_compute.managed_duckdb_compute_output_values(receiver),
    run.transport,
  )
}

///|
#export_name("managedOutputCancel")
pub fn managed_output_cancel(value : ManagedNodeOutput) -> Unit {
  value.open = false
  value.valid.val = false
  match value.receiver {
    Values(receiver) =>
      @duckdb.cancel_managed_physical_output(receiver) |> ignore
    Compute(_, receiver) =>
      @duckdb_compute.cancel_managed_duckdb_compute_output(receiver)
  }
  @execution.cancel_managed_output_retention_port(value.retention) |> ignore
}

///|
#export_name("managedOutputAccept")
pub fn managed_output_accept(
  value : ManagedNodeOutput,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  if !value.open {
    raise InvalidCommand
  }
  errdefer managed_output_cancel(value)
  let columns = chunk_columns(value.transport, data)
  match value.receiver {
    Values(receiver) =>
      match @duckdb.append_managed_physical_output(receiver, rows, columns) {
        Ok(_) => ()
        Err(issue) => raise ManagedValues(issue)
      }
    Compute(run, receiver) => {
      if run.closed {
        raise InvalidCommand
      }
      match
        @duckdb_compute.receive_managed_duckdb_compute_output(
          receiver, rows, columns,
        ) {
        Ok(_) => ()
        Err(issue) => raise Compute(issue)
      }
    }
  }
}

///|
#export_name("managedOutputFinish")
pub fn managed_output_finish(
  value : ManagedNodeOutput,
) -> Unit raise NodeHostFailure {
  if !value.open {
    raise InvalidCommand
  }
  value.open = false
  errdefer managed_output_cancel(value)
  value.receipt = Some(
    match value.receiver {
      Values(receiver) =>
        match @duckdb.finish_managed_physical_output(receiver) {
          Ok(receipt) => receipt
          Err(issue) => raise ManagedValues(issue)
        }
      Compute(run, receiver) => {
        if run.closed {
          raise InvalidCommand
        }
        match @duckdb_compute.finish_managed_duckdb_compute_output(receiver) {
          Ok(receipt) => receipt
          Err(issue) => raise Compute(issue)
        }
      }
    },
  )
}

///|
/// Actual transport settlement, consumer demand and exact Store evidence are
/// required. A value-only receiver can never pass this execution boundary.
#export_name("managedOutputVerifyCompute")
pub fn managed_output_verify_compute(
  value : ManagedNodeOutput,
) -> Unit raise NodeHostFailure {
  errdefer managed_output_cancel(value)
  guard value.receiver is Compute(run, receiver) &&
    !run.closed &&
    value.material is Some(_) &&
    value.valid.val else {
    raise InvalidCommand
  }
  match @duckdb_compute.verify_managed_duckdb_compute_output(receiver) {
    Err(issue) => raise Compute(issue)
    Ok(_) => ()
  }
  if !managed_output_compute_verified(value) {
    raise InvalidCommand
  }
}

///|
#export_name("managedOutputComputeVerified")
pub fn managed_output_compute_verified(value : ManagedNodeOutput) -> Bool {
  guard value.receiver is Compute(run, receiver) &&
    !run.closed &&
    value.valid.val &&
    value.material is Some(material) else {
    return false
  }
  @duckdb_compute.verified_managed_duckdb_compute_material(receiver, material)
  is Some(_) &&
  !run.closed &&
  value.valid.val
}

///|
/// Only installed Store wiring calls this after verifying/sealing the exact
/// received representation. Physical bytes are not a logical CID or logical
/// byte measure. This does not replace Store pin/resource/use admission.
#export_name("managedOutputRetain")
pub fn managed_output_retain(
  value : ManagedNodeOutput,
  bytes : Int64,
  available : () -> Bool,
) -> Unit raise NodeHostFailure {
  guard value.receipt is Some(receipt) else { raise InvalidCommand }
  let valid = value.valid
  match
    @execution.retain_managed_output(value.retention, {
      receipt,
      bytes,
      available: fn() { valid.val && available() && valid.val },
    }) {
    Err(issue) => raise ManagedRetention(issue)
    Ok(material) => value.material = Some(material)
  }
}

///|
#export_name("managedOutputAvailable")
pub fn managed_output_available(value : ManagedNodeOutput) -> Bool {
  guard value.material is Some(material) && value.receipt is Some(receipt) else {
    return false
  }
  @execution.managed_retained_output_matches(material, receipt)
}

///|
#export_name("managedOutputMeasurements")
pub fn managed_output_measurements(
  value : ManagedNodeOutput,
) -> Array[Int] raise NodeHostFailure {
  guard value.receipt is Some(receipt) else { raise InvalidCommand }
  let (work, bytes, nodes) = @execution.managed_output_value_measurement(
    receipt,
  )
  [@execution.managed_output_value_row_count(receipt), work, bytes, nodes]
}
