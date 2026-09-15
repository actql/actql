///|
pub(all) enum NativeOutputRetentionIssue {
  InvalidState
  Retention(@execution.CaptureIssue)
} derive(Eq, Debug)

///|
/// A bounded materialization of the exact native receipt, not a success token.
/// Keep the receiver relationship distinct from row-engine execution evidence.
struct NativeOutputRows {
  receiver : NativeReceiving
  rows : @execution.AdmittedOutputRows
}

///|
/// Explicit row-container conversion, charged under a fresh physical retention
/// allowance. Immutable values are shared, never decoded or evaluated again.
pub fn retain_native_output_rows(
  receiver : NativeReceiving,
  max_rows : Int,
  limits : @execution.ValueLimits,
) -> Result[NativeOutputRows, NativeOutputRetentionIssue] {
  guard receiver.phase is Received else { return Err(InvalidState) }
  let output = match
    @execution.prepare_admitted_output(
      receiver.scan.query.owner,
      @pipeline.Step(1),
      max_rows,
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(Retention(issue))
  }
  for batch in receiver.native_batches {
    let width = @schema.field_count(receiver.scan.output_schema)
    for row in 0..<batch.rows {
      match
        @execution.append_admitted_output_cells(output, width, column => {
          physical_batch_cell(batch, row, column)
        }) {
        Ok(_) => ()
        Err(issue) => return Err(Retention(issue))
      }
    }
  }
  @execution.finish_admitted_output(output)
  .map(rows => { receiver, rows, })
  .map_err(issue => Retention(issue))
}

///|
pub fn native_output_rows_match(
  output : NativeOutputRows,
  receiver : NativeReceiving,
) -> Bool {
  receiver.phase is Received && physical_equal(output.receiver, receiver)
}

///|
/// Read-only provisional data. A caller still needs successful retained live
/// evidence before publishing capture or crossing a producer boundary.
pub fn native_output_rows(
  output : NativeOutputRows,
) -> @execution.AdmittedOutputRows? {
  if output.receiver.phase is Received {
    Some(output.rows)
  } else {
    None
  }
}
