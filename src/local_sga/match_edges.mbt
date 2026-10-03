///|
priv enum MatchEdgesPhase {
  InitializeTypes
  InitializeScratch
  SelectEdges
  PreparePredicate
  EvaluatePredicate
  PrepareSort
  PrepareMerge
  Merge
  CompareMerge
  CopyPass
  BeginEmit
  ReadField
  CommitRow
  Finish
}

///|
priv struct MatchEdgesState {
  source : GraphReadSource
  graph : @carrier.Graph
  edge_count : Int
  prepared : @lower.PreparedGraphMatch
  schema : @schema.Schema
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : MatchEdgesPhase
  type_count : Int?
  mut type_cursor : Int
  mut property_type_match : Bool
  type_probes : Ref[Int]
  mut source_index : Int
  select_all : Bool
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
  mut comparison_unit : Int
  mut emit_index : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut control_work_remaining : Int
}

///|
struct MatchEdgesExecution {
  session : @bounded.Session[
    MatchEdgesState,
    @execution.CompletedOutput,
    MatchEdgesIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  scratch_slots : Ref[Int]
  type_probes : Ref[Int]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum MatchEdgesPoll {
  MatchEdgesContinue(progress~ : Int64, work~ : Int64)
  MatchEdgesComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  MatchEdgesFailed(MatchEdgesIssue, progress~ : Int64, work~ : Int64)
  MatchEdgesStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum MatchEdgesIssue {
  InvalidMatchEdgesKernel
  InvalidMatchEdgesLimits
  MatchEdgesInputUnavailable
  MatchEdgesWorkspaceLimit
  MatchEdgesWorkLimit
  MatchEdgesPredicate(@execution.EvalIssueKind)
  MatchEdgesKeyOrder(@value.KeyOrderIssue)
  MatchEdgesOutput(@execution.CaptureIssue)
  MatchEdgesCompletion(@execution.TrustedOutputIssue)
  MatchEdgesExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_match_edges_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_match_edges_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn match_edges_workspace(edges : Int, width : Int) -> Int? {
  guard checked_match_edges_multiply(edges, 2) is Some(sort_slots) &&
    checked_match_edges_add(sort_slots, width) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn capped_match_edges_run_end(start : Int, width : Int, count : Int) -> Int {
  if start > count - Int::min(width, count) {
    count
  } else {
    Int::min(start + width, count)
  }
}

///|
fn edge_predicate_binding(
  state : MatchEdgesState,
  edge : Int,
  index : Int,
) -> (String, @execution.Value)? {
  let fields = @lower.graph_match_property_scope_fields(state.prepared)
  guard @carrier.field_at(fields, index) is Some(field) &&
    field.contract is Some(contract) &&
    match_edge_value(state, edge, field.name, contract) is Some(value) else {
    return None
  }
  Some((@schema.reference_name(field.name), @execution.capture(value.value)))
}

///|
fn match_edge_field(
  state : MatchEdgesState,
  edge : Int,
  expected : @schema.Field,
) -> @value.CheckedValue? {
  match_edge_value(state, edge, expected.name, expected.contract)
}

///|
fn match_edge_value(
  state : MatchEdgesState,
  edge : Int,
  name : @schema.FieldName,
  contract : @contract.Contract,
) -> @value.CheckedValue? {
  guard graph_read_edge_endpoints(state.source, edge) is Some((source, target)) else {
    return None
  }
  let checked = if @lower.graph_match_property_binding(
      state.prepared,
      "identity",
    ) ==
    Some(name) {
    graph_read_edge_identity(state.source, edge)
  } else if @lower.graph_match_property_binding(state.prepared, "source") ==
    Some(name) {
    graph_read_node_identity(state.source, source)
  } else if @lower.graph_match_property_binding(state.prepared, "target") ==
    Some(name) {
    graph_read_node_identity(state.source, target)
  } else {
    property_match_field_index(state.prepared, name).bind(index => {
      graph_read_edge_property(state.source, edge, index)
    })
  }
  checked.bind(value => {
    @value.recheck_runtime_value(value.value, contract, state.value_limits)
  })
}

///|
fn compare_selected_edges_step(
  state : MatchEdgesState,
  left : Int,
  right : Int,
) -> Result[Int?, MatchEdgesIssue] {
  guard graph_read_edge_identity_order_key(state.source, left) is Some(left_key) &&
    graph_read_edge_identity_order_key(state.source, right) is Some(right_key) else {
    return Err(MatchEdgesInputUnavailable)
  }
  let (order, next) = graph_identity_compare_unit(
    left_key,
    right_key,
    state.comparison_unit,
  )
  state.comparison_unit = next
  Ok(order)
}

///|
fn edge_matches_types(state : MatchEdgesState, edge : Int) -> Bool {
  state.type_probes.val += 1
  let definition = @lower.graph_match_property_definition(state.prepared)
  guard graph_read_edge_definition(state.source, edge) == Some(definition) else {
    return false
  }
  match state.type_count {
    None => true
    Some(_) => state.property_type_match
  }
}

///|
fn prepare_match_edges_merge(state : MatchEdgesState) -> Unit {
  state.middle = capped_match_edges_run_end(
    state.run_start,
    state.width,
    state.selected.length(),
  )
  state.run_end = capped_match_edges_run_end(
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
fn emit_match_edges_merge(state : MatchEdgesState, take_left : Bool) -> Unit {
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
fn merge_match_edges(state : MatchEdgesState) -> Unit {
  if state.left_index >= state.middle {
    emit_match_edges_merge(state, false)
  } else if state.right_index >= state.run_end {
    emit_match_edges_merge(state, true)
  } else {
    state.phase = CompareMerge
  }
}

///|
fn match_edges_step(
  state : MatchEdgesState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, MatchEdgesIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.source) {
      return @bounded.Failed(MatchEdgesInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(MatchEdgesWorkLimit, progress, used)
    }
    match state.phase {
      InitializeTypes => {
        let count = state.type_count.unwrap_or(0)
        if state.type_cursor < count {
          used += 1
          guard @lower.graph_match_type_at(state.prepared, state.type_cursor)
            is Some(name) else {
            return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
          }
          ignore(name)
          let profile = @carrier.graph_property_definition(state.graph)
          let definition = @lower.graph_match_property_definition(
            state.prepared,
          )
          if @carrier.property_graph_edge_at(profile, definition)
            is Some(edge_definition) &&
            @carrier.property_definition_has_label(
              @carrier.property_edge_element(edge_definition),
              name,
            ) {
            state.property_type_match = true
          }
          state.type_cursor += 1
          progress += 1
        } else {
          state.phase = InitializeScratch
        }
      }
      InitializeScratch => {
        if state.scratch.length() == state.scratch_count {
          state.phase = SelectEdges
          continue
        }
        state.scratch.push(None)
        state.scratch_slots.val += 1
        used += 1
        progress += 1
      }
      SelectEdges =>
        if state.source_index < state.edge_count {
          if edge_matches_types(state, state.source_index) {
            match state.predicate {
              Some(_) => {
                state.predicate_field = 0
                state.predicate_input.clear()
                state.phase = PreparePredicate
              }
              None => {
                if state.select_all {
                  state.selected.push(state.source_index)
                }
                state.source_index += 1
              }
            }
          } else {
            state.source_index += 1
          }
          used += 1
        } else {
          state.width = 1
          state.phase = PrepareSort
        }
      PreparePredicate =>
        if state.predicate_field < state.predicate_fields {
          used += 1
          guard edge_predicate_binding(
              state,
              state.source_index,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(MatchEdgesInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.predicate is Some(predicate) else {
            return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
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
                MatchEdgesPredicate(issue.kind),
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
          return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              MatchEdgesPredicate(issue.kind),
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
              state.selected.push(state.source_index)
            }
            state.predicate_input.clear()
            state.source_index += 1
            state.phase = SelectEdges
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
          prepare_match_edges_merge(state)
        }
      Merge => {
        merge_match_edges(state)
        used += 1
      }
      CompareMerge => {
        used += 1
        match
          compare_selected_edges_step(
            state,
            state.selected[state.left_index],
            state.selected[state.right_index],
          ) {
          Ok(Some(comparison)) => emit_match_edges_merge(state, comparison <= 0)
          Ok(None) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass =>
        if state.copy_index < state.selected.length() {
          guard state.scratch[state.copy_index] is Some(edge) else {
            return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
          }
          state.selected[state.copy_index] = edge
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
        } else {
          state.column = 0
          state.values = []
          state.phase = ReadField
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          used += 1
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            match_edge_field(state, state.selected[state.emit_index], field)
            is Some(value) else {
            return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.emit_index += 1
            state.phase = BeginEmit
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(MatchEdgesOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidMatchEdgesKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(MatchEdgesOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(MatchEdgesCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_match_edges_state(state : MatchEdgesState) -> Bool {
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
  state.comparison_unit = 0
  state.values = []
  state.predicate_input.clear()
  true
}

///|
pub fn start_match_edges(
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
) -> Result[MatchEdgesExecution, MatchEdgesIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(storage) &&
    @storage.carrier(storage) is @carrier.GraphValue(graph) else {
    return Err(InvalidMatchEdgesKernel)
  }
  start_match_edges_read(
    control,
    preparation,
    sequence,
    step,
    Stored(input),
    graph,
    @storage.edge_count(storage),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit~,
  )
}

///|
/// Read an exact managed Graph input through the same bounded match kernel.
pub fn start_match_edges_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[MatchEdgesExecution, MatchEdgesIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(@carrier.GraphValue(graph)) &&
    @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_edge_count(input) is Some(edge_count) else {
    return Err(InvalidMatchEdgesKernel)
  }
  start_match_edges_read(
    control,
    preparation,
    sequence,
    step,
    Viewed(input),
    graph,
    edge_count,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit~,
  )
}

///|
fn start_match_edges_read(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : GraphReadSource,
  graph : @carrier.Graph,
  edge_count : Int,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[MatchEdgesExecution, MatchEdgesIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphMatchStep(prepared)) &&
    !@lower.graph_match_nodes(prepared) else {
    return Err(InvalidMatchEdgesKernel)
  }
  let select_all = !@lower.graph_match_has_predicate(prepared) ||
    @lower.graph_match_literal_selection(prepared) == @lower.SelectAllEntities
  let predicate = if @lower.graph_match_has_predicate(prepared) &&
    @lower.graph_match_literal_selection(prepared) == @lower.NoLiteralSelection {
    @lower.graph_match_predicate(prepared)
  } else {
    None
  }
  let count = edge_count
  let type_count = @lower.graph_match_type_count(prepared)
  let schema = @lower.graph_match_output_schema(prepared)
  let width = @schema.field_count(schema)
  let predicate_fields = if predicate is Some(_) {
    @carrier.field_count(@lower.graph_match_property_scope_fields(prepared))
  } else {
    0
  }
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 0 {
    return Err(MatchEdgesWorkLimit)
  }
  guard max_rows >= 0 &&
    limits.max_nodes >= 0 &&
    limits.max_text_bytes >= 0 &&
    limits.max_depth >= 0 &&
    limits.max_work >= 0 &&
    match_edges_workspace(count, width) is Some(workspace) &&
    checked_match_edges_add(workspace, predicate_fields) is Some(base_workspace) &&
    checked_match_edges_add(base_workspace, type_count.unwrap_or(0))
    is Some(fixed_workspace) &&
    fixed_workspace <= max_workspace_slots else {
    return Err(MatchEdgesWorkspaceLimit)
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
    Err(issue) => return Err(MatchEdgesOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let scratch_slots = Ref(0)
  let type_probes = Ref(0)
  let port_result = match source {
    Stored(read) if @lifecycle.producer_read_reference_matches_input(
        @graph.producer_read_carrier_reference(read),
        owner,
        0,
      ) => {
      let retained_inputs = [
        @execution.trusted_output_carrier_input(
          @graph.producer_read_carrier_reference(read),
        ),
      ]
      for input in inputs {
        retained_inputs.push(@execution.trusted_output_relation_input(input))
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=retained_inputs,
      )
    }
    Stored(_) =>
      @execution.prepare_trusted_output_port(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs~,
      )
    Viewed(view) => {
      guard inputs.is_empty() else {
        @execution.cancel_admitted_output(output) |> ignore
        return Err(InvalidMatchEdgesKernel)
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=[
          @execution.trusted_output_carrier_input(
            @lifecycle.producer_view_read_reference(view),
          ),
        ],
      )
    }
  }
  let port = match port_result {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(MatchEdgesCompletion(issue))
    }
  }
  let state : MatchEdgesState = {
    source,
    graph,
    edge_count,
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
    phase: InitializeTypes,
    type_count,
    type_cursor: 0,
    property_type_match: false,
    type_probes,
    source_index: 0,
    select_all,
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
    comparison_unit: 0,
    emit_index: 0,
    column: 0,
    values: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    match_edges_step,
    cleanup_match_edges_state,
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
    type_probes,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn match_edges_max_noninterruptible_value_nodes(
  value : MatchEdgesExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
/// Structural scratch entries retained by the bounded initialization phase.
pub fn match_edges_scratch_slots(value : MatchEdgesExecution) -> Int {
  value.scratch_slots.val
}

///|
pub fn match_edges_type_probes(value : MatchEdgesExecution) -> Int {
  value.type_probes.val
}

///|
pub fn match_edges_max_noninterruptible_value_bytes(
  value : MatchEdgesExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_match_edges(
  value : MatchEdgesExecution,
  quantum : Int,
) -> Result[MatchEdgesPoll, MatchEdgesIssue] {
  guard value.token is Some(token) else {
    return Err(MatchEdgesExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(MatchEdgesExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(MatchEdgesContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(MatchEdgesComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(MatchEdgesFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(MatchEdgesStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn match_edges_stopped(value : MatchEdgesExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn match_edges_cleanup_pending(value : MatchEdgesExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_match_edges(
  value : MatchEdgesExecution,
) -> Result[Bool, MatchEdgesIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    MatchEdgesExecutionIssue(issue)
  })
}
