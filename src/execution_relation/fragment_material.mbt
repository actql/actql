///|
/// One owner for request, local machine graph and complete ordered root list.
/// This is generation material, not sealed-fragment admission or a Run permit.
priv struct FragmentMaterial {
  request : RequestArtifact
  graph : GeneratedArtifact
  roots : Array[RootArtifact]
  ordered : OrderedBinding?
}

///|
pub(all) enum FragmentMaterialIssue {
  Artifact(RootArtifactIssue)
  Demand(@lower.DemandIssue)
  Root(@lower.RootEvidenceIssue)
  Budget
  OrderedContractRequired
  UnexpectedOrderedContract
  OrderedContractMismatch
  OrderedReferences(@lower.OrderedReferenceIssue)
  OrderedResource(OrderedLimitsIssue)
  OrderedShape(OrderedShapeIssue)
  OrderedLinks(OrderedLinkIssue)
}

///|
fn prepare_fragment_material(
  request : @lower.FragmentRequest,
  demand_limits : @lower.DemandLimits,
  budget : RegistryLimits,
  ordered? : RegisteredOrderedContract? = None,
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
  let binding = match
    (@lower.fragment_request_row_limits(request.request), ordered) {
    (None, None) => None
    (None, Some(_)) => return Err(UnexpectedOrderedContract)
    (Some(_), None) => return Err(OrderedContractRequired)
    (Some(limits), Some(contract)) => {
      let remaining = {
        ..budget,
        max_body_bytes: bytes,
        max_body_nodes: nodes,
      }
      let binding = match
        prepare_fragment_ordered_binding(
          request.request,
          demands,
          contract,
          limits,
          remaining,
        ) {
        Ok(binding) => binding
        Err(issue) => return Err(issue)
      }
      // These immutable generated artifacts remain live alongside the final
      // graph and its canonical root array. Charge them, not merely output.
      for
        artifact in [binding.node.source, binding.node.graph, binding.artifact] {
        if artifact.bytes > bytes || artifact.nodes > nodes {
          return Err(Budget)
        }
        bytes -= artifact.bytes
        nodes -= artifact.nodes
      }
      for slot in binding.links.slots {
        if slot.root.bytes > bytes || slot.root.nodes > nodes {
          return Err(Budget)
        }
        bytes -= slot.root.bytes
        nodes -= slot.root.nodes
      }
      Some(binding)
    }
  }
  let graph_text = try {
    let out = @encode.writer(bytes, nodes, budget.max_body_depth)
    match binding {
      None => @lower.emit_fragment_machine_pipeline(pipeline, out)
      Some(binding) => emit_ordered_machine_pipeline(binding.node, out)
    }
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
  Ok({ request, graph, roots, ordered: binding, })
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
