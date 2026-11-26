///|
/// A checked Result dependency is not its producer's unprojected terminal.
/// Resolve the original import at the checked Unit/input coordinate. Internal
/// operation edges and supplied inputs never become inferred Result ports.
pub fn graph_result_input_port(
  graph : CheckedDAG,
  edge_index : Int,
) -> Result[@ports.ResultPort?, GraphIssue] {
  guard graph_data_at(graph, edge_index) is Some(edge) else {
    return Err(ForeignPort(-1, edge_index))
  }
  let consumer = data_edge_consumer(edge)
  let foreign = ForeignPort(consumer, data_edge_input(edge))
  guard graph_task_owner(graph, consumer) is Some(owner) &&
    graph_task_unit_index(graph, consumer) is Some(unit) else {
    return Err(foreign)
  }
  let prepared = @lower.bound_preparation(owner)
  let index = match data_edge_operation_input(edge) {
    Some((step, position)) => {
      if graph_task_selected_step(graph, consumer) is Some(selected) &&
        selected != step {
        return Err(foreign)
      }
      guard @lower.node_at(prepared, step) is Some(node) else {
        return Err(foreign)
      }
      match @lower.node_input_target(node, position) {
        Some(@pipeline.Input(index)) => index
        Some(@pipeline.Step(_)) => return Ok(None)
        None => return Err(foreign)
      }
    }
    None => data_edge_input(edge)
  }
  guard @checked.unit_input_completeness(
      graph_program(graph),
      unit,
      index,
    )
    is Some(completeness) else {
    return Err(foreign)
  }
  let (interface, producer) = match completeness.binding {
    @checked.Imported(interface, producer) => (interface, producer)
    _ => return Ok(None)
  }
  guard @pipeline.input_at(@lower.pipeline(prepared), index) is Some((name, _)) &&
    @pipeline.input_producer(@lower.pipeline(prepared), index) is Some(actual) &&
    physical_equal(actual, producer) &&
    interface.input_name == name else {
    return Err(foreign)
  }
  let site = @context.result_import_type_site(interface.row)
  guard site.stage == unit &&
    site.requirement is @context.Result(import_name, _, imported) &&
    import_name == name &&
    physical_equal(@results.input_producer(imported), producer) &&
    graph_task_owner(graph, data_edge_producer(edge))
    is Some(source) &&
    physical_equal(
      @pipeline.producer_pipeline(producer),
      @lower.pipeline(@lower.bound_preparation(source)),
    ) &&
    @pipeline.producer_target(producer) == data_edge_target(edge) else {
    return Err(foreign)
  }
  let port = @results.input_port(imported)
  if @ports.port_target(port) != data_edge_target(edge) ||
    !physical_equal(@ports.port_input(port), producer) {
    return Err(foreign)
  }
  Ok(Some(port))
}
