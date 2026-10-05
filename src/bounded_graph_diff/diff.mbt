///|
pub(all) struct Limits {
  max_workspace_slots : Int
  max_output_nodes : Int
  max_output_text_bytes : Int
  max_output_depth : Int
  max_identity_bytes : Int
  max_identity_nodes : Int
  max_identity_depth : Int
  value_limits : @value.Limits
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidGraph
  InvalidDeltaContract
  InvalidDelta
  WrongBase
  BeforeMismatch
  TargetMismatch
  Storage(@storage.Issue)
  UnsupportedGraphOperation
  WorkspaceLimit
  OutputLimit
  Snapshot(@snapshot.Issue)
  Comparison(@value.CompleteEqualityIssue)
  Terminal
} derive(Eq, Debug)

///|
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(Delta, progress~ : Int64, work~ : Int64)
  Failed(Issue, progress~ : Int64, work~ : Int64)
}

///|
struct Delta {
  value : @value.CheckedValue
  base_cid : String
  target_cid : String
}

///|
priv enum DiffSource {
  Stored(@storage.Storage)
  Viewed(@lifecycle.ProducerView, @carrier.Graph)
}

///|
priv enum Phase {
  SnapshotLeft
  ReadLeftBody
  SnapshotRight
  ReadRightBody
  Nodes
  Edges
  Assemble
  ValidateOutput
  Finished
} derive(Eq)

///|
/// Snapshot framing, record emission and identity stay with the existing
/// snapshot owner. Delta contains their typed wire data, not reference rights.
/// The decoded immutable records are shared by action arrays, never repaired.
struct Preparation {
  right : DiffSource
  graph_contract_cid : String
  limits : Limits
  mut snapshot_preparation : @snapshot.Preparation?
  mut left_snapshot : @snapshot.Snapshot?
  mut right_snapshot : @snapshot.Snapshot?
  mut left_body : @value.Value?
  mut right_body : @value.Value?
  mut body_admission : BodyAdmission?
  chunks : Array[String]
  mut phase : Phase
  mut left_cursor : Int
  mut right_cursor : Int
  mut comparison : @value.CompleteEquality?
  mut comparison_recheck : @value.RecheckCursor?
  mut checked_before : @value.CheckedValue?
  mut checked_after : @value.CheckedValue?
  mut action : PendingAction?
  mut output_recheck : @value.RecheckCursor?
  mut node_add : @value.ArrayBuilder?
  mut node_remove : @value.ArrayBuilder?
  mut node_update : @value.ArrayBuilder?
  mut edge_add : @value.ArrayBuilder?
  mut edge_remove : @value.ArrayBuilder?
  mut edge_update : @value.ArrayBuilder?
  mut output_nodes : Int
  mut output_text : Int
}

///|
/// Admission and append are separate resumable steps. Failed admission leaves
/// the construction array unchanged, with all work charged in its actual poll.
priv struct PendingAction {
  item : @value.Value
  destination : @value.ArrayBuilder
  checker : @value.RecheckCursor
  mut usage : (Int, Int)?
}

///|
fn valid_limits(limits : Limits) -> Bool {
  limits.max_workspace_slots >= 0 &&
  limits.max_output_nodes >= 0 &&
  limits.max_output_text_bytes >= 0 &&
  limits.max_output_depth >= 0 &&
  limits.max_identity_bytes >= 0 &&
  limits.max_identity_nodes >= 0 &&
  limits.max_identity_depth >= 0 &&
  limits.value_limits.max_nodes >= 0 &&
  limits.value_limits.max_depth >= 0 &&
  limits.value_limits.max_text_bytes >= 0
}

///|
fn checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn source_graph(source : DiffSource) -> @carrier.Graph? {
  match source {
    Stored(storage) =>
      match @storage.carrier(storage) {
        @carrier.GraphValue(graph) => Some(graph)
        _ => None
      }
    Viewed(_, graph) => Some(graph)
  }
}

///|
fn source_counts(source : DiffSource) -> (Int, Int)? {
  match source {
    Stored(storage) =>
      Some((@storage.node_count(storage), @storage.edge_count(storage)))
    Viewed(view, _) =>
      match
        (
          @lifecycle.producer_view_node_count(view),
          @lifecycle.producer_view_edge_count(view),
        ) {
        (Some(nodes), Some(edges)) => Some((nodes, edges))
        _ => None
      }
  }
}

///|
fn snapshot_limits(limits : Limits) -> @snapshot.Limits {
  {
    max_workspace_slots: limits.max_workspace_slots,
    max_identity_bytes: limits.max_identity_bytes,
    max_identity_nodes: limits.max_identity_nodes,
    max_identity_depth: limits.max_identity_depth,
    value_limits: limits.value_limits,
  }
}

///|
fn source_workspace(source : DiffSource) -> Int? {
  match source {
    Stored(storage) => @snapshot.workspace_slots(storage)
    Viewed(view, graph) => @snapshot.workspace_slots_view(view, graph)
  }
}

///|
fn start_snapshot(
  source : DiffSource,
  limits : Limits,
) -> Result[@snapshot.Preparation, Issue] {
  let result = match source {
    Stored(storage) =>
      @snapshot.prepare_property(storage, snapshot_limits(limits))
    Viewed(view, graph) =>
      @snapshot.prepare_property_view(view, graph, snapshot_limits(limits))
  }
  result.map_err(issue => Snapshot(issue))
}

///|
fn delta_value(
  base : String,
  target : String,
  contract : String,
  nodes : @value.Value,
  edges : @value.Value,
  text_limit : Int,
) -> @value.Value? {
  guard @value.text_value("actql-graph-delta/0.1", text_limit) is Some(version) &&
    @value.text_value(base, text_limit) is Some(base) &&
    @value.text_value(target, text_limit) is Some(target) &&
    @value.text_value(contract, text_limit) is Some(contract) else {
    return None
  }
  @value.object_value([
    ("base_graph_cid", base),
    ("edges", edges),
    ("graph_contract_cid", contract),
    ("nodes", nodes),
    ("target_graph_cid", target),
    ("version", version),
  ])
}

///|
fn empty_actions() -> @value.Value? {
  @value.object_value([
    ("add", @value.array_value([])),
    ("remove", @value.array_value([])),
    ("update", @value.array_value([])),
  ])
}

///|
pub fn prepare(
  left : @storage.Storage,
  right : @storage.Storage,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(
    Stored(left),
    Stored(right),
    delta_contract,
    graph_contract_cid,
    limits,
  )
}

///|
pub fn prepare_view(
  left : @lifecycle.ProducerView,
  left_graph : @carrier.Graph,
  right : @lifecycle.ProducerView,
  right_graph : @carrier.Graph,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(
    Viewed(left, left_graph),
    Viewed(right, right_graph),
    delta_contract,
    graph_contract_cid,
    limits,
  )
}

///|
fn prepare_source(
  left : DiffSource,
  right : DiffSource,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  let caps : @graph_contract.Limits = {
    max_bytes: limits.max_identity_bytes,
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
  }
  guard source_graph(left) is Some(left_graph) &&
    source_graph(right) is Some(right_graph) &&
    @graph_contract.admit_graph(left_graph, caps) is Ok(left_contract) &&
    @graph_contract.admit_graph(right_graph, caps) is Ok(right_contract) &&
    @graph_contract.cid(left_contract) == graph_contract_cid &&
    @graph_contract.cid(right_contract) == graph_contract_cid else {
    return Err(InvalidGraph)
  }
  // The existing heterogeneous Delta field is ordinary JSON plus its checked
  // graph-contract expectation. Never issue a Number or nullable field as Delta.
  if delta_contract.nullable || !(delta_contract.shape is @contract.Json) {
    return Err(InvalidDeltaContract)
  }
  guard source_counts(left) is Some((left_nodes, left_edges)) &&
    source_counts(right) is Some((right_nodes, right_edges)) &&
    source_workspace(left) is Some(left_slots) &&
    source_workspace(right) is Some(right_slots) &&
    checked_add(left_nodes, right_nodes) is Some(node_capacity) &&
    checked_add(left_edges, right_edges) is Some(edge_capacity) &&
    checked_add(node_capacity, edge_capacity) is Some(action_capacity) &&
    checked_add(left_slots, right_slots) is Some(snapshot_slots) &&
    checked_add(action_capacity, action_capacity) is Some(twice_actions) &&
    checked_add(twice_actions, action_capacity) is Some(action_slots) &&
    body_workspace_slots(limits) is Some(body_slots) &&
    checked_add(body_slots, snapshot_slots) is Some(with_snapshots) &&
    checked_add(with_snapshots, action_slots) is Some(with_actions) &&
    checked_add(limits.max_output_depth.max(limits.value_limits.max_depth), 1)
    is Some(recheck_depth) &&
    checked_add(recheck_depth, recheck_depth) is Some(recheck_frames) &&
    checked_add(with_actions, recheck_frames) is Some(with_recheck) &&
    checked_add(with_recheck, 32) is Some(required) else {
    return Err(WorkspaceLimit)
  }
  // Both snapshot indexes, decoded bodies, six bounded action arrays and
  // framing state coexist. One resumable recheck is active at a time: each
  // nested container retains its continuation and one child frame. Immutable
  // checked records and pending append state retain references, not copies.
  // Input storage remains borrowed, not copied.
  if required > limits.max_workspace_slots {
    return Err(WorkspaceLimit)
  }
  let sample_cid = "sha256:" + "0".repeat(64)
  guard empty_actions() is Some(nodes) &&
    empty_actions() is Some(edges) &&
    delta_value(
      sample_cid,
      sample_cid,
      graph_contract_cid,
      nodes,
      edges,
      limits.max_output_text_bytes,
    )
    is Some(empty) &&
    @value.recheck_json_payload_usage(empty, {
      max_nodes: limits.max_output_nodes,
      max_depth: limits.max_output_depth,
      max_text_bytes: limits.max_output_text_bytes,
    })
    is Some((_, output_nodes, output_text)) else {
    return Err(OutputLimit)
  }
  guard @value.prepare_array_value(node_capacity) is Some(node_add) &&
    @value.prepare_array_value(node_capacity) is Some(node_remove) &&
    @value.prepare_array_value(node_capacity) is Some(node_update) &&
    @value.prepare_array_value(edge_capacity) is Some(edge_add) &&
    @value.prepare_array_value(edge_capacity) is Some(edge_remove) &&
    @value.prepare_array_value(edge_capacity) is Some(edge_update) else {
    return Err(WorkspaceLimit)
  }
  let snapshot_preparation = match start_snapshot(left, limits) {
    Ok(value) => Some(value)
    Err(issue) => return Err(issue)
  }
  Ok({
    right,
    graph_contract_cid,
    limits,
    snapshot_preparation,
    left_snapshot: None,
    right_snapshot: None,
    left_body: None,
    right_body: None,
    body_admission: None,
    chunks: [],
    phase: SnapshotLeft,
    left_cursor: 0,
    right_cursor: 0,
    comparison: None,
    comparison_recheck: None,
    checked_before: None,
    checked_after: None,
    action: None,
    output_recheck: None,
    node_add: Some(node_add),
    node_remove: Some(node_remove),
    node_update: Some(node_update),
    edge_add: Some(edge_add),
    edge_remove: Some(edge_remove),
    edge_update: Some(edge_update),
    output_nodes,
    output_text,
  })
}

///|
fn record(body : @value.Value?, index : Int, edge : Bool) -> @value.Value? {
  guard body is Some(@value.Array(parts)) &&
    @value.element_at(parts, if edge { 4 } else { 3 })
    is Some(@value.Array(records)) else {
    return None
  }
  @value.element_at(records, index)
}

///|
fn prepare_action(
  value : Preparation,
  item : @value.Value,
  array : @value.ArrayBuilder,
) -> PendingAction? {
  guard @value.start_json_payload_recheck(item, {
      max_nodes: value.limits.max_output_nodes - value.output_nodes,
      max_depth: value.limits.max_output_depth,
      max_text_bytes: value.limits.max_output_text_bytes - value.output_text,
    })
    is Some(checker) else {
    return None
  }
  Some({ item, destination: array, checker, usage: None, })
}

///|
fn finish_actions(
  add : @value.ArrayBuilder,
  remove : @value.ArrayBuilder,
  update : @value.ArrayBuilder,
) -> @value.Value? {
  guard @value.finish_bounded_array_value(add) is Some(add) &&
    @value.finish_bounded_array_value(remove) is Some(remove) &&
    @value.finish_bounded_array_value(update) is Some(update) else {
    return None
  }
  @value.object_value([("add", add), ("remove", remove), ("update", update)])
}

///|
fn failed(
  value : Preparation,
  issue : Issue,
  progress : Int64,
  work : Int64,
) -> Poll {
  value.phase = Finished
  Failed(issue, progress~, work~)
}

///|
pub fn advance(value : Preparation, quantum : Int) -> Result[Poll, Issue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if value.phase == Finished {
    return Err(Terminal)
  }
  let mut used = 0L
  let mut progress = 0L
  while used < quantum.to_int64() {
    if value.action is Some(action) {
      used += 1
      if action.usage is Some((nodes, text)) {
        if !@value.append_array_item(action.destination, action.item) {
          return Ok(failed(value, OutputLimit, progress, used))
        }
        value.output_nodes += nodes
        value.output_text += text
        value.action = None
        progress += 1
      } else {
        match @value.advance_recheck_runtime_value(action.checker) {
          @value.RecheckContinue => ()
          @value.RecheckComplete(_, nodes, text) =>
            action.usage = Some((nodes, text))
          @value.RecheckFailed =>
            return Ok(failed(value, OutputLimit, progress, used))
        }
      }
      continue
    }
    match value.phase {
      SnapshotLeft | SnapshotRight => {
        guard value.snapshot_preparation is Some(preparation) else {
          return Err(Terminal)
        }
        let poll = match
          @snapshot.advance(preparation, quantum - used.to_int()) {
          Ok(poll) => poll
          Err(issue) =>
            return Ok(failed(value, Snapshot(issue), progress, used))
        }
        match poll {
          @snapshot.Continue(progress=made, work~)
          | @snapshot.Complete(_, progress=made, work~) => {
            used += work
            progress += made
          }
        }
        // An output-drain failure still leaves this completed index owned by
        // preparation cleanup, and includes the child poll's reported work.
        if poll is @snapshot.Complete(snapshot, ..) {
          if value.phase == SnapshotLeft {
            value.left_snapshot = Some(snapshot)
          } else {
            value.right_snapshot = Some(snapshot)
          }
        }
        let chunk = match @snapshot.take_property_output(preparation) {
          Ok(chunk) => chunk
          Err(issue) =>
            return Ok(failed(value, Snapshot(issue), progress, used))
        }
        if !chunk.is_empty() {
          value.chunks.push(chunk)
        }
        match poll {
          @snapshot.Continue(..) => ()
          @snapshot.Complete(_, ..) => {
            value.snapshot_preparation = None
            value.body_admission = Some(start_body(value.chunks, value.limits))
            value.phase = if value.phase == SnapshotLeft {
              ReadLeftBody
            } else {
              ReadRightBody
            }
          }
        }
      }
      ReadLeftBody | ReadRightBody => {
        guard value.body_admission is Some(admission) else {
          return Err(Terminal)
        }
        match advance_body(admission, quantum - used.to_int()) {
          BodyContinue(work~) => used += work.to_int64()
          BodyFailed(issue, work~) =>
            return Ok(failed(value, issue, progress, used + work.to_int64()))
          BodyComplete(body, _, work~) => {
            used += work.to_int64()
            value.body_admission = None
            if value.phase == ReadLeftBody {
              value.left_body = @value.json_payload(body.value)
              value.snapshot_preparation = match
                start_snapshot(value.right, value.limits) {
                Ok(preparation) => Some(preparation)
                Err(issue) => return Ok(failed(value, issue, progress, used))
              }
              value.phase = SnapshotRight
            } else {
              value.right_body = @value.json_payload(body.value)
              value.phase = Nodes
            }
          }
        }
      }
      Nodes | Edges => {
        let edge = value.phase == Edges
        guard value.left_snapshot is Some(left) &&
          value.right_snapshot is Some(right) else {
          return Err(InvalidGraph)
        }
        let left_count = if edge {
          @snapshot.edge_count(left)
        } else {
          @snapshot.node_count(left)
        }
        let right_count = if edge {
          @snapshot.edge_count(right)
        } else {
          @snapshot.node_count(right)
        }
        let add = if edge {
          value.edge_add.unwrap()
        } else {
          value.node_add.unwrap()
        }
        let remove = if edge {
          value.edge_remove.unwrap()
        } else {
          value.node_remove.unwrap()
        }
        let update = if edge {
          value.edge_update.unwrap()
        } else {
          value.node_update.unwrap()
        }
        if value.left_cursor >= left_count && value.right_cursor >= right_count {
          value.left_cursor = 0
          value.right_cursor = 0
          value.phase = if edge { Assemble } else { Edges }
          continue
        }
        let left_record = record(value.left_body, value.left_cursor, edge)
        let right_record = record(value.right_body, value.right_cursor, edge)
        let ordering = if value.left_cursor >= left_count {
          1
        } else if value.right_cursor >= right_count {
          -1
        } else {
          let left_key = if edge {
            @snapshot.property_edge_key_at(left, value.left_cursor)
          } else {
            @snapshot.node_key_at(left, value.left_cursor)
          }
          let right_key = if edge {
            @snapshot.property_edge_key_at(right, value.right_cursor)
          } else {
            @snapshot.node_key_at(right, value.right_cursor)
          }
          guard left_key is Some(a) && right_key is Some(b) else {
            return Err(InvalidGraph)
          }
          @canonical.compare_utf16(a, b)
        }
        if ordering < 0 {
          guard left_record is Some(item) &&
            prepare_action(value, item, remove) is Some(action) else {
            return Ok(failed(value, OutputLimit, progress, used + 1))
          }
          value.action = Some(action)
          value.left_cursor += 1
          used += 1
        } else if ordering > 0 {
          guard right_record is Some(item) &&
            prepare_action(value, item, add) is Some(action) else {
            return Ok(failed(value, OutputLimit, progress, used + 1))
          }
          value.action = Some(action)
          value.right_cursor += 1
          used += 1
        } else {
          guard left_record is Some(before) && right_record is Some(after) else {
            return Err(InvalidGraph)
          }
          if value.checked_before is None || value.checked_after is None {
            let checking_before = value.checked_before is None
            let checker = match value.comparison_recheck {
              Some(checker) => checker
              None => {
                guard @value.start_json_payload_recheck(
                    if checking_before {
                      before
                    } else {
                      after
                    },
                    value.limits.value_limits,
                  )
                  is Some(checker) else {
                  return Ok(failed(value, OutputLimit, progress, used))
                }
                value.comparison_recheck = Some(checker)
                checker
              }
            }
            used += 1
            match @value.advance_recheck_runtime_value(checker) {
              @value.RecheckContinue => ()
              @value.RecheckComplete(checked, _, _) => {
                if checking_before {
                  value.checked_before = Some(checked)
                } else {
                  value.checked_after = Some(checked)
                }
                value.comparison_recheck = None
              }
              @value.RecheckFailed =>
                return Ok(failed(value, OutputLimit, progress, used))
            }
            continue
          }
          if value.comparison is None {
            value.comparison = match
              @value.start_complete_equality(
                value.checked_before.unwrap(),
                value.checked_after.unwrap(),
                value.limits.value_limits,
              ) {
              Ok(comparison) => Some(comparison)
              Err(issue) =>
                return Ok(failed(value, Comparison(issue), progress, used))
            }
            used += 1
            continue
          }
          let comparison = value.comparison.unwrap()
          match
            @value.advance_complete_equality(
              comparison,
              quantum - used.to_int(),
            ) {
            @value.EqualityContinue(work~) => used += work.to_int64()
            @value.EqualityComplete(equal~, work~) => {
              used += work.to_int64()
              value.comparison = None
              value.checked_before = None
              value.checked_after = None
              if !equal {
                guard @value.object_value([("after", after), ("before", before)])
                  is Some(item) &&
                  prepare_action(value, item, update) is Some(action) else {
                  return Ok(failed(value, OutputLimit, progress, used))
                }
                value.action = Some(action)
              } else {
                progress += 1
              }
              value.left_cursor += 1
              value.right_cursor += 1
            }
            @value.EqualityFailed(issue, work~) =>
              return Ok(
                failed(
                  value,
                  Comparison(issue),
                  progress,
                  used + work.to_int64(),
                ),
              )
          }
        }
      }
      Assemble => {
        guard value.left_snapshot is Some(left) &&
          value.right_snapshot is Some(right) &&
          finish_actions(
            value.node_add.unwrap(),
            value.node_remove.unwrap(),
            value.node_update.unwrap(),
          )
          is Some(nodes) &&
          finish_actions(
            value.edge_add.unwrap(),
            value.edge_remove.unwrap(),
            value.edge_update.unwrap(),
          )
          is Some(edges) &&
          delta_value(
            @snapshot.cid(left),
            @snapshot.cid(right),
            value.graph_contract_cid,
            nodes,
            edges,
            value.limits.max_output_text_bytes,
          )
          is Some(raw) &&
          @value.start_json_payload_recheck(raw, {
            max_nodes: value.limits.max_output_nodes,
            max_depth: value.limits.max_output_depth,
            max_text_bytes: value.limits.max_output_text_bytes,
          })
          is Some(checker) else {
          return Ok(failed(value, OutputLimit, progress, used + 1))
        }
        // Drop construction handles; the immutable Delta owns their frozen arrays.
        value.node_add = None
        value.node_remove = None
        value.node_update = None
        value.edge_add = None
        value.edge_remove = None
        value.edge_update = None
        value.output_recheck = Some(checker)
        value.phase = ValidateOutput
        used += 1
      }
      ValidateOutput => {
        guard value.output_recheck is Some(checker) &&
          value.left_snapshot is Some(left) &&
          value.right_snapshot is Some(right) else {
          return Err(Terminal)
        }
        used += 1
        match @value.advance_recheck_runtime_value(checker) {
          @value.RecheckContinue => ()
          @value.RecheckFailed =>
            return Ok(failed(value, OutputLimit, progress, used))
          @value.RecheckComplete(checked, nodes, text) => {
            value.output_recheck = None
            if nodes != value.output_nodes || text != value.output_text {
              return Ok(failed(value, OutputLimit, progress, used))
            }
            value.phase = Finished
            return Ok(
              Complete(
                {
                  value: checked,
                  base_cid: @snapshot.cid(left),
                  target_cid: @snapshot.cid(right),
                },
                progress=progress + 1,
                work=used,
              ),
            )
          }
        }
      }
      Finished => return Err(Terminal)
    }
  }
  Ok(Continue(progress~, work=used))
}

///|
pub fn value(delta : Delta) -> @value.CheckedValue {
  delta.value
}

///|
pub fn base_cid(delta : Delta) -> String {
  delta.base_cid
}

///|
pub fn target_cid(delta : Delta) -> String {
  delta.target_cid
}

///|
pub fn cleanup(value : Preparation) -> Bool {
  if value.snapshot_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    value.snapshot_preparation = None
  }
  if value.left_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    value.left_snapshot = None
  }
  if value.right_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    value.right_snapshot = None
  }
  value.chunks.clear()
  if value.body_admission is Some(admission) {
    cleanup_body(admission)
  }
  value.body_admission = None
  value.left_body = None
  value.right_body = None
  value.comparison = None
  for checker in [value.comparison_recheck, value.output_recheck] {
    if checker is Some(checker) {
      @value.cancel_recheck_runtime_value(checker)
    }
  }
  if value.action is Some(action) {
    @value.cancel_recheck_runtime_value(action.checker)
  }
  value.comparison_recheck = None
  value.checked_before = None
  value.checked_after = None
  value.action = None
  value.output_recheck = None
  for
    builder in [
      value.node_add,
      value.node_remove,
      value.node_update,
      value.edge_add,
      value.edge_remove,
      value.edge_update,
    ] {
    if builder is Some(builder) {
      @value.cancel_array_value(builder) |> ignore
    }
  }
  value.node_add = None
  value.node_remove = None
  value.node_update = None
  value.edge_add = None
  value.edge_remove = None
  value.edge_update = None
  value.phase = Finished
  true
}
