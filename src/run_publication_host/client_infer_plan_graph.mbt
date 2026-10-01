///|
/// Private compilation material, not an executable admission. The installing
/// Host must still admit the referenced limits, retry, media and egress bodies
/// and register a physical provider before accepting a Run.
pub struct ClientInferPlanGraph {
  owner : PreparedClientProgram
  execution : @environment.ModelExecutionContract
  graph : ClientTaskPlanGraph
  input_fragment_cid : String
  request_wire : String
  request_cid : String
  barrier_cid : String
}

///|
pub(all) enum ClientInferPlanGraphIssue {
  UnsupportedProgram
  ForeignExecution
  InvalidDependency
  Execution(@environment.ModelTaskIssue)
  Input(ClientTaskFragmentIssue)
  Mapping(@lower.InferInputIssue)
  Result(ClientResultPlanPartsIssue)
  Encoding
}

///|
/// Admit an execution-contract body against the ModelTask already installed
/// in this prepared Program. Neither its dependency references nor current
/// egress authority are implicitly admitted by this reader.
pub fn read_prepared_client_infer_model_execution(
  value : PreparedClientProgram,
  step : Int,
  body : Bytes,
  expected_cid : String,
  limits : @environment.Limits,
  max_work : Int,
) -> Result[@environment.ModelExecutionContract, ClientInferPlanGraphIssue] {
  guard client_infer_prefix_owner(value, 0, step) is Some(owner) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return Err(UnsupportedProgram)
  }
  @environment.read_model_execution_contract(
    @infer.model_task(infer),
    body,
    expected_cid,
    limits,
    max_work,
  ).map_err(issue => Execution(issue))
}

///|
pub fn client_infer_plan_graph_matches(
  value : ClientInferPlanGraph,
  owner : PreparedClientProgram,
  execution : @environment.ModelExecutionContract,
) -> Bool {
  physical_equal(value.owner, owner) &&
  physical_equal(value.execution, execution)
}

///|
pub fn client_infer_plan_graph_wire(value : ClientInferPlanGraph) -> String {
  value.graph.wire
}

///|
pub fn client_infer_plan_graph_input_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.input_fragment_cid
}

///|
pub fn client_infer_plan_graph_request_wire(
  value : ClientInferPlanGraph,
) -> String {
  value.request_wire
}

///|
pub fn client_infer_plan_graph_request_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.request_cid
}

///|
pub fn client_infer_plan_graph_barrier_cid(
  value : ClientInferPlanGraph,
) -> String {
  value.barrier_cid
}

///|
fn client_infer_dependency_cid(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<71 {
    let c = value[index].to_int()
    if !((c >= 48 && c <= 57) || (c >= 97 && c <= 102)) {
      return false
    }
  }
  true
}

///|
/// Select one terminal Infer under the ordinary checked Program owner. The
/// prefix stays AoA and the model node stays an acquisition barrier. Checked
/// Result transformations consume the barrier's actual Relation port.
pub fn issue_prepared_client_infer_plan_graph(
  value : PreparedClientProgram,
  step : Int,
  execution : @environment.ModelExecutionContract,
  limits_cid : String,
  egress_requirements_cid : String,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientInferPlanGraph, ClientInferPlanGraphIssue] {
  guard client_infer_prefix_owner(value, 0, step) is Some(owner) &&
    @strategy.graph_task_target(value.graph, 0) == Some(@pipeline.Step(step)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return Err(UnsupportedProgram)
  }
  if !physical_equal(
      @infer.model_task(infer),
      @environment.model_execution_task(execution),
    ) {
    return Err(ForeignExecution)
  }
  if !client_infer_dependency_cid(limits_cid) ||
    !client_infer_dependency_cid(egress_requirements_cid) {
    return Err(InvalidDependency)
  }
  let prefix = match
    issue_prepared_client_infer_prefix_fragment(
      value, 0, step, sequence_limits, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let mappings = match
    @lower.prepare_infer_inputs(
      infer,
      @lower.parameter_bindings(owner),
      sequence_limits.expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Mapping(issue))
  }
  guard client_task_carrier_contract(
      @lower.node_output_carrier(node),
      max_wire_bytes,
      max_nodes,
      max_depth,
    )
    is Some(("relation", output_contract_cid)) else {
    return Err(UnsupportedProgram)
  }
  try {
    let request_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(request_writer)
    for index in 0..<@infer.input_binding_count(infer) {
      guard @infer.input_binding_at(infer, index) is Some(binding) &&
        @lower.infer_input_expression_at(mappings, index) is Some(expression) else {
        return Err(Encoding)
      }
      @encode.key(request_writer, @infer.input_binding_role(binding))
      @lower.emit_expression(expression, request_writer)
    }
    @encode.end_object(request_writer)
    guard parse_plan_identity_value(
        @encode.finish(request_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(request) else {
      return Err(Encoding)
    }
    let request_wire = @canonical.stringify_value(
      request, max_wire_bytes, max_nodes, max_depth,
    )
    let request_cid = @canonical.cid_value(
      request, max_wire_bytes, max_nodes, max_depth,
    )
    let barrier_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(barrier_writer)
    @encode.key(barrier_writer, "egress_requirements_cid")
    @encode.string_value(barrier_writer, egress_requirements_cid)
    @encode.key(barrier_writer, "input_contract_cid")
    @encode.string_value(barrier_writer, prefix.output_contract_cid)
    @encode.key(barrier_writer, "input_fragment_cid")
    @encode.string_value(barrier_writer, prefix.logical_cid)
    @encode.key(barrier_writer, "input_roles")
    @encode.begin_object(barrier_writer)
    for index in 0..<@infer.input_binding_count(infer) {
      let role = @infer.input_binding_role(
        @infer.input_binding_at(infer, index).unwrap(),
      )
      @encode.key(barrier_writer, role)
      @encode.string_value(
        barrier_writer,
        "/" + role.replace(old="~", new="~0").replace(old="/", new="~1"),
      )
    }
    @encode.end_object(barrier_writer)
    @encode.key(barrier_writer, "key_fields")
    @encode.begin_array(barrier_writer)
    for index in 0..<@infer.key_count(infer) {
      @encode.string_value(
        barrier_writer,
        @schema.reference_name(@infer.key_at(infer, index).unwrap().field),
      )
    }
    @encode.end_array(barrier_writer)
    @encode.key(barrier_writer, "limits_cid")
    @encode.string_value(barrier_writer, limits_cid)
    @encode.key(barrier_writer, "model_execution_contract_cid")
    @encode.string_value(
      barrier_writer,
      @environment.model_execution_cid(execution),
    )
    @encode.key(barrier_writer, "model_task_contract_cid")
    @encode.string_value(
      barrier_writer,
      @environment.model_task_identity(@infer.model_task(infer)).2,
    )
    @encode.key(barrier_writer, "on_non_success")
    @encode.string_value(
      barrier_writer,
      match @infer.result_mode(infer) {
        Outcomes => "outcomes"
        Fail => "fail"
      },
    )
    @encode.key(barrier_writer, "output_contract_cid")
    @encode.string_value(barrier_writer, output_contract_cid)
    @encode.key(barrier_writer, "request_fragment_cid")
    @encode.string_value(barrier_writer, request_cid)
    @encode.key(barrier_writer, "version")
    @encode.string_value(barrier_writer, "actql-inference-barrier/0.1")
    @encode.end_object(barrier_writer)
    guard parse_plan_identity_value(
        @encode.finish(barrier_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(barrier_body) else {
      return Err(Encoding)
    }
    let barrier_cid = @canonical.cid_value(
      barrier_body, max_wire_bytes, max_nodes, max_depth,
    )
    guard @canonical.object_with_string_field(
        barrier_body, "barrier_cid", barrier_cid,
      )
      is Some(barrier) &&
      parse_plan_identity_value(
        prefix.wire,
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(prefix_node) else {
      return Err(Encoding)
    }
    let barrier_id = "task_0_infer_" + step.to_string()
    let output_port = @lower.node_id(node)
    let nodes : Array[@canonical.CanonicalValue] = [prefix_node]
    let edges : Array[@canonical.CanonicalValue] = []
    let roots : Array[@canonical.CanonicalValue] = []
    let transformations : Array[ClientResultTransformation] = []
    let node_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(node_writer)
    @encode.key(node_writer, "barrier")
    @canonical.emit_value(barrier, node_writer)
    @encode.key(node_writer, "barrier_contract_cid")
    @encode.string_value(
      node_writer,
      @environment.compiler_inference_barrier_contract_cid(),
    )
    @encode.key(node_writer, "input_contracts")
    @encode.begin_object(node_writer)
    @encode.key(node_writer, "input_0")
    @encode.string_value(node_writer, prefix.output_contract_cid)
    @encode.end_object(node_writer)
    @encode.key(node_writer, "input_refs")
    @encode.begin_array(node_writer)
    @encode.string_value(node_writer, "input_0")
    @encode.end_array(node_writer)
    @encode.key(node_writer, "kind")
    @encode.string_value(node_writer, "acquisition_barrier")
    @encode.key(node_writer, "node_id")
    @encode.string_value(node_writer, barrier_id)
    @encode.key(node_writer, "output_contracts")
    @encode.begin_object(node_writer)
    @encode.key(node_writer, output_port)
    @encode.string_value(node_writer, output_contract_cid)
    @encode.end_object(node_writer)
    @encode.key(node_writer, "output_ref")
    @encode.string_value(node_writer, output_port)
    @encode.key(node_writer, "profile_id")
    @encode.string_value(node_writer, "actql-infer/0.1")
    @encode.end_object(node_writer)
    guard parse_plan_identity_value(
        @encode.finish(node_writer),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(barrier_node) else {
      return Err(Encoding)
    }
    nodes.push(barrier_node)
    let edge_wire = "{\"carrier\":\"relation\",\"contract_cid\":\"" +
      prefix.output_contract_cid +
      "\",\"from\":{\"node_id\":\"" +
      prefix.node_id +
      "\",\"port\":\"" +
      prefix.output_port +
      "\"},\"to\":{\"node_id\":\"" +
      barrier_id +
      "\",\"port\":\"input_0\"}}"
    guard parse_plan_identity_value(
        edge_wire, max_wire_bytes, max_nodes, max_depth,
      )
      is Some(edge) else {
      return Err(Encoding)
    }
    edges.push(edge)
    for result in 0..<@strategy.graph_result_count(value.graph) {
      let parts = match
        issue_client_result_plan_parts(
          value, result, barrier_id, output_port, output_contract_cid, max_wire_bytes,
          max_nodes, max_depth,
        ) {
        Ok(parts) => parts
        Err(issue) => return Err(Result(issue))
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
    let graph_writer = @encode.writer(max_wire_bytes, max_nodes, max_depth)
    @encode.begin_object(graph_writer)
    @encode.key(graph_writer, "data_edges")
    client_plan_emit_array(graph_writer, edges)
    @encode.key(graph_writer, "nodes")
    client_plan_emit_array(graph_writer, nodes)
    @encode.key(graph_writer, "root_refs")
    client_plan_emit_array(graph_writer, roots)
    @encode.end_object(graph_writer)
    Ok({
      owner: value,
      execution,
      graph: { wire: @encode.finish(graph_writer), transformations, },
      input_fragment_cid: prefix.logical_cid,
      request_wire,
      request_cid,
      barrier_cid,
    })
  } catch {
    _ => Err(Encoding)
  }
}
