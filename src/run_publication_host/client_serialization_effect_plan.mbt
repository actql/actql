///|
/// Checked compiler material, not another execution or custody owner. The
/// original Effect graph supplies every external producer; internal edges
/// retain the actual Content barrier and ordinary pure consumer fragments.
priv struct ClientSerializationTaskComponent {
  serialization : ClientSerializationPlanGraph
  input : ClientTaskFragmentNode
  output : ClientTaskFragmentNode
  graph : ClientTaskPlanGraph
  external_ports : Array[(String, String, String, String)]
}

///|
pub(all) enum ClientSerializationEffectPlanIssue {
  UnsupportedGraph
  Capacity(@environment.CapacityIssue)
  MissingCeiling(String)
  InvalidCeiling(String)
  Preparation(ClientSerializationPreparationIssue)
  Generation(ClientSerializationPlanGraphIssue)
  Consumer(ClientTaskFragmentIssue)
  InvalidEdge
  Encoding
}

///|
fn issue_client_serialization_effect_plan(
  owner : PreparedClientProgram,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientSerializationPlanGraph?, ClientSerializationEffectPlanIssue] {
  let occurrences = prepared_client_serialization_occurrences(owner)
  if occurrences.is_empty() {
    return Ok(None)
  }
  guard occurrences.length() == 1 &&
    @strategy.graph_program_has_effects(owner.graph) &&
    @strategy.graph_task_count(owner.graph) >= 2 &&
    @strategy.graph_captured_prefix(owner.graph) == 1 else {
    return Err(UnsupportedGraph)
  }
  let (task, step) = occurrences[0]
  // Resolve finite installed Host policy before selection. Author guards can
  // only tighten it; wire/planning limits are not byte custody capacity.
  let capacity = match
    @environment.read_capacity(
      @checked.checked_environment(@strategy.graph_program(owner.graph)),
      { max_bytes: 100000, max_nodes: 10000, max_depth: 100, },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capacity(issue))
  }
  let bounds = []
  for field in ["max_artifact_rows", "max_artifact_bytes"] {
    guard @capacity_policy.ceiling(
        @environment.capacity_policy(capacity),
        field,
      )
      is Some(ceiling) else {
      return Err(MissingCeiling(field))
    }
    let value = @capacity_policy.ceiling_value(ceiling)
    if value < 0L || value > 2147483647L {
      return Err(InvalidCeiling(field))
    }
    bounds.push(value.to_int())
  }
  let serialization = match
    issue_acquired_client_serialization_plan_graph(
      owner,
      task,
      step,
      bounds[0],
      bounds[1],
      max_nodes,
      sequence_limits,
      max_wire_bytes,
      max_nodes,
      max_depth,
      false,
      effect_component=true,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Generation(issue))
  }
  Ok(Some(serialization))
}

///|
/// Compose ordinary consumers only after selecting the authentic Content
/// barrier. Mixed Model callers retain that same barrier in their own checked
/// component instead of reconstructing a prefix or dropping generation.
fn issue_client_serialization_effect_component(
  owner : PreparedClientProgram,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  ClientSerializationTaskComponent?,
  ClientSerializationEffectPlanIssue,
] {
  let serialization = match
    issue_client_serialization_effect_plan(
      owner, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(Some(value)) => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
  }
  let task = serialization.task
  let step = serialization.step
  let barrier = serialization.barrier
  let preparation = @lower.bound_preparation(
    @lower.serialization_owner(barrier),
  )
  guard client_task_output_step(
      owner.graph,
      task,
      @lower.node_count(preparation),
    )
    is Some(terminal) &&
    terminal >= step else {
    return Err(UnsupportedGraph)
  }
  let base = parse_plan_identity_value(
    serialization.graph.wire,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
  guard base is Some(base) &&
    @canonical.object_field(base, "nodes") is Some(@canonical.Array(base_nodes)) &&
    @canonical.object_field(base, "data_edges")
    is Some(@canonical.Array(base_edges)) &&
    @canonical.object_field(base, "root_refs") is Some(@canonical.Array(roots)) &&
    @canonical.array_values(roots).is_empty() else {
    return Err(Encoding)
  }
  let nodes = @canonical.array_values(base_nodes).copy()
  let edges = @canonical.array_values(base_edges).copy()
  let producers = [serialization.output]
  if serialization.input.output_port != serialization.output.output_port {
    producers.push(serialization.input)
  }
  let external_ports = []
  let mut output = serialization.output
  for next in (step + 1)..<(terminal + 1) {
    if nodes.length() >= max_nodes {
      return Err(UnsupportedGraph)
    }
    let fragment = match
      issue_client_serialized_compute_fragment(
        serialization, terminal, next, sequence_limits, max_wire_bytes, max_nodes,
        max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Consumer(issue))
    }
    guard parse_plan_identity_value(
        fragment.wire,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(node) &&
      @canonical.object_field(node, "input_contracts") is Some(contracts) &&
      @lower.node_at(preparation, next) is Some(consumer) else {
      return Err(Encoding)
    }
    nodes.push(node)
    for port in 0..<@lower.node_input_count(consumer) {
      if edges.length() + external_ports.length() >= max_nodes {
        return Err(UnsupportedGraph)
      }
      let port_name = "input_" + port.to_string()
      guard @canonical.object_field(contracts, port_name)
        is Some(@canonical.String(contract_cid)) else {
        return Err(InvalidEdge)
      }
      match @lower.node_input_target(consumer, port) {
        Some(@pipeline.Step(source)) => {
          guard @lower.node_at(preparation, source) is Some(source_node) else {
            return Err(InvalidEdge)
          }
          let mut producer : ClientTaskFragmentNode? = None
          for candidate in producers {
            if candidate.output_port == @lower.node_id(source_node) {
              if producer is Some(_) {
                return Err(InvalidEdge)
              }
              producer = Some(candidate)
            }
          }
          if producer is None && source < step {
            // A later consumer can also borrow a pure branch from before the
            // Content barrier. Bind that original checked output to the same
            // captured inputs; it is not another acquisition or a Values copy.
            if nodes.length() >= max_nodes {
              return Err(UnsupportedGraph)
            }
            let prefix = match
              issue_client_compute_prefix_fragment_for_owner(
                @lower.serialization_owner(barrier),
                source,
                source,
                "task_" +
                task.to_string() +
                "_before_serialize_reference_" +
                source.to_string(),
                sequence_limits,
                max_wire_bytes,
                max_nodes,
                max_depth,
              ) {
              Ok(value) => value
              Err(issue) => return Err(Consumer(issue))
            }
            guard parse_plan_identity_value(
                prefix.wire,
                max_wire_bytes,
                max_nodes,
                max_depth,
              )
              is Some(node) &&
              @canonical.object_field(node, "input_contracts")
              is Some(contracts) else {
              return Err(Encoding)
            }
            for input in 0..<@pipeline.input_count(@lower.pipeline(preparation)) {
              if edges.length() + external_ports.length() >= max_nodes {
                return Err(UnsupportedGraph)
              }
              guard @pipeline.input_at(@lower.pipeline(preparation), input)
                is Some((name, _)) &&
                @canonical.object_field(contracts, name)
                is Some(@canonical.String(cid)) else {
                return Err(InvalidEdge)
              }
              external_ports.push((name, prefix.node_id, name, cid))
            }
            nodes.push(node)
            producers.push(prefix)
            producer = Some(prefix)
          }
          guard producer is Some(producer) &&
            producer.output_contract_cid == contract_cid else {
            return Err(InvalidEdge)
          }
          let edge = client_serialization_plan_edge(
            producer,
            fragment.node_id,
            port_name,
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          guard edge is Some(edge) else { return Err(Encoding) }
          edges.push(edge)
        }
        Some(@pipeline.Input(index)) => {
          guard @pipeline.input_at(@lower.pipeline(preparation), index)
            is Some((name, carrier)) &&
            client_task_carrier_contract(
              carrier, max_wire_bytes, max_nodes, max_depth,
            )
            is Some(("relation", cid)) &&
            cid == contract_cid else {
            return Err(InvalidEdge)
          }
          external_ports.push((name, fragment.node_id, port_name, contract_cid))
        }
        _ => return Err(InvalidEdge)
      }
    }
    producers.push(fragment)
    output = fragment
  }
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(writer)
    @encode.key(writer, "data_edges")
    client_plan_emit_array(writer, edges)
    @encode.key(writer, "nodes")
    client_plan_emit_array(writer, nodes)
    @encode.key(writer, "root_refs")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    @encode.end_object(writer)
    Ok(
      Some({
        serialization,
        input: serialization.input,
        output,
        graph: {
          wire: @encode.finish(writer),
          transformations: [],
          standard_progress_keys: None,
        },
        external_ports,
      }),
    )
  } catch {
    _ => Err(Encoding)
  }
}

///|
fn client_serialization_plan_edge(
  source : ClientTaskFragmentNode,
  node_id : String,
  port : String,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> @canonical.CanonicalValue? {
  try {
    let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
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
    @encode.string_value(writer, node_id)
    @encode.key(writer, "port")
    @encode.string_value(writer, port)
    @encode.end_object(writer)
    @encode.end_object(writer)
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
