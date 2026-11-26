///|
priv struct ClientTaskResultInputProjection {
  node : @canonical.CanonicalValue
  edge : @canonical.CanonicalValue
  node_id : String
  output_port : String
  output_contract_cid : String
}

///|
fn client_task_result_input_output(port : @results.ResultPort) -> String {
  if @results.publication_term_count(@results.port_order(port)) == 0 {
    "projected"
  } else {
    "ordered"
  }
}

///|
// SAME original publication codec for dependency and public-root projection.
// A dependency has no new Named Result or publication root.
fn[P, C] emit_client_task_result_input_parts(
  writer : @encode.Writer,
  port : @results.ResultPort,
  node_id : String,
  source_node : String,
  source_port : String,
  source_contract : C,
  output_contract : C,
  logical_cid : C,
  pipeline : P,
  emit_pipeline : (P, @encode.Writer) -> Unit raise @encode.EncodeFailure,
  emit_cid : (C, @encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(writer)
  @encode.key(writer, "node")
  emit_client_result_projection_node(
    writer,
    source_contract,
    logical_cid,
    node_id,
    client_task_result_input_output(port),
    output_contract,
    pipeline,
    emit_pipeline,
    emit_cid,
  )
  @encode.key(writer, "edge")
  emit_client_result_projection_edge(
    writer, source_contract, source_node, source_port, node_id, emit_cid,
  )
  @encode.end_object(writer)
}

///|
fn issue_client_task_result_input_projection(
  graph : @strategy.CheckedDAG,
  index : Int,
  source : ClientTaskFragmentNode,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskResultInputProjection?, ClientTaskPlanGraphIssue] {
  let port = match @strategy_view.graph_result_input_port(graph, index) {
    Ok(Some(port)) => port
    Ok(None) => return Ok(None)
    Err(_) => return Err(InvalidEdge)
  }
  let projection = @pipeline.publication_projection(
    @results.port_publication(port),
  )
  let input = @carrier.relation(
    @carrier.typed_rows(@relation.input_schema(projection)),
  )
  let output = @carrier.relation(
    @carrier.typed_rows(@results.port_schema(port)),
  )
  guard client_task_carrier_contract(
      input, max_wire_bytes, max_nodes, max_depth,
    )
    is Some((kind, input_cid)) &&
    kind == source.output_carrier &&
    input_cid == source.output_contract_cid &&
    client_task_carrier_contract(output, max_wire_bytes, max_nodes, max_depth)
    is Some(("relation", output_cid)) else {
    return Err(ContractMismatch)
  }
  let node_id = client_compilation_result_input_node_id(index)
  try {
    let pipeline_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_result_projection_pipeline(pipeline_writer, port)
    guard parse_plan_identity_value(
        @encode.finish(pipeline_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(pipeline) else {
      return Err(Encoding)
    }
    let logical_cid = @canonical.cid_value(
      pipeline, max_wire_bytes, max_nodes, max_depth,
    )
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_task_result_input_parts(
      writer,
      port,
      node_id,
      source.node_id,
      source.output_port,
      source.output_contract_cid,
      output_cid,
      logical_cid,
      pipeline,
      @canonical.emit_value,
      (cid, writer) => @encode.string_value(writer, cid),
    )
    guard parse_plan_identity_value(
        @encode.finish(writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(parts) &&
      @canonical.object_field(parts, "node") is Some(node) &&
      @canonical.object_field(parts, "edge") is Some(edge) else {
      return Err(Encoding)
    }
    Ok(
      Some({
        node,
        edge,
        node_id,
        output_port: client_task_result_input_output(port),
        output_contract_cid: output_cid,
      }),
    )
  } catch {
    _ => Err(Encoding)
  }
}

///|
/// Include a possible dependency projection before construction. As for root
/// projection, this upper bound does not select the actual CID-equality branch.
fn measure_client_task_result_input_projection(
  graph : @strategy.CheckedDAG,
  index : Int,
  source_node : String,
  source_port : String,
) -> Result[ClientResultGraphConstruction?, ClientTaskPlanGraphIssue] {
  let port = match @strategy_view.graph_result_input_port(graph, index) {
    Ok(Some(port)) => port
    Ok(None) => return Ok(None)
    Err(_) => return Err(InvalidEdge)
  }
  let node_id = client_compilation_result_input_node_id(index)
  let output = client_task_result_input_output(port)
  try {
    let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
    emit_client_result_projection_pipeline(writer, port)
    let pipeline = @encode.finish_measurement_usage(writer)
    let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
    emit_client_result_projection_node(
      writer,
      (),
      (),
      node_id,
      output,
      (),
      pipeline,
      emit_client_task_pipeline_measurement,
      measure_client_fragment_cid,
    )
    let node = @encode.finish_measurement_usage(writer)
    let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
    emit_client_result_projection_edge(
      writer,
      (),
      source_node,
      source_port,
      node_id,
      measure_client_fragment_cid,
    )
    let edge = @encode.finish_measurement_usage(writer)
    let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
    emit_client_task_result_input_parts(
      writer,
      port,
      node_id,
      source_node,
      source_port,
      (),
      (),
      (),
      pipeline,
      emit_client_task_pipeline_measurement,
      measure_client_fragment_cid,
    )
    Ok(
      Some({
        pipeline,
        node,
        edge,
        parts: @encode.finish_measurement_usage(writer),
        root: (0, 0, 0),
        direct_root: (0, 0, 0),
      }),
    )
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn client_task_result_input_projection_edge(
  source : ClientTaskResultInputProjection,
  node : String,
  port : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @canonical.CanonicalValue? {
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_compilation_data_edge(
      writer,
      "relation",
      source.output_contract_cid,
      source.node_id,
      source.output_port,
      node,
      port,
      (cid, writer) => @encode.string_value(writer, cid),
    )
    parse_plan_identity_value(
      @encode.finish(writer),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
  } catch {
    _ => None
  }
}
