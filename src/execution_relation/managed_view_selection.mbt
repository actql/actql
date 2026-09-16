///|
/// A bounded, independent copy of selected measurement metadata. Still
/// conditional: the adopted executor must prove its actual row correspondence.
/// The resulting output receipt contains only this copied index, not the plan
/// or source material. One issuance consumes the metadata transfer opportunity.
struct ManagedViewSelection[T] {
  plan : ManagedViewPlan[T]
  rows : Array[Int]
  facts : ManagedViewOutputFacts
  index : ManagedRowMeasurements
  mut claimed : Bool
}

///|
pub fn[T] prepare_managed_view_selection(
  plan : ManagedViewPlan[T],
  selected_rows : Array[Int],
  max_cells : Int,
  max_work : Int,
) -> Result[ManagedViewSelection[T], ManagedSelectionMeasureIssue] {
  prepare_managed_view_selection_base(
    plan, selected_rows, max_cells, max_work, false,
  )
}

///|
fn[T] prepare_managed_view_selection_base(
  plan : ManagedViewPlan[T],
  selected_rows : Array[Int],
  max_cells : Int,
  max_work : Int,
  computed : Bool,
) -> Result[ManagedViewSelection[T], ManagedSelectionMeasureIssue] {
  if max_cells < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  let width = plan.columns.length()
  if width > 0 && selected_rows.length() > max_cells / width {
    return Err(Limit)
  }
  let count = selected_rows.length() * width
  if count > max_work || selected_rows.length() > max_work - count {
    return Err(Limit)
  }
  // Charge the copied cells and defensive row-map copy in addition to the
  // aggregate metadata traversal's existing bounded work.
  let rows = selected_rows.copy()
  let measurements = match
    managed_view_selection_measurements(
      plan,
      rows,
      max_work - count - rows.length(),
    ) {
    Ok(facts) => facts
    Err(issue) => return Err(issue)
  }
  let columns = []
  for measurement in measurements {
    match measurement {
      Some(measurement) => columns.push(measurement)
      None => {
        if !computed {
          return Err(UnsupportedColumns)
        }
        columns.push({
          rows: rows.length(),
          bytes: 0,
          nodes: 0,
          max_value_bytes: 0,
          null_rows: 0,
          admitted_depth: 0,
        })
      }
    }
  }
  let receipt = plan.input.output.material.receipt
  let source = receipt.row_measurements.unwrap()
  let source_width = @schema.field_count(receipt.schema)
  let cells = []
  for row in rows {
    for origin in plan.columns {
      match origin {
        Some(origin) => {
          let column = plan.input.columns[origin]
          cells.push(source.cells[row * source_width + column])
        }
        None => cells.push((0, 0, false))
      }
    }
  }
  if !managed_producer_read_available(plan.input) {
    return Err(ForeignInput)
  }
  Ok({
    plan,
    rows,
    facts: {
      rows: rows.length(),
      columns,
      admission_usage: { work: 0, nodes: 0, text_bytes: 0, },
    },
    index: { max_cells: count, cells, },
    claimed: false,
  })
}

///|
/// Original source occurrence for the output position. Not a content identity
/// and not authority to read the material; normal pin/admission still applies.
pub fn[T] managed_view_selection_row(
  selection : ManagedViewSelection[T],
  row : Int,
) -> Int? {
  selection.rows.get(row)
}

///|
/// Host-installed verification must bind the exact selection to executed
/// expressions/order/failures and to the sealed output generation. No caller
/// supplied fact records can replace the copied source measurements here.
pub fn[P, T] prepare_managed_selected_view_output_port(
  selection : ManagedViewSelection[T],
  stream : ManagedOutputValues,
  verify : (P) -> Bool,
) -> Result[ManagedViewOutputPort[P, T], ManagedViewOutputIssue] {
  if selection.claimed {
    return Err(Closed)
  }
  // Consume before any liveness callback can re-enter installation.
  selection.claimed = true
  let port = match
    prepare_managed_view_output_port(selection.plan, stream, proof => {
      if verify(proof) {
        Some(selection.facts)
      } else {
        None
      }
    }) {
    Ok(port) => port
    Err(issue) => return Err(issue)
  }
  Ok({ ..port, index: Some(selection.index), })
}
