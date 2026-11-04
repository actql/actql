///|
/// Wire/tree geometry of a possible publication projection for one original
/// checked Result. The direct-root geometry uses the same producer coordinates.
/// Dependency projections have zero root extents: they expose no Named Result.
/// This is construction DATA, not selection of either graph branch, a contract,
/// or evidence that a producer/Result correspondence has been admitted.
pub(all) struct ClientResultGraphConstruction {
  pipeline : (Int, Int, Int)
  node : (Int, Int, Int)
  edge : (Int, Int, Int)
  root : (Int, Int, Int)
  parts : (Int, Int, Int)
  direct_root : (Int, Int, Int)
} derive(Eq, Debug)

///|
/// Measure the original projection/order serializers before allocating their
/// wires and parsed trees. All variable field names, order terms and Result
/// names come from the same checked port used by actual Plan construction.
/// Future identities contribute only their encoded extent to a measuring
/// writer. The actual constructor still selects direct versus transformed
/// roots and validates its exact producer, contracts and component originals.
pub fn measure_prepared_client_result_graph_construction(
  value : PreparedClientProgram,
  result : Int,
  producer_node : String,
  producer_port : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientResultGraphConstruction, ClientResultPlanPartsIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(Root(InvalidLimits))
  }
  let (_, port, name, _, _, _) = match
    client_result_plan_originals(value, result) {
    Ok(originals) => originals
    Err(issue) => return Err(Root(ResultPlan(issue)))
  }
  let ordered = @results.publication_term_count(@results.port_order(port)) != 0
  let output = if ordered { "ordered" } else { "projected" }
  let node_id = client_compilation_result_node_id(result)
  try {
    let pipeline_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_result_projection_pipeline(pipeline_writer, port)
    let pipeline = @encode.finish_measurement_usage(pipeline_writer)
    let node_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_result_projection_node(
      node_writer,
      (),
      (),
      node_id,
      output,
      (),
      pipeline,
      (value, writer) => @encode.emit_measurement(writer, value),
      measure_client_fragment_cid,
    )
    let node = @encode.finish_measurement_usage(node_writer)
    let edge_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_result_projection_edge(
      edge_writer,
      (),
      producer_node,
      producer_port,
      node_id,
      measure_client_fragment_cid,
    )
    let edge = @encode.finish_measurement_usage(edge_writer)
    let root_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_requested_result_root(root_writer, name, node_id, output)
    let root = @encode.finish_measurement_usage(root_writer)
    let parts_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    @encode.begin_object(parts_writer)
    @encode.key(parts_writer, "node")
    @encode.emit_measurement(parts_writer, node)
    @encode.key(parts_writer, "edge")
    @encode.emit_measurement(parts_writer, edge)
    @encode.key(parts_writer, "root")
    @encode.emit_measurement(parts_writer, root)
    @encode.end_object(parts_writer)
    let parts = @encode.finish_measurement_usage(parts_writer)
    let direct = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_requested_result_root(
      direct, name, producer_node, producer_port,
    )
    Ok({
      pipeline,
      node,
      edge,
      root,
      parts,
      direct_root: @encode.finish_measurement_usage(direct),
    })
  } catch {
    _ => Err(Encoding)
  }
}
