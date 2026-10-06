///|
/// Stage a copied runtime cell using the shared contract recheck cursor.
/// Raw Text must not run its Unicode scan before the first resumable step.
fn start_ordered_output_value_recheck(
  value : Value,
  contract : @contract.Contract,
  limits : @admitted.Limits,
) -> @admitted.RecheckCursor? {
  if value is Text(text) {
    return @admitted.start_recheck_runtime_text(text, contract, limits)
  }
  let admitted = match value {
    Null => Some(@admitted.null_value())
    Number(number) => @admitted.number_value(number)
    Boolean(boolean) => Some(@admitted.boolean_value(boolean))
    Text(_) => None
    Captured(captured) => Some(captured)
  }
  guard admitted is Some(admitted) else { return None }
  @admitted.start_recheck_runtime_value(admitted, contract, limits)
}

///|
priv enum BoundedOutputRowChargePhase {
  Name
  Value
  MeasureName
  MeasureValue
  Commit
  Terminal
}

///|
/// A row of already rechecked immutable values stays private until all its
/// logical output occurrences have been charged. The caller owns the row's
/// storage reservation; this cursor accounts its temporary traversal frames.
priv struct BoundedOutputRowCharge {
  output : AdmittedOutput
  workspace : RowWorkspace
  mut cells : Array[@admitted.Value]
  mut presence_cells : Array[@admitted.Value?]?
  initial_usage : ValueUsage
  mut column : Int
  mut measure : SteppedValueMeasure?
  mut phase : BoundedOutputRowChargePhase
}

///|
priv enum BoundedOutputRowChargeIssue {
  OutputCapture(CaptureIssue)
  OutputWorkspace
}

///|
fn start_bounded_output_row_charge(
  output : AdmittedOutput,
  cells : Array[@admitted.Value],
  workspace : RowWorkspace,
  presence_cells? : Array[@admitted.Value?]? = None,
) -> Result[BoundedOutputRowCharge, BoundedOutputRowChargeIssue] {
  let buffer = output.buffer
  if !buffer.open || buffer.reading {
    return Err(OutputCapture(ClosedCapture))
  }
  let width = @schema.field_count(buffer.schema)
  let conditional = !@schema.all_fields_required(buffer.schema)
  let valid = match presence_cells {
    Some(presence) =>
      conditional && cells.is_empty() && presence.length() == width
    None => !conditional && cells.length() == width
  }
  if !valid {
    return Err(OutputCapture(InvalidCheckedRow))
  }
  let count = if conditional {
    buffer.presence_rows.length()
  } else {
    buffer.rows.length()
  }
  let initial_usage = {
    nodes: buffer.budget.nodes,
    text_bytes: buffer.budget.text,
    work: buffer.budget.work,
  }
  if count >= buffer.max_rows ||
    !charge_node(buffer.budget, 1) ||
    width > buffer.budget.limits.max_nodes - buffer.budget.nodes {
    return Err(OutputCapture(CaptureLimit))
  }
  buffer.reading = true
  Ok({
    output,
    workspace,
    cells,
    presence_cells,
    initial_usage,
    column: 0,
    measure: None,
    phase: if width == 0 {
      Commit
    } else {
      Name
    },
  })
}

///|
fn cleanup_bounded_output_row_charge(cursor : BoundedOutputRowCharge) -> Unit {
  if cursor.measure is Some(measure) {
    clear_stepped_measure(measure)
    cursor.measure = None
  }
  if !(cursor.phase is Terminal) {
    cursor.output.buffer.reading = false
  }
  cursor.cells = []
  cursor.presence_cells = None
  cursor.phase = Terminal
}

///|
/// One field-name chunk, bounded small value, or nested value traversal step.
/// The final commit transfers the existing row array without a second copy.
fn advance_bounded_output_row_charge(
  cursor : BoundedOutputRowCharge,
) -> Result[Bool, BoundedOutputRowChargeIssue] {
  let buffer = cursor.output.buffer
  if !buffer.open || !buffer.reading || cursor.phase is Terminal {
    return Err(OutputCapture(ClosedCapture))
  }
  match cursor.phase {
    Name => {
      guard @schema.field_at(buffer.schema, cursor.column) is Some(field) else {
        return Err(OutputCapture(InvalidCheckedRow))
      }
      if cursor.presence_cells is None &&
        !(@schema.field_presence(field) is @schema.Required) {
        return Err(OutputCapture(ConditionalInputRequiresPresence))
      }
      let name = @schema.reference_name(field.name)
      if name.length() <= 64 {
        if !charge_text(buffer.budget, name) {
          return Err(OutputCapture(CaptureLimit))
        }
        cursor.phase = Value
      } else {
        let measure = {
          frames: [],
          workspace: cursor.workspace,
          workspace_failed: false,
        }
        if !push_stepped_measure(measure, SteppedTextNext(name, 0)) {
          return Err(OutputWorkspace)
        }
        cursor.measure = Some(measure)
        cursor.phase = MeasureName
      }
    }
    Value => {
      let cell = match cursor.presence_cells {
        Some(cells) => cells.get(cursor.column)
        None => cursor.cells.get(cursor.column).map(value => Some(value))
      }
      guard cell is Some(cell) else {
        return Err(OutputCapture(InvalidCheckedRow))
      }
      let value = match cell {
        Some(value) => value
        None => {
          guard @schema.field_at(buffer.schema, cursor.column) is Some(field) &&
            field.presence == @schema.Conditional else {
            return Err(OutputCapture(InvalidCheckedRow))
          }
          // The physical presence slot has a node cost, not a NULL value.
          if !charge_node(buffer.budget, 2) {
            return Err(OutputCapture(CaptureLimit))
          }
          cursor.column += 1
          cursor.phase = if cursor.column == @schema.field_count(buffer.schema) {
            Commit
          } else {
            Name
          }
          return Ok(false)
        }
      }
      if bounded_small_output_value(Captured(value)) {
        if !measure(value, 2, buffer.budget) {
          return Err(OutputCapture(CaptureLimit))
        }
        cursor.column += 1
        cursor.phase = if cursor.column == @schema.field_count(buffer.schema) {
          Commit
        } else {
          Name
        }
      } else {
        guard start_stepped_measure_result(Captured(value), cursor.workspace)
          is Some(measure) else {
          return Err(OutputWorkspace)
        }
        cursor.measure = Some(measure)
        cursor.phase = MeasureValue
      }
    }
    MeasureName | MeasureValue => {
      guard cursor.measure is Some(measure) else {
        return Err(OutputCapture(InvalidCheckedRow))
      }
      match advance_stepped_measure_result(measure, buffer.budget) {
        SteppedMeasureLimit => return Err(OutputCapture(CaptureLimit))
        SteppedMeasureWorkspaceLimit => return Err(OutputWorkspace)
        SteppedMeasureContinue => ()
        SteppedMeasureComplete => {
          clear_stepped_measure(measure)
          cursor.measure = None
          if cursor.phase is MeasureName {
            cursor.phase = Value
          } else {
            cursor.column += 1
            cursor.phase = if cursor.column ==
              @schema.field_count(buffer.schema) {
              Commit
            } else {
              Name
            }
          }
        }
      }
    }
    Commit => {
      if cursor.presence_cells is Some(cells) {
        buffer.presence_rows.push({
          schema: buffer.schema,
          cells,
          usage: {
            nodes: buffer.budget.nodes - cursor.initial_usage.nodes,
            text_bytes: buffer.budget.text - cursor.initial_usage.text_bytes,
            work: buffer.budget.work - cursor.initial_usage.work,
          },
        })
        cursor.presence_cells = None
      } else {
        buffer.rows.push(cursor.cells)
      }
      cursor.cells = []
      buffer.reading = false
      cursor.phase = Terminal
      return Ok(true)
    }
    Terminal => return Err(OutputCapture(ClosedCapture))
  }
  Ok(false)
}
