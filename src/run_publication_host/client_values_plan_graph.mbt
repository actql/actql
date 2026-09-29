///|
/// Checked graph material for one source-free Values task. This is a Plan
/// component, not an Executable Plan or admission decision.
pub struct ClientValuesPlanGraph {
  wire : String
  transformations : Array[ClientResultTransformation]
}

///|
pub(all) enum ClientValuesPlanGraphIssue {
  InvalidLimits
  UnsupportedGraph
  Fragment(ClientValuesFragmentIssue)
  Root(ClientResultPlanPartsIssue)
  Encoding
}

///|
pub(all) enum ClientValuesPlanGraphAdmissionIssue {
  Issue(ClientValuesPlanGraphIssue)
  MismatchedGraph
}

///|
pub fn client_values_plan_graph_wire(value : ClientValuesPlanGraph) -> String {
  value.wire
}

///|
/// Close the fragment and every requested Result root over the same checked
/// single-task Values graph, with checked publication transformations when
/// needed. These fragments are executed by the existing Result exporter.
pub fn issue_prepared_client_values_plan_graph(
  value : PreparedClientProgram,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesPlanGraph, ClientValuesPlanGraphIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = value.graph
  if @strategy.graph_task_count(graph) != 1 ||
    @strategy.graph_result_count(graph) == 0 ||
    @strategy.graph_task_input_count(graph, 0) != Some(0) {
    return Err(UnsupportedGraph)
  }
  let fragment = match
    issue_prepared_client_values_fragment(
      value, 0, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(fragment) => fragment
    Err(issue) => return Err(Fragment(issue))
  }
  guard parse_plan_identity_value(
      fragment.wire,
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(node) else {
    return Err(Encoding)
  }
  let roots : Array[@canonical.CanonicalValue] = []
  let transformations : Array[ClientResultTransformation] = []
  let nodes = [node]
  let edges : Array[@canonical.CanonicalValue] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    let parts = match
      issue_client_result_plan_parts(
        value,
        result,
        fragment.node_id,
        fragment.node_id,
        fragment.output_contract_cid,
        max_wire_bytes,
        max_nodes,
        max_depth,
      ) {
      Ok(parts) => parts
      Err(issue) => return Err(Root(issue))
    }
    if parts.transformation is Some((node, edge)) {
      nodes.push(node)
      edges.push(edge)
    }
    roots.push(parts.root)
    if parts.selection is Some(selection) {
      transformations.push(selection)
    }
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    @encode.begin_object(writer)
    @encode.key(writer, "data_edges")
    @encode.begin_array(writer)
    for edge in edges {
      @canonical.emit_value(edge, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "nodes")
    @encode.begin_array(writer)
    for node in nodes {
      @canonical.emit_value(node, writer)
    }
    @encode.end_array(writer)
    @encode.key(writer, "root_refs")
    @encode.begin_array(writer)
    for root in roots {
      @canonical.emit_value(root, writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok({ wire: @encode.finish(writer), transformations, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Recheck saved graph material against the exact checked Program before Plan
/// admission. A canonical graph from another checked Values Program fails.
pub fn admit_prepared_client_values_plan_graph(
  value : PreparedClientProgram,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientValuesPlanGraph, ClientValuesPlanGraphAdmissionIssue] {
  let issued = match
    issue_prepared_client_values_plan_graph(
      value, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Issue(issue))
  }
  if saved_wire != issued.wire {
    return Err(MismatchedGraph)
  }
  Ok(issued)
}
