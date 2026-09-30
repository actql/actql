///|
priv enum GraphsEqualPhase {
  CompareCounts
  SelectNode
  CompareNodeProperty
  SelectEdge
  CompareEdgeProperty
  Emit
  Finish
}

///|
priv struct GraphsEqualState {
  left : GraphReadSource
  right : GraphReadSource
  graph : @carrier.Graph
  left_nodes : Int
  right_nodes : Int
  left_edges : Int
  right_edges : Int
  schema : @schema.Schema
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  value_limits : @value.Limits
  mut comparison : @value.CompleteEquality?
  mut comparison_failure_work : Int
  mut phase : GraphsEqualPhase
  mut equal : Bool
  mut record : Int
  mut property : Int
  mut other : Int
  mut control_work_remaining : Int
}

///|
struct GraphsEqualExecution {
  session : @bounded.Session[
    GraphsEqualState,
    @execution.CompletedOutput,
    GraphsEqualIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub fn graphs_equal_max_noninterruptible_value_nodes(
  value : GraphsEqualExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn graphs_equal_max_noninterruptible_value_bytes(
  value : GraphsEqualExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub enum GraphsEqualPoll {
  GraphsEqualContinue(progress~ : Int64, work~ : Int64)
  GraphsEqualComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  GraphsEqualFailed(GraphsEqualIssue, progress~ : Int64, work~ : Int64)
  GraphsEqualStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphsEqualIssue {
  InvalidGraphsEqualKernel
  GraphsEqualInputUnavailable
  GraphsEqualWorkLimit
  GraphsEqualComparison(@value.CompleteEqualityIssue)
  GraphsEqualStorage(@storage.Issue)
  GraphsEqualOutput(@execution.CaptureIssue)
  GraphsEqualCompletion(@execution.TrustedOutputIssue)
  GraphsEqualExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
priv enum CheckedValuesEqualPoll {
  CheckedValuesContinue(Int)
  CheckedValuesComplete(Bool, Int)
}

///|
fn advance_checked_values_equal(
  state : GraphsEqualState,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  quantum : Int,
) -> Result[CheckedValuesEqualPoll, GraphsEqualIssue] {
  let comparison = match state.comparison {
    Some(value) => value
    None =>
      match @value.start_complete_equality(left, right, state.value_limits) {
        Ok(value) => {
          state.comparison = Some(value)
          value
        }
        Err(issue) => return Err(GraphsEqualComparison(issue))
      }
  }
  match @value.advance_complete_equality(comparison, quantum) {
    @value.EqualityContinue(work~) => Ok(CheckedValuesContinue(work))
    @value.EqualityComplete(equal~, work~) => {
      state.comparison = None
      Ok(CheckedValuesComplete(equal, work))
    }
    @value.EqualityFailed(issue, work~) => {
      state.comparison = None
      state.comparison_failure_work = work
      Err(GraphsEqualComparison(issue))
    }
  }
}

///|
fn equal_node_index(
  source : GraphReadSource,
  identity : @value.CheckedValue,
) -> Result[Int?, GraphsEqualIssue] {
  match source {
    Stored(read) =>
      match @graph.producer_read_storage(read) {
        Some(storage) =>
          @storage.node_index(storage, identity).map_err(issue => {
            GraphsEqualStorage(issue)
          })
        None => Err(GraphsEqualInputUnavailable)
      }
    Viewed(_) =>
      graph_read_node_index(source, identity).map_err(_ => {
        GraphsEqualInputUnavailable
      })
  }
}

///|
fn equal_edge_index(
  source : GraphReadSource,
  from : @value.CheckedValue,
  to : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Int?, GraphsEqualIssue] {
  match source {
    Stored(read) =>
      match @graph.producer_read_storage(read) {
        Some(storage) =>
          @storage.edge_index(storage, from, to, label).map_err(issue => {
            GraphsEqualStorage(issue)
          })
        None => Err(GraphsEqualInputUnavailable)
      }
    Viewed(_) =>
      graph_read_edge_index(source, from, to, label).map_err(_ => {
        GraphsEqualInputUnavailable
      })
  }
}

///|
fn select_equal_node(
  state : GraphsEqualState,
) -> Result[Unit, GraphsEqualIssue] {
  guard graph_read_node_identity(state.left, state.record) is Some(identity) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match equal_node_index(state.right, identity) {
    Err(issue) => Err(issue)
    Ok(None) => {
      state.equal = false
      state.phase = Emit
      Ok(())
    }
    Ok(Some(other)) => {
      state.other = other
      state.property = 0
      state.phase = CompareNodeProperty
      Ok(())
    }
  }
}

///|
fn compare_equal_node_property(
  state : GraphsEqualState,
  quantum : Int,
) -> Result[(Bool, Int), GraphsEqualIssue] {
  let count = @carrier.field_count(@carrier.graph_node_properties(state.graph))
  if state.property >= count {
    state.record += 1
    state.phase = SelectNode
    return Ok((true, 0))
  }
  guard graph_read_node_property(state.left, state.record, state.property)
    is Some(left) &&
    graph_read_node_property(state.right, state.other, state.property)
    is Some(right) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match advance_checked_values_equal(state, left, right, quantum) {
    Err(issue) => Err(issue)
    Ok(CheckedValuesContinue(work)) => Ok((false, work))
    Ok(CheckedValuesComplete(false, work)) => {
      state.equal = false
      state.phase = Emit
      Ok((true, work))
    }
    Ok(CheckedValuesComplete(true, work)) => {
      state.property += 1
      Ok((true, work))
    }
  }
}

///|
fn select_equal_edge(
  state : GraphsEqualState,
) -> Result[Unit, GraphsEqualIssue] {
  guard graph_read_edge_endpoints(state.left, state.record)
    is Some((source, target)) &&
    graph_read_node_identity(state.left, source) is Some(source_id) &&
    graph_read_node_identity(state.left, target) is Some(target_id) &&
    graph_read_edge_label(state.left, state.record) is Some(label) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match equal_edge_index(state.right, source_id, target_id, label) {
    Err(issue) => Err(issue)
    Ok(None) => {
      state.equal = false
      state.phase = Emit
      Ok(())
    }
    Ok(Some(other)) => {
      state.other = other
      state.property = 0
      state.phase = CompareEdgeProperty
      Ok(())
    }
  }
}

///|
fn compare_equal_edge_property(
  state : GraphsEqualState,
  quantum : Int,
) -> Result[(Bool, Int), GraphsEqualIssue] {
  let count = @carrier.field_count(@carrier.graph_edge_properties(state.graph))
  if state.property >= count {
    state.record += 1
    state.phase = SelectEdge
    return Ok((true, 0))
  }
  guard graph_read_edge_property(state.left, state.record, state.property)
    is Some(left) &&
    graph_read_edge_property(state.right, state.other, state.property)
    is Some(right) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match advance_checked_values_equal(state, left, right, quantum) {
    Err(issue) => Err(issue)
    Ok(CheckedValuesContinue(work)) => Ok((false, work))
    Ok(CheckedValuesComplete(false, work)) => {
      state.equal = false
      state.phase = Emit
      Ok((true, work))
    }
    Ok(CheckedValuesComplete(true, work)) => {
      state.property += 1
      Ok((true, work))
    }
  }
}

///|
fn graphs_equal_step(
  state : GraphsEqualState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, GraphsEqualIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.left) || !graph_read_available(state.right) {
      return @bounded.Failed(GraphsEqualInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(GraphsEqualWorkLimit, progress, used)
    }
    match state.phase {
      CompareCounts => {
        used += 1
        if state.left_nodes != state.right_nodes ||
          state.left_edges != state.right_edges {
          state.equal = false
          state.phase = Emit
        } else {
          state.phase = SelectNode
        }
      }
      SelectNode =>
        if state.record >= state.left_nodes {
          state.record = 0
          state.phase = SelectEdge
        } else {
          used += 1
          match select_equal_node(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      CompareNodeProperty =>
        match
          compare_equal_node_property(
            state,
            Int::min(quantum - used, state.control_work_remaining - used),
          ) {
          Ok((_, work)) => used += work
          Err(issue) => {
            used += state.comparison_failure_work
            state.comparison_failure_work = 0
            return @bounded.Failed(issue, progress, used)
          }
        }
      SelectEdge =>
        if state.record >= state.left_edges {
          state.phase = Emit
        } else {
          used += 1
          match select_equal_edge(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      CompareEdgeProperty =>
        match
          compare_equal_edge_property(
            state,
            Int::min(quantum - used, state.control_work_remaining - used),
          ) {
          Ok((_, work)) => used += work
          Err(issue) => {
            used += state.comparison_failure_work
            state.comparison_failure_work = 0
            return @bounded.Failed(issue, progress, used)
          }
        }
      Emit => {
        used += 1
        guard state.output is Some(output) &&
          @schema.field_count(state.schema) == 1 &&
          @schema.field_at(state.schema, 0) is Some(field) &&
          field.name == @schema.Unqualified("equal") &&
          @value.checked_boolean_value(state.equal, field.contract)
          is Some(value) else {
          return @bounded.Failed(InvalidGraphsEqualKernel, progress, used)
        }
        match @execution.append_admitted_output(output, [value]) {
          Ok(_) => {
            state.phase = Finish
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(GraphsEqualOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphsEqualKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(GraphsEqualOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(GraphsEqualCompletion(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graphs_equal_state(state : GraphsEqualState) -> Bool {
  state.comparison = None
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn start_graphs_equal_read(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left : GraphReadSource,
  right : GraphReadSource,
  graph : @carrier.Graph,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[GraphsEqualExecution, GraphsEqualIssue] {
  let owner = @lower.sequence_owner(sequence)
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 0 {
    return Err(GraphsEqualWorkLimit)
  }
  let input_matches = match (left, right) {
    (Stored(left_read), Stored(right_read)) =>
      @graph.producer_read_matches_operation_input(left_read, owner, step, 0) &&
      @graph.producer_read_matches_operation_input(right_read, owner, step, 1)
    (Viewed(left_view), Viewed(right_view)) =>
      @lifecycle.producer_view_kind(left_view) == @carrier.GraphKind &&
      @lifecycle.producer_view_kind(right_view) == @carrier.GraphKind &&
      @lifecycle.producer_read_reference_matches_operation_input(
        @lifecycle.producer_view_read_reference(left_view),
        owner,
        step,
        0,
      ) &&
      @lifecycle.producer_read_reference_matches_operation_input(
        @lifecycle.producer_view_read_reference(right_view),
        owner,
        step,
        1,
      )
    _ => false
  }
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.GraphsEqualRelation &&
    input_matches &&
    graph_read_node_count(left) is Some(left_nodes) &&
    graph_read_node_count(right) is Some(right_nodes) &&
    graph_read_edge_count(left) is Some(left_edges) &&
    graph_read_edge_count(right) is Some(right_edges) else {
    return Err(InvalidGraphsEqualKernel)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(GraphsEqualOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port_result = match (left, right) {
    (Stored(_), Stored(_)) =>
      @execution.prepare_trusted_output_port(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs~,
      )
    (Viewed(left_view), Viewed(right_view)) =>
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=[
          @execution.trusted_output_carrier_input(
            @lifecycle.producer_view_read_reference(left_view),
          ),
          @execution.trusted_output_carrier_input(
            @lifecycle.producer_view_read_reference(right_view),
          ),
        ],
      )
    _ => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(InvalidGraphsEqualKernel)
    }
  }
  let port = match port_result {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphsEqualCompletion(issue))
    }
  }
  let state : GraphsEqualState = {
    left,
    right,
    graph,
    left_nodes,
    right_nodes,
    left_edges,
    right_edges,
    schema: @lower.graph_relation_output_schema(prepared),
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    comparison: None,
    comparison_failure_work: 0,
    phase: CompareCounts,
    equal: true,
    record: 0,
    property: 0,
    other: 0,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    graphs_equal_step,
    cleanup_graphs_equal_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn start_graphs_equal(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left_read : @graph.ProducerRead,
  right_read : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[GraphsEqualExecution, GraphsEqualIssue] {
  guard @graph.producer_read_storage(left_read) is Some(storage) &&
    @storage.carrier(storage) is @carrier.GraphValue(graph) else {
    return Err(GraphsEqualInputUnavailable)
  }
  start_graphs_equal_read(
    control,
    preparation,
    sequence,
    step,
    Stored(left_read),
    Stored(right_read),
    graph,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit~,
  )
}

///|
pub fn start_graphs_equal_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left : @lifecycle.ProducerView,
  right : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  control_work_limit? : Int? = None,
) -> Result[GraphsEqualExecution, GraphsEqualIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_count(node) == 2 &&
    @lower.node_input_target(node, 0) is Some(left_target) &&
    @lower.node_input_target(node, 1) is Some(right_target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), left_target)
    is Some(@carrier.GraphValue(graph)) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), right_target)
    is Some(@carrier.GraphValue(_)) &&
    inputs.is_empty() else {
    return Err(InvalidGraphsEqualKernel)
  }
  start_graphs_equal_read(
    control,
    preparation,
    sequence,
    step,
    Viewed(left),
    Viewed(right),
    graph,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    inputs,
    control_work_limit~,
  )
}

///|
pub fn advance_graphs_equal(
  value : GraphsEqualExecution,
  quantum : Int,
) -> Result[GraphsEqualPoll, GraphsEqualIssue] {
  guard value.token is Some(token) else {
    return Err(GraphsEqualExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphsEqualExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraphsEqualContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(GraphsEqualComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraphsEqualFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraphsEqualStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn graphs_equal_stopped(value : GraphsEqualExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn graphs_equal_cleanup_pending(value : GraphsEqualExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_graphs_equal(
  value : GraphsEqualExecution,
) -> Result[Bool, GraphsEqualIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    GraphsEqualExecutionIssue(issue)
  })
}
