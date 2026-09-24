///|
priv enum MatchNodesPhase {
  InitializeScratch
  ResolveIdentities
  PreparePredicate
  EvaluatePredicate
  PrepareSort
  PrepareMerge
  Merge
  CompareMerge
  CopyPass
  BeginEmit
  CompareDuplicate
  ReadField
  CommitRow
  Finish
}

///|
priv struct MatchNodesState {
  input : @graph.ProducerRead
  source : @storage.Storage
  graph : @carrier.Graph
  prepared : @lower.PreparedGraphMatch
  schema : @schema.Schema
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : MatchNodesPhase
  mut identity_index : Int
  select_all_nodes : Bool?
  predicate : @lower.Expression?
  mut predicate_field : Int
  predicate_fields : Int
  predicate_workspace : Int
  mut predicate_work_remaining : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut selected : Array[Int]
  mut scratch : Array[Int?]
  scratch_count : Int
  scratch_slots : Ref[Int]
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left_index : Int
  mut right_index : Int
  mut merge_index : Int
  mut copy_index : Int
  mut emit_index : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut control_work_remaining : Int
}

///|
struct MatchNodesExecution {
  session : @bounded.Session[
    MatchNodesState,
    @execution.CompletedOutput,
    MatchNodesIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  scratch_slots : Ref[Int]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum MatchNodesPoll {
  MatchNodesContinue(progress~ : Int64, work~ : Int64)
  MatchNodesComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  MatchNodesFailed(MatchNodesIssue, progress~ : Int64, work~ : Int64)
  MatchNodesStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum MatchNodesIssue {
  InvalidMatchNodesKernel
  InvalidMatchNodesLimits
  MatchNodesInputUnavailable
  MissingMatchNodeIdentity(Int)
  MatchNodesWorkspaceLimit
  MatchNodesWorkLimit
  MatchNodesPredicate(@execution.EvalIssueKind)
  MatchNodesKeyOrder(@value.KeyOrderIssue)
  MatchNodesOutput(@execution.CaptureIssue)
  MatchNodesCompletion(@execution.TrustedOutputIssue)
  MatchNodesExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_match_nodes_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_match_nodes_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn match_nodes_workspace(identities : Int, width : Int) -> Int? {
  guard checked_match_nodes_multiply(identities, 2) is Some(sort_slots) &&
    checked_match_nodes_add(sort_slots, width) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn capped_match_nodes_run_end(start : Int, width : Int, count : Int) -> Int {
  if start > count - Int::min(width, count) {
    count
  } else {
    Int::min(start + width, count)
  }
}

///|
fn graph_node_alias(graph : @carrier.Graph) -> @schema.FieldName? {
  match @carrier.graph_names(graph) {
    Some(names) => {
      let (node, _, _, _) = @carrier.graph_row_fields(names)
      Some(node)
    }
    None => None
  }
}

///|
fn graph_node_property_index(
  graph : @carrier.Graph,
  name : @schema.FieldName,
) -> Int? {
  let properties = @carrier.graph_node_properties(graph)
  for index in 0..<@carrier.field_count(properties) {
    if @carrier.field_at(properties, index).unwrap().name == name {
      return Some(index)
    }
  }
  None
}

///|
fn node_predicate_field_count(graph : @carrier.Graph) -> Int {
  graph_node_predicate_binding_count(graph)
}

///|
fn node_predicate_binding(
  state : MatchNodesState,
  node : Int,
  index : Int,
) -> (String, @execution.Value)? {
  graph_node_predicate_binding(state.graph, state.source, node, index)
}

///|
fn match_node_field(
  state : MatchNodesState,
  node : Int,
  expected : @schema.Field,
) -> @value.CheckedValue? {
  let source = if graph_node_alias(state.graph) == Some(expected.name) {
    @storage.node_identity(state.source, node)
  } else {
    match graph_node_property_index(state.graph, expected.name) {
      Some(property) => @storage.node_property(state.source, node, property)
      None => None
    }
  }
  source.bind(checked => {
    @value.recheck_runtime_value(
      checked.value,
      expected.contract,
      state.value_limits,
    )
  })
}

///|
fn compare_selected_nodes(
  state : MatchNodesState,
  left : Int,
  right : Int,
) -> Result[Int, MatchNodesIssue] {
  guard @storage.node_identity(state.source, left) is Some(left_value) &&
    @storage.node_identity(state.source, right) is Some(right_value) else {
    return Err(MatchNodesInputUnavailable)
  }
  @value.compare_key_values(left_value, right_value).map_err(issue => {
    MatchNodesKeyOrder(issue)
  })
}

///|
fn prepare_match_nodes_merge(state : MatchNodesState) -> Unit {
  state.middle = capped_match_nodes_run_end(
    state.run_start,
    state.width,
    state.selected.length(),
  )
  state.run_end = capped_match_nodes_run_end(
    state.middle,
    state.width,
    state.selected.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = Merge
}

///|
fn emit_match_nodes_merge(state : MatchNodesState, take_left : Bool) -> Unit {
  let selected = if take_left {
    let value = state.selected[state.left_index]
    state.left_index += 1
    value
  } else {
    let value = state.selected[state.right_index]
    state.right_index += 1
    value
  }
  state.scratch[state.merge_index] = Some(selected)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareMerge
  } else {
    state.phase = Merge
  }
}

///|
fn merge_match_nodes(state : MatchNodesState) -> Unit {
  if state.left_index >= state.middle {
    emit_match_nodes_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_match_nodes_merge(state, true)
  } else {
    state.phase = CompareMerge
  }
}

///|
fn match_nodes_step(
  state : MatchNodesState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, MatchNodesIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(MatchNodesInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(MatchNodesWorkLimit, progress, used)
    }
    match state.phase {
      InitializeScratch => {
        if state.scratch.length() == state.scratch_count {
          state.phase = ResolveIdentities
          continue
        }
        state.scratch.push(None)
        state.scratch_slots.val += 1
        used += 1
        progress += 1
      }
      ResolveIdentities =>
        if state.predicate is Some(_) {
          if state.identity_index < @storage.node_count(state.source) {
            state.predicate_field = 0
            state.predicate_input.clear()
            state.phase = PreparePredicate
          } else {
            state.width = 1
            state.phase = PrepareSort
          }
        } else if state.select_all_nodes is Some(select_all) {
          if state.identity_index < @storage.node_count(state.source) {
            if select_all {
              state.selected.push(state.identity_index)
            }
            state.identity_index += 1
            used += 1
          } else {
            state.width = 1
            state.phase = PrepareSort
          }
        } else if state.identity_index <
          @lower.graph_match_id_count(state.prepared) {
          let authored = state.identity_index
          used += 1
          guard @lower.graph_match_id_at(state.prepared, authored)
            is Some(identity) else {
            return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
          }
          match @storage.node_index(state.source, identity) {
            Ok(Some(node)) => {
              state.selected.push(node)
              state.identity_index += 1
            }
            Ok(None) =>
              return @bounded.Failed(
                MissingMatchNodeIdentity(authored),
                progress,
                used,
              )
            Err(_) =>
              return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
          }
        } else {
          state.width = 1
          state.phase = PrepareSort
        }
      PreparePredicate =>
        if state.predicate_field < state.predicate_fields {
          used += 1
          guard node_predicate_binding(
              state,
              state.identity_index,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(MatchNodesInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.predicate is Some(predicate) else {
            return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
          }
          match
            @execution.start_predicate_expression(
              predicate,
              state.predicate_input,
              state.predicate_work_remaining,
              state.value_limits.max_nodes,
              state.predicate_workspace,
            ) {
            Err(issue) =>
              return @bounded.Failed(
                MatchNodesPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluatePredicate
            }
          }
        }
      EvaluatePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              MatchNodesPredicate(issue.kind),
              progress,
              used,
            )
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            if selected {
              state.selected.push(state.identity_index)
            }
            state.predicate_input.clear()
            state.identity_index += 1
            state.phase = ResolveIdentities
          }
        }
      }
      PrepareSort =>
        if state.width >= state.selected.length() {
          state.emit_index = 0
          state.phase = BeginEmit
        } else {
          state.run_start = 0
          state.phase = PrepareMerge
        }
      PrepareMerge =>
        if state.run_start >= state.selected.length() {
          state.copy_index = 0
          state.phase = CopyPass
        } else {
          prepare_match_nodes_merge(state)
        }
      Merge => {
        merge_match_nodes(state)
        used += 1
      }
      CompareMerge => {
        used += 1
        match
          compare_selected_nodes(
            state,
            state.selected[state.left_index],
            state.selected[state.right_index],
          ) {
          Ok(comparison) => emit_match_nodes_merge(state, comparison <= 0)
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass =>
        if state.copy_index < state.selected.length() {
          guard state.scratch[state.copy_index] is Some(node) else {
            return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
          }
          state.selected[state.copy_index] = node
          state.scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.selected.length() / 2 {
            state.selected.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareSort
        }
      BeginEmit =>
        if state.emit_index >= state.selected.length() {
          state.phase = Finish
        } else if state.emit_index == 0 {
          state.column = 0
          state.values = []
          state.phase = ReadField
        } else {
          state.phase = CompareDuplicate
        }
      CompareDuplicate => {
        used += 1
        match
          compare_selected_nodes(
            state,
            state.selected[state.emit_index - 1],
            state.selected[state.emit_index],
          ) {
          Ok(0) => {
            state.emit_index += 1
            state.phase = BeginEmit
          }
          Ok(_) => {
            state.column = 0
            state.values = []
            state.phase = ReadField
          }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          used += 1
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            match_node_field(state, state.selected[state.emit_index], field)
            is Some(value) else {
            return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.emit_index += 1
            state.phase = BeginEmit
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(MatchNodesOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMatchNodesKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(MatchNodesOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(MatchNodesCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_match_nodes_state(state : MatchNodesState) -> Bool {
  if state.predicate_execution is Some(execution) {
    @execution.cancel_predicate_expression(execution) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.selected = []
  state.scratch = []
  state.scratch_slots.val = 0
  state.values = []
  state.predicate_input.clear()
  true
}

///|
pub fn start_match_nodes(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[MatchNodesExecution, MatchNodesIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphMatchStep(prepared)) &&
    @lower.graph_match_nodes(prepared) &&
    (
      @lower.graph_match_id_count(prepared) > 0 ||
      @lower.graph_match_has_predicate(prepared)
    ) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.GraphValue(graph) else {
    return Err(InvalidMatchNodesKernel)
  }
  let literal = @lower.graph_match_literal_selection(prepared)
  let select_all_nodes = match literal {
    @lower.NoLiteralSelection => None
    @lower.SelectNoEntities => Some(false)
    @lower.SelectAllEntities => Some(true)
  }
  let predicate = if @lower.graph_match_has_predicate(prepared) &&
    literal == @lower.NoLiteralSelection {
    @lower.graph_match_predicate(prepared)
  } else {
    None
  }
  let count = if predicate is Some(_) {
    @storage.node_count(source)
  } else {
    match select_all_nodes {
      Some(true) => @storage.node_count(source)
      Some(false) => 0
      None => @lower.graph_match_id_count(prepared)
    }
  }
  let schema = @lower.graph_match_output_schema(prepared)
  let width = @schema.field_count(schema)
  let predicate_fields = if predicate is Some(_) {
    node_predicate_field_count(graph)
  } else {
    0
  }
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 0 {
    return Err(MatchNodesWorkLimit)
  }
  guard max_rows >= 0 &&
    match_nodes_workspace(count, width) is Some(workspace) &&
    checked_match_nodes_add(workspace, predicate_fields)
    is Some(fixed_workspace) &&
    fixed_workspace <= max_workspace_slots else {
    return Err(MatchNodesWorkspaceLimit)
  }
  let predicate_workspace = max_workspace_slots - fixed_workspace
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(MatchNodesOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let scratch_slots = Ref(0)
  let port = match
    @execution.prepare_trusted_output_port(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(MatchNodesCompletion(issue))
    }
  }
  let state : MatchNodesState = {
    input,
    source,
    graph,
    prepared,
    schema,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: InitializeScratch,
    identity_index: 0,
    select_all_nodes,
    predicate,
    predicate_field: 0,
    predicate_fields,
    predicate_workspace,
    predicate_work_remaining: limits.max_work,
    predicate_input: Map([]),
    predicate_execution: None,
    selected: [],
    scratch: [],
    scratch_count: count,
    scratch_slots,
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left_index: 0,
    right_index: 0,
    merge_index: 0,
    copy_index: 0,
    emit_index: 0,
    column: 0,
    values: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    match_nodes_step,
    cleanup_match_nodes_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    scratch_slots,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn match_nodes_max_noninterruptible_value_nodes(
  value : MatchNodesExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
/// Structural scratch entries retained by the bounded initialization phase.
pub fn match_nodes_scratch_slots(value : MatchNodesExecution) -> Int {
  value.scratch_slots.val
}

///|
pub fn match_nodes_max_noninterruptible_value_bytes(
  value : MatchNodesExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_match_nodes(
  value : MatchNodesExecution,
  quantum : Int,
) -> Result[MatchNodesPoll, MatchNodesIssue] {
  guard value.token is Some(token) else {
    return Err(MatchNodesExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(MatchNodesExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(MatchNodesContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(MatchNodesComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(MatchNodesFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(MatchNodesStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn match_nodes_stopped(value : MatchNodesExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn match_nodes_cleanup_pending(value : MatchNodesExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_match_nodes(
  value : MatchNodesExecution,
) -> Result[Bool, MatchNodesIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    MatchNodesExecutionIssue(issue)
  })
}
