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
  BaseSnapshot
  ReadBaseBody
  ApplyNodes
  ApplyEdges
  TargetSnapshot
  ApplyFinished
} derive(Eq)

///|
/// One provisional builder from the existing Graph storage owner. No result is
/// transferred before both exact-base/before admission and target-CID checking.
struct ApplyPreparation {
  graph : @carrier.Graph
  limits : Limits
  storage_limits : @storage.Limits
  reference_issuer : @value.ReferenceIssuer?
  expected_base : String
  expected_target : String
  nodes : ActionSet
  edges : ActionSet
  mut snapshot_preparation : @snapshot.Preparation?
  mut base_snapshot : @snapshot.Snapshot?
  mut base_body : @value.Value?
  mut body_admission : BodyAdmission?
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
fn delta_record_key(
  cursor : @decode.Cursor,
  edge : Bool,
  limits : Limits,
) -> String? {
  let names = if edge {
    ["dst", "id", "key", "props", "src"]
  } else {
    ["id", "key", "props"]
  }
  guard delta_object(cursor, names) is Some(object) &&
    @decode.lookup(object, "id") is Some(identity) &&
    @value.admit(json_contract(), identity, limits.value_limits) is Ok(id) else {
    return None
  }
  try {
    let writer = @encode.writer(
      limits.max_identity_bytes,
      limits.max_identity_nodes,
      limits.max_identity_depth,
    )
    @encode.begin_array(writer)
    @value.emit_checked_wire_value(id, writer)
    @encode.end_array(writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
/// Arrays are already ordered by the contract. One namespace per entity kind
/// rejects repeated identities across actions, including add/remove pairs.
fn read_actions(
  cursor : @decode.Cursor,
  edge : Bool,
  limits : Limits,
) -> ActionSet? {
  guard delta_object(cursor, ["add", "remove", "update"]) is Some(object) else {
    return None
  }
  let result : ActionSet = { add: [], remove: [], update: [], }
  let seen : Map[String, Bool] = Map([])
  let mut remaining_text = limits.max_identity_bytes
  for name in ["add", "remove", "update"] {
    guard @decode.lookup(object, name) is Some(array) &&
      @decode.array_length(array) is Some(count) else {
      return None
    }
    let values = if name == "add" {
      result.add
    } else if name == "remove" {
      result.remove
    } else {
      result.update
    }
    let mut previous = None
    for i in 0..<count {
      let item = @decode.element_at(array, i).unwrap()
      let action = if name == "update" {
        guard delta_object(item, ["before", "after"]) is Some(update) &&
          @decode.lookup(update, "before") is Some(before) &&
          @decode.lookup(update, "after") is Some(after) &&
          delta_record_key(before, edge, limits) is Some(key) &&
          delta_record_key(after, edge, limits) == Some(key) else {
          return None
        }
        { key, before: Some(before), after: Some(after), }
      } else {
        guard delta_record_key(item, edge, limits) is Some(key) else {
          return None
        }
        {
          key,
          before: if name == "remove" {
            Some(item)
          } else {
            None
          },
          after: if name == "add" {
            Some(item)
          } else {
            None
          },
        }
      }
      if seen.contains(action.key) ||
        (
          previous is Some(old) &&
          @canonical.compare_utf16(old, action.key) >= 0
        ) {
        return None
      }
      guard @scalar.admit_utf8_length(action.key, remaining_text) is Ok(bytes) else {
        return None
      }
      remaining_text -= bytes
      seen[action.key] = true
      previous = Some(action.key)
      values.push(action)
    }
  }
  Some(result)
}

///|
pub fn prepare_apply(
  base : @storage.Storage,
  delta : @decode.Cursor,
  limits : Limits,
  storage_limits : @storage.Limits,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[ApplyPreparation, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  guard source_graph(Stored(base)) is Some(graph) &&
    @graph_contract.admit_graph(graph, {
      max_bytes: limits.max_identity_bytes,
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
    })
    is Ok(contract) else {
    return Err(InvalidGraph)
  }
  let usage = @decode.admission_usage(delta)
  if usage.nodes > limits.max_output_nodes ||
    usage.depth > limits.max_output_depth ||
    usage.total_string_bytes > limits.max_output_text_bytes {
    return Err(OutputLimit)
  }
  // Decoded Delta retention, action/key indexes, base snapshot/decoded framing,
  // and the existing provisional Storage all remain in the resolved budget.
  guard checked_add(usage.nodes, usage.nodes) is Some(twice_delta) &&
    checked_add(twice_delta, twice_delta) is Some(action_slots) &&
    source_workspace(Stored(base)) is Some(snapshot_slots) &&
    body_workspace_slots(limits) is Some(body_slots) &&
    checked_add(action_slots, snapshot_slots) is Some(with_snapshot) &&
    checked_add(with_snapshot, body_slots) is Some(with_body) &&
    checked_add(with_body, storage_limits.max_workspace_slots)
    is Some(with_storage) &&
    checked_add(with_storage, 16) is Some(required) &&
    required <= limits.max_workspace_slots else {
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
    read_actions(nodes_cursor, false, limits) is Some(nodes) &&
    read_actions(edges_cursor, true, limits) is Some(edges) else {
    return Err(InvalidDelta)
  }
  let preparation = match start_snapshot(Stored(base), limits) {
    Ok(preparation) => preparation
    Err(issue) => return Err(issue)
  }
  Ok({
    graph,
    limits,
    storage_limits,
    reference_issuer,
    expected_base,
    expected_target,
    nodes,
    edges,
    snapshot_preparation: Some(preparation),
    base_snapshot: None,
    base_body: None,
    body_admission: None,
    chunks: [],
    builder: None,
    result: None,
    phase: BaseSnapshot,
    base_cursor: 0,
    add_cursor: 0,
    remove_cursor: 0,
    update_cursor: 0,
  })
}

///|
fn wire_record(value : @value.Value, limits : Limits) -> String? {
  try {
    let writer = @encode.writer(
      limits.max_identity_bytes,
      limits.max_identity_nodes,
      limits.max_identity_depth,
    )
    @value.emit_wire_value(value, writer)
    Some(@encode.finish(writer))
  } catch {
    _ => None
  }
}

///|
fn record_cursor(value : @value.Value, limits : Limits) -> @decode.Cursor? {
  guard wire_record(value, limits) is Some(text) &&
    @source.parse_json(text, {
      max_input_bytes: limits.max_identity_bytes,
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
    })
    is Ok(source) else {
    return None
  }
  @decode.admit(source, {
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
    max_string_bytes: limits.max_identity_bytes,
    max_total_string_bytes: limits.max_identity_bytes,
  }).to_option()
}

///|
fn exact_before(
  before : @decode.Cursor,
  actual : @value.Value,
  limits : Limits,
) -> Bool {
  guard @value.admit(json_contract(), before, {
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
      max_text_bytes: limits.max_identity_bytes,
    })
    is Ok(before) &&
    wire_record(before.value, limits) is Some(before) &&
    wire_record(actual, limits) is Some(actual) else {
    return false
  }
  before == actual
}

///|
fn append_apply_record(
  value : ApplyPreparation,
  cursor : @decode.Cursor,
  edge : Bool,
) -> (Result[Unit, Issue], Int64) {
  guard value.builder is Some(builder) else { return (Err(Terminal), 0L) }
  let before = @storage.builder_construction_work(builder)
  let result = if edge {
    @storage.append_property_snapshot_edge(
      builder,
      cursor,
      reference_issuer=value.reference_issuer,
    )
  } else {
    @storage.append_property_snapshot_node(
      builder,
      cursor,
      reference_issuer=value.reference_issuer,
    )
  }
  let work = @storage.builder_construction_work(builder) - before
  // A failed admission can already have charged the existing builder. Return
  // its delta independently of success; the parent reports it exactly once.
  (result.map_err(issue => Storage(issue)), work.to_int64())
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
  let mut used = 0L
  let mut progress = 0L
  while used < quantum.to_int64() {
    match value.phase {
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
              value.result = None
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
          BodyComplete(body, work~) => {
            used += work.to_int64()
            value.body_admission = None
            value.base_body = Some(body.value)
            value.builder = match
              @storage.prepare(
                @carrier.graph_carrier(value.graph),
                DeclaredNodes,
                value.storage_limits,
              ) {
              Ok(builder) => Some(builder)
              Err(issue) =>
                return Ok(apply_failure(value, Storage(issue), used, progress))
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
        let output : @decode.Cursor? = if order < 0 {
          guard actual is Some(actual) &&
            record_cursor(actual, value.limits) is Some(cursor) else {
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
            guard action.before is Some(before) &&
              actual is Some(actual) &&
              exact_before(before, actual, value.limits) else {
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
        if output is Some(cursor) {
          let (result, work) = append_apply_record(value, cursor, edge)
          used += work + @decode.admission_usage(cursor).nodes.to_int64() * 3
          if result is Err(issue) {
            return Ok(apply_failure(value, issue, used, progress))
          }
        } else {
          used += 1
        }
        progress += 1
      }
      ApplyFinished => return Err(Terminal)
    }
  }
  Ok(ApplyContinue(progress~, work=used))
}

///|
pub fn cleanup_apply(value : ApplyPreparation) -> Bool {
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
  value.result = None
  value.base_body = None
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
