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
  left_read : @graph.ProducerRead
  right_read : @graph.ProducerRead
  left : @storage.Storage
  right : @storage.Storage
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
  GraphsEqualComparison(@value.CompleteEqualityIssue)
  GraphsEqualStorage(@storage.Issue)
  GraphsEqualOutput(@execution.CaptureIssue)
  GraphsEqualCompletion(@execution.TrustedOutputIssue)
  GraphsEqualExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn advance_checked_values_equal(
  state : GraphsEqualState,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  quantum : Int,
) -> Result[(Bool, Bool, Int), GraphsEqualIssue] {
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
    @value.EqualityContinue(work~) => Ok((false, false, work))
    @value.EqualityComplete(equal~, work~) => {
      state.comparison = None
      Ok((true, equal, work))
    }
    @value.EqualityFailed(issue, work~) => {
      state.comparison = None
      state.comparison_failure_work = work
      Err(GraphsEqualComparison(issue))
    }
  }
}

///|
fn select_equal_node(
  state : GraphsEqualState,
) -> Result[Unit, GraphsEqualIssue] {
  guard @storage.node_identity(state.left, state.record) is Some(identity) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match @storage.node_index(state.right, identity) {
    Err(issue) => Err(GraphsEqualStorage(issue))
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
  guard @storage.carrier(state.left) is @carrier.GraphValue(graph) else {
    return Err(GraphsEqualInputUnavailable)
  }
  let count = @carrier.field_count(@carrier.graph_node_properties(graph))
  if state.property >= count {
    state.record += 1
    state.phase = SelectNode
    return Ok((true, 0))
  }
  guard @storage.node_property(state.left, state.record, state.property)
    is Some(left) &&
    @storage.node_property(state.right, state.other, state.property)
    is Some(right) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match advance_checked_values_equal(state, left, right, quantum) {
    Err(issue) => Err(issue)
    Ok((_, false, work)) => {
      state.equal = false
      state.phase = Emit
      Ok((true, work))
    }
    Ok((true, true, work)) => {
      state.property += 1
      Ok((true, work))
    }
    Ok((false, true, work)) => Ok((false, work))
  }
}

///|
fn select_equal_edge(
  state : GraphsEqualState,
) -> Result[Unit, GraphsEqualIssue] {
  guard @storage.edge_endpoints(state.left, state.record)
    is Some((source, target)) &&
    @storage.node_identity(state.left, source) is Some(source_id) &&
    @storage.node_identity(state.left, target) is Some(target_id) &&
    @storage.edge_label(state.left, state.record) is Some(label) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match @storage.edge_index(state.right, source_id, target_id, label) {
    Err(issue) => Err(GraphsEqualStorage(issue))
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
  guard @storage.carrier(state.left) is @carrier.GraphValue(graph) else {
    return Err(GraphsEqualInputUnavailable)
  }
  let count = @carrier.field_count(@carrier.graph_edge_properties(graph))
  if state.property >= count {
    state.record += 1
    state.phase = SelectEdge
    return Ok((true, 0))
  }
  guard @storage.edge_property(state.left, state.record, state.property)
    is Some(left) &&
    @storage.edge_property(state.right, state.other, state.property)
    is Some(right) else {
    return Err(GraphsEqualInputUnavailable)
  }
  match advance_checked_values_equal(state, left, right, quantum) {
    Err(issue) => Err(issue)
    Ok((_, false, work)) => {
      state.equal = false
      state.phase = Emit
      Ok((true, work))
    }
    Ok((true, true, work)) => {
      state.property += 1
      Ok((true, work))
    }
    Ok((false, true, work)) => Ok((false, work))
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
    if !@graph.producer_read_available(state.left_read) ||
      !@graph.producer_read_available(state.right_read) {
      return @bounded.Failed(GraphsEqualInputUnavailable, progress, used)
    }
    match state.phase {
      CompareCounts => {
        used += 1
        if @storage.node_count(state.left) != @storage.node_count(state.right) ||
          @storage.edge_count(state.left) != @storage.edge_count(state.right) {
          state.equal = false
          state.phase = Emit
        } else {
          state.phase = SelectNode
        }
      }
      SelectNode =>
        if state.record >= @storage.node_count(state.left) {
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
        match compare_equal_node_property(state, quantum - used) {
          Ok((_, work)) => used += work
          Err(issue) => {
            used += state.comparison_failure_work
            state.comparison_failure_work = 0
            return @bounded.Failed(issue, progress, used)
          }
        }
      SelectEdge =>
        if state.record >= @storage.edge_count(state.left) {
          state.phase = Emit
        } else {
          used += 1
          match select_equal_edge(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      CompareEdgeProperty =>
        match compare_equal_edge_property(state, quantum - used) {
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
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graphs_equal_state(state : GraphsEqualState) -> Bool {
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
) -> Result[GraphsEqualExecution, GraphsEqualIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.GraphsEqualRelation &&
    @graph.producer_read_matches_operation_input(left_read, owner, step, 0) &&
    @graph.producer_read_matches_operation_input(right_read, owner, step, 1) &&
    @graph.producer_read_storage(left_read) is Some(left) &&
    @graph.producer_read_storage(right_read) is Some(right) else {
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
      return Err(GraphsEqualCompletion(issue))
    }
  }
  let state : GraphsEqualState = {
    left_read,
    right_read,
    left,
    right,
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
