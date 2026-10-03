///|
/// A private, row-at-a-time Graph projection. A produced row remains owned by
/// this cursor until the installed receiver acknowledges its provisional use.
/// Neither a row nor an acknowledgement is a completed Relation or Store fact.
struct PropertyNodeRowsExecution {
  mut available : (() -> Bool)?
  mut start_row : ((Int, Int) -> Result[
    PropertyNodeRowExecution,
    PropertyNodeRowIssue,
  ])?
  node_count : Int
  max_rows : Int
  max_work : Int
  mut work : Int
  mut node : Int
  mut active : PropertyNodeRowExecution?
  mut child_reported_work : Int64
  mut pending : @execution.ConditionalRow?
  mut cancelled : Bool
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
pub enum PropertyNodeRowsPoll {
  PropertyNodeRowsContinue(work~ : Int64)
  PropertyNodeRowsRow(@execution.ConditionalRow, work~ : Int64)
  PropertyNodeRowsComplete(work~ : Int64)
  PropertyNodeRowsFailed(PropertyNodeRowsIssue, work~ : Int64)
  PropertyNodeRowsStopped(work~ : Int64)
}

///|
pub(all) enum PropertyNodeRowsIssue {
  InvalidLimits
  InvalidBinding
  InputUnavailable
  RowLimit
  WorkLimit
  RowPending
  Closed
  Row(PropertyNodeRowIssue)
} derive(Eq, Debug)

///|
fn start_property_node_rows_read(
  node_count : Int,
  max_rows : Int,
  max_work : Int,
  available : () -> Bool,
  start_row : (Int, Int) -> Result[
    PropertyNodeRowExecution,
    PropertyNodeRowIssue,
  ],
) -> Result[PropertyNodeRowsExecution, PropertyNodeRowsIssue] {
  if node_count < 0 || max_rows < 0 || max_work < 0 {
    return Err(InvalidLimits)
  }
  if !available() {
    return Err(InputUnavailable)
  }
  Ok({
    available: Some(available),
    start_row: Some(start_row),
    node_count,
    max_rows,
    max_work,
    work: 0,
    node: 0,
    active: None,
    child_reported_work: 0L,
    pending: None,
    cancelled: false,
    terminal: false,
    reclaimed: false,
  })
}

///|
/// Bind every projected node to the exact retained Graph input edge. The
/// cursor stores no unbounded row collection; the receiving owner must admit
/// each provisional row before acknowledging it.
pub fn start_property_node_rows_stored(
  plan : @projection.CheckedPropertyNodeRows,
  receiver : @lower.BoundPrepared,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[PropertyNodeRowsExecution, PropertyNodeRowsIssue] {
  let prepared = @lower.bound_preparation(receiver)
  guard @graph.producer_read_matches_operation_input(input, receiver, step, 0) &&
    @graph.producer_read_storage(input) is Some(storage) &&
    @storage.carrier(storage) is @carrier.GraphValue(actual) &&
    @projection.property_node_rows_input(plan) is @carrier.GraphValue(expected) &&
    physical_equal(
      @carrier.graph_property_definition(actual),
      @carrier.graph_property_definition(expected),
    ) &&
    @lower.node_at(prepared, step) is Some(operation) &&
    @lower.node_input_target(operation, 0) is Some(target) &&
    @lower.preparation_carrier_at(prepared, target)
    is Some(@carrier.GraphValue(checked)) &&
    physical_equal(
      @carrier.graph_property_definition(checked),
      @carrier.graph_property_definition(expected),
    ) else {
    return Err(InvalidBinding)
  }
  start_property_node_rows_read(
    @storage.node_count(storage),
    max_rows,
    max_work,
    () => @graph.producer_read_available(input),
    (node, remaining) => {
      start_property_node_row_stored(
        plan, receiver, step, input, node, limits, remaining, max_workspace_slots,
      )
    },
  )
}

///|
/// Use the same bounded row cursor for a task-acquired Graph view. The view
/// remains with its upstream owner until the enclosing execution stops.
pub fn start_property_node_rows_view(
  plan : @projection.CheckedPropertyNodeRows,
  receiver : @lower.BoundPrepared,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_work : Int,
  max_workspace_slots : Int,
) -> Result[PropertyNodeRowsExecution, PropertyNodeRowsIssue] {
  let prepared = @lower.bound_preparation(receiver)
  guard @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      receiver,
      step,
      0,
    ) &&
    @lifecycle.producer_view_property_graph_definition(input) is Ok(actual) &&
    @projection.property_node_rows_input(plan) is @carrier.GraphValue(expected) &&
    physical_equal(actual, @carrier.graph_property_definition(expected)) &&
    @lower.node_at(prepared, step) is Some(operation) &&
    @lower.node_input_target(operation, 0) is Some(target) &&
    @lower.preparation_carrier_at(prepared, target)
    is Some(@carrier.GraphValue(checked)) &&
    physical_equal(
      @carrier.graph_property_definition(checked),
      @carrier.graph_property_definition(expected),
    ) &&
    @lifecycle.producer_view_node_count(input) is Some(node_count) else {
    return Err(InvalidBinding)
  }
  start_property_node_rows_read(
    node_count,
    max_rows,
    max_work,
    () => {
      @lifecycle.producer_read_reference_available(
        @lifecycle.producer_view_read_reference(input),
      )
    },
    (node, remaining) => {
      start_property_node_row_view(
        plan, receiver, step, input, node, limits, remaining, max_workspace_slots,
      )
    },
  )
}

///|
fn stop_property_node_rows_child(value : PropertyNodeRowsExecution) -> Bool {
  if value.pending is Some(_) {
    return true
  }
  match value.active {
    None => true
    Some(active) => {
      cancel_property_node_row(active) |> ignore
      match advance_property_node_row(active, 1) {
        Ok(PropertyNodeRowStopped(..)) | Err(InputUnavailable) => true
        _ => false
      }
    }
  }
}

///|
pub fn advance_property_node_rows(
  value : PropertyNodeRowsExecution,
  quantum : Int,
) -> Result[PropertyNodeRowsPoll, PropertyNodeRowsIssue] {
  if quantum <= 0 {
    return Err(InvalidLimits)
  }
  if value.reclaimed || value.terminal {
    return Err(Closed)
  }
  if value.cancelled {
    if !stop_property_node_rows_child(value) {
      return Err(Closed)
    }
    value.terminal = true
    return Ok(PropertyNodeRowsStopped(work=0L))
  }
  if value.pending is Some(_) {
    return Err(RowPending)
  }
  let mut used = 0
  while used < quantum {
    if value.available is None || !value.available.unwrap()() {
      if !stop_property_node_rows_child(value) {
        return Err(Closed)
      }
      value.terminal = true
      return Ok(PropertyNodeRowsFailed(InputUnavailable, work=used.to_int64()))
    }
    if value.active is None {
      if value.node == value.node_count {
        value.terminal = true
        return Ok(PropertyNodeRowsComplete(work=used.to_int64()))
      }
      if value.node >= value.max_rows {
        value.terminal = true
        return Ok(PropertyNodeRowsFailed(RowLimit, work=used.to_int64()))
      }
      if value.work >= value.max_work {
        value.terminal = true
        return Ok(PropertyNodeRowsFailed(WorkLimit, work=used.to_int64()))
      }
      let child = match
        value.start_row.unwrap()(value.node, value.max_work - value.work - 1) {
        Ok(child) => child
        Err(issue) => {
          value.terminal = true
          return Ok(PropertyNodeRowsFailed(Row(issue), work=used.to_int64()))
        }
      }
      value.active = Some(child)
      value.child_reported_work = 0L
      value.work += 1
      used += 1
      continue
    }
    if value.work >= value.max_work {
      if !stop_property_node_rows_child(value) {
        return Err(Closed)
      }
      value.terminal = true
      return Ok(PropertyNodeRowsFailed(WorkLimit, work=used.to_int64()))
    }
    let remaining = Int::min(quantum - used, value.max_work - value.work)
    let child = value.active.unwrap()
    let poll = match advance_property_node_row(child, remaining) {
      Ok(poll) => poll
      Err(issue) => {
        value.terminal = true
        return Ok(PropertyNodeRowsFailed(Row(issue), work=used.to_int64()))
      }
    }
    let reported = match poll {
      PropertyNodeRowContinue(work~) => work
      PropertyNodeRowComplete(_, work~) => work
      PropertyNodeRowFailed(_, work~) => work
      PropertyNodeRowStopped(work~) => work
    }
    let consumed = reported - value.child_reported_work
    if consumed < 0L || consumed > remaining.to_int64() {
      value.terminal = true
      return Ok(PropertyNodeRowsFailed(WorkLimit, work=used.to_int64()))
    }
    value.child_reported_work = reported
    let amount = consumed.to_int()
    value.work += amount
    used += amount
    match poll {
      PropertyNodeRowContinue(..) =>
        if amount == 0 {
          return Ok(PropertyNodeRowsContinue(work=used.to_int64()))
        }
      PropertyNodeRowComplete(row, ..) => {
        value.pending = Some(row)
        return Ok(PropertyNodeRowsRow(row, work=used.to_int64()))
      }
      PropertyNodeRowFailed(issue, ..) => {
        value.terminal = true
        return Ok(PropertyNodeRowsFailed(Row(issue), work=used.to_int64()))
      }
      PropertyNodeRowStopped(..) => {
        value.terminal = true
        return Ok(PropertyNodeRowsStopped(work=used.to_int64()))
      }
    }
  }
  Ok(PropertyNodeRowsContinue(work=used.to_int64()))
}

///|
/// Only the installed receiver calls this after its own bounded admission of
/// the exact row. A failed append must cancel and clean up instead.
pub fn acknowledge_property_node_rows_row(
  value : PropertyNodeRowsExecution,
  row : @execution.ConditionalRow,
) -> Result[Bool, PropertyNodeRowsIssue] {
  if value.reclaimed || value.terminal || value.cancelled {
    return Err(Closed)
  }
  guard value.pending is Some(pending) &&
    physical_equal(pending, row) &&
    value.active is Some(active) else {
    return Err(RowPending)
  }
  match cleanup_property_node_row(active) {
    Ok(true) => {
      value.active = None
      value.child_reported_work = 0L
      value.pending = None
      value.node += 1
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(Row(issue))
  }
}

///|
pub fn cancel_property_node_rows(value : PropertyNodeRowsExecution) -> Bool {
  if value.reclaimed || value.terminal || value.cancelled {
    return false
  }
  value.cancelled = true
  if value.active is Some(active) {
    cancel_property_node_row(active) |> ignore
  }
  true
}

///|
/// Stop must be observed before this releases the exact Graph input callback.
pub fn cleanup_property_node_rows(
  value : PropertyNodeRowsExecution,
) -> Result[Bool, PropertyNodeRowsIssue] {
  if value.reclaimed {
    return Ok(true)
  }
  if !value.terminal {
    return Err(Closed)
  }
  if value.active is Some(active) {
    match cleanup_property_node_row(active) {
      Ok(true) => value.active = None
      Ok(false) => return Ok(false)
      Err(issue) => return Err(Row(issue))
    }
  }
  value.pending = None
  value.child_reported_work = 0L
  value.start_row = None
  value.available = None
  value.reclaimed = true
  Ok(true)
}
