///|
pub struct ClientTaskCompilation {
  owner : PreparedClientProgram
  plan : ClientTaskExecutablePlan
  template : @publication.RunEvidenceValue
  compiled_plan : @publication.PublicationContract
  result_names : Array[String]
  infer : ClientInferPlanGraph?
  infers : Array[ClientInferPlanGraph]
  serialization : ClientSerializationPlanGraph?
  priv standard_progress_keys : Array[String]?
}

///|
pub(all) enum ClientTaskCompilationIssue {
  Plan(ClientValuesExecutablePlanIssue)
  Material(ClientExecutionMaterialIssue)
  Graph(ClientTaskPlanGraphIssue)
  Template(@publication.RunEvidenceValueIssue)
  CompiledPlan(@publication.PublicationContractIssue)
  Encoding
  ForeignInferOwner
  ForeignSerializationOwner
}

///|
pub fn client_task_compilation_plan(
  value : ClientTaskCompilation,
) -> ClientTaskExecutablePlan {
  value.plan
}

///|
pub fn client_task_compilation_template(
  value : ClientTaskCompilation,
) -> @publication.RunEvidenceValue {
  value.template
}

///|
pub fn client_task_compilation_compiled_plan(
  value : ClientTaskCompilation,
) -> @publication.PublicationContract {
  value.compiled_plan
}

///|
pub fn client_task_compilation_result_names(
  value : ClientTaskCompilation,
) -> Array[String] {
  value.result_names.copy()
}

///|
/// Compile the checked task graph and all named Result occurrences. The
/// AoA logical identity is the canonical graph of its typed task fragments,
/// edges and roots; the Executable Plan additionally binds material and
/// enforcement facts. Site selection and captured values remain outside it.
pub fn issue_prepared_client_task_compilation(
  value : PreparedClientProgram,
  manifests : ClientCompilationManifests,
  sequence_limits : @lower.SequenceLimits,
  max_facts : Int,
  max_witnesses : Int,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  let (plan, template, graph) = match
    issue_prepared_client_task_plan_parts(
      value, manifests, sequence_limits, max_facts, max_witnesses, max_wire_bytes,
      max_nodes, max_depth,
    ) {
    Ok(parts) => parts
    Err(issue) => return Err(Plan(issue))
  }
  // The private Plan composition issued this exact template under these
  // same bounds. Keep its admitted original instead of decoding its wire again.
  finish_client_task_compilation(
    value, plan, template, graph, max_wire_bytes, max_nodes, max_depth,
  )
}

///|
fn finish_client_task_compilation(
  value : PreparedClientProgram,
  plan : ClientTaskExecutablePlan,
  template : @publication.RunEvidenceValue,
  graph : ClientTaskPlanGraph,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  infer? : ClientInferPlanGraph? = None,
  infers? : Array[ClientInferPlanGraph] = [],
  serialization? : ClientSerializationPlanGraph? = None,
) -> Result[ClientTaskCompilation, ClientTaskCompilationIssue] {
  // Consume before any fallible work. The completed Plan retains no extra
  // parsed graph/material tree, including after a refused continuation.
  let original = plan.plan.read_originals
  plan.plan.read_originals = None
  // Project only the canonical selection in this exact executable Plan.
  // No caller flag or reconstructed alias inventory can mark a Run.
  let selection_cid = match
    client_task_plan_target_selections_cid(
      plan,
      max_wire_bytes,
      max_nodes,
      max_depth,
      original~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard client_task_compilation_graph_original(
      value,
      plan,
      graph,
      max_wire_bytes,
      max_nodes,
      max_depth,
      original~,
    )
    is Some(graph_value) else {
    return Err(Encoding)
  }
  let aoa_logical_cid = match infer {
    // The model acquisition is not an AoA operation. The complete mixed
    // graph, Result transformations and barrier are bound by the Executable
    // Plan; the pure input computation retains its own AoA identity.
    Some(value) if value.serialization is Some(_) => {
      // Bind every pure component, rather than naming just the immediate
      // Model input as the entire computation. Content and Model barriers
      // are outside AoA and remain bound by the complete Executable Plan.
      guard @canonical.object_field(graph_value, "nodes")
        is Some(@canonical.Array(nodes)) else {
        return Err(Encoding)
      }
      let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
        _ => return Err(Encoding)
      }
      try {
        @encode.begin_array(writer)
        for node in @canonical.array_values(nodes) {
          if @canonical.object_field(node, "kind")
            is Some(@canonical.String("aoa_fragment")) {
            guard @canonical.object_field(node, "node_id")
              is Some(@canonical.String(node_id)) &&
              @canonical.object_field(node, "logical_cid")
              is Some(@canonical.String(logical_cid)) else {
              return Err(Encoding)
            }
            @encode.begin_object(writer)
            @encode.key(writer, "node_id")
            @encode.string_value(writer, node_id)
            @encode.key(writer, "logical_cid")
            @encode.string_value(writer, logical_cid)
            @encode.end_object(writer)
          }
        }
        @encode.end_array(writer)
        guard parse_plan_identity_value(
            @encode.finish(writer),
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(components) else {
          return Err(Encoding)
        }
        @canonical.cid_value(components, max_wire_bytes, max_nodes, max_depth)
      } catch {
        _ => return Err(Encoding)
      }
    }
    Some(value) => value.input_fragment_cid
    None if !infers.is_empty() => {
      // A Model barrier is outside AoA. Bind every pure input prefix in the
      // checked task order; the complete mixed graph remains in the executable
      // Plan. Do not select one prefix as the identity of all components.
      let writer = @encode.writer(max_wire_bytes, max_nodes, max_depth) catch {
        _ => return Err(Encoding)
      }
      try {
        @encode.begin_array(writer)
        for component in infers {
          @encode.begin_object(writer)
          @encode.key(writer, "node_id")
          @encode.string_value(writer, component.input.node_id)
          @encode.key(writer, "logical_cid")
          @encode.string_value(writer, component.input_fragment_cid)
          @encode.end_object(writer)
        }
        @encode.end_array(writer)
        guard parse_plan_identity_value(
            @encode.finish(writer),
            max_wire_bytes,
            max_nodes,
            max_depth,
          )
          is Some(prefixes) else {
          return Err(Encoding)
        }
        @canonical.cid_value(prefixes, max_wire_bytes, max_nodes, max_depth)
      } catch {
        _ => return Err(Encoding)
      }
    }
    None if serialization is Some(component) => component.input.logical_cid
    None =>
      @canonical.cid_value(graph_value, max_wire_bytes, max_nodes, max_depth) catch {
        _ => return Err(Encoding)
      }
  }
  let identity = prepared_client_identity(value)
  let body = "{\"version\":\"actql-compiled-plan/0.1\"," +
    "\"compiler_version\":\"" +
    @environment.compiler_version_token() +
    "\",\"aoa_ir_version\":\"" +
    @environment.compiler_aoa_ir_version_token() +
    "\",\"executable_plan_cid\":\"" +
    client_task_executable_plan_cid(plan) +
    "\",\"program_definition_cid\":\"" +
    identity.program_definition_cid +
    "\",\"program_semantics_cid\":\"" +
    prepared_client_program_semantics_cid(value) +
    "\",\"aoa_contract_cid\":\"" +
    @environment.compiler_aoa_contract_cid() +
    "\",\"aoa_logical_cid\":\"" +
    aoa_logical_cid +
    "\"" +
    (match selection_cid {
      None => ""
      Some(cid) => ",\"effect_target_selections_cid\":\"" + cid + "\""
    }) +
    "}"
  let compiled_plan = match
    @publication.seal_publication_contract(
      "compiled_plan", body, max_wire_bytes, max_nodes, max_depth,
    ) {
    Ok(compiled) => compiled
    Err(issue) => return Err(CompiledPlan(issue))
  }
  let result_names : Array[String] = []
  for index in 0..<prepared_client_result_count(value) {
    guard prepared_client_result_name(value, index) is Some(name) else {
      return Err(Encoding)
    }
    result_names.push(name)
  }
  let retained = match infer {
    Some(component) => [component]
    None => infers.copy()
  }
  Ok({
    owner: value,
    plan,
    template,
    compiled_plan,
    result_names,
    infer,
    infers: retained,
    serialization,
    standard_progress_keys: graph.standard_progress_keys,
  })
}

///|
/// The executable Plan is already retained by the compiler. Hash its existing
/// nonempty canonical tuple array without introducing another identity domain.
fn client_task_plan_target_selections_cid(
  plan : ClientTaskExecutablePlan,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original? : ClientExecutablePlanReadOriginals? = None,
) -> Result[String?, ClientTaskCompilationIssue] {
  let material = if original is Some(original) &&
    plan.plan.wire == original.plan_wire &&
    client_executable_plan_original_limits_fit(
      original, max_wire_bytes, max_nodes, max_depth,
    ) {
    original.material
  } else {
    // Tighter callers retain the complete original wire admission and order.
    guard parse_plan_identity_value(
        client_task_executable_plan_wire(plan),
        max_wire_bytes,
        max_nodes,
        max_depth,
      )
      is Some(body) &&
      @canonical.object_field(body, "execution_material") is Some(material) else {
      return Err(Encoding)
    }
    material
  }
  match @canonical.object_field(material, "effect_target_selections") {
    None => Ok(None)
    Some(selection) => {
      guard selection is @canonical.Array(values) &&
        @canonical.array_count(values) > 0 else {
        return Err(Encoding)
      }
      let cid = @canonical.cid_value(
        selection, max_wire_bytes, max_nodes, max_depth,
      ) catch {
        _ => return Err(Encoding)
      }
      Ok(Some(cid))
    }
  }
}

///|
pub fn client_task_compilation_infers(
  value : ClientTaskCompilation,
) -> Array[ClientInferPlanGraph] {
  value.infers.copy()
}

///|
/// Retain the exact checked model barrier, not a caller-supplied selector or
/// a replacement Program owner. This is compilation material only.
pub fn client_task_compilation_infer(
  value : ClientTaskCompilation,
) -> ClientInferPlanGraph? {
  value.infer
}

///|
/// Retain the original Content barrier through Run admission. A decoded Plan
/// or a matching CID cannot substitute for the checked compilation owner.
pub fn client_task_compilation_serialization(
  value : ClientTaskCompilation,
) -> ClientSerializationPlanGraph? {
  value.serialization
}

///|
fn client_task_compilation_graph_original(
  owner : PreparedClientProgram,
  plan : ClientTaskExecutablePlan,
  graph : ClientTaskPlanGraph,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  original? : ClientExecutablePlanReadOriginals? = None,
) -> @canonical.CanonicalValue? {
  if original is Some(original) &&
    physical_equal(owner, original.owner) &&
    plan.plan.wire == original.plan_wire &&
    graph.wire == original.graph_wire &&
    client_executable_plan_original_limits_fit(
      original, max_wire_bytes, max_nodes, max_depth,
    ) {
    Some(original.graph)
  } else {
    parse_plan_identity_value(graph.wire, max_wire_bytes, max_nodes, max_depth)
  }
}
