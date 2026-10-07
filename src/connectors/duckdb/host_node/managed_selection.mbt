///|
/// Opaque conditional selection preparation. It owns only private copied
/// metadata; input authority and actual execution remain with existing owners.
struct ManagedNodeSelection {
  cursor : @execution.ManagedViewSelectionPreparation[Int]
  available : () -> Bool
}

///|
#export_name("managedQuerySelectionBegin")
pub fn managed_query_selection_begin(
  query : @duckdb.ManagedFixedQuery[Int],
  rows : Array[Int],
  max_cells : Int,
  max_work : Int,
) -> ManagedNodeSelection raise NodeHostFailure {
  match
    @duckdb.begin_managed_fixed_query_selection(
      query, rows, max_cells, max_work,
    ) {
    Ok(cursor) => { cursor, available: fn() { true }, }
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("managedSelectionAdvance")
pub fn managed_selection_advance(
  selection : ManagedNodeSelection,
  quantum : Int,
) -> (Bool, Int) raise NodeHostFailure {
  if !(selection.available)() {
    managed_selection_cancel(selection) |> ignore
    raise InvalidCommand
  }
  match @execution.advance_managed_view_selection(selection.cursor, quantum) {
    Ok(poll) => poll
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("managedSelectionTake")
pub fn managed_selection_take(
  selection : ManagedNodeSelection,
) -> @execution.ManagedViewSelection[Int] raise NodeHostFailure {
  if !(selection.available)() {
    managed_selection_cancel(selection) |> ignore
    raise InvalidCommand
  }
  match @execution.take_managed_view_selection(selection.cursor) {
    Ok(value) => value
    Err(_) => raise InvalidCommand
  }
}

///|
#export_name("managedSelectionCancel")
pub fn managed_selection_cancel(selection : ManagedNodeSelection) -> Bool {
  @execution.cancel_managed_view_selection_preparation(selection.cursor)
}

///|
#export_name("managedStrategySelectionBegin")
pub fn managed_strategy_selection_begin(
  run : ManagedComputeNodeRun,
  rows : Array[Int],
) -> ManagedNodeSelection raise NodeHostFailure {
  if run.closed {
    raise InvalidCommand
  }
  let selection = managed_query_selection_begin(
    @duckdb_driver.captured_managed_duckdb_query(run.task),
    rows,
    run.max_index_cells,
    run.limits.values.max_work,
  )
  { ..selection, available: fn() { !run.closed }, }
}
