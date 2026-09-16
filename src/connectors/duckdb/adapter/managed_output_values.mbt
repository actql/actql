///|
/// Typed chunk adapter for new-profile value evidence. This does not issue a
/// native execution receipt, Acquisition observation or common completion.
struct ManagedPhysicalOutput {
  physical : PhysicalResult
  values : @execution.ManagedOutputValues
  mut open : Bool
}

///|
pub(all) enum ManagedPhysicalOutputIssue {
  Physical(PhysicalResultIssue)
  Values(@execution.ManagedOutputValueIssue)
  Closed
}

///|
pub fn prepare_managed_physical_output(
  values : @execution.ManagedOutputValues,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[ManagedPhysicalOutput, ManagedPhysicalOutputIssue] {
  prepare_physical_result(
    @execution.managed_output_values_schema(values),
    fields,
    limits,
    max_metadata_work,
  )
  .map(physical => { physical, values, open: true, })
  .map_err(issue => Physical(issue))
}

///|
pub fn cancel_managed_physical_output(output : ManagedPhysicalOutput) -> Bool {
  if !output.open {
    return false
  }
  output.open = false
  output.physical.terminal = true
  @execution.cancel_managed_output_values(output.values) |> ignore
  true
}

///|
pub fn append_managed_physical_output(
  output : ManagedPhysicalOutput,
  rows : Int,
  columns : Array[@decode.Cursor],
) -> Result[Unit, ManagedPhysicalOutputIssue] {
  if !output.open {
    return Err(Closed)
  }
  let batch = match admit_physical_chunk(output.physical, rows, columns) {
    Ok(batch) => batch
    Err(issue) => {
      cancel_managed_physical_output(output) |> ignore
      return Err(Physical(issue))
    }
  }
  for row in 0..<rows {
    match
      @execution.append_managed_output_values(
        output.values,
        output.physical.mappings.length(),
        column => physical_batch_cell(batch, row, column),
      ) {
      Ok(_) => ()
      Err(issue) => {
        cancel_managed_physical_output(output) |> ignore
        return Err(Values(issue))
      }
    }
  }
  Ok(())
}

///|
pub fn finish_managed_physical_output(
  output : ManagedPhysicalOutput,
) -> Result[@execution.ManagedOutputValueReceipt, ManagedPhysicalOutputIssue] {
  if !output.open {
    return Err(Closed)
  }
  output.open = false
  output.physical.terminal = true
  @execution.finish_managed_output_values(output.values).map_err(issue => {
    Values(issue)
  })
}
