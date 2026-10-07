///|
/// Source and lowered graph steps share the same checked kernel. The graph
/// artifact CID is the derive-binding node identity; evidence stays outside it.
priv struct OrderedNodeArtifact {
  params : OrderedParams
  source : GeneratedArtifact
  graph : GeneratedArtifact
}

///|
fn emit_ordered_fragment_step(
  params : OrderedParams,
  source : Bool,
  out : @encode.Writer,
  local_input? : Bool = true,
) -> Unit raise @encode.EncodeFailure {
  let kernel = ordered_params_kernel(params)
  let prepared = @lower.bound_preparation(@lower.kernel_owner(kernel))
  let node = @lower.node_at(prepared, @lower.kernel_step(kernel)).unwrap()
  @encode.begin_object(out)
  @encode.key(out, "id")
  @encode.string_value(out, @lower.node_id(node))
  @encode.key(out, "in")
  @encode.begin_array(out)
  @encode.string_value(
    out,
    if local_input {
      "input"
    } else {
      @lower.kernel_input(kernel)
    },
  )
  @encode.end_array(out)
  @encode.key(out, "op")
  @encode.string_value(out, "REL.derive")
  @encode.key(out, "params")
  if source {
    guard @lower.kernel_body(kernel) is @lower.OrderedBindings(bindings) else {
      raise @encode.InvalidStructure
    }
    @encode.begin_object(out)
    @encode.key(out, "bindings")
    @encode.begin_array(out)
    for (name, expr) in bindings {
      @encode.begin_object(out)
      @encode.key(out, "expr")
      @lower.emit_expression_source(expr, out)
      @encode.key(out, "name")
      @encode.string_value(out, name)
      @encode.end_object(out)
    }
    @encode.end_array(out)
    @encode.end_object(out)
  } else {
    emit_ordered_params(params, out)
  }
  @encode.end_object(out)
}

///|
/// Emit a logical Plan node from registered params and their exact kernel.
/// The original checked edge is retained; this is not fragment admission,
/// runtime enforcement or execution permission. Fragment-local emission
/// continues to bind its separate canonical input and evidence closure.
pub fn emit_ordered_kernel_node(
  params : OrderedParams,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  emit_ordered_fragment_step(params, false, out, local_input=false)
}

///|
fn prepare_ordered_node_artifact(
  params : OrderedParams,
  limits : RegistryLimits,
) -> Result[OrderedNodeArtifact, RootArtifactIssue] {
  if limits.max_body_bytes < 0 ||
    limits.max_body_nodes < 1 ||
    limits.max_body_depth < 0 {
    return Err(InvalidLimits)
  }
  let artifacts : Array[GeneratedArtifact] = []
  let mut bytes = limits.max_body_bytes
  let mut nodes = limits.max_body_nodes
  for source in [true, false] {
    let text = try {
      let out = @encode.writer(bytes, nodes, limits.max_body_depth)
      emit_ordered_fragment_step(params, source, out)
      @encode.finish(out)
    } catch {
      _ => return Err(OutputLimit)
    }
    let artifact = match
      canonicalize_generated_artifact(text, bytes, nodes, limits.max_body_depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    bytes -= artifact.bytes
    nodes -= artifact.nodes
    artifacts.push(artifact)
  }
  Ok({ params, source: artifacts[0], graph: artifacts[1], })
}
