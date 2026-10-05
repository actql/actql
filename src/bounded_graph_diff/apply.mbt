///|
priv struct DeltaAction {
  key : String
  before : @decode.Cursor?
  after : @decode.Cursor?
}

///|
priv struct ActionSet {
  add : Array[DeltaAction]
  remove : Array[DeltaAction]
  update : Array[DeltaAction]
}

///|
priv enum ApplyPhase {
  AdmitNodeActions
  AdmitEdgeActions
  BaseSnapshot
  ReadBaseBody
  ApplyNodes
  ApplyEdges
  ValidateBefore
  AppendRecord
  TargetSnapshot
  ApplyFinished
} derive(Eq)

///|
/// One provisional builder from the existing Graph storage owner. No result is
/// transferred before both exact-base/before admission and target-CID checking.
struct ApplyPreparation {
  mut base_view : @lifecycle.ProducerView?
  graph : @carrier.Graph
  limits : Limits
  storage_limits : @storage.Limits
  reference_issuer : @value.ReferenceIssuer?
  expected_base : String
  expected_target : String
  nodes : ActionSet
  edges : ActionSet
  mut node_admission : ActionAdmission?
  mut edge_admission : ActionAdmission?
  mut snapshot_preparation : @snapshot.Preparation?
  mut base_snapshot : @snapshot.Snapshot?
  mut base_body : @value.Value?
  mut base_decoded : @decode.Cursor?
  mut body_admission : BodyAdmission?
  mut before_admission : BeforeAdmission?
  mut record_append : @storage.PropertySnapshotAppend?
  mut pending_output : @decode.Cursor?
  mut pending_edge : Bool
  chunks : Array[String]
  mut builder : @storage.Builder?
  mut result : @storage.Storage?
  mut phase : ApplyPhase
  mut base_cursor : Int
  mut add_cursor : Int
  mut remove_cursor : Int
  mut update_cursor : Int
}

///|
fn delta_object(
  cursor : @decode.Cursor,
  names : Array[String],
) -> @decode.ObjectView? {
  if @decode.object_length(cursor) != Some(names.length()) {
    return None
  }
  @decode.closed_object(cursor, names).to_option()
}

///|
fn delta_cid(cursor : @decode.Cursor) -> String? {
  guard @decode.text(cursor) is Ok(cid) &&
    cid.has_prefix("sha256:") &&
    cid.length() == 71 else {
    return None
  }
  for c in cid.to_array()[7:] {
    if !(c >= '0' && c <= '9') && !(c >= 'a' && c <= 'f') {
      return None
    }
  }
  Some(cid)
}

///|
fn complete_action_admission(value : ActionAdmission) -> Bool {
  while true {
    match advance_actions(value, 64) {
      ActionsContinue(..) => ()
      ActionsComplete(..) => {
        cleanup_actions(value)
        return true
      }
      ActionsFailed(..) => {
        cleanup_actions(value)
        return false
      }
    }
  } nobreak {
    false
  }
}

///|
pub fn prepare_apply(
  base : @storage.Storage,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer? : @value.ReferenceIssuer? = None,
  output_builder? : @storage.Builder? = None,
) -> Result[ApplyPreparation, Issue] {
  prepare_apply_source(
    Stored(base),
    delta,
    limits,
    storage_limits,
    reference_issuer~,
    output_builder~,
    defer_actions=false,
  )
}

///|
/// Borrow the exact managed producer occurrence through the existing snapshot
/// owner. The expected Graph cannot relabel the view or confer availability.
pub fn prepare_apply_view(
  base : @lifecycle.ProducerView,
  graph : @carrier.Graph,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer? : @value.ReferenceIssuer? = None,
  output_builder? : @storage.Builder? = None,
) -> Result[ApplyPreparation, Issue] {
  prepare_apply_source(
    Viewed(base, graph),
    delta,
    limits,
    storage_limits,
    reference_issuer~,
    output_builder~,
    defer_actions=false,
  )
}

///|
/// Start the same application with action admission charged by advance_apply.
/// The envelope, declared configuration and workspace are checked before start;
/// action order, identity equality and duplicate rejection remain resumable.
pub fn start_apply(
  base : @storage.Storage,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer? : @value.ReferenceIssuer? = None,
  output_builder? : @storage.Builder? = None,
) -> Result[ApplyPreparation, Issue] {
  prepare_apply_source(
    Stored(base),
    delta,
    limits,
    storage_limits,
    reference_issuer~,
    output_builder~,
    defer_actions=true,
  )
}

///|
/// Resumable action admission from the exact managed Graph view. The caller
/// must still bind and admit the Delta Relation occurrence before supplying its
/// immutable cursor; this entry does not confer authority on unbound JSON.
pub fn start_apply_view(
  base : @lifecycle.ProducerView,
  graph : @carrier.Graph,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer? : @value.ReferenceIssuer? = None,
  output_builder? : @storage.Builder? = None,
) -> Result[ApplyPreparation, Issue] {
  prepare_apply_source(
    Viewed(base, graph),
    delta,
    limits,
    storage_limits,
    reference_issuer~,
    output_builder~,
    defer_actions=true,
  )
}

///|
fn prepare_apply_source(
  base : DiffSource,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer~ : @value.ReferenceIssuer?,
  output_builder~ : @storage.Builder?,
  defer_actions~ : Bool,
  admitted_base? : ApplyBasePreparation? = None,
) -> Result[ApplyPreparation, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let (graph, contract) = match admitted_base {
    Some(admitted) => (admitted.graph, admitted.contract)
    None => {
      guard source_graph(base) is Some(graph) &&
        @graph_contract.admit_graph(graph, {
          max_bytes: limits.max_identity_bytes,
          max_nodes: limits.max_identity_nodes,
          max_depth: limits.max_identity_depth,
        })
        is Ok(contract) else {
        return Err(InvalidGraph)
      }
      (graph, contract)
    }
  }
  // The output owner and kernel share a single provisional builder. Equal
  // schemas or finished payload CIDs cannot substitute a different builder.
  if output_builder is Some(builder) &&
    !@storage.builder_accepts_output(builder, graph, storage_limits) {
    return Err(Storage(@storage.WrongCarrier))
  }
  let usage = @decode.admission_usage(delta)
  if usage.nodes > limits.max_output_nodes ||
    usage.depth > limits.max_output_depth ||
    usage.total_string_bytes > limits.max_output_text_bytes {
    return Err(OutputLimit)
  }
  // Decoded Delta retention, action/key indexes, base snapshot/decoded framing,
  // the existing provisional Storage, and its staged record preparation all
  // remain in the same resolved budget. No second workspace owner is created.
  guard checked_add(usage.nodes, usage.nodes) is Some(twice_delta) &&
    checked_add(twice_delta, twice_delta) is Some(action_slots) &&
    (match admitted_base {
      Some(admitted) => Some(admitted.workspace)
      None => fixed_apply_workspace(base, graph, limits, storage_limits)
    })
    is Some(fixed_slots) &&
    checked_add(action_slots, fixed_slots) is Some(with_actions) &&
    with_actions <= limits.max_workspace_slots else {
    return Err(WorkspaceLimit)
  }
  guard delta_object(delta, [
      "version", "base_graph_cid", "target_graph_cid", "graph_contract_cid", "nodes",
      "edges",
    ])
    is Some(object) &&
    @decode.lookup(object, "version").map(@decode.text) ==
    Some(Ok("actql-graph-delta/0.1")) &&
    @decode.lookup(object, "base_graph_cid").bind(delta_cid)
    is Some(expected_base) &&
    @decode.lookup(object, "target_graph_cid").bind(delta_cid)
    is Some(expected_target) &&
    @decode.lookup(object, "graph_contract_cid").bind(delta_cid) ==
    Some(@graph_contract.cid(contract)) &&
    @decode.lookup(object, "nodes") is Some(nodes_cursor) &&
    @decode.lookup(object, "edges") is Some(edges_cursor) &&
    start_actions(nodes_cursor, false, limits) is Some(node_admission) &&
    start_actions(edges_cursor, true, limits) is Some(edge_admission) else {
    return Err(InvalidDelta)
  }
  if !defer_actions &&
    (
      !complete_action_admission(node_admission) ||
      !complete_action_admission(edge_admission)
    ) {
    cleanup_actions(node_admission)
    cleanup_actions(edge_admission)
    return Err(InvalidDelta)
  }
  let preparation = match admitted_base {
    Some(admitted) => {
      guard admitted.snapshot is Some(preparation) else { return Err(Terminal) }
      admitted.snapshot = None
      admitted.source = None
      admitted.output_builder = None
      preparation
    }
    None =>
      match start_snapshot(base, limits) {
        Ok(preparation) => preparation
        Err(issue) => return Err(issue)
      }
  }
  Ok({
    base_view: match base {
      Stored(_) => None
      Viewed(view, _) => Some(view)
    },
    graph,
    limits,
    storage_limits,
    reference_issuer,
    expected_base,
    expected_target,
    nodes: node_admission.result,
    edges: edge_admission.result,
    node_admission: if defer_actions {
      Some(node_admission)
    } else {
      None
    },
    edge_admission: if defer_actions {
      Some(edge_admission)
    } else {
      None
    },
    snapshot_preparation: Some(preparation),
    base_snapshot: None,
    base_body: None,
    base_decoded: None,
    body_admission: None,
    before_admission: None,
    record_append: None,
    pending_output: None,
    pending_edge: false,
    chunks: [],
    builder: output_builder,
    result: None,
    phase: if defer_actions {
      AdmitNodeActions
    } else {
      BaseSnapshot
    },
    base_cursor: 0,
    add_cursor: 0,
    remove_cursor: 0,
    update_cursor: 0,
  })
}

///|
fn decoded_record(
  body : @decode.Cursor?,
  index : Int,
  edge : Bool,
) -> @decode.Cursor? {
  guard body is Some(body) &&
    @decode.element_at(body, if edge { 4 } else { 3 }) is Some(records) else {
    return None
  }
  @decode.element_at(records, index)
}

///|
fn apply_failure(
  value : ApplyPreparation,
  issue : Issue,
  work : Int64,
  progress : Int64,
) -> ApplyPoll {
  value.phase = ApplyFinished
  ApplyFailed(issue, progress~, work~)
}

///|
pub enum ApplyPoll {
  ApplyContinue(progress~ : Int64, work~ : Int64)
  ApplyComplete(@storage.Storage, progress~ : Int64, work~ : Int64)
  ApplyFailed(Issue, progress~ : Int64, work~ : Int64)
}

///|
/// Bind the prepared kernel to the caller's one provisional output. This is
/// valid only before execution; it conveys no right to substitute operands.
pub fn apply_uses_output_builder(
  value : ApplyPreparation,
  builder : @storage.Builder,
) -> Bool {
  (value.phase == AdmitNodeActions || value.phase == BaseSnapshot) &&
  value.builder is Some(actual) &&
  physical_equal(actual, builder) &&
  @storage.builder_accepts_output(builder, value.graph, value.storage_limits)
}

///|
pub fn advance_apply(
  value : ApplyPreparation,
  quantum : Int,
) -> Result[ApplyPoll, Issue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if value.phase == ApplyFinished {
    return Err(Terminal)
  }
  // Snapshot bytes are not a replacement for the current read occurrence.
  // Revocation after base capture still prevents publication of the target.
  let mut used = 0L
  let mut progress = 0L
  while used < quantum.to_int64() {
    if value.base_view is Some(view) &&
      !@lifecycle.producer_read_reference_available(
        @lifecycle.producer_view_read_reference(view),
      ) {
      return Ok(
        apply_failure(value, Snapshot(@snapshot.InvalidGraph), used, progress),
      )
    }
    match value.phase {
      AdmitNodeActions | AdmitEdgeActions => {
        let admission = if value.phase == AdmitNodeActions {
          value.node_admission
        } else {
          value.edge_admission
        }
        guard admission is Some(admission) else { return Err(Terminal) }
        match advance_actions(admission, quantum - used.to_int()) {
          ActionsContinue(work~) => used += work.to_int64()
          ActionsFailed(work~) =>
            return Ok(
              apply_failure(
                value,
                InvalidDelta,
                used + work.to_int64(),
                progress,
              ),
            )
          ActionsComplete(work~) => {
            used += work.to_int64()
            cleanup_actions(admission)
            if value.phase == AdmitNodeActions {
              value.node_admission = None
              value.phase = AdmitEdgeActions
            } else {
              value.edge_admission = None
              value.phase = BaseSnapshot
            }
          }
        }
      }
      BaseSnapshot | TargetSnapshot => {
        guard value.snapshot_preparation is Some(preparation) else {
          return Err(Terminal)
        }
        let poll = match
          @snapshot.advance(preparation, quantum - used.to_int()) {
          Ok(poll) => poll
          Err(issue) =>
            return Ok(apply_failure(value, Snapshot(issue), used, progress))
        }
        match poll {
          @snapshot.Continue(progress=made, work~)
          | @snapshot.Complete(_, progress=made, work~) => {
            used += work
            progress += made
          }
        }
        // Retain a completed base index before draining. A transport/writer
        // failure must not lose either its custody or the work already done.
        if value.phase == BaseSnapshot &&
          poll is @snapshot.Complete(snapshot, ..) {
          value.base_snapshot = Some(snapshot)
        }
        let chunk = match @snapshot.take_property_output(preparation) {
          Ok(chunk) => chunk
          Err(issue) => {
            if value.phase == TargetSnapshot &&
              poll is @snapshot.Complete(snapshot, ..) {
              @snapshot.cleanup(snapshot) |> ignore
            }
            return Ok(apply_failure(value, Snapshot(issue), used, progress))
          }
        }
        if value.phase == BaseSnapshot {
          if !chunk.is_empty() {
            value.chunks.push(chunk)
          }
        }
        match poll {
          @snapshot.Continue(..) => ()
          @snapshot.Complete(snapshot, ..) => {
            value.snapshot_preparation = None
            if value.phase == TargetSnapshot {
              let valid = @snapshot.cid(snapshot) == value.expected_target
              @snapshot.cleanup(snapshot) |> ignore
              if !valid {
                return Ok(apply_failure(value, TargetMismatch, used, progress))
              }
              guard value.result is Some(result) else { return Err(Terminal) }
              if value.base_view is Some(view) &&
                !@lifecycle.producer_read_reference_available(
                  @lifecycle.producer_view_read_reference(view),
                ) {
                return Ok(
                  apply_failure(
                    value,
                    Snapshot(@snapshot.InvalidGraph),
                    used,
                    progress,
                  ),
                )
              }
              value.result = None
              value.base_view = None
              value.phase = ApplyFinished
              return Ok(ApplyComplete(result, progress~, work=used))
            }
            if @snapshot.cid(snapshot) != value.expected_base {
              return Ok(apply_failure(value, WrongBase, used, progress))
            }
            value.body_admission = Some(start_body(value.chunks, value.limits))
            value.phase = ReadBaseBody
          }
        }
      }
      ReadBaseBody => {
        guard value.body_admission is Some(admission) else {
          return Err(Terminal)
        }
        match advance_body(admission, quantum - used.to_int()) {
          BodyContinue(work~) => used += work.to_int64()
          BodyFailed(issue, work~) =>
            return Ok(
              apply_failure(value, issue, used + work.to_int64(), progress),
            )
          BodyComplete(body, decoded, work~) => {
            used += work.to_int64()
            value.body_admission = None
            value.base_body = Some(body.value)
            value.base_decoded = Some(decoded)
            if value.builder is None {
              value.builder = match
                @storage.prepare(
                  @carrier.graph_carrier(value.graph),
                  DeclaredNodes,
                  value.storage_limits,
                ) {
                Ok(builder) => Some(builder)
                Err(issue) =>
                  return Ok(
                    apply_failure(value, Storage(issue), used, progress),
                  )
              }
            } else if !@storage.builder_accepts_output(
                value.builder.unwrap(),
                value.graph,
                value.storage_limits,
              ) {
              return Ok(
                apply_failure(
                  value,
                  Storage(@storage.WrongCarrier),
                  used,
                  progress,
                ),
              )
            }
            value.phase = ApplyNodes
          }
        }
      }
      ApplyNodes | ApplyEdges => {
        let edge = value.phase == ApplyEdges
        let actions = if edge { value.edges } else { value.nodes }
        guard value.base_snapshot is Some(snapshot) else {
          return Err(InvalidGraph)
        }
        let base_count = if edge {
          @snapshot.edge_count(snapshot)
        } else {
          @snapshot.node_count(snapshot)
        }
        let mut selected : (Int, DeltaAction)? = None
        for
          (kind, action) in [
            (0, actions.add.get(value.add_cursor)),
            (1, actions.remove.get(value.remove_cursor)),
            (2, actions.update.get(value.update_cursor)),
          ] {
          if action is Some(action) &&
            (
              selected is None ||
              @canonical.compare_utf16(action.key, selected.unwrap().1.key) < 0
            ) {
            selected = Some((kind, action))
          }
        }
        if value.base_cursor >= base_count && selected is None {
          if !edge {
            value.phase = ApplyEdges
            value.base_cursor = 0
            value.add_cursor = 0
            value.remove_cursor = 0
            value.update_cursor = 0
            continue
          }
          guard value.builder is Some(builder) else { return Err(Terminal) }
          let result = match @storage.finish(builder) {
            Ok(result) => result
            Err(issue) =>
              return Ok(apply_failure(value, Storage(issue), used, progress))
          }
          value.builder = None
          value.result = Some(result)
          value.snapshot_preparation = match
            start_snapshot(Stored(result), value.limits) {
            Ok(preparation) => Some(preparation)
            Err(issue) => return Ok(apply_failure(value, issue, used, progress))
          }
          value.phase = TargetSnapshot
          continue
        }
        let base_key = if edge {
          @snapshot.property_edge_key_at(snapshot, value.base_cursor)
        } else {
          @snapshot.node_key_at(snapshot, value.base_cursor)
        }
        let actual = record(value.base_body, value.base_cursor, edge)
        let order = if value.base_cursor >= base_count {
          1
        } else if selected is None {
          -1
        } else {
          guard base_key is Some(key) else { return Err(InvalidGraph) }
          @canonical.compare_utf16(key, selected.unwrap().1.key)
        }
        value.pending_edge = edge
        value.pending_output = if order < 0 {
          guard actual is Some(_) &&
            decoded_record(value.base_decoded, value.base_cursor, edge)
            is Some(cursor) else {
            return Ok(apply_failure(value, InvalidGraph, used, progress))
          }
          value.base_cursor += 1
          Some(cursor)
        } else {
          guard selected is Some((kind, action)) else {
            return Err(InvalidDelta)
          }
          if order > 0 {
            if kind != 0 {
              return Ok(apply_failure(value, BeforeMismatch, used, progress))
            }
          } else {
            if kind == 0 {
              return Ok(apply_failure(value, BeforeMismatch, used, progress))
            }
            guard action.before is Some(before) && actual is Some(actual) else {
              return Ok(apply_failure(value, BeforeMismatch, used, progress))
            }
            value.before_admission = match
              start_before(before, actual, value.limits) {
              Some(admission) => Some(admission)
              None =>
                return Ok(apply_failure(value, BeforeMismatch, used, progress))
            }
            value.base_cursor += 1
          }
          if kind == 0 {
            value.add_cursor += 1
          } else if kind == 1 {
            value.remove_cursor += 1
          } else {
            value.update_cursor += 1
          }
          action.after
        }
        value.phase = if value.before_admission is Some(_) {
          ValidateBefore
        } else {
          AppendRecord
        }
        used += 1
      }
      ValidateBefore => {
        guard value.before_admission is Some(admission) else {
          return Err(Terminal)
        }
        match advance_before(admission, quantum - used.to_int()) {
          BeforeContinue(work~) => used += work.to_int64()
          BeforeComplete(work~) => {
            used += work.to_int64()
            cleanup_before(admission)
            value.before_admission = None
            value.phase = AppendRecord
          }
          BeforeFailed(issue, work~) =>
            return Ok(
              apply_failure(value, issue, used + work.to_int64(), progress),
            )
        }
      }
      AppendRecord =>
        if value.record_append is Some(append) {
          match
            @storage.advance_property_snapshot_append(
              append,
              quantum - used.to_int(),
            ) {
            @storage.PropertySnapshotAppendContinue(work~) =>
              used += work.to_int64()
            @storage.PropertySnapshotAppendFailed(issue, work~) =>
              return Ok(
                apply_failure(
                  value,
                  Storage(issue),
                  used + work.to_int64(),
                  progress,
                ),
              )
            @storage.PropertySnapshotAppendComplete(work~) => {
              used += work.to_int64()
              @storage.cleanup_property_snapshot_append(append)
              value.record_append = None
              value.pending_output = None
              value.phase = if value.pending_edge {
                ApplyEdges
              } else {
                ApplyNodes
              }
              progress += 1
            }
          }
        } else if value.pending_output is Some(cursor) {
          used += 1
          match
            @storage.start_property_snapshot_append(
              value.builder.unwrap(),
              cursor,
              edge=value.pending_edge,
              reference_issuer=value.reference_issuer,
            ) {
            Ok(append) => value.record_append = Some(append)
            Err(issue) =>
              return Ok(apply_failure(value, Storage(issue), used, progress))
          }
        } else {
          used += 1
          value.phase = if value.pending_edge { ApplyEdges } else { ApplyNodes }
          progress += 1
        }
      ApplyFinished => return Err(Terminal)
    }
  }
  Ok(ApplyContinue(progress~, work=used))
}

///|
pub fn cleanup_apply(value : ApplyPreparation) -> Bool {
  value.base_view = None
  if value.node_admission is Some(admission) {
    cleanup_actions(admission)
  }
  if value.edge_admission is Some(admission) {
    cleanup_actions(admission)
  }
  value.node_admission = None
  value.edge_admission = None
  if value.record_append is Some(append) {
    @storage.cleanup_property_snapshot_append(append)
    value.record_append = None
  }
  if value.snapshot_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    value.snapshot_preparation = None
  }
  if value.base_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    value.base_snapshot = None
  }
  if value.builder is Some(builder) {
    @storage.cancel(builder) |> ignore
    value.builder = None
  }
  if value.result is Some(result) {
    @storage.discard(result)
    value.result = None
  }
  value.base_body = None
  value.base_decoded = None
  value.pending_output = None
  if value.before_admission is Some(admission) {
    cleanup_before(admission)
  }
  value.before_admission = None
  value.chunks.clear()
  if value.body_admission is Some(admission) {
    cleanup_body(admission)
  }
  value.body_admission = None
  value.nodes.add.clear()
  value.nodes.remove.clear()
  value.nodes.update.clear()
  value.edges.add.clear()
  value.edges.remove.clear()
  value.edges.update.clear()
  value.phase = ApplyFinished
  true
}
