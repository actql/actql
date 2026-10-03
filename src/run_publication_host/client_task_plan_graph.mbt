///|
/// Checked AoA nodes, their producer edges, and named Result roots. Supplied
/// source inputs still require physical capture and admission before a Run.
pub struct ClientTaskPlanGraph {
  wire : String
  transformations : Array[ClientResultTransformation]
}

///|
pub(all) enum ClientTaskPlanGraphIssue {
  InvalidLimits
  UnsupportedGraph
  Fragment(ClientTaskFragmentIssue)
  Root(ClientResultPlanPartsIssue)
  InvalidEdge
  ContractMismatch
  Encoding
}

///|
pub(all) enum ClientTaskPlanGraphAdmissionIssue {
  Issue(ClientTaskPlanGraphIssue)
  MismatchedGraph
}

///|
pub fn client_task_plan_graph_wire(value : ClientTaskPlanGraph) -> String {
  value.wire
}

///|
pub fn issue_prepared_client_task_plan_graph(
  value : PreparedClientProgram,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphIssue] {
  issue_client_task_plan_graph(
    value,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    false,
    [],
  )
}

///|
/// Splice the original Model component into its checked task position. The
/// common graph still validates every producer edge and issues Named Results.
pub fn issue_prepared_client_composed_task_plan_graph(
  value : PreparedClientProgram,
  infer : ClientInferPlanGraph,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphIssue] {
  issue_client_task_plan_graph(
    value,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    false,
    [],
    infer=Some(infer),
  )
}

///|
fn issue_client_task_plan_graph(
  value : PreparedClientProgram,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  effects : Bool,
  effect_roots : Array[(String, Int)],
  infer? : ClientInferPlanGraph? = None,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = value.graph
  let count = @strategy.graph_task_count(graph)
  if count == 0 ||
    count > max_nodes ||
    @strategy.graph_result_count(graph) == 0 ||
    (@strategy.graph_program_has_effects(graph) && !effects) ||
    !@strategy.graph_ordered_inputs_complete(graph) {
    return Err(UnsupportedGraph)
  }
  let fragments : Array[ClientTaskFragmentNode] = []
  let input_fragments : Array[ClientTaskFragmentNode] = []
  let input_nodes : Array[@canonical.CanonicalValue] = []
  let model_edges : Array[@canonical.CanonicalValue] = []
  let transformations : Array[ClientResultTransformation] = []
  let nodes : Array[@canonical.CanonicalValue] = []
  if infer is Some(infer) &&
    (
      !physical_equal(value, infer.owner) ||
      infer.task < 0 ||
      infer.task >= count
    ) {
    return Err(UnsupportedGraph)
  }
  for task in 0..<count {
    let fragment = match infer {
      Some(infer) if task == infer.task => infer.output
      _ =>
        match
          issue_prepared_client_task_fragment(
            value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
          ) {
          Ok(fragment) => fragment
          Err(issue) => return Err(Fragment(issue))
        }
    }
    let input = match infer {
      Some(infer) if task == infer.task => infer.input
      _ => fragment
    }
    guard parse_plan_identity_value(
        input.wire,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(node) else {
      return Err(Encoding)
    }
    fragments.push(fragment)
    input_fragments.push(input)
    input_nodes.push(node)
    match infer {
      Some(infer) if task == infer.task => {
        guard parse_plan_identity_value(
            infer.graph.wire,
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(component) &&
          @canonical.object_field(component, "nodes")
          is Some(@canonical.Array(component_nodes)) &&
          @canonical.object_field(component, "data_edges")
          is Some(@canonical.Array(component_edges)) &&
          @canonical.object_field(component, "root_refs")
          is Some(@canonical.Array(component_roots)) &&
          @canonical.array_values(component_roots).is_empty() &&
          infer.graph.transformations.is_empty() else {
          return Err(UnsupportedGraph)
        }
        for component_node in @canonical.array_values(component_nodes) {
          nodes.push(component_node)
        }
        for edge in @canonical.array_values(component_edges) {
          model_edges.push(edge)
        }
      }
      _ => nodes.push(node)
    }
  }
  let roots : Array[@canonical.CanonicalValue] = []
  let result_edges : Array[@canonical.CanonicalValue] = []
  for result in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, result) is Some(task) &&
      fragments.get(task) is Some(fragment) else {
      return Err(UnsupportedGraph)
    }
    let parts = match
      issue_client_result_plan_parts(
        value,
        result,
        fragment.node_id,
        fragment.output_port,
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
      result_edges.push(edge)
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
    for index in 0..<@strategy.graph_data_count(graph) {
      guard @strategy.graph_data_at(graph, index) is Some(edge) else {
        return Err(InvalidEdge)
      }
      let producer = @strategy.data_edge_producer(edge)
      let consumer = @strategy.data_edge_consumer(edge)
      if producer < 0 || producer >= consumer || consumer >= count {
        return Err(InvalidEdge)
      }
      let input = match @strategy.graph_task_selected_step(graph, consumer) {
        Some(step) =>
          match @strategy.data_edge_operation_input(edge) {
            Some((source_step, position)) =>
              if source_step == step &&
                position == @strategy.data_edge_input(edge) {
                @strategy.graph_task_owner(graph, consumer)
                .map(@lower.bound_preparation)
                .bind(prepared => {
                  @lower.node_at(prepared, step)
                  .bind(node => @lower.node_input_target(node, position))
                  .bind(target => {
                    @lower.preparation_carrier_at(prepared, target)
                  })
                })
                .map(carrier => ("input_" + position.to_string(), carrier))
              } else {
                None
              }
            None => None
          }
        None =>
          @strategy.graph_task_owner(graph, consumer).bind(owner => {
            @pipeline.input_at(
              @lower.pipeline(@lower.bound_preparation(owner)),
              @strategy.data_edge_input(edge),
            )
          })
      }
      guard fragments.get(producer) is Some(source) &&
        input_fragments.get(consumer) is Some(destination) &&
        input is Some((input_name, carrier)) &&
        client_task_carrier_kind(source.output_carrier) is Some(source_kind) &&
        @carrier.kind(carrier) == source_kind &&
        input_nodes.get(consumer) is Some(consumer_node) &&
        @canonical.object_field(consumer_node, "input_contracts")
        is Some(input_contracts) &&
        @canonical.object_field(input_contracts, input_name)
        is Some(@canonical.String(input_contract_cid)) else {
        return Err(InvalidEdge)
      }
      if input_contract_cid != source.output_contract_cid {
        return Err(ContractMismatch)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "carrier")
      @encode.string_value(writer, source.output_carrier)
      @encode.key(writer, "contract_cid")
      @encode.string_value(writer, source.output_contract_cid)
      @encode.key(writer, "from")
      @encode.begin_object(writer)
      @encode.key(writer, "node_id")
      @encode.string_value(writer, source.node_id)
      @encode.key(writer, "port")
      @encode.string_value(writer, source.output_port)
      @encode.end_object(writer)
      @encode.key(writer, "to")
      @encode.begin_object(writer)
      @encode.key(writer, "node_id")
      @encode.string_value(writer, destination.node_id)
      @encode.key(writer, "port")
      @encode.string_value(writer, input_name)
      @encode.end_object(writer)
      @encode.end_object(writer)
    }
    for edge in model_edges {
      @canonical.emit_value(edge, writer)
    }
    for edge in result_edges {
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
    for (name, task) in effect_roots {
      guard fragments.get(task) is Some(fragment) else {
        return Err(InvalidEdge)
      }
      @encode.begin_object(writer)
      @encode.key(writer, "name")
      @encode.string_value(writer, name)
      @encode.key(writer, "ref")
      @encode.begin_object(writer)
      @encode.key(writer, "node_id")
      @encode.string_value(writer, fragment.node_id)
      @encode.key(writer, "port")
      @encode.string_value(writer, fragment.output_port)
      @encode.end_object(writer)
      @encode.key(writer, "role")
      @encode.string_value(writer, "effect_result")
      @encode.end_object(writer)
    }
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok({ wire: @encode.finish(writer), transformations, })
  } catch {
    _ => Err(Encoding)
  }
}

///|
pub fn admit_prepared_client_task_plan_graph(
  value : PreparedClientProgram,
  saved_wire : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphAdmissionIssue] {
  let issued = match
    issue_prepared_client_task_plan_graph(
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
