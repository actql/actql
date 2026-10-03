///|
priv enum PropertySnapshotPhase {
  ReloadNodes
  ReloadEdges
  RetainReload
  CheckSnapshot
} derive(Eq)

///|
/// Operation state, not a new material owner. Private completion remains under
/// the same retention owner until its entire canonical snapshot is verified.
priv struct PropertySnapshotState {
  mut header : @snapshot.PropertyHeader?
  limits : @snapshot.Limits
  expected_cid : String
  input_available : () -> Bool
  reference_issuer : @value.ReferenceIssuer?
  mut output : @graph.OutputBuilder?
  mut completed : @graph.Completed?
  mut hashing : @snapshot.Preparation?
  mut phase : PropertySnapshotPhase
  mut index : Int
  mut control_work_remaining : Int?
}

///|
fn cleanup_property_snapshot_reload(state : PropertySnapshotState) -> Bool {
  if state.hashing is Some(hashing) {
    @snapshot.cancel(hashing) |> ignore
    state.hashing = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  if state.completed is Some(output) {
    @graph.discard_completed(output) |> ignore
    state.completed = None
  }
  state.header = None
  true
}

///|
fn property_snapshot_reload_step(
  state : PropertySnapshotState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !(state.input_available)() {
      return @bounded.Failed(GraphInputUnavailable, progress, used)
    }
    if state.control_work_remaining is Some(remaining) && remaining < 1 {
      return @bounded.Failed(GraphControlWorkLimit, progress, used)
    }
    let remaining = match state.control_work_remaining {
      None => quantum - used
      Some(remaining) => Int::min(quantum - used, remaining)
    }
    let mut consumed = 1
    match state.phase {
      ReloadNodes | ReloadEdges => {
        guard state.header is Some(header) && state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        let edge = state.phase == ReloadEdges
        let count = if edge {
          @snapshot.property_header_edge_count(header)
        } else {
          @snapshot.property_header_node_count(header)
        }
        if state.index == count {
          state.index = 0
          state.phase = if edge { RetainReload } else { ReloadEdges }
        } else {
          let record = if edge {
            @snapshot.property_header_edge_at(header, state.index)
          } else {
            @snapshot.property_header_node_at(header, state.index)
          }
          guard record is Some(record) else {
            return @bounded.Failed(InvalidGraphKernel, progress, used)
          }
          let appended = if edge {
            @graph.append_property_snapshot_edge(
              output,
              record,
              reference_issuer=state.reference_issuer,
            )
          } else {
            @graph.append_property_snapshot_node(
              output,
              record,
              reference_issuer=state.reference_issuer,
            )
          }
          match appended {
            Ok(_) => {
              state.index += 1
              progress += 1
            }
            Err(issue) =>
              return @bounded.Failed(
                GraphSnapshotOutput(issue),
                progress,
                used + 1,
              )
          }
        }
      }
      RetainReload => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        state.output = None
        let completed = match @graph.finish_output(output) {
          Ok(output) => output
          Err(issue) =>
            return @bounded.Failed(
              GraphSnapshotOutput(issue),
              progress,
              used + 1,
            )
        }
        state.completed = Some(completed)
        guard @graph.completed_storage(completed) is Some(storage) else {
          return @bounded.Failed(GraphInputUnavailable, progress, used + 1)
        }
        state.hashing = match
          @snapshot.prepare_property(storage, state.limits) {
          Ok(hashing) => Some(hashing)
          Err(issue) =>
            return @bounded.Failed(GraphSnapshot(issue), progress, used + 1)
        }
        state.phase = CheckSnapshot
      }
      CheckSnapshot => {
        guard state.completed is Some(completed) &&
          state.hashing is Some(hashing) &&
          @graph.completed_available(completed) else {
          return @bounded.Failed(GraphInputUnavailable, progress, used)
        }
        let polled = match @snapshot.advance(hashing, remaining) {
          Ok(poll) => poll
          Err(issue) =>
            return @bounded.Failed(GraphSnapshot(issue), progress, used + 1)
        }
        // Verification drains into no persistent sink; these provisional bytes
        // are not a second serialization owner or a published snapshot.
        match @snapshot.take_property_output(hashing) {
          Ok(_) => ()
          Err(issue) =>
            return @bounded.Failed(GraphSnapshot(issue), progress, used + 1)
        }
        match polled {
          @snapshot.Continue(progress=made, work~) => {
            consumed = work.to_int()
            progress += made.to_int()
          }
          @snapshot.Complete(snapshot, progress=made, work~) => {
            consumed = work.to_int()
            progress += made.to_int()
            let matches = @snapshot.cid(snapshot) == state.expected_cid
            @snapshot.cleanup(snapshot) |> ignore
            state.hashing = None
            if !matches {
              return @bounded.Failed(
                GraphSnapshot(@snapshot.SnapshotIdentityMismatch),
                progress,
                used + consumed,
              )
            }
            state.completed = None
            state.header = None
            return @bounded.Complete(completed, progress, used + consumed)
          }
        }
      }
    }
    used += consumed
    if state.control_work_remaining is Some(remaining) {
      state.control_work_remaining = Some(remaining - consumed)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_property_snapshot_reload(
  control : @bounded.Control,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
  input : @decode.Cursor,
  expected_snapshot_cid : String,
  storage_limits : @graph_storage.Limits,
  snapshot_limits : @snapshot.Limits,
  storage_bytes : Int64,
  max_workspace_slots : Int,
  input_available : () -> Bool,
  available : () -> Bool,
  reference_issuer? : @value.ReferenceIssuer? = None,
  control_work_limit? : Int? = None,
) -> Result[RowsToGraphExecution, GraphBridgeIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(GraphControlWorkLimit)
  }
  if !input_available() {
    return Err(GraphInputUnavailable)
  }
  if expected_snapshot_cid.length() != 71 ||
    !expected_snapshot_cid.has_prefix("sha256:") ||
    !expected_snapshot_cid.to_array()[7:]
    .iter()
    .all(c => (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')) {
    return Err(GraphSnapshot(@snapshot.SnapshotIdentityMismatch))
  }
  guard @lifecycle.prepare_binding(owner, target) is Ok(binding) &&
    @lifecycle.binding_carrier(binding) is @carrier.GraphValue(graph) else {
    return Err(InvalidGraphKernel)
  }
  let profile = @carrier.graph_property_definition(graph)
  let header = match
    @snapshot.read_property_header(input, graph, snapshot_limits) {
    Ok(header) => header
    Err(issue) => return Err(GraphSnapshot(issue))
  }
  // Bound the widest private record's temporary decoded values; retained
  // material and snapshot sort have their existing separate owner ceilings.
  let mut width = 0
  for edge in [false, true] {
    let count = if edge {
      @carrier.property_graph_edge_count(profile)
    } else {
      @carrier.property_graph_node_count(profile)
    }
    for index in 0..<count {
      let definition = if edge {
        @carrier.property_edge_element(
          @carrier.property_graph_edge_at(profile, index).unwrap(),
        )
      } else {
        @carrier.property_graph_node_at(profile, index).unwrap()
      }
      let keys = @carrier.property_definition_key_count(definition)
      let fields = @carrier.field_count(
        @carrier.property_definition_properties(definition),
      )
      if max_workspace_slots < 16 ||
        keys > (max_workspace_slots - 16) / 2 ||
        fields > max_workspace_slots - 16 - keys * 2 {
        return Err(GraphWorkspaceLimit)
      }
      width = Int::max(width, keys * 2 + fields)
    }
  }
  if max_workspace_slots < 16 || width > max_workspace_slots - 16 {
    return Err(GraphWorkspaceLimit)
  }
  let output = match
    @graph.prepare_output(
      owner,
      target,
      @graph_storage.DeclaredNodes,
      storage_limits,
      storage_bytes,
      available,
    ) {
    Ok(output) => output
    Err(issue) => return Err(GraphSnapshotOutput(issue))
  }
  let state : PropertySnapshotState = {
    header: Some(header),
    limits: snapshot_limits,
    expected_cid: expected_snapshot_cid,
    input_available,
    reference_issuer,
    output: Some(output),
    completed: None,
    hashing: None,
    phase: ReloadNodes,
    index: 0,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    PropertySnapshotReload(state),
    graph_construction_step,
    cleanup_graph_construction_state,
    @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}
