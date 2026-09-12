///|
/// One owner for request, local machine graph and complete ordered root list.
/// This is generation material, not sealed-fragment admission or a Run permit.
priv struct FragmentMaterial {
  request : RequestArtifact
  graph : GeneratedArtifact
  roots : Array[RootArtifact]
}

///|
priv enum FragmentMaterialIssue {
  Artifact(RootArtifactIssue)
  Demand(@lower.DemandIssue)
  Root(@lower.RootEvidenceIssue)
  Budget
}

///|
fn prepare_fragment_material(
  request : @lower.FragmentRequest,
  demand_limits : @lower.DemandLimits,
  budget : RegistryLimits,
) -> Result[FragmentMaterial, FragmentMaterialIssue] {
  if budget.max_body_bytes < 0 ||
    budget.max_body_nodes < 1 ||
    budget.max_body_depth < 0 {
    return Err(Budget)
  }
  let pipeline = @lower.fragment_request_pipeline(request)
  // Do not accept independently prepared roots or a graph from another owner.
  let demands = match
    @lower.prepare_demand(
      @lower.fragment_pipeline_roots(pipeline),
      demand_limits,
    ) {
    Ok(demands) => demands
    Err(issue) => return Err(Demand(issue))
  }
  let request = match
    prepare_request_artifact(
      request,
      budget.max_body_bytes,
      budget.max_body_nodes,
      budget.max_body_depth,
    ) {
    Ok(request) => request
    Err(issue) => return Err(Artifact(issue))
  }
  let mut bytes = budget.max_body_bytes - request.artifact.bytes
  let mut nodes = budget.max_body_nodes - request.artifact.nodes
  let graph_text = try {
    let out = @encode.writer(bytes, nodes, budget.max_body_depth)
    @lower.emit_fragment_machine_pipeline(pipeline, out)
    @encode.finish(out)
  } catch {
    _ => return Err(Budget)
  }
  let graph = match
    canonicalize_generated_artifact(
      graph_text,
      bytes,
      nodes,
      budget.max_body_depth,
    ) {
    Ok(graph) => graph
    Err(issue) => return Err(Artifact(issue))
  }
  bytes -= graph.bytes
  nodes -= graph.nodes
  let count = @lower.root_count(@lower.demand_roots(demands))
  if count > nodes {
    return Err(Budget)
  }
  let roots = []
  for i = 0; i < count; i = i + 1 {
    let evidence = match
      @lower.prepare_root_evidence(demands, i, {
        max_nodes: nodes,
        max_tests: nodes,
        max_pointer_bytes: bytes,
      }) {
      Ok(evidence) => evidence
      Err(issue) => return Err(Root(issue))
    }
    let root = match
      prepare_root_artifact(evidence, bytes, nodes, budget.max_body_depth) {
      Ok(root) => root
      Err(issue) => return Err(Artifact(issue))
    }
    bytes -= root.bytes
    nodes -= root.nodes
    roots.push(root)
  }
  Ok({ request, graph, roots, })
}

///|
fn emit_fragment_material_roots(
  material : FragmentMaterial,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(out)
  for root in material.roots {
    @identity.emit_value(root.value, out)
  }
  @encode.end_array(out)
}
