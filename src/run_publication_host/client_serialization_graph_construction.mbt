///|
/// Original codec geometry for the existing Content Graph constructor. This
/// is sizing DATA only: no Graph, policy, Result selection or identity is
/// issued. Prefix/Result arrays describe the whole co-held construction,
/// including a later writer or Result refusal.
pub(all) struct ClientSerializationGraphConstruction {
  prefix : ClientTaskFragmentConstruction?
  input_contract : (Int, Int, Int)?
  output_contract : (Int, Int, Int)
  barrier : (Int, Int, Int)
  node : (Int, Int, Int)
  input_edge : (Int, Int, Int)?
  results : Array[(Int, Int, Int)]
  projections : Array[ClientResultGraphConstruction]
  nodes : Array[(Int, Int, Int)]
  edges : Array[(Int, Int, Int)]
  roots : Array[(Int, Int, Int)]
  graph : (Int, Int, Int)
}

///|
/// Measure exactly the same barrier/node emitters and checked prefix/Result
/// inventory before their wires/trees exist. Possible direct/transformed
/// Results are conservatively co-counted; real construction still chooses
/// its original branch and validates every policy and producer binding.
pub fn measure_prepared_client_serialization_graph_construction(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_rows : Int,
  max_bytes : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  include_results? : Bool = true,
) -> Result[
  ClientSerializationGraphConstruction,
  ClientSerializationPlanGraphIssue,
] {
  if max_rows < 0 ||
    max_bytes < 0 ||
    max_preparation_work <= 0 ||
    max_wire_bytes <= 0 ||
    max_nodes <= 0 ||
    max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let barrier = match
    prepare_client_serialization(
      owner,
      task,
      step,
      max_work=max_preparation_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let preparation = @lower.bound_preparation(
    @lower.serialization_owner(barrier),
  )
  guard @lower.preparation_output_target(preparation)
    is Some(@pipeline.Step(terminal)) &&
    terminal >= step &&
    (!include_results || terminal == step) &&
    step > 0 &&
    @lower.node_at(preparation, step) is Some(output) else {
    return Err(UnsupportedGraph)
  }
  let selected = @strategy.graph_task_selected_step(owner.graph, task) ==
    Some(step)
  let prefix = if selected &&
    @pipeline.serialization_sort(@lower.serialization_checked(barrier)) is None {
    None
  } else {
    Some(
      match
        measure_prepared_client_serialization_prefix_construction(
          owner, task, step, max_preparation_work, sequence_limits, max_wire_bytes,
          max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Input(issue))
      },
    )
  }
  guard measure_client_task_carrier_contract(
      @lower.node_output_carrier(output),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(output_contract) else {
    return Err(UnsupportedGraph)
  }
  let input_contract = match prefix {
    Some(_) => None // The prefix already retains this original contract geometry.
    None => {
      guard @lower.node_input_target(output, 0) is Some(target) &&
        @lower.preparation_carrier_at(preparation, target) is Some(carrier) &&
        measure_client_task_carrier_contract(
          carrier, max_wire_bytes, max_nodes, max_depth,
        )
        is Some(value) else {
        return Err(UnsupportedGraph)
      }
      Some(value)
    }
  }
  let (row_guard, byte_guard) = @lower.serialization_author_guards(barrier)
  let rows = match row_guard {
    Some(value) if value < max_rows.to_int64() => value.to_int()
    _ => max_rows
  }
  let bytes = match byte_guard {
    Some(value) if value < max_bytes.to_int64() => value.to_int()
    _ => max_bytes
  }
  let barrier_id = "task_" + task.to_string() + "_serialize_" + step.to_string()
  let output_port = @lower.node_id(output)
  try {
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_serialization_barrier_body(
      writer,
      barrier,
      barrier_id,
      output_port,
      (),
      rows,
      bytes,
      Some(()),
      measure_client_fragment_cid,
    )
    let body = @encode.finish_measurement_usage(writer)
    let writer = @encode.measuring_writer(max_wire_bytes, max_nodes, max_depth)
    emit_client_serialization_node_body(
      writer,
      body,
      emit_client_task_pipeline_measurement,
      barrier_id,
      output_port,
      (),
      (),
      measure_client_fragment_cid,
    )
    let node = @encode.finish_measurement_usage(writer)
    let nodes = []
    let edges = []
    let roots = []
    let results = []
    let projections = []
    let input_edge = match prefix {
      None => None
      Some(prefix) => {
        nodes.push(prefix.fragment)
        let writer = @encode.measuring_writer(
          max_wire_bytes, max_nodes, max_depth,
        )
        @encode.begin_object(writer)
        @encode.key(writer, "carrier")
        @encode.string_value(writer, "relation")
        @encode.key(writer, "contract_cid")
        measure_client_fragment_cid((), writer)
        @encode.key(writer, "from")
        @encode.begin_object(writer)
        @encode.key(writer, "node_id")
        @encode.string_value(writer, prefix.node_id)
        @encode.key(writer, "port")
        @encode.string_value(writer, prefix.output_port)
        @encode.end_object(writer)
        @encode.key(writer, "to")
        @encode.begin_object(writer)
        @encode.key(writer, "node_id")
        @encode.string_value(writer, barrier_id)
        @encode.key(writer, "port")
        @encode.string_value(writer, "input_0")
        @encode.end_object(writer)
        @encode.end_object(writer)
        let edge = @encode.finish_measurement_usage(writer)
        edges.push(edge)
        Some(edge)
      }
    }
    nodes.push(node)
    for
      result in 0..<(if include_results {
        @strategy.graph_result_count(owner.graph)
      } else {
        0
      }) {
      if @strategy.graph_result_task(owner.graph, result) != Some(task) {
        return Err(UnsupportedGraph)
      }
      let projection = match
        measure_prepared_client_result_graph_construction(
          owner, result, barrier_id, output_port, max_wire_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Root(issue))
      }
      let plan = match
        measure_prepared_client_result_plan(
          owner, result, max_wire_bytes, max_nodes, max_depth,
        ) {
        Ok(value) => value
        Err(issue) => return Err(Root(Root(ResultPlan(issue))))
      }
      // The same original constructor may retain a projected node/edge or
      // direct root. Do not guess its admitted branch during measurement.
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
    // The final writer is one bounded output; partial prefix/Result bodies
    // above stay separately represented even if this assembled graph refuses.
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
      prefix,
      input_contract,
      output_contract,
      barrier: body,
      node,
      input_edge,
      results,
      projections,
      nodes,
      edges,
      roots,
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
