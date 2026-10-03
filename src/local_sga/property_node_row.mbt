///|
/// One retained Graph node becomes one private conditional Relation row. The
/// enclosing provider still owns row count, ordering and Store completion.
struct PropertyNodeRowExecution {
  mut available : (() -> Bool)?
  row : @execution.ConditionalRowPreparation
}

///|
pub enum PropertyNodeRowPoll {
  PropertyNodeRowContinue(work~ : Int64)
  PropertyNodeRowComplete(@execution.ConditionalRow, work~ : Int64)
  PropertyNodeRowFailed(PropertyNodeRowIssue, work~ : Int64)
  PropertyNodeRowStopped(work~ : Int64)
}

///|
pub(all) enum PropertyNodeRowIssue {
  InvalidBinding
  InputUnavailable
  InvalidNode
  Row(@execution.ConditionalRowIssue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn start_property_node_row_read(
  plan : @projection.CheckedPropertyNodeRows,
  node : Int,
  available : () -> Bool,
  definition : () -> Int?,
  identity : () -> @value.CheckedValue?,
  property : (Int) -> @value.CheckedValue?,
  limits : @execution.ValueLimits,
  max_step_work : Int,
  max_workspace_slots : Int,
) -> Result[PropertyNodeRowExecution, PropertyNodeRowIssue] {
  if node < 0 {
    return Err(InvalidNode)
  }
  if !available() {
    return Err(InputUnavailable)
  }
  guard definition() is Some(definition_index) &&
    definition_index >= 0 &&
    definition_index < @projection.property_node_rows_definition_count(plan) &&
    identity() is Some(_) else {
    return Err(InvalidNode)
  }
  let schema = @projection.property_node_rows_schema(plan)
  let id_column = @projection.property_node_rows_id_column(plan)
  let row = match
    @execution.start_conditional_row_preparation(
      schema,
      limits,
      max_step_work,
      max_workspace_slots,
      column => {
        if !available() {
          return None
        }
        if column == id_column {
          return identity().map(value => Some(value))
        }
        match
          @projection.property_node_rows_source_property(
            plan, definition_index, column,
          ) {
          Some(source_index) => property(source_index).map(value => Some(value))
          None => Some(None)
        }
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Row(issue))
  }
  Ok({ available: Some(available), row, })
}

///|
/// The checked layout and retained producer must describe the exact Graph
/// input edge. A raw Storage object cannot bypass the producer read owner.
pub fn start_property_node_row_stored(
  plan : @projection.CheckedPropertyNodeRows,
  receiver : @lower.BoundPrepared,
  step : Int,
  input : @graph.ProducerRead,
  node : Int,
  limits : @execution.ValueLimits,
  max_step_work : Int,
  max_workspace_slots : Int,
) -> Result[PropertyNodeRowExecution, PropertyNodeRowIssue] {
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
  start_property_node_row_read(
    plan,
    node,
    () => @graph.producer_read_available(input),
    () => @storage.node_definition_index(storage, node),
    () => @storage.node_identity(storage, node),
    index => @storage.node_property(storage, node, index),
    limits,
    max_step_work,
    max_workspace_slots,
  )
}

///|
pub fn advance_property_node_row(
  value : PropertyNodeRowExecution,
  quantum : Int,
) -> Result[PropertyNodeRowPoll, PropertyNodeRowIssue] {
  if value.available is None || !value.available.unwrap()() {
    @execution.cancel_conditional_row_preparation(value.row) |> ignore
    @execution.advance_conditional_row_preparation(value.row, 1) |> ignore
    return Err(InputUnavailable)
  }
  match @execution.advance_conditional_row_preparation(value.row, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@execution.ConditionalRowContinue(work~)) =>
      Ok(PropertyNodeRowContinue(work~))
    Ok(@execution.ConditionalRowComplete(row, work~)) =>
      Ok(PropertyNodeRowComplete(row, work~))
    Ok(@execution.ConditionalRowFailed(issue, work~)) =>
      Ok(PropertyNodeRowFailed(Row(issue), work~))
    Ok(@execution.ConditionalRowStopped(work~)) =>
      Ok(PropertyNodeRowStopped(work~))
  }
}

///|
pub fn cancel_property_node_row(value : PropertyNodeRowExecution) -> Bool {
  @execution.cancel_conditional_row_preparation(value.row)
}

///|
pub fn cleanup_property_node_row(
  value : PropertyNodeRowExecution,
) -> Result[Bool, PropertyNodeRowIssue] {
  match @execution.cleanup_conditional_row_preparation(value.row) {
    Ok(true) => {
      value.available = None
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(issue) => Err(Execution(issue))
  }
}
