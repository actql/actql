///|
priv enum ManagedSelectionPhase {
  CopyRows
  ValidateRows
  CheckDuplicates
  BeginColumns
  BeginColumn
  MeasureColumn
  BuildColumns
  AllocateIndex
  CopyCells
  Complete
} derive(Eq)

///|
/// Conditional occurrence metadata under the existing selection owner. Its
/// control quantum is separate from logical work; no receipt or retention is
/// issued until the installed executor verifies the actual correspondence.
struct ManagedViewSelectionPreparation[T] {
  plan : ManagedViewPlan[T]
  mut supplied : ManagedOccurrences
  row_count : Int
  width : Int
  source_width : Int
  source : ManagedRowMeasurements
  copy_index : Bool
  computed : Bool
  validate_occurrence : (Int, Int) -> Bool
  mut rows : ManagedOccurrences
  mut phase : ManagedSelectionPhase
  mut position : Int
  mut column : Int
  mut previous : Int
  mut increasing : Bool
  mut seen : Map[Int, Bool]
  mut work : Int
  mut bytes : Int
  mut nodes : Int
  mut maximum : Int
  mut null_rows : Int
  mut measurements : Array[ManagedColumnMeasurement?]
  mut columns : Array[ManagedColumnMeasurement]
  mut index : ManagedRowMeasurements?
  mut closed : Bool
  mut reading : Bool
}

///|
pub fn[T] begin_managed_view_selection(
  plan : ManagedViewPlan[T],
  rows : Array[Int],
  max_cells : Int,
  max_work : Int,
  validate_occurrence? : (Int, Int) -> Bool = fn(_, _) { true },
) -> Result[ManagedViewSelectionPreparation[T], ManagedSelectionMeasureIssue] {
  begin_managed_occurrence_selection(
    plan,
    Indices(rows),
    max_cells,
    max_work,
    false,
    true,
    validate_occurrence,
  )
}

///|
pub fn[T] begin_managed_view_slice(
  plan : ManagedViewPlan[T],
  start : Int,
  count : Int,
  max_cells : Int,
  max_work : Int,
  validate_occurrence? : (Int, Int) -> Bool = fn(_, _) { true },
) -> Result[ManagedViewSelectionPreparation[T], ManagedSelectionMeasureIssue] {
  let available = plan.input.output.material.receipt.rows
  if start < 0 || count < 0 || start > available || count > available - start {
    return Err(InvalidSelection)
  }
  begin_managed_occurrence_selection(
    plan,
    Slice(start, count),
    max_cells,
    max_work,
    false,
    true,
    validate_occurrence,
  )
}

///|
fn[T] begin_managed_occurrence_selection(
  plan : ManagedViewPlan[T],
  supplied : ManagedOccurrences,
  max_cells : Int,
  max_work : Int,
  computed : Bool,
  copy_index : Bool,
  validate_occurrence : (Int, Int) -> Bool,
) -> Result[ManagedViewSelectionPreparation[T], ManagedSelectionMeasureIssue] {
  if max_cells < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let width = plan.columns.length()
  let count = supplied.length()
  let mut work = max_work
  if copy_index {
    if width > 0 && count > max_cells / width {
      return Err(Limit)
    }
    let cells = count * width
    let copy_work = match supplied {
      Indices(_) => count
      Slice(_, _) => 0
    }
    if cells > work || copy_work > work - cells {
      return Err(Limit)
    }
    work -= cells + copy_work
  }
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignInput)
  }
  let receipt = plan.input.output.material.receipt
  guard receipt.row_measurements is Some(source) else {
    return Err(MissingIndex)
  }
  if count > receipt.rows ||
    (plan.rows != SelectedRows && count != receipt.rows) {
    return Err(InvalidSelection)
  }
  if count > work {
    return Err(Limit)
  }
  work -= count
  let copy_rows = copy_index && supplied is Indices(_)
  Ok({
    plan,
    supplied,
    row_count: count,
    width,
    source_width: @schema.field_count(receipt.schema),
    source,
    copy_index,
    computed,
    validate_occurrence,
    rows: if copy_rows {
      Indices([])
    } else {
      supplied
    },
    phase: if copy_rows {
      CopyRows
    } else {
      ValidateRows
    },
    position: 0,
    column: 0,
    previous: -1,
    increasing: true,
    seen: Map([]),
    work,
    bytes: 0,
    nodes: 0,
    maximum: 0,
    null_rows: 0,
    measurements: [],
    columns: [],
    index: None,
    closed: false,
    reading: false,
  })
}

///|
/// Drop only owned preparation roots; borrowed source measurements survive.
/// This does not establish physical stop, Store release or task settlement.
pub fn[T] cancel_managed_view_selection_preparation(
  cursor : ManagedViewSelectionPreparation[T],
) -> Bool {
  if cursor.closed {
    return false
  }
  cursor.closed = true
  cursor.rows = Slice(0, 0)
  cursor.supplied = Slice(0, 0)
  cursor.seen = Map([])
  cursor.columns = []
  cursor.measurements = []
  if cursor.index is Some(index) {
    discard_managed_row_measurements(index)
  }
  cursor.index = None
  true
}

///|
pub fn[T] advance_managed_view_selection(
  cursor : ManagedViewSelectionPreparation[T],
  quantum : Int,
) -> Result[(Bool, Int), ManagedSelectionMeasureIssue] {
  if cursor.closed || cursor.reading || quantum <= 0 {
    return Err(Closed)
  }
  cursor.reading = true
  let result = advance_managed_view_selection_active(cursor, quantum)
  cursor.reading = false
  if result is Err(_) {
    cancel_managed_view_selection_preparation(cursor) |> ignore
  }
  result
}

///|
fn[T] advance_managed_view_selection_active(
  cursor : ManagedViewSelectionPreparation[T],
  quantum : Int,
) -> Result[(Bool, Int), ManagedSelectionMeasureIssue] {
  for step in 0..<quantum {
    if cursor.closed {
      return Err(Closed)
    }
    if !managed_producer_read_available(cursor.plan.input) {
      return Err(ForeignInput)
    }
    if cursor.closed {
      return Err(Closed)
    }
    if cursor.phase != CopyRows && cursor.rows.length() != cursor.row_count {
      return Err(InvalidSelection)
    }
    match cursor.phase {
      CopyRows => {
        if cursor.supplied.length() != cursor.row_count {
          return Err(InvalidSelection)
        }
        if cursor.position == cursor.row_count {
          cursor.position = 0
          cursor.phase = ValidateRows
        } else {
          guard cursor.rows is Indices(rows) else {
            return Err(InvalidSelection)
          }
          rows.push(cursor.supplied.get(cursor.position).unwrap())
          cursor.position += 1
        }
      }
      ValidateRows =>
        if cursor.position == cursor.row_count {
          cursor.position = 0
          if !cursor.increasing {
            if cursor.row_count > cursor.work {
              return Err(Limit)
            }
            cursor.work -= cursor.row_count
            cursor.phase = CheckDuplicates
          } else {
            cursor.phase = BeginColumns
          }
        } else {
          let row = cursor.rows.get(cursor.position).unwrap()
          let available = cursor.plan.input.output.material.receipt.rows
          if row < 0 ||
            row >= available ||
            row == cursor.previous ||
            (cursor.plan.rows == AllRows && cursor.position != row) ||
            !(cursor.validate_occurrence)(cursor.position, row) {
            return Err(InvalidSelection)
          }
          if cursor.closed {
            return Err(Closed)
          }
          if row < cursor.previous {
            cursor.increasing = false
          }
          cursor.previous = row
          cursor.position += 1
        }
      CheckDuplicates =>
        if cursor.position == cursor.row_count {
          cursor.seen = Map([])
          cursor.phase = BeginColumns
        } else {
          let row = cursor.rows.get(cursor.position).unwrap()
          if cursor.seen.contains(row) {
            return Err(InvalidSelection)
          }
          cursor.seen[row] = true
          cursor.position += 1
        }
      BeginColumns => {
        if cursor.width > cursor.work {
          return Err(Limit)
        }
        cursor.work -= cursor.width
        cursor.phase = BeginColumn
      }
      BeginColumn =>
        if cursor.column == cursor.width {
          cursor.column = 0
          cursor.phase = if cursor.copy_index { BuildColumns } else { Complete }
        } else {
          match cursor.plan.columns[cursor.column] {
            None => {
              cursor.measurements.push(None)
              cursor.column += 1
            }
            Some(_) => {
              if cursor.row_count > cursor.work {
                return Err(Limit)
              }
              cursor.work -= cursor.row_count
              cursor.position = 0
              cursor.bytes = 0
              cursor.nodes = 0
              cursor.maximum = 0
              cursor.null_rows = 0
              cursor.phase = MeasureColumn
            }
          }
        }
      MeasureColumn =>
        if cursor.position == cursor.row_count {
          let measurement : ManagedColumnMeasurement = {
            rows: cursor.row_count,
            bytes: cursor.bytes,
            nodes: cursor.nodes,
            max_value_bytes: cursor.maximum,
            null_rows: cursor.null_rows,
            admitted_depth: cursor.plan.input.output.material.receipt.measured_depth,
          }
          cursor.measurements.push(Some(measurement))
          cursor.column += 1
          cursor.phase = BeginColumn
        } else {
          let row = cursor.rows.get(cursor.position).unwrap()
          let origin = cursor.plan.columns[cursor.column].unwrap()
          let column = cursor.plan.input.columns[origin]
          guard managed_row_measurement_get(
              cursor.source,
              row * cursor.source_width + column,
            )
            is Some((bytes, nodes, null)) else {
            return Err(ForeignInput)
          }
          cursor.bytes += bytes
          cursor.nodes += nodes
          cursor.maximum = Int::max(cursor.maximum, bytes)
          if null {
            cursor.null_rows += 1
          }
          cursor.position += 1
        }
      BuildColumns =>
        if cursor.column == cursor.width {
          cursor.phase = AllocateIndex
        } else {
          let measurement = match cursor.measurements[cursor.column] {
            Some(value) => value
            None => {
              if !cursor.computed {
                return Err(UnsupportedColumns)
              }
              {
                rows: cursor.row_count,
                bytes: 0,
                nodes: 0,
                max_value_bytes: 0,
                null_rows: 0,
                admitted_depth: 0,
              }
            }
          }
          cursor.columns.push(measurement)
          cursor.column += 1
        }
      AllocateIndex => {
        // A checked physical allocation bound precedes this allocation. This
        // quantum bounds traversal, not the allocator's wall-clock latency.
        guard new_managed_row_measurements(cursor.row_count * cursor.width)
          is Some(index) else {
          return Err(Limit)
        }
        cursor.index = Some(index)
        cursor.position = 0
        cursor.column = 0
        cursor.phase = CopyCells
      }
      CopyCells =>
        if cursor.position == cursor.row_count || cursor.width == 0 {
          cursor.phase = Complete
        } else {
          let cell = match cursor.plan.columns[cursor.column] {
            Some(origin) => {
              let row = cursor.rows.get(cursor.position).unwrap()
              guard managed_row_measurement_get(
                  cursor.source,
                  row * cursor.source_width + cursor.plan.input.columns[origin],
                )
                is Some(cell) else {
                return Err(ForeignInput)
              }
              cell
            }
            None => (0, 0, false)
          }
          if !managed_row_measurement_push(cursor.index.unwrap(), cell) {
            return Err(Limit)
          }
          cursor.column += 1
          if cursor.column == cursor.width {
            cursor.column = 0
            cursor.position += 1
          }
        }
      Complete => return Ok((true, step + 1))
    }
  }
  Ok((false, quantum))
}

///|
/// Transfer the independent selection once, after all bounded passes. It is
/// still provisional and cannot bypass execution verification or retention.
pub fn[T] take_managed_view_selection(
  cursor : ManagedViewSelectionPreparation[T],
) -> Result[ManagedViewSelection[T], ManagedSelectionMeasureIssue] {
  if cursor.closed ||
    cursor.reading ||
    cursor.phase != Complete ||
    !cursor.copy_index {
    return Err(Closed)
  }
  cursor.reading = true
  let available = managed_producer_read_available(cursor.plan.input)
  cursor.reading = false
  if !available || cursor.closed {
    cancel_managed_view_selection_preparation(cursor) |> ignore
    return Err(if available { Closed } else { ForeignInput })
  }
  let selection : ManagedViewSelection[T] = {
    plan: cursor.plan,
    rows: cursor.rows,
    facts: {
      rows: cursor.row_count,
      columns: cursor.columns,
      admission_usage: { work: 0, nodes: 0, text_bytes: 0, },
    },
    index: cursor.index.unwrap(),
    claimed: false,
  }
  cursor.closed = true
  cursor.rows = Slice(0, 0)
  cursor.index = None
  cursor.supplied = Slice(0, 0)
  cursor.columns = []
  cursor.measurements = []
  Ok(selection)
}
