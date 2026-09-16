///|
/// Installed Node Host content receiver. It issues no execution completion,
/// consumer authorization or portable evidence. Store binding is trusted wiring.
struct ManagedNodeOutput {
  receiver : @duckdb.ManagedPhysicalOutput
  transport : @duckdb.TransportColumnLimits
  retention : @execution.ManagedOutputRetentionPort[ManagedNodeHolding, Int]
  mut receipt : @execution.ManagedOutputValueReceipt?
  mut material : @execution.ManagedRetainedOutput[Int]?
  mut open : Bool
  valid : Ref[Bool]
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
#export_name("managedOutputCancel")
pub fn managed_output_cancel(value : ManagedNodeOutput) -> Unit {
  value.open = false
  value.valid.val = false
  @duckdb.cancel_managed_physical_output(value.receiver) |> ignore
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
  match @duckdb.append_managed_physical_output(value.receiver, rows, columns) {
    Ok(_) => ()
    Err(issue) => raise ManagedValues(issue)
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
  match @duckdb.finish_managed_physical_output(value.receiver) {
    Err(issue) => {
      managed_output_cancel(value)
      raise ManagedValues(issue)
    }
    Ok(receipt) => value.receipt = Some(receipt)
  }
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
