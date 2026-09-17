///|
/// Optional bounded metadata captured during the original value measurement.
/// Two non-negative Ints use fixed little-endian words and the NULL fact uses
/// one byte. This avoids one heap object per cell on JS while retaining the
/// exact same facts on every target.
priv struct ManagedRowMeasurements {
  max_cells : Int
  mut cells : FixedArray[Byte]
  mut count : Int
}

///|
const MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL : Int = 9

///|
const MANAGED_ROW_MEASUREMENT_HEADER_BYTES : Int64 = 512L

///|
fn new_managed_row_measurements(max_cells : Int) -> ManagedRowMeasurements? {
  if max_cells < 0 ||
    max_cells > 2147483647 / MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL {
    return None
  }
  Some({
    max_cells,
    cells: FixedArray::make(
      max_cells * MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL,
      0,
    ),
    count: 0,
  })
}

///|
/// Exact retained allocation bound for the packed payload plus a conservative
/// fixed owner allowance. Selection arrays and preparation scratch are
/// separate.
pub fn managed_row_measurement_capacity_bytes(max_cells : Int) -> Int64? {
  if max_cells < 0 ||
    max_cells > 2147483647 / MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL {
    return None
  }
  Some(
    MANAGED_ROW_MEASUREMENT_HEADER_BYTES +
    (max_cells * MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL).to_int64(),
  )
}

///|
fn managed_row_measurement_set(
  index : ManagedRowMeasurements,
  position : Int,
  value : (Int, Int, Bool),
) -> Bool {
  if position < 0 || position >= index.max_cells || value.0 < 0 || value.1 < 0 {
    return false
  }
  let offset = position * MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL
  managed_row_measurement_write_int(index.cells, offset, value.0)
  managed_row_measurement_write_int(index.cells, offset + 4, value.1)
  index.cells[offset + 8] = if value.2 { 1 } else { 0 }
  true
}

///|
fn managed_row_measurement_write_int(
  cells : FixedArray[Byte],
  offset : Int,
  value : Int,
) -> Unit {
  cells[offset] = (value & 0xff).to_byte()
  cells[offset + 1] = ((value >> 8) & 0xff).to_byte()
  cells[offset + 2] = ((value >> 16) & 0xff).to_byte()
  cells[offset + 3] = ((value >> 24) & 0xff).to_byte()
}

///|
fn managed_row_measurement_read_int(
  cells : FixedArray[Byte],
  offset : Int,
) -> Int {
  cells[offset].to_int() |
  (cells[offset + 1].to_int() << 8) |
  (cells[offset + 2].to_int() << 16) |
  (cells[offset + 3].to_int() << 24)
}

///|
fn managed_row_measurement_push(
  index : ManagedRowMeasurements,
  value : (Int, Int, Bool),
) -> Bool {
  if !managed_row_measurement_set(index, index.count, value) {
    return false
  }
  index.count += 1
  true
}

///|
fn managed_row_measurement_get(
  index : ManagedRowMeasurements,
  position : Int,
) -> (Int, Int, Bool)? {
  if position < 0 || position >= index.count {
    return None
  }
  let offset = position * MANAGED_ROW_MEASUREMENT_BYTES_PER_CELL
  Some(
    (
      managed_row_measurement_read_int(index.cells, offset),
      managed_row_measurement_read_int(index.cells, offset + 4),
      index.cells[offset + 8] != 0,
    ),
  )
}

///|
fn discard_managed_row_measurements(index : ManagedRowMeasurements) -> Unit {
  index.cells = FixedArray::make(0, 0)
  index.count = 0
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
  guard new_managed_row_measurements(max_cells) is Some(index) else {
    return Err(MeasurementIndexLimit)
  }
  stream.row_measurements = Some(index)
  Ok(())
}

///|
pub fn managed_output_measurement_index_cells(
  receipt : ManagedOutputValueReceipt,
) -> Int? {
  receipt.row_measurements.map(index => index.count)
}

///|
/// Revoke and physically clear the retained measurement index. This does not
/// revoke the Store representation by itself; the installed owner must couple
/// it with that output's availability and physical-allocation release.
pub fn discard_managed_output_measurement_index(
  receipt : ManagedOutputValueReceipt,
) -> Bool {
  guard receipt.row_measurements is Some(index) else { return false }
  discard_managed_row_measurements(index)
  receipt.row_measurements = None
  true
}

///|
pub(all) enum ManagedSelectionMeasureIssue {
  InvalidLimits
  Limit
  ForeignInput
  MissingIndex
  InvalidSelection
  UnsupportedColumns
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
  managed_occurrence_measurements(plan, Indices(selected_rows), max_work)
}

///|
fn[T] managed_occurrence_measurements(
  plan : ManagedViewPlan[T],
  selected_rows : ManagedOccurrences,
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
  let mut increasing = true
  let mut previous = -1
  for position in 0..<selected_rows.length() {
    let row = selected_rows.get(position).unwrap()
    if row < 0 ||
      row >= receipt.rows ||
      row == previous ||
      (plan.rows == AllRows && position != row) {
      return Err(InvalidSelection)
    }
    if row < previous {
      increasing = false
    }
    previous = row
  }
  // Take/filter preserve source occurrence order. Strictly increasing indices
  // prove uniqueness without allocating a row-sized temporary hash map.
  // Permutations still need a bounded duplicate check; charge its extra pass.
  if !increasing {
    if selected_rows.length() > work {
      return Err(Limit)
    }
    work -= selected_rows.length()
    let seen : Map[Int, Bool] = Map([])
    for position in 0..<selected_rows.length() {
      let row = selected_rows.get(position).unwrap()
      if seen.contains(row) {
        return Err(InvalidSelection)
      }
      seen[row] = true
    }
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
    for position in 0..<selected_rows.length() {
      let row = selected_rows.get(position).unwrap()
      // Completed indexes have exactly rows * width cells, checked at sealing.
      let (cell_bytes, cell_nodes, is_null) = managed_row_measurement_get(
        index,
        row * width + source_column,
      ).unwrap()
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
