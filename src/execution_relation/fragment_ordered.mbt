///|
/// All ordered material is regenerated from this request's checked owner and
/// selected contract. No independently supplied limits, roots or node IDs.
fn prepare_fragment_ordered_binding(
  request : @lower.FragmentRequest,
  demand : @lower.DemandIndex,
  contract : RegisteredOrderedContract,
  limits : LogicalLimits,
  budget : RegistryLimits,
) -> Result[OrderedBinding, FragmentMaterialIssue] {
  if contract.cid != selected_ordered_contract_cid ||
    contract.relation.registry_cid != selected_registry_cid ||
    contract.relation.values_contract_cid != selected_values_contract_cid {
    return Err(OrderedContractMismatch)
  }
  let roots = @lower.fragment_pipeline_roots(
    @lower.fragment_request_pipeline(request),
  )
  let (start, end) = @lower.root_step_range(roots)
  guard end == start + 1 &&
    @lower.sequence_step(@lower.root_sequence(roots), start)
    is Some(@lower.RowStep(kernel)) else {
    return Err(OrderedContractMismatch)
  }
  let refs = match
    @lower.prepare_ordered_references(kernel, {
      max_references: budget.max_body_nodes,
      max_pointer_bytes: budget.max_body_bytes,
      max_work: budget.max_body_nodes,
      max_frames: budget.max_body_depth,
    }) {
    Ok(refs) => refs
    Err(issue) => return Err(OrderedReferences(issue))
  }
  let params = prepare_ordered_params(contract, refs)
  let ceilings = @lower.fragment_request_ceilings(request)
  let context = match
    prepare_ordered_limits(params, limits, ceilings.0, ceilings.1) {
    Ok(context) => context
    Err(issue) => return Err(OrderedResource(issue))
  }
  let shapes = match prepare_ordered_shapes(params, budget) {
    Ok(shapes) => shapes
    Err(issue) => return Err(OrderedShape(issue))
  }
  let links = match prepare_ordered_links(shapes, context, demand, budget) {
    Ok(links) => links
    Err(issue) => return Err(OrderedLinks(issue))
  }
  match prepare_ordered_binding(links, budget) {
    Ok(binding) => Ok(binding)
    Err(issue) => Err(Artifact(issue))
  }
}

///|
fn emit_ordered_machine_pipeline(
  node : OrderedNodeArtifact,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  let kernel = ordered_params_kernel(node.params)
  let prepared = @lower.bound_preparation(@lower.kernel_owner(kernel))
  let id = @lower.node_id(
    @lower.node_at(prepared, @lower.kernel_step(kernel)).unwrap(),
  )
  @encode.begin_object(out)
  @encode.key(out, "output")
  @encode.string_value(out, id)
  @encode.key(out, "sources")
  @encode.begin_object(out)
  @encode.key(out, "input")
  @encode.begin_object(out)
  @encode.key(out, "sort")
  @encode.string_value(out, "relation")
  @encode.end_object(out)
  @encode.end_object(out)
  @encode.key(out, "steps")
  @encode.begin_array(out)
  @identity.emit_value(node.graph.value, out)
  @encode.end_array(out)
  @encode.key(out, "version")
  @encode.string_value(out, "aoa-pipeline/0.1")
  @encode.end_object(out)
}
