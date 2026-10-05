///|
/// Cold Graph/configuration preparation for the existing application kernel.
/// It is not an input binding, execution permit or resource receipt. The one
/// snapshot preparation transfers to Apply only after Delta envelope admission;
/// its borrowed producer and optional output builder remain with their owners.
struct ApplyBasePreparation {
  mut source : DiffSource?
  graph : @carrier.Graph
  contract : @graph_contract.CheckedContract
  limits : Limits
  storage_limits : @storage.Limits
  workspace : Int
  mut output_builder : @storage.Builder?
  mut snapshot : @snapshot.Preparation?
}

///|
fn fixed_apply_workspace(
  base : DiffSource,
  graph : @carrier.Graph,
  limits : Limits,
  storage_limits : @storage.Limits,
) -> Int? {
  guard source_workspace(base) is Some(snapshot_slots) &&
    body_workspace_slots(limits) is Some(body_slots) &&
    checked_add(snapshot_slots, body_slots) is Some(with_body) &&
    checked_add(with_body, storage_limits.max_workspace_slots)
    is Some(with_storage) &&
    before_workspace_slots(limits) is Some(before_slots) &&
    checked_add(with_storage, before_slots) is Some(with_before) &&
    @storage.property_snapshot_append_workspace_slots(graph, storage_limits)
    is Some(append_slots) &&
    checked_add(with_before, append_slots) is Some(with_append) &&
    action_workspace_slots(limits) is Some(action_slots) else {
    return None
  }
  checked_add(with_append, action_slots)
}

///|
fn prepare_apply_base_source(
  base : DiffSource,
  limits : Limits,
  storage_limits : @storage.Limits,
  output_builder : @storage.Builder?,
  reserved_workspace_slots : Int,
) -> Result[ApplyBasePreparation, Issue] {
  if !valid_limits(limits) || reserved_workspace_slots < 0 {
    return Err(InvalidLimits)
  }
  guard source_graph(base) is Some(graph) &&
    @graph_contract.admit_graph(graph, {
      max_bytes: limits.max_identity_bytes,
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
    })
    is Ok(contract) else {
    return Err(InvalidGraph)
  }
  if output_builder is Some(builder) &&
    !@storage.builder_accepts_output(builder, graph, storage_limits) {
    return Err(Storage(@storage.WrongCarrier))
  }
  guard fixed_apply_workspace(base, graph, limits, storage_limits)
    is Some(workspace) &&
    checked_add(workspace, reserved_workspace_slots) is Some(total) &&
    total <= limits.max_workspace_slots else {
    return Err(WorkspaceLimit)
  }
  let snapshot = match start_snapshot(base, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    source: Some(base),
    graph,
    contract,
    limits,
    storage_limits,
    workspace,
    output_builder,
    snapshot: Some(snapshot),
  })
}

///|
/// Perform synchronous configuration admission before resumable Delta input
/// conversion. This does not inspect or advance the input's action records.
pub fn prepare_apply_base_view(
  base : @lifecycle.ProducerView,
  graph : @carrier.Graph,
  limits : Limits,
  storage_limits : @storage.Limits,
  output_builder? : @storage.Builder? = None,
  reserved_workspace_slots? : Int = 0,
) -> Result[ApplyBasePreparation, Issue] {
  prepare_apply_base_source(
    Viewed(base, graph),
    limits,
    storage_limits,
    output_builder,
    reserved_workspace_slots,
  )
}

///|
pub fn start_apply_from_prepared_base(
  base : ApplyBasePreparation,
  delta : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[ApplyPreparation, Issue] {
  guard base.source is Some(source) && base.snapshot is Some(_) else {
    return Err(Terminal)
  }
  let available = match source {
    Stored(storage) => @storage.available(storage)
    Viewed(view, _) =>
      @lifecycle.producer_read_reference_available(
        @lifecycle.producer_view_read_reference(view),
      )
  }
  if !available {
    return Err(InvalidGraph)
  }
  prepare_apply_source(
    source,
    delta,
    base.limits,
    base.storage_limits,
    reference_issuer~,
    output_builder=base.output_builder,
    defer_actions=true,
    admitted_base=Some(base),
  )
}

///|
/// Cancel only this unused snapshot preparation. Borrowed input storage and
/// the caller's Graph output builder are never reclaimed here.
pub fn cleanup_apply_base(base : ApplyBasePreparation) -> Unit {
  if base.snapshot is Some(snapshot) {
    @snapshot.cancel(snapshot) |> ignore
  }
  base.snapshot = None
  base.source = None
  base.output_builder = None
}
