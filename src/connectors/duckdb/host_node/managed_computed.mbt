///|
/// Installed Host transport for computed columns only. It cannot issue a
/// completion or substitute for the scoped native execution verifier.
struct ManagedNodeComputed {
  receiver : @duckdb.ManagedComputedPhysicalOutput[Int]
  transport : @duckdb.TransportColumnLimits
}

///|
#export_name("managedComputedOpen")
pub fn managed_computed_open(
  computed : @execution.ManagedComputedView[Int],
  fields : String,
  physical : @duckdb.PhysicalResultLimits,
  transport : @duckdb.TransportColumnLimits,
  max_metadata_work : Int,
) -> ManagedNodeComputed raise NodeHostFailure {
  errdefer @execution.cancel_managed_computed_view(computed) |> ignore
  match
    @duckdb.prepare_managed_computed_physical_output(
      computed,
      transport_fields(transport, fields),
      physical,
      max_metadata_work,
    ) {
    Ok(receiver) => { receiver, transport, }
    Err(issue) => raise ManagedComputed(issue)
  }
}

///|
#export_name("managedComputedCancel")
pub fn managed_computed_cancel(value : ManagedNodeComputed) -> Bool {
  @duckdb.cancel_managed_computed_physical_output(value.receiver)
}

///|
#export_name("managedComputedAccept")
pub fn managed_computed_accept(
  value : ManagedNodeComputed,
  rows : Int,
  data : String,
) -> Unit raise NodeHostFailure {
  errdefer managed_computed_cancel(value) |> ignore
  let columns = chunk_columns(value.transport, data)
  match
    @duckdb.append_managed_computed_physical_output(
      value.receiver,
      rows,
      columns,
    ) {
    Ok(_) => ()
    Err(issue) => raise ManagedComputed(issue)
  }
}

///|
#export_name("managedComputedFinish")
pub fn managed_computed_finish(
  value : ManagedNodeComputed,
) -> @execution.ManagedViewSelection[Int] raise NodeHostFailure {
  match @duckdb.finish_managed_computed_physical_output(value.receiver) {
    Ok(selection) => selection
    Err(issue) => raise ManagedComputed(issue)
  }
}

///|
#export_name("managedComputedUsage")
pub fn managed_computed_usage(value : ManagedNodeComputed) -> Array[Int] {
  let (rows, cells, nodes, bytes) = @duckdb.managed_computed_physical_usage(
    value.receiver,
  )
  [rows, cells, nodes, bytes]
}
