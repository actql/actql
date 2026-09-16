///|
/// Optional bounded metadata captured during the original value measurement.
/// No values, source buffers or canonical strings are retained here. The Host
/// must reserve metadata storage; max_cells is an entry cap, not physical bytes.
priv struct ManagedRowMeasurements {
  max_cells : Int
  cells : Array[(Int, Int, Bool)]
}

///|
pub fn enable_managed_row_measurements(
  stream : ManagedOutputValues,
  max_cells : Int,
) -> Result[Unit, ManagedOutputValueIssue] {
  if !stream.open ||
    stream.reading ||
    stream.rows != 0 ||
    stream.row_measurements is Some(_) {
    return Err(Closed)
  }
  if max_cells < 0 {
    return Err(Guard(InvalidLimits))
  }
  stream.row_measurements = Some({ max_cells, cells: [], })
  Ok(())
}

///|
pub fn managed_output_measurement_index_cells(
  receipt : ManagedOutputValueReceipt,
) -> Int? {
  receipt.row_measurements.map(index => index.cells.length())
}

///|
pub(all) enum ManagedSelectionMeasureIssue {
  InvalidLimits
  Limit
  ForeignInput
  MissingIndex
  InvalidSelection
}

///|
/// Conditional facts for exact input row occurrences, not proof that an
/// executor actually selected them. The scoped output verifier must bind this
/// map to real execution. Computed columns return None and require new facts.
/// Only index metadata is read; no cell decode/admission/encoding occurs.
pub fn[T] managed_view_selection_measurements(
  plan : ManagedViewPlan[T],
  selected_rows : Array[Int],
  max_work : Int,
) -> Result[Array[ManagedColumnMeasurement?], ManagedSelectionMeasureIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignInput)
  }
  let receipt = plan.input.output.material.receipt
  guard receipt.row_measurements is Some(index) else {
    return Err(MissingIndex)
  }
  if selected_rows.length() > receipt.rows ||
    (plan.rows != SelectedRows && selected_rows.length() != receipt.rows) {
    return Err(InvalidSelection)
  }
  if selected_rows.length() > max_work {
    return Err(Limit)
  }
  let mut work = max_work - selected_rows.length()
  let seen : Map[Int, Bool] = Map([])
  for position, row in selected_rows {
    if row < 0 ||
      row >= receipt.rows ||
      seen.contains(row) ||
      (plan.rows == AllRows && position != row) {
      return Err(InvalidSelection)
    }
    seen[row] = true
  }
  if plan.columns.length() > work {
    return Err(Limit)
  }
  work -= plan.columns.length()
  let width = @schema.field_count(receipt.schema)
  let result = []
  for origin in plan.columns {
    guard origin is Some(origin) else {
      result.push(None)
      continue
    }
    let source_column = plan.input.columns[origin]
    if selected_rows.length() > work {
      return Err(Limit)
    }
    work -= selected_rows.length()
    let mut bytes = 0
    let mut nodes = 0
    let mut maximum = 0
    let mut null_rows = 0
    for row in selected_rows {
      // Completed indexes have exactly rows * width cells, checked at sealing.
      let (cell_bytes, cell_nodes, is_null) = index.cells[row * width +
        source_column]
      bytes += cell_bytes
      nodes += cell_nodes
      maximum = Int::max(maximum, cell_bytes)
      if is_null {
        null_rows += 1
      }
    }
    result.push(
      Some({
        rows: selected_rows.length(),
        bytes,
        nodes,
        max_value_bytes: maximum,
        null_rows,
        admitted_depth: receipt.measured_depth,
      }),
    )
  }
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignInput)
  }
  Ok(result)
}
