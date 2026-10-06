///|
priv enum AdmittedOutputRowPhase {
  ReadCell
  RecheckCell
  StartCharge
  Charge
  Complete
  Failed
}

///|
/// One provisional row, driven by its caller's existing bounded execution.
/// It grants neither execution completion nor publication authority.
struct AdmittedOutputRowCursor {
  output : AdmittedOutput
  workspace : RowWorkspace
  mut scope : SlotScope?
  mut read : ((Int) -> @admitted.Value?)?
  mut column : Int
  mut cells : Array[@admitted.Value]
  mut recheck : @admitted.RecheckCursor?
  mut charge : BoundedOutputRowCharge?
  mut phase : AdmittedOutputRowPhase
  mut cleaned : Bool
}

///|
pub enum AdmittedOutputRowIssue {
  OutputRowCapture(CaptureIssue)
  OutputRowWorkspace
} derive(Eq, Debug)

///|
/// Reserve the temporary row before reading. The existing output buffer stays
/// exclusively held across every yield, including contract rechecking.
pub fn start_admitted_output_row(
  output : AdmittedOutput,
  max_workspace_slots : Int,
  read : (Int) -> @admitted.Value?,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  let buffer = output.buffer
  if !buffer.open || buffer.reading {
    return Err(OutputRowCapture(ClosedCapture))
  }
  let width = @schema.field_count(buffer.schema)
  if buffer.rows.length() >= buffer.max_rows {
    return Err(OutputRowCapture(CaptureLimit))
  }
  if !@schema.all_fields_required(buffer.schema) {
    return Err(OutputRowCapture(ConditionalInputRequiresPresence))
  }
  let workspace = row_workspace(max_workspace_slots)
  guard width < 2147483647 &&
    begin_slot_scope(workspace, width + 1) is Some(scope) else {
    return Err(OutputRowWorkspace)
  }
  buffer.reading = true
  Ok({
    output,
    workspace,
    scope: Some(scope),
    read: Some(read),
    column: 0,
    cells: [],
    recheck: None,
    charge: None,
    phase: if width == 0 {
      StartCharge
    } else {
      ReadCell
    },
    cleaned: false,
  })
}

///|
fn fail_admitted_output_row(
  cursor : AdmittedOutputRowCursor,
  issue : AdmittedOutputRowIssue,
) -> Result[Bool, AdmittedOutputRowIssue] {
  // Keep both custody and the buffer lock until the stopped caller cleans up.
  cursor.phase = Failed
  Err(issue)
}

///|
/// One cell read, shared recheck poll, or shared logical-charge poll. True
/// commits this row only; the existing output owner must still finish/seal it.
pub fn advance_admitted_output_row(
  cursor : AdmittedOutputRowCursor,
) -> Result[Bool, AdmittedOutputRowIssue] {
  let buffer = cursor.output.buffer
  if cursor.cleaned || cursor.phase is Complete || cursor.phase is Failed {
    return Err(OutputRowCapture(ClosedCapture))
  }
  if !buffer.open || !buffer.reading {
    return fail_admitted_output_row(cursor, OutputRowCapture(ClosedCapture))
  }
  match cursor.phase {
    ReadCell => {
      guard cursor.read is Some(read) &&
        read(cursor.column) is Some(value) &&
        @schema.field_at(buffer.schema, cursor.column) is Some(field) else {
        return fail_admitted_output_row(
          cursor,
          OutputRowCapture(InvalidCheckedRow),
        )
      }
      if !buffer.open || !buffer.reading {
        return fail_admitted_output_row(cursor, OutputRowCapture(ClosedCapture))
      }
      guard @admitted.start_recheck_runtime_value(value, field.contract, {
          max_nodes: buffer.budget.limits.max_nodes - buffer.budget.nodes,
          max_depth: buffer.budget.limits.max_depth,
          max_text_bytes: buffer.budget.limits.max_text_bytes -
          buffer.budget.text,
        })
        is Some(recheck) else {
        return fail_admitted_output_row(
          cursor,
          OutputRowCapture(InvalidCheckedRow),
        )
      }
      cursor.recheck = Some(recheck)
      cursor.phase = RecheckCell
    }
    RecheckCell => {
      guard cursor.recheck is Some(recheck) else {
        return fail_admitted_output_row(
          cursor,
          OutputRowCapture(InvalidCheckedRow),
        )
      }
      match @admitted.advance_recheck_runtime_value(recheck) {
        @admitted.RecheckContinue => ()
        @admitted.RecheckFailed =>
          return fail_admitted_output_row(
            cursor,
            OutputRowCapture(InvalidCheckedRow),
          )
        @admitted.RecheckComplete(checked, _, _) => {
          cursor.cells.push(checked.value)
          cursor.recheck = None
          cursor.column += 1
          cursor.phase = if cursor.column == @schema.field_count(buffer.schema) {
            StartCharge
          } else {
            ReadCell
          }
        }
      }
    }
    StartCharge => {
      // No callback or await occurs between the two lock transitions.
      buffer.reading = false
      match
        start_bounded_output_row_charge(
          cursor.output,
          cursor.cells,
          cursor.workspace,
        ) {
        Err(OutputCapture(issue)) => {
          buffer.reading = true
          return fail_admitted_output_row(cursor, OutputRowCapture(issue))
        }
        Err(OutputWorkspace) => {
          buffer.reading = true
          return fail_admitted_output_row(cursor, OutputRowWorkspace)
        }
        Ok(charge) => cursor.charge = Some(charge)
      }
      cursor.cells = []
      cursor.phase = Charge
    }
    Charge => {
      guard cursor.charge is Some(charge) else {
        return fail_admitted_output_row(
          cursor,
          OutputRowCapture(InvalidCheckedRow),
        )
      }
      match advance_bounded_output_row_charge(charge) {
        Err(OutputCapture(issue)) =>
          return fail_admitted_output_row(cursor, OutputRowCapture(issue))
        Err(OutputWorkspace) =>
          return fail_admitted_output_row(cursor, OutputRowWorkspace)
        Ok(false) => ()
        Ok(true) => {
          cleanup_bounded_output_row_charge(charge)
          cursor.charge = None
          cursor.read = None
          guard cursor.scope is Some(scope) && scope.close() else {
            return fail_admitted_output_row(cursor, OutputRowWorkspace)
          }
          cursor.scope = None
          cursor.phase = Complete
          return Ok(true)
        }
      }
    }
    Complete | Failed => return Err(OutputRowCapture(ClosedCapture))
  }
  Ok(false)
}

///|
/// The stopped caller discards an incomplete output, not just its newest row.
/// Successful row cleanup leaves committed rows under the original owner.
pub fn cleanup_admitted_output_row(cursor : AdmittedOutputRowCursor) -> Bool {
  if cursor.cleaned {
    return false
  }
  if cursor.recheck is Some(recheck) {
    @admitted.cancel_recheck_runtime_value(recheck)
    cursor.recheck = None
  }
  if cursor.charge is Some(charge) {
    cleanup_bounded_output_row_charge(charge)
    cursor.charge = None
  }
  if !(cursor.phase is Complete) {
    cancel_admitted_output(cursor.output) |> ignore
    cursor.output.buffer.reading = false
  }
  cursor.cells = []
  cursor.read = None
  if cursor.scope is Some(scope) {
    scope.close() |> ignore
    cursor.scope = None
  }
  cursor.cleaned = true
  workspace_healthy(cursor.workspace) && cursor.workspace.live == 0
}
