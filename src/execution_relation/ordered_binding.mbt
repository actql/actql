///|
/// One checked node and its complete binding record. Construction derives the
/// node from the links' params owner; callers cannot splice a foreign node CID.
priv struct OrderedBinding {
  links : OrderedLinks
  node : OrderedNodeArtifact
  artifact : GeneratedArtifact
}

///|
fn emit_ordered_binding_body(
  links : OrderedLinks,
  node_cid : String,
  self_cid : String?,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "aoa_node_cid")
  @encode.string_value(out, node_cid)
  @encode.key(out, "bindings")
  @encode.begin_array(out)
  for slot in links.slots {
    @encode.begin_object(out)
    @encode.key(out, "checked_expression_cid")
    @encode.string_value(out, slot.root.cid)
    @encode.key(out, "context_contract_cid")
    @encode.string_value(out, slot.context_cid)
    @encode.key(out, "name")
    @encode.string_value(out, slot.name)
    @encode.end_object(out)
  }
  @encode.end_array(out)
  @encode.key(out, "failure_scope")
  @encode.string_value(out, "row-binding-expression")
  @encode.key(out, "input_contract_cid")
  @encode.string_value(out, links.shapes.input_cid)
  @encode.key(out, "input_passthrough")
  @encode.bool_value(out, true)
  @encode.key(out, "limits_cid")
  @encode.string_value(out, links.limits.cid)
  @encode.key(out, "mode")
  @encode.string_value(out, "ordered_array")
  @encode.key(out, "output_contract_cid")
  @encode.string_value(out, links.shapes.output_cid)
  if self_cid is Some(cid) {
    @encode.key(out, "self_cid")
    @encode.string_value(out, cid)
  }
  @encode.key(out, "version")
  @encode.string_value(out, "actql-derive-binding/0.1")
  @encode.end_object(out)
}

///|
fn prepare_ordered_binding(
  links : OrderedLinks,
  limits : RegistryLimits,
) -> Result[OrderedBinding, RootArtifactIssue] {
  let node = match prepare_ordered_node_artifact(links.shapes.params, limits) {
    Ok(node) => node
    Err(issue) => return Err(issue)
  }
  let bytes = limits.max_body_bytes - node.source.bytes - node.graph.bytes
  let nodes = limits.max_body_nodes - node.source.nodes - node.graph.nodes
  let text = try {
    let out = @encode.writer(bytes, nodes, limits.max_body_depth)
    emit_ordered_binding_body(links, node.graph.cid, None, out)
    @encode.finish(out)
  } catch {
    _ => return Err(OutputLimit)
  }
  let artifact = match
    canonicalize_generated_artifact(text, bytes, nodes, limits.max_body_depth) {
    Ok(artifact) => artifact
    Err(issue) => return Err(issue)
  }
  // The artifact and subsequent emission must not diverge when the caller
  // releases its temporary slot array. Referenced values are immutable.
  Ok({ links: { ..links, slots: links.slots.copy(), }, node, artifact, })
}

///|
/// Exact closure for one ordered step; graph and request are still separate.
fn emit_ordered_evidence(
  binding : OrderedBinding,
  max_entries : Int,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  @encode.key(out, "bindings")
  @encode.begin_array(out)
  emit_ordered_binding_body(
    binding.links,
    binding.node.graph.cid,
    Some(binding.artifact.cid),
    out,
  )
  @encode.end_array(out)
  @encode.key(out, "contexts")
  emit_ordered_context_bodies(binding.links, max_entries, out)
  @encode.key(out, "limits")
  emit_ordered_limit_bodies(binding.links, out)
  @encode.key(out, "shapes")
  emit_ordered_shape_bodies(binding.links, out)
  @encode.end_object(out)
}
