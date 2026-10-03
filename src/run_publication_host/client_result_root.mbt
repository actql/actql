///|
/// A checked Result can use an existing AoA output directly only when no
/// publication projection or ordering operation remains to execute.
pub struct ClientDirectResultRoot {
  wire : String
  result_name : String
  result_plan_cid : String
  node_id : String
  port : String
  row_contract_cid : String
}

///|
pub(all) enum ClientDirectResultRootIssue {
  InvalidLimits
  MissingResult
  Fragment(ClientValuesFragmentIssue)
  TaskFragment(ClientTaskFragmentIssue)
  ResultPlan(ClientResultPlanIssue)
  RequiresResultTransformation
  Encoding
}

///|
pub(all) enum ClientDirectResultRootAdmissionIssue {
  Issue(ClientDirectResultRootIssue)
  MismatchedRoot
}

///|
pub fn client_direct_result_root_wire(value : ClientDirectResultRoot) -> String {
  value.wire
}

///|
pub fn client_direct_result_root_plan_cid(
  value : ClientDirectResultRoot,
) -> String {
  value.result_plan_cid
}

///|
pub fn client_direct_result_root_name(value : ClientDirectResultRoot) -> String {
  value.result_name
}

///|
pub fn client_direct_result_root_row_contract_cid(
  value : ClientDirectResultRoot,
) -> String {
  value.row_contract_cid
}

///|
/// Issue the `requested_result` root only when the checked Result port is
/// exactly the checked Values fragment output, including field order and
/// inherited row order. Other Results need their own checked AoA operation.
pub fn issue_prepared_client_direct_values_result_root(
  value : PreparedClientProgram,
  result : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientDirectResultRoot, ClientDirectResultRootIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = value.graph
  guard @strategy.graph_result_task(graph, result) is Some(task) else {
    return Err(MissingResult)
  }
  let fragment = match
    issue_prepared_client_values_fragment(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(fragment) => fragment
    Err(issue) => return Err(Fragment(issue))
  }
  issue_prepared_client_direct_result_root_for_output(
    value,
    result,
    client_values_fragment_node_id(fragment),
    client_values_fragment_node_id(fragment),
    client_values_fragment_output_contract_cid(fragment),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// Bind a checked Result to any checked task output with no remaining
/// projection or ordering operation.
pub fn issue_prepared_client_direct_task_result_root(
  value : PreparedClientProgram,
  result : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientDirectResultRoot, ClientDirectResultRootIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  guard @strategy.graph_result_task(value.graph, result) is Some(task) else {
    return Err(MissingResult)
  }
  let fragment = match
    issue_prepared_client_task_fragment(
      value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(fragment) => fragment
    Err(issue) => return Err(TaskFragment(issue))
  }
  issue_prepared_client_direct_result_root_for_output(
    value,
    result,
    client_task_fragment_node_id(fragment),
    client_task_fragment_output_port(fragment),
    client_task_fragment_output_contract_cid(fragment),
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
// A captured acquisition has no Compute target. Its checked acquisition
// capture still identifies the exact producer Result port; do not invent a
// Compute step merely to export that already produced Relation.
fn client_publication_task_target(
  value : PreparedClientProgram,
  task : Int,
) -> @pipeline.Target? {
  let graph = value.graph
  match @strategy.graph_task_target(graph, task) {
    Some(target) => Some(target)
    None => {
      if task != 0 || @strategy.graph_captured_prefix(graph) != 1 {
        return None
      }
      guard @strategy.graph_task_unit_index(graph, task) is Some(stage) else {
        return None
      }
      match prepare_client_query_acquisition(value, stage, 0) {
        Ok(acquisition) =>
          Some(@acquisition.query_acquisition_capture(acquisition))
        Err(_) => None
      }
    }
  }
}

///|
fn issue_prepared_client_direct_result_root_for_output(
  value : PreparedClientProgram,
  result : Int,
  output_node_id : String,
  output_port : String,
  output_contract_cid : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientDirectResultRoot, ClientDirectResultRootIssue] {
  let graph = value.graph
  guard @strategy.graph_result_task(graph, result) is Some(task) &&
    @strategy.graph_result_occurrence(graph, result) is Some(occurrence) else {
    return Err(MissingResult)
  }
  let port = @execution.managed_result_occurrence_port(occurrence)
  guard client_publication_task_target(value, task) is Some(target) &&
    @results.port_target(port) == target else {
    return Err(RequiresResultTransformation)
  }
  let order = @results.port_order(port)
  if @results.publication_strategy(order) != @results.Inherited ||
    @results.port_order_term_count(port) != 0 {
    return Err(RequiresResultTransformation)
  }
  guard @strategy.graph_task_owner(graph, task) is Some(owner) else {
    return Err(RequiresResultTransformation)
  }
  let prepared = @lower.bound_preparation(owner)
  guard client_task_output_step(
      graph,
      task,
      @pipeline.step_count(@lower.pipeline(prepared)),
    )
    is Some(output_step) &&
    @lower.node_at(prepared, output_step) is Some(node) else {
    return Err(RequiresResultTransformation)
  }
  let task_schema = @lower.node_output_schema(node)
  let names = @results.fields(@results.port_result(port))
  if names.length() != @schema.field_count(task_schema) ||
    names.length() != @results.port_projection_count(port) {
    return Err(RequiresResultTransformation)
  }
  for index in 0..<names.length() {
    // Port projection indices follow the canonical schema, while Result
    // `fields` retain authored order. Compare the matching port field.
    guard @schema.field_at(@results.port_schema(port), index) is Some(output) &&
      @results.port_projection_input_at(port, index) is Some(input) &&
      input == output.name &&
      @schema.lookup(task_schema, input) is Some(_) else {
      return Err(RequiresResultTransformation)
    }
  }
  let plan = match
    issue_prepared_client_result_plan(
      value, result, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(plan) => plan
    Err(issue) => return Err(ResultPlan(issue))
  }
  if output_contract_cid != client_result_plan_row_contract_cid(plan) {
    return Err(RequiresResultTransformation)
  }
  let result_name = client_result_plan_name(plan)
  let node_id = output_node_id
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  @encode.begin_object(writer) catch {
    _ => return Err(Encoding)
  }
  @encode.key(writer, "name") catch {
    _ => return Err(Encoding)
  }
  @encode.string_value(writer, result_name) catch {
    _ => return Err(Encoding)
  }
  @encode.key(writer, "ref") catch {
    _ => return Err(Encoding)
  }
  @encode.begin_object(writer) catch {
    _ => return Err(Encoding)
  }
  @encode.key(writer, "node_id") catch {
    _ => return Err(Encoding)
  }
  @encode.string_value(writer, node_id) catch {
    _ => return Err(Encoding)
  }
  @encode.key(writer, "port") catch {
    _ => return Err(Encoding)
  }
  @encode.string_value(writer, output_port) catch {
    _ => return Err(Encoding)
  }
  @encode.end_object(writer) catch {
    _ => return Err(Encoding)
  }
  @encode.key(writer, "role") catch {
    _ => return Err(Encoding)
  }
  @encode.string_value(writer, "requested_result") catch {
    _ => return Err(Encoding)
  }
  @encode.end_object(writer) catch {
    _ => return Err(Encoding)
  }
  let wire = @encode.finish(writer) catch { _ => return Err(Encoding) }
  Ok({
    wire,
    result_name,
    result_plan_cid: client_result_plan_cid(plan),
    node_id,
    port: output_port,
    row_contract_cid: client_result_plan_row_contract_cid(plan),
  })
}

///|
pub fn admit_prepared_client_direct_values_result_root(
  value : PreparedClientProgram,
  result : Int,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientDirectResultRoot, ClientDirectResultRootAdmissionIssue] {
  let issued = match
    issue_prepared_client_direct_values_result_root(
      value, result, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(root) => root
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedRoot)
  }
  Ok(issued)
}
