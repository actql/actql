///|
priv enum ManagedOutputFactsPhase {
  ValidateColumns
  ChooseMeasurement
  MeasureIndex
  Complete
}

///|
/// The same summary admission algorithm serves blocking and resumed issuers.
/// It owns no independent budget: successful summary charges commit once, and
/// ordered diagnostics charge the original guard as each row/cell is visited.
priv struct ManagedOutputFactsCursor {
  stream : ManagedOutputValues
  facts : ManagedViewOutputFacts
  validate_column : (Int, ManagedColumnMeasurement) -> Bool
  index : ManagedRowMeasurements?
  width : Int
  mut phase : ManagedOutputFactsPhase
  mut column : Int
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  mut needs_ordered : Bool
  mut measurement : ManagedOutputIndexCursor?
}

///|
priv struct ManagedOutputIndexCursor {
  index : ManagedRowMeasurements
  rows : Int
  width : Int
  ceiling : Int
  budget : FixedInputGuardBudget
  mut row : Int
  mut column : Int
  mut row_started : Bool
}

///|
fn prepare_managed_output_facts_cursor(
  stream : ManagedOutputValues,
  facts : ManagedViewOutputFacts,
  validate_column : (Int, ManagedColumnMeasurement) -> Bool,
  index : ManagedRowMeasurements?,
) -> Result[ManagedOutputFactsCursor, ManagedViewOutputIssue] {
  if !stream.open || facts.rows < 0 ||
    facts.columns.length() != @schema.field_count(stream.buffer.schema) {
    return Err(if !stream.open { Closed } else { InconsistentFacts })
  }
  let usage = facts.admission_usage
  let limits = stream.buffer.budget.limits
  if usage.nodes < 0 || usage.text_bytes < 0 || usage.work < 0 {
    return Err(InconsistentFacts)
  }
  if facts.rows > stream.max_rows || usage.nodes > limits.max_nodes ||
    usage.text_bytes > limits.max_text_bytes || usage.work > limits.max_work {
    return Err(OutputRepresentationRequired)
  }
  let budget = stream.measurement
  Ok({
    stream, facts, validate_column, index,
    width: facts.columns.length(),
    phase: ValidateColumns, column: 0,
    work: if facts.rows > budget.work { budget.work } else { budget.work - facts.rows },
    bytes: budget.bytes, nodes: budget.nodes,
    needs_ordered: facts.rows > budget.work,
    measurement: None,
  })
}

///|
fn advance_managed_output_facts_cursor(
  cursor : ManagedOutputFactsCursor,
  quantum : Int,
) -> Result[(Bool, Int), ManagedViewOutputIssue] {
  if quantum <= 0 { return Err(Closed) }
  let stream = cursor.stream
  let facts = cursor.facts
  let budget = stream.measurement
  let limits = stream.buffer.budget.limits
  for step in 0..<quantum {
    if !stream.open { return Err(Closed) }
    match cursor.phase {
      ValidateColumns =>
        if facts.columns.length() != cursor.width {
          return Err(InconsistentFacts)
        } else if cursor.column == cursor.width {
          cursor.phase = ChooseMeasurement
        } else {
          let column = facts.columns[cursor.column]
          if column.rows != facts.rows || column.bytes < 0 || column.nodes < 0 ||
            column.max_value_bytes < 0 || column.null_rows < 0 ||
            column.null_rows > facts.rows || column.admitted_depth < 0 ||
            column.max_value_bytes > column.bytes ||
            (facts.rows == 0 && (column.bytes != 0 || column.nodes != 0)) {
            return Err(InconsistentFacts)
          }
          if !(cursor.validate_column)(cursor.column, column) {
            return Err(InconsistentFacts)
          }
          if !stream.open { return Err(Closed) }
          if facts.rows > 0 &&
            (column.admitted_depth > budget.depth || column.admitted_depth > limits.max_depth) {
            return Err(OutputRepresentationRequired)
          }
          if !cursor.needs_ordered {
            if column.max_value_bytes > stream.max_value_bytes ||
              facts.rows > cursor.work || column.bytes > cursor.bytes ||
              column.nodes > cursor.nodes {
              cursor.needs_ordered = true
            } else {
              cursor.work -= facts.rows
              cursor.bytes -= column.bytes
              cursor.nodes -= column.nodes
            }
          }
          // Snapshot validated scalars into existing private metadata. Never
          // reread a verifier-owned mutable array after a yield or allocate a
          // second per-column snapshot outside the existing capacity owner.
          stream.column_usage[cursor.column] = (column.bytes, column.nodes)
          stream.column_maxima[cursor.column] = column.max_value_bytes
          stream.column_nulls[cursor.column] = column.null_rows
          cursor.column += 1
        }
      ChooseMeasurement => {
        if cursor.needs_ordered {
          guard cursor.index is Some(index) else { return Err(OutputRepresentationRequired) }
          let measurement = match prepare_managed_output_index_cursor(
            index, facts.rows, cursor.width, stream.max_value_bytes, budget,
          ) {
            Ok(value) => value
            Err(issue) => return Err(Values(Guard(issue)))
          }
          cursor.measurement = Some(measurement)
          cursor.phase = MeasureIndex
        } else {
          budget.work = cursor.work
          budget.bytes = cursor.bytes
          budget.nodes = cursor.nodes
          stream.buffer.budget.nodes = facts.admission_usage.nodes
          stream.buffer.budget.text = facts.admission_usage.text_bytes
          stream.buffer.budget.work = facts.admission_usage.work
          stream.rows = facts.rows
          stream.row_measurements = cursor.index
          cursor.phase = Complete
        }
      }
      MeasureIndex =>
        match advance_managed_output_index_cursor(cursor.measurement.unwrap(), 1) {
          // An index cannot make contradictory aggregate facts publishable.
          Ok((true, _)) => return Err(InconsistentFacts)
          Ok((false, _)) => ()
          Err(issue) => return Err(Values(Guard(issue)))
        }
      Complete => return Ok((true, step + 1))
    }
  }
  Ok((false, quantum))
}

///|
fn prepare_managed_output_index_cursor(
  index : ManagedRowMeasurements,
  rows : Int,
  width : Int,
  ceiling : Int,
  budget : FixedInputGuardBudget,
) -> Result[ManagedOutputIndexCursor, FixedInputGuardIssue] {
  if (width == 0 && index.count != 0) ||
    (width > 0 && (index.count / width != rows || index.count % width != 0)) {
    return Err(InvalidLayout)
  }
  Ok({ index, rows, width, ceiling, budget, row: 0, column: 0, row_started: false, })
}

///|
fn advance_managed_output_index_cursor(
  cursor : ManagedOutputIndexCursor,
  quantum : Int,
) -> Result[(Bool, Int), FixedInputGuardIssue] {
  for step in 0..<quantum {
    if cursor.row == cursor.rows { return Ok((true, step + 1)) }
    let budget = cursor.budget
    if !cursor.row_started {
      if budget.work <= 0 { return Err(MeasurementWork) }
      budget.work -= 1
      cursor.row_started = true
      if cursor.width == 0 {
        cursor.row += 1
        cursor.row_started = false
      }
    } else {
      if budget.work <= 0 { return Err(MeasurementWork) }
      budget.work -= 1
      let (bytes, nodes, _) = managed_row_measurement_get(
        cursor.index, cursor.row * cursor.width + cursor.column,
      ).unwrap()
      if bytes <= 0 || nodes <= 0 { return Err(InvalidLayout) }
      if bytes > budget.bytes || nodes > budget.nodes {
        return Err(Measurement(Output, cursor.row, cursor.column, @encode.OutputLimit))
      }
      budget.bytes -= bytes
      budget.nodes -= nodes
      if bytes > cursor.ceiling {
        return Err(ValueBytes(Output, cursor.row, cursor.column))
      }
      cursor.column += 1
      if cursor.column == cursor.width {
        cursor.row += 1
        cursor.column = 0
        cursor.row_started = false
      }
    }
  }
  Ok((false, quantum))
}
