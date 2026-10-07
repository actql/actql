///|
/// A bounded, independent copy of selected measurement metadata. Still
/// conditional: the adopted executor must prove its actual row correspondence.
/// The resulting output receipt contains only this copied index, not the plan
/// or source material. One issuance consumes the metadata transfer opportunity.
struct ManagedViewSelection[T] {
  plan : ManagedViewPlan[T]
  rows : ManagedOccurrences
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
  prepare_managed_occurrence_selection(
    plan,
    Indices(selected_rows),
    max_cells,
    max_work,
    computed,
  )
}

///|
/// Contiguous source occurrences, without allocating a row-sized map. The
/// interval is exact, not clamped; the checked executor must still verify it.
pub fn[T] prepare_managed_view_slice(
  plan : ManagedViewPlan[T],
  start : Int,
  count : Int,
  max_cells : Int,
  max_work : Int,
) -> Result[ManagedViewSelection[T], ManagedSelectionMeasureIssue] {
  let available = plan.input.output.material.receipt.rows
  if start < 0 || count < 0 || start > available || count > available - start {
    return Err(InvalidSelection)
  }
  prepare_managed_occurrence_selection(
    plan,
    Slice(start, count),
    max_cells,
    max_work,
    false,
  )
}

///|
fn[T] prepare_managed_occurrence_selection(
  plan : ManagedViewPlan[T],
  selected_rows : ManagedOccurrences,
  max_cells : Int,
  max_work : Int,
  computed : Bool,
) -> Result[ManagedViewSelection[T], ManagedSelectionMeasureIssue] {
  let cursor = match begin_managed_occurrence_selection(
    plan, selected_rows, max_cells, max_work, computed, true, fn(_, _) { true },
  ) {
    Ok(cursor) => cursor
    Err(issue) => return Err(issue)
  }
  while true {
    match advance_managed_view_selection(cursor, 64) {
      Ok((true, _)) => break
      Ok((false, _)) => continue
      Err(issue) => return Err(issue)
    }
  }
  take_managed_view_selection(cursor)
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
/// Exact copied measurement cells owned by this one-use selection. This is a
/// physical metadata quantity, not a logical row or value-byte measurement.
pub fn[T] managed_view_selection_cells(
  selection : ManagedViewSelection[T],
) -> Int {
  selection.index.count
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
    Err(issue) => {
      // The one-shot selection has been consumed, but no output owns its
      // copied metadata. Do not retain it behind a failed installation.
      discard_managed_row_measurements(selection.index)
      return Err(issue)
    }
  }
  Ok({ ..port, index: Some(selection.index), })
}
