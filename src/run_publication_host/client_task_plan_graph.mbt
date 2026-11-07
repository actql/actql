///|
/// Resolve the checked consumer port without reconstructing a Plan in callers.
fn client_task_edge_input(
  graph : @strategy.CheckedDAG,
  edge : @strategy.DataEdge,
) -> (String, @carrier.Carrier)? {
  let consumer = @strategy.data_edge_consumer(edge)
  match @strategy.graph_task_selected_step(graph, consumer) {
    Some(step) =>
      match @strategy.data_edge_operation_input(edge) {
        Some((source_step, position)) =>
          if source_step == step && position == @strategy.data_edge_input(edge) {
            @strategy.graph_task_owner(graph, consumer)
            .map(@lower.bound_preparation)
            .bind(prepared => {
              @lower.node_at(prepared, step)
              .bind(node => @lower.node_input_target(node, position))
              .bind(target => @lower.preparation_carrier_at(prepared, target))
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
}

///|
/// Checked AoA nodes, their producer edges, and checked Result/Effect roots. Supplied
/// source inputs still require physical capture and admission before a Run.
pub struct ClientTaskPlanGraph {
  wire : String
  transformations : Array[ClientResultTransformation]
  priv result_plans : Array[ClientResultPlanIdentity]
  priv standard_progress_keys : Array[String]?
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
/// The complete checked Model inventory is required in graph order. Dropping,
/// duplicating or substituting one component cannot compile a partial Run.
pub fn issue_prepared_client_multi_infer_task_plan_graph(
  value : PreparedClientProgram,
  components : Array[ClientInferPlanGraph],
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphIssue] {
  guard prepared_client_composed_infer_occurrences(value) is Some(occurrences) &&
    !occurrences.is_empty() &&
    occurrences.length() == components.length() else {
    return Err(UnsupportedGraph)
  }
  for index in 0..<occurrences.length() {
    if !client_infer_occurrence_matches_plan(
        occurrences[index],
        components[index],
      ) {
      return Err(UnsupportedGraph)
    }
  }
  issue_client_task_plan_graph(
    value,
    sequence_limits,
    max_wire_bytes,
    max_nodes,
    max_depth,
    false,
    [],
    infers=components,
  )
}

///|
// These are the original fragment issuer's limits, not execution authority.
// Only an equal sequence profile and no looser encoding bounds can supply the
// existing progress profile without regenerating the same immutable nodes.
fn client_task_graph_standard_progress_limits(
  sequence : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Bool {
  let standard = client_standard_values_sequence_limits()
  sequence.max_steps == standard.max_steps &&
  sequence.max_rows == standard.max_rows &&
  sequence.max_cells == standard.max_cells &&
  sequence.max_bindings == standard.max_bindings &&
  sequence.max_name_bytes == standard.max_name_bytes &&
  sequence.expressions == standard.expressions &&
  max_wire_bytes <= 1000000 &&
  max_nodes <= 100000 &&
  max_depth <= 100
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
  infers? : Array[ClientInferPlanGraph] = [],
  serialization? : ClientSerializationTaskComponent? = None,
) -> Result[ClientTaskPlanGraph, ClientTaskPlanGraphIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidLimits)
  }
  let graph = value.graph
  let count = @strategy.graph_task_count(graph)
  if infer is Some(_) && !infers.is_empty() {
    return Err(UnsupportedGraph)
  }
  let components = match infer {
    Some(component) => [component]
    None => infers
  }
  let mut planned_inputs = @strategy.graph_ordered_inputs_complete(graph)
  if !planned_inputs {
    for component in components {
      if physical_equal(component.owner, value) &&
        @strategy.graph_keyed_model_plan_inputs_complete(
          graph,
          component.task,
          component.source_ordinal,
        ) {
        planned_inputs = true
        break
      }
    }
  }
  if count == 0 ||
    count > max_nodes ||
    (
      @strategy.graph_result_count(graph) == 0 &&
      (
        !effects ||
        !@strategy.graph_program_has_effects(graph) ||
        effect_roots.is_empty()
      )
    ) ||
    (@strategy.graph_program_has_effects(graph) && !effects) ||
    !planned_inputs {
    return Err(UnsupportedGraph)
  }
  let fragments : Array[ClientTaskFragmentNode] = []
  let input_fragments : Array[ClientTaskFragmentNode] = []
  let input_nodes : Array[@canonical.CanonicalValue] = []
  let model_edges : Array[@canonical.CanonicalValue] = []
  let transformations : Array[ClientResultTransformation] = []
  let result_plans : Array[ClientResultPlanIdentity] = []
  let nodes : Array[@canonical.CanonicalValue] = []
  if serialization is Some(component) &&
    (
      !components.is_empty() ||
      !physical_equal(component.serialization.owner, value) ||
      !effects ||
      component.serialization.task < 0 ||
      component.serialization.task >= count
    ) {
    return Err(UnsupportedGraph)
  }
  let by_task : Map[Int, ClientInferPlanGraph] = Map([])
  for component in components {
    if !physical_equal(value, component.owner) ||
      component.task < 0 ||
      component.task >= count ||
      by_task.contains(component.task) {
      return Err(UnsupportedGraph)
    }
    by_task[component.task] = component
  }
  for task in 0..<count {
    let selected = by_task.get(task)
    let content = match serialization {
      Some(component) if component.serialization.task == task => Some(component)
      _ => None
    }
    let fragment = match selected {
      Some(infer) if task == infer.task => infer.output
      _ if content is Some(component) => component.output
      _ =>
        match
          issue_prepared_client_task_fragment(
            value, task, sequence_limits, max_wire_bytes, max_nodes, max_depth,
          ) {
          Ok(fragment) => fragment
          Err(issue) => return Err(Fragment(issue))
        }
    }
    let input = match selected {
      Some(infer) if task == infer.task =>
        match infer.serialization {
          Some(component) => component.input
          None => infer.input
        }
      _ if content is Some(component) => component.input
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
    match selected {
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
      _ if content is Some(component) => {
        guard parse_plan_identity_value(
            component.graph.wire,
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(component_graph) &&
          @canonical.object_field(component_graph, "nodes")
          is Some(@canonical.Array(component_nodes)) &&
          @canonical.object_field(component_graph, "data_edges")
          is Some(@canonical.Array(component_edges)) &&
          @canonical.object_field(component_graph, "root_refs")
          is Some(@canonical.Array(component_roots)) &&
          @canonical.array_values(component_roots).is_empty() &&
          component.graph.transformations.is_empty() else {
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
    // A declared intermediate Content Result belongs to its authentic barrier,
    // not to the later task terminal. Reuse that checked producer; do not run
    // generation again or reconstruct its five fields from the final consumer.
    let content_result = match serialization {
      Some(component) if component.serialization.task == task =>
        match @strategy.graph_result_occurrence(graph, result) {
          Some(occurrence) if @results.port_target(
              @execution.managed_result_occurrence_port(occurrence),
            ) ==
            @pipeline.Step(component.serialization.step) =>
            Some(component.serialization)
          _ => None
        }
      _ => None
    }
    let infer_result = match by_task.get(task) {
      Some(component) => {
        guard client_infer_occurrence_matches_plan(
            component.occurrence,
            component,
          ) &&
          client_infer_result_producer(
            component.occurrence,
            result,
            component.result_producers,
          )
          is Some(producer) else {
          return Err(Root(Root(RequiresResultTransformation)))
        }
        Some((component.occurrence, producer))
      }
      None => None
    }
    let (producer_node, producer_port, producer_contract) = match infer_result {
      Some((_, (_, node, port, contract))) => (node, port, contract)
      None => {
        let producer = match content_result {
          Some(content) => content.output
          None => fragment
        }
        (producer.node_id, producer.output_port, producer.output_contract_cid)
      }
    }
    let parts = match
      issue_client_result_plan_parts(
        value,
        result,
        producer_node,
        producer_port,
        producer_contract,
        max_wire_bytes,
        max_nodes,
        max_depth,
        serialization_output=content_result.map(content => content.barrier),
        infer_output=infer_result.map(value => (value.0, value.1.0)),
      ) {
      Ok(parts) => parts
      Err(issue) => return Err(Root(issue))
    }
    if parts.transformation is Some((node, edge)) {
      nodes.push(node)
      result_edges.push(edge)
    }
    roots.push(parts.root)
    result_plans.push(parts.plan)
    if parts.selection is Some(selection) {
      transformations.push(selection)
    }
  }
  let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
    _ => return Err(Encoding)
  }
  try {
    let emitted : Result[Unit, ClientTaskPlanGraphIssue] = emit_client_compilation_graph(
      writer,
      writer => {
        for index in 0..<@strategy.graph_data_count(graph) {
          guard @strategy.graph_data_at(graph, index) is Some(edge) else {
            return Err(InvalidEdge)
          }
          let producer = @strategy.data_edge_producer(edge)
          let consumer = @strategy.data_edge_consumer(edge)
          if producer < 0 || producer >= consumer || consumer >= count {
            return Err(InvalidEdge)
          }
          let input = client_task_edge_input(graph, edge)
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
          let projection = if input_contract_cid != source.output_contract_cid {
            match
              issue_client_task_result_input_projection(
                graph, edge, index, source, max_wire_bytes, max_nodes, max_depth,
              ) {
              Ok(value) => value
              Err(issue) => return Err(issue)
            }
          } else {
            None
          }
          let (source_node, source_port, source_contract) = match projection {
            None =>
              (source.node_id, source.output_port, source.output_contract_cid)
            Some(projection) => {
              nodes.push(projection.node)
              result_edges.push(projection.edge)
              (
                projection.node_id,
                projection.output_port,
                projection.output_contract_cid,
              )
            }
          }
          if input_contract_cid != source_contract {
            return Err(ContractMismatch)
          }
          emit_client_compilation_data_edge(
            writer,
            source.output_carrier,
            source_contract,
            source_node,
            source_port,
            destination.node_id,
            input_name,
            (value, writer) => @encode.string_value(writer, value),
          )
          if serialization is Some(component) &&
            component.serialization.task == consumer {
            for (name, node_id, port, cid) in component.external_ports {
              if name != input_name {
                continue
              }
              if cid != source_contract {
                return Err(ContractMismatch)
              }
              let extra = match projection {
                None =>
                  client_serialization_plan_edge(
                    source, node_id, port, max_wire_bytes, max_nodes, max_depth,
                  )
                Some(projected) =>
                  client_task_result_input_projection_edge(
                    projected, node_id, port, max_wire_bytes, max_nodes, max_depth,
                  )
              }
              guard extra is Some(extra) else { return Err(Encoding) }
              @canonical.emit_value(extra, writer)
            }
          }
        }
        for edge in model_edges {
          @canonical.emit_value(edge, writer)
        }
        for edge in result_edges {
          @canonical.emit_value(edge, writer)
        }
        Ok(())
      },
      writer => {
        for node in nodes {
          @canonical.emit_value(node, writer)
        }
      },
      writer => {
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
        Ok(())
      },
    )
    match emitted {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    let standard_progress_keys = if components.is_empty() &&
      serialization is None &&
      client_task_graph_standard_progress_limits(
        sequence_limits, max_wire_bytes, max_nodes, max_depth,
      ) {
      Some(fragments.map(fragment => fragment.node_id))
    } else {
      None
    }
    Ok({
      wire: @encode.finish(writer),
      transformations,
      result_plans,
      standard_progress_keys,
    })
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
