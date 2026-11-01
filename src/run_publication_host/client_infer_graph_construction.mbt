///|
/// Geometry of this original Model occurrence's complete prefix/request/
/// barrier/suffix/Result construction. This is DATA, never a Graph, policy,
/// provider admission or Resource permission. The same construction also owns
/// its actual original mappings and lowered Fragment inputs. The real issuer
/// consumes these originals; it still selects and validates every Result.
pub struct ClientInferGraphConstruction {
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
  priv occurrence : ClientInferOccurrence
  priv execution : @environment.ModelExecutionContract
  priv sequence_limits : @lower.SequenceLimits
  priv max_wire_bytes : Int
  priv max_nodes : Int
  priv max_depth : Int
  priv mappings : @lower.PreparedInferInputs
  priv pipeline_inputs : Array[ClientTaskPipelineInput]
  priv serialization : ClientSerializationPlanGraph?
}

///|
/// The same Model emitter also measures its already retained Content producer.
/// Keeping a component original does not authorize byte generation or Model I/O;
/// the Request must back both constructors and their failed-child overlap.
pub fn measure_installed_client_composed_infer_graph_construction(
  occurrence : ClientInferOccurrence,
  execution : @environment.ModelExecutionContract,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization? : ClientSerializationPlanGraph? = None,
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
  // Preserve the ordinary constructor's original prefix-before-mapping order.
  let ordinary_prefix = match serialization {
    None =>
      Some(
        match
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
        },
      )
    Some(_) => None
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
    let fragments : Array[ClientTaskFragmentConstruction] = []
    let pipeline_inputs : Array[ClientTaskPipelineInput] = []
    let nodes : Array[(Int, Int, Int)] = []
    let edges : Array[(Int, Int, Int)] = []
    let roots : Array[(Int, Int, Int)] = []
    let projections : Array[ClientResultGraphConstruction] = []
    let results : Array[(Int, Int, Int)] = []
    let producers : Array[(Int, String, String)] = []
    match serialization {
      None => {
        let (prefix, input) = ordinary_prefix.unwrap()
        fragments.push(prefix)
        pipeline_inputs.push(input)
        nodes.push(prefix.fragment)
        producers.push((step - 1, prefix.node_id, prefix.output_port))
      }
      Some(component) => {
        guard physical_equal(component.owner, prepared) &&
          physical_equal(@lower.serialization_owner(component.barrier), bound) &&
          component.task == occurrence.task &&
          component.step < step &&
          client_serialization_graph_original_parts(
            component, prepared, max_wire_bytes, max_nodes, max_depth,
          )
          is Some((content_nodes, content_edges, content_roots)) &&
          content_roots.is_empty() else {
          return Err(UnsupportedProgram)
        }
        // These are original admitted values, not another graph-wire parse.
        for
          (originals, measured) in [
            (content_nodes, nodes),
            (content_edges, edges),
          ] {
          for original in originals {
            let writer = @encode.measuring_writer(
              max_wire_bytes, max_nodes, max_depth,
            )
            @canonical.emit_value(original, writer)
            measured.push(@encode.finish_measurement_usage(writer))
          }
        }
        producers.push(
          (
            component.step,
            component.output.node_id,
            component.output.output_port,
          ),
        )
        for next in (component.step + 1)..<step {
          let (fragment, input) = match
            measure_client_serialized_infer_fragment_construction(
              occurrence, component, next, sequence_limits, max_wire_bytes, max_nodes,
              max_depth,
            ) {
            Err(issue) => return Err(Input(issue))
            Ok(value) => value
          }
          fragments.push(fragment)
          pipeline_inputs.push(input)
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
      }
    }
    let (prefix_step, prefix_id, prefix_port) = producers[producers.length() - 1]
    if prefix_step != step - 1 {
      return Err(UnsupportedProgram)
    }
    nodes.push(barrier_node)
    producers.push((step, barrier_id, output_port))
    let edge_writer = @encode.measuring_writer(
      max_wire_bytes, max_nodes, max_depth,
    )
    emit_client_compilation_data_edge(
      edge_writer,
      "relation",
      (),
      prefix_id,
      prefix_port,
      barrier_id,
      "input_0",
      measure_client_fragment_cid,
    )
    edges.push(@encode.finish_measurement_usage(edge_writer))
    for next in (step + 1)..<(terminal + 1) {
      let (fragment, prepared_input) = match
        measure_client_infer_fragment_construction(
          occurrence,
          next,
          sequence_limits,
          max_wire_bytes,
          max_nodes,
          max_depth,
          serialization_boundary=serialization.map(component => component.step),
        ) {
        Err(issue) => return Err(Input(issue))
        Ok(value) => value
      }
      fragments.push(fragment)
      pipeline_inputs.push(prepared_input)
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
      occurrence,
      execution,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      mappings,
      pipeline_inputs,
      serialization,
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
