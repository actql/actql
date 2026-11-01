///|
/// Geometry of this original Model occurrence's complete prefix/request/
/// barrier/suffix/Result construction. This is DATA, never a Graph, policy,
/// provider admission or Resource permission. The real issuer still selects
/// every Result branch and binds the original execution/occurrence.
pub(all) struct ClientInferGraphConstruction {
  fragments : Array[ClientTaskFragmentConstruction]
  request : (Int, Int, Int)
  barrier : (Int, Int, Int)
  node : (Int, Int, Int)
  output_contract : (Int, Int, Int)
  nodes : Array[(Int, Int, Int)]
  edges : Array[(Int, Int, Int)]
  roots : Array[(Int, Int, Int)]
  projections : Array[ClientResultGraphConstruction]
  results : Array[(Int, Int, Int)]
  graph : (Int, Int, Int)
}

///|
/// The existing Mock Model profile has no Serialization component. Other
/// installed profiles keep their original constructor until their complete
/// component/physical connection is selected; this measurer does not cast it.
pub fn measure_installed_client_composed_infer_graph_construction(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientInferGraphConstruction, ClientInferPlanGraphIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(UnsupportedProgram)
  }
  let prepared = occurrence.owner
  let bound = occurrence.preparation
  let step = occurrence.step
  guard client_infer_occurrence_matches(occurrence, prepared) &&
    step > 0 &&
    client_infer_occurrence_output_step(occurrence) is Some(terminal) &&
    terminal >= step &&
    @lower.node_at(@lower.bound_preparation(bound), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return Err(UnsupportedProgram)
  }
  if !physical_equal(
      @infer.model_task(infer),
      @environment.model_execution_task(execution),
    ) {
    return Err(ForeignExecution)
  }
  let prefix = match
    measure_client_infer_fragment_construction(
      occurrence,
      step - 1,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Err(issue) => return Err(Input(issue))
    Ok(value) => value
  }
  let mappings = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(bound),
      sequence_limits.expressions,
    ) {
    Err(issue) => return Err(Mapping(issue))
    Ok(value) => value
  }
  guard measure_client_task_carrier_contract(
      @lower.node_output_carrier(node),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(output_contract) else {
    return Err(UnsupportedProgram)
  }
  try {
    let request_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    if !emit_client_infer_request_body(infer, mappings, request_writer) {
      return Err(Encoding)
    }
    let request = @encode.finish_measurement_usage(request_writer)
    let barrier_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_infer_barrier_body(
      barrier_writer,
      infer,
      (),
      (),
      (),
      (),
      (),
      (),
      (),
      (),
      Some(()),
      measure_client_fragment_cid,
    )
    let barrier = @encode.finish_measurement_usage(barrier_writer)
    let barrier_id = "task_" +
      occurrence.task.to_string() +
      "_infer_" +
      step.to_string()
    let output_port = @lower.node_id(node)
    let node_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_infer_node_body(
      node_writer,
      barrier,
      emit_client_task_pipeline_measurement,
      barrier_id,
      output_port,
      (),
      (),
      measure_client_fragment_cid,
    )
    let barrier_node = @encode.finish_measurement_usage(node_writer)
    let fragments = [prefix]
    let nodes = [prefix.fragment, barrier_node]
    let edges : Array[(Int, Int, Int)] = []
    let roots : Array[(Int, Int, Int)] = []
    let projections : Array[ClientResultGraphConstruction] = []
    let results : Array[(Int, Int, Int)] = []
    let producers : Array[(Int, String, String)] = [
      (step - 1, prefix.node_id, prefix.output_port),
      (step, barrier_id, output_port),
    ]
    let edge_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_compilation_data_edge(
      edge_writer,
      "relation",
      (),
      prefix.node_id,
      prefix.output_port,
      barrier_id,
      "input_0",
      measure_client_fragment_cid,
    )
    edges.push(@encode.finish_measurement_usage(edge_writer))
    for next in (step + 1)..<(terminal + 1) {
      let fragment = match
        measure_client_infer_fragment_construction(
          occurrence, next, sequence_limits, max_wire_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(Input(issue))
        Ok(value) => value
      }
      fragments.push(fragment)
      nodes.push(fragment.fragment)
      guard @lower.node_at(@lower.bound_preparation(bound), next)
        is Some(consumer) else {
        return Err(UnsupportedProgram)
      }
      for port in 0..<@lower.node_input_count(consumer) {
        guard @lower.node_input_target(consumer, port)
          is Some(@pipeline.Step(source)) else {
          return Err(UnsupportedProgram)
        }
        let mut producer : (Int, String, String)? = None
        for candidate in producers {
          if candidate.0 == source {
            producer = Some(candidate)
          }
        }
        guard producer is Some((_, name, output)) else {
          return Err(UnsupportedProgram)
        }
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        emit_client_compilation_data_edge(
          writer,
          "relation",
          (),
          name,
          output,
          fragment.node_id,
          "input_" + port.to_string(),
          measure_client_fragment_cid,
        )
        edges.push(@encode.finish_measurement_usage(writer))
      }
      producers.push((next, fragment.node_id, fragment.output_port))
    }
    for result in 0..<@strategy.graph_result_count(prepared.graph) {
      if @strategy.graph_result_task(prepared.graph, result) !=
        Some(occurrence.task) {
        continue
      }
      guard @strategy.graph_result_occurrence(prepared.graph, result)
        is Some(original) &&
        @results.port_target(
          @execution.managed_result_occurrence_port(original),
        )
        is @pipeline.Step(target) else {
        return Err(UnsupportedProgram)
      }
      let mut producer : (Int, String, String)? = None
      for candidate in producers {
        if candidate.0 == target {
          producer = Some(candidate)
        }
      }
      guard producer is Some((_, name, output)) else {
        return Err(UnsupportedProgram)
      }
      let projection = match
        measure_prepared_client_result_graph_construction(
          prepared, result, name, output, max_wire_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(Result(issue))
        Ok(value) => value
      }
      let plan = match
        measure_prepared_client_result_plan(
          prepared, result, max_wire_bytes, max_nodes, max_depth,
        ) {
        Err(issue) => return Err(Result(Root(ResultPlan(issue))))
        Ok(value) => value
      }
      // All possible co-held branches, without selecting a successful Result.
      nodes.push(projection.node)
      edges.push(projection.edge)
      roots.push(
        (
          Int::max(projection.root.0, projection.direct_root.0),
          Int::max(projection.root.1, projection.direct_root.1),
          Int::max(projection.root.2, projection.direct_root.2),
        ),
      )
      projections.push(projection)
      results.push(plan)
    }
    let writer = @encode.measuring_writer(2147483647, 2147483647, 2147483647)
    @encode.begin_object(writer)
    @encode.key(writer, "data_edges")
    client_plan_emit_array(writer, edges, emit_client_task_pipeline_measurement)
    @encode.key(writer, "nodes")
    client_plan_emit_array(writer, nodes, emit_client_task_pipeline_measurement)
    @encode.key(writer, "root_refs")
    client_plan_emit_array(writer, roots, emit_client_task_pipeline_measurement)
    @encode.end_object(writer)
    Ok({
      fragments,
      request,
      barrier,
      node: barrier_node,
      output_contract,
      nodes,
      edges,
      roots,
      projections,
      results,
      graph: client_compilation_successful_geometry(
        @encode.finish_measurement_usage(writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      ),
    })
  } catch {
    _ => Err(Encoding)
  }
}
