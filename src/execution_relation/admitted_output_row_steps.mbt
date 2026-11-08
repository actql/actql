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
  buffer : AdmittedRowBuffer
  workspace : RowWorkspace
  mut scope : SlotScope?
  mut read : ((Int) -> RelationCell?)?
  mut column : Int
  mut cells : Array[@admitted.Value]
  mut presence_cells : Array[@admitted.Value?]?
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
  start_admitted_output_row_state(
    output,
    max_workspace_slots,
    column => read(column).map(value => Present(value)),
    false,
  )
}

///|
/// Explicit absence is accepted only for a conditional schema field. An
/// unavailable coordinate is not an absent cell, and NULL remains a value.
pub fn start_admitted_presence_output_row(
  output : AdmittedOutput,
  max_workspace_slots : Int,
  read : (Int) -> RelationCell?,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  start_admitted_output_row_state(output, max_workspace_slots, read, true)
}

///|
fn start_admitted_output_row_state(
  output : AdmittedOutput,
  max_workspace_slots : Int,
  read : (Int) -> RelationCell?,
  allow_presence : Bool,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  start_admitted_buffer_row_state(
    output.buffer,
    max_workspace_slots,
    read,
    allow_presence,
  )
}

///|
fn start_admitted_buffer_row_state(
  buffer : AdmittedRowBuffer,
  max_workspace_slots : Int,
  read : (Int) -> RelationCell?,
  allow_presence : Bool,
) -> Result[AdmittedOutputRowCursor, AdmittedOutputRowIssue] {
  if !buffer.open || buffer.reading {
    return Err(OutputRowCapture(ClosedCapture))
  }
  let width = @schema.field_count(buffer.schema)
  let conditional = !@schema.all_fields_required(buffer.schema)
  let count = if conditional {
    buffer.presence_rows.length()
  } else {
    buffer.rows.length()
  }
  if count >= buffer.max_rows {
    return Err(OutputRowCapture(CaptureLimit))
  }
  if conditional && !allow_presence {
    return Err(OutputRowCapture(ConditionalInputRequiresPresence))
  }
  let workspace = row_workspace(max_workspace_slots)
  guard width < 2147483647 &&
    begin_slot_scope(workspace, width + 1) is Some(scope) else {
    return Err(OutputRowWorkspace)
  }
  buffer.reading = true
  Ok({
    buffer,
    workspace,
    scope: Some(scope),
    read: Some(read),
    column: 0,
    cells: [],
    presence_cells: if conditional {
      Some([])
    } else {
      None
    },
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
  let buffer = cursor.buffer
  if cursor.cleaned || cursor.phase is Complete || cursor.phase is Failed {
    return Err(OutputRowCapture(ClosedCapture))
  }
  if !buffer.open || !buffer.reading {
    return fail_admitted_output_row(cursor, OutputRowCapture(ClosedCapture))
  }
  match cursor.phase {
    ReadCell => {
      guard cursor.read is Some(read) &&
        read(cursor.column) is Some(cell) &&
        @schema.field_at(buffer.schema, cursor.column) is Some(field) else {
        return fail_admitted_output_row(
          cursor,
          OutputRowCapture(InvalidCheckedRow),
        )
      }
      if !buffer.open || !buffer.reading {
        return fail_admitted_output_row(cursor, OutputRowCapture(ClosedCapture))
      }
      let value = match cell {
        Absent => {
          guard field.presence == @schema.Conditional &&
            cursor.presence_cells is Some(cells) else {
            return fail_admitted_output_row(
              cursor,
              OutputRowCapture(InvalidCheckedRow),
            )
          }
          cells.push(None)
          cursor.column += 1
          cursor.phase = if cursor.column == @schema.field_count(buffer.schema) {
            StartCharge
          } else {
            ReadCell
          }
          return Ok(false)
        }
        Present(value) => value
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
          if cursor.presence_cells is Some(cells) {
            cells.push(Some(checked.value))
          } else {
            cursor.cells.push(checked.value)
          }
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
        start_bounded_buffer_row_charge(
          cursor.buffer,
          cursor.cells,
          cursor.workspace,
          presence_cells=cursor.presence_cells,
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
      cursor.presence_cells = None
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
    revoke_admitted_buffer(cursor.buffer)
    cursor.buffer.reading = false
  }
  cursor.cells = []
  cursor.presence_cells = None
  cursor.read = None
  if cursor.scope is Some(scope) {
    scope.close() |> ignore
    cursor.scope = None
  }
  cursor.cleaned = true
  workspace_healthy(cursor.workspace) && cursor.workspace.live == 0
}

///|
/// Read-only accounting for the caller's encompassing workspace reservation.
/// This does not grant access to provisional cells or completion authority.
pub fn admitted_output_row_workspace_usage(
  cursor : AdmittedOutputRowCursor,
) -> (Int, Int) {
  (cursor.workspace.live, cursor.workspace.peak)
}

///|
/// Construction for the NEXT original row-admission step. Payloads and field
/// contracts remain borrowed. Recheck and value-charge continuations each pop
/// one frame and push at most two, so live pending frames plus one suffice.
/// This is an actual cursor projection, not the logical node/work ceiling.
/// The caller retains its existing fixed controls and grows before advancing.
pub fn admitted_output_row_next_construction(
  cursor : AdmittedOutputRowCursor,
) -> PreparationRepresentationUnits? {
  if cursor.cleaned || cursor.phase is Complete || cursor.phase is Failed {
    return None
  }
  let pending = match cursor.phase {
    RecheckCell =>
      cursor.recheck.map(@admitted.recheck_pending_frames).unwrap_or(0)
    Charge =>
      match cursor.charge {
        Some(charge) =>
          charge.measure.map(value => value.frames.length()).unwrap_or(0)
        None => 0
      }
    _ => 0
  }
  // Include the popped frame and transient next-frame/result carriers. Every
  // recheck variant has at most four references/six scalar payload words;
  // the charge variants fit the same envelope. No child array/String is copied.
  let frames = pending.to_int64() + 2L
  guard @shape.collection_construction_extent({
      records: frames,
      record_references: frames * 4L,
      record_words: frames * 6L,
      reference_arrays: 1L,
      reference_items: frames,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: 0L,
      map_entries: 0L,
    })
    is Some(extent) else {
    return None
  }
  Some({
    record_headers: extent.record_headers,
    reference_slots: extent.reference_slots,
    scalar_words: extent.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}
