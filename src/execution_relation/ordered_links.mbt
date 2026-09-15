///|
priv struct OrderedSlotLink {
  name : String
  root : RootArtifact
  context_cid : String
}

///|
/// Authored slot order; roots retain their separate canonical root-array slots.
/// The node CID and final evidence envelope are not constructed here.
priv struct OrderedLinks {
  shapes : OrderedShapes
  limits : OrderedLimits
  slots : Array[OrderedSlotLink]
}

///|
pub(all) enum OrderedLinkIssue {
  OwnerMismatch
  RootMismatch
  Limit
  RootPreparation(@lower.RootEvidenceIssue)
  RootArtifact(RootArtifactIssue)
}

///|
fn prepare_ordered_links(
  shapes : OrderedShapes,
  limits : OrderedLimits,
  demand : @lower.DemandIndex,
  budget : RegistryLimits,
) -> Result[OrderedLinks, OrderedLinkIssue] {
  if budget.max_body_bytes < 0 ||
    budget.max_body_nodes < 0 ||
    budget.max_body_depth < 0 {
    return Err(Limit)
  }
  let kernel = ordered_params_kernel(shapes.params)
  if ordered_limits_for_kernel(limits, kernel) is Err(_) {
    return Err(OwnerMismatch)
  }
  let roots = @lower.demand_roots(demand)
  let sequence = @lower.root_sequence(roots)
  let step = @lower.kernel_step(kernel)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.RowStep(root_kernel)) else {
    return Err(OwnerMismatch)
  }
  if !physical_equal(kernel, root_kernel) ||
    @lower.root_step_range(roots) != (step, step + 1) {
    return Err(OwnerMismatch)
  }
  let count = @lower.ordered_binding_count(kernel)
  if @lower.root_count(roots) != count {
    return Err(RootMismatch)
  }
  if count > budget.max_body_nodes {
    return Err(Limit)
  }
  let by_pointer : Map[String, Int] = Map([])
  for r = 0; r < count; r = r + 1 {
    let root = @lower.root_at(roots, r).unwrap()
    if by_pointer.contains(root.parameter_pointer) {
      return Err(RootMismatch)
    }
    by_pointer[root.parameter_pointer] = r
  }
  let mut bytes = budget.max_body_bytes
  let mut nodes = budget.max_body_nodes
  let slots = []
  for i = 0; i < count; i = i + 1 {
    guard @lower.ordered_binding_at(kernel, i) is Some((name, expression)) else {
      return Err(RootMismatch)
    }
    guard by_pointer.get("/bindings/" + i.to_string() + "/expr") is Some(r) else {
      return Err(RootMismatch)
    }
    if !physical_equal(@lower.root_at(roots, r).unwrap().expression, expression) {
      return Err(RootMismatch)
    }
    let evidence = match
      @lower.prepare_root_evidence(demand, r, {
        max_nodes: nodes,
        max_tests: nodes,
        max_pointer_bytes: bytes,
      }) {
      Ok(evidence) => evidence
      Err(e) => return Err(RootPreparation(e))
    }
    let root = match
      prepare_root_artifact(evidence, bytes, nodes, budget.max_body_depth) {
      Ok(root) => root
      Err(e) => return Err(RootArtifact(e))
    }
    bytes -= root.bytes
    nodes -= root.nodes
    let context = try {
      let out = @encode.hashing_writer(bytes, nodes, budget.max_body_depth)
      emit_ordered_context(shapes, i, out)
      @encode.finish_hash_usage(out)
    } catch {
      _ => return Err(Limit)
    }
    bytes -= context.1
    nodes -= context.2
    slots.push({ name, root, context_cid: "sha256:" + context.0, })
  }
  Ok({ shapes, limits, slots, })
}
