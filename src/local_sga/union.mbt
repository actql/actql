///|
priv enum UnionPhase {
  PrepareUnionFold
  ExecuteUnionFold
  CompleteUnionOutput
  UnionFinished
}

///|
priv struct UnionState {
  owner : @lower.BoundPrepared
  step : Int
  checked : @graph_type.CheckedUnion
  subtraction : Bool
  inputs : Array[GraphReadSource]
  limits : @storage.Limits
  storage_bytes : Int64
  mut available : () -> Bool
  output_available : () -> Bool
  mut remaining : Int
  mut rows_remaining : Int
  mut bytes_remaining : Int
  mut fold : Int
  mut phase : UnionPhase
  mut active : UnionFoldPreparation?
  mut accumulator : @storage.Storage?
  mut output : @graph.OutputBuilder?
  mut result : @storage.Storage?
}

///|
struct UnionExecution {
  session : @bounded.Session[UnionState, @graph.Completed, UnionIssue]
  mut token : @bounded.Token?
}

///|
pub enum UnionPoll {
  UnionContinue(progress~ : Int64, work~ : Int64)
  UnionComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  UnionFailed(UnionIssue, progress~ : Int64, work~ : Int64)
  UnionStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
/// Logical transient slot ceiling in addition to retained Graph records. The
/// record append owner accounts for staged columns and identity conversion;
/// union adds bounded set entries, equality/order frames and its control state.
/// This is not a physical-byte proof or a total Graph capacity guarantee.
pub fn union_workspace_slots(
  graph : @carrier.Graph,
  limits : @storage.Limits,
  input_count : Int,
) -> Int? {
  if input_count < 2 {
    return None
  }
  guard @storage.property_snapshot_append_workspace_slots(graph, limits)
    is Some(append) else {
    return None
  }
  let extra = 16L * limits.max_value_nodes.to_int64() +
    8L * limits.max_value_depth.to_int64() +
    4L * input_count.to_int64() +
    64L
  if extra > 2147483647L - append.to_int64() {
    None
  } else {
    Some(append + extra.to_int())
  }
}

///|
/// Peak canonical UTF-8 order bytes, not a compiler heap-size claim. One
/// retained key set and one provisional writer each use the Host-selected
/// per-value byte quota. Actual retained keys are separately metered by the
/// field cursor, including non-text items' type tags and punctuation.
pub fn union_order_workspace_bytes(
  checked : @graph_type.CheckedUnion,
  limits : @storage.Limits,
) -> Int? {
  if limits.max_value_bytes < 0 {
    return None
  }
  let mut ordered_sets = false
  for edge in [false, true] {
    for index in 0..<@graph_type.union_strategy_count(checked, edge~) {
      if @graph_type.union_strategy_at(checked, index, edge~)
        is Some((_, strategy)) &&
        (
          strategy == @graph_type.UnionSetUnion ||
          strategy == @graph_type.UnionSetDifference
        ) {
        ordered_sets = true
      }
    }
  }
  if !ordered_sets {
    return Some(0)
  }
  if limits.max_value_bytes > 2147483647 / 2 {
    None
  } else {
    Some(2 * limits.max_value_bytes)
  }
}

///|
fn union_step(
  state : UnionState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, UnionIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if !(state.available)() {
    return @bounded.Failed(UnionInputUnavailable, 0, 0)
  }
  if state.remaining < 1 {
    return @bounded.Failed(UnionFoldWorkLimit, 0, 0)
  }
  let budget = Int::min(quantum, state.remaining)
  match state.phase {
    PrepareUnionFold => {
      state.remaining -= 1
      guard @graph_type.union_fold_output(state.checked, state.fold)
        is Some(@carrier.GraphValue(graph)) &&
        state.inputs.get(state.fold + 1) is Some(right) &&
        union_workspace_slots(graph, state.limits, state.inputs.length())
        is Some(scratch) &&
        union_order_workspace_bytes(state.checked, state.limits)
        is Some(order_bytes) else {
        return @bounded.Failed(InvalidUnionFold, 0, 1)
      }
      let accumulator_slots = state.accumulator
        .map(@storage.retained_workspace_slots)
        .unwrap_or(0)
      let accumulator_bytes = state.accumulator
        .map(@storage.retained_value_bytes)
        .unwrap_or(0)
      // The previous private generation stays alive until its successor has
      // finished. Reserve their simultaneous retention plus bounded cursors;
      // cleanup, not failure notification, returns these reservations.
      if scratch > state.limits.max_workspace_slots ||
        accumulator_slots > state.limits.max_workspace_slots - scratch ||
        order_bytes > state.limits.max_retained_value_bytes ||
        accumulator_bytes > state.limits.max_retained_value_bytes - order_bytes {
        return @bounded.Failed(UnionFoldWorkspaceLimit, 0, 1)
      }
      let limits = {
        ..state.limits,
        max_work: state.remaining,
        max_input_rows: state.rows_remaining,
        max_total_value_bytes: state.bytes_remaining,
        // This internal composition peak includes the previous generation,
        // successor and canonical order keys. It is not an external-input
        // preflight bound copied from the Graph's admitted metadata.
        max_retained_value_bytes: state.limits.max_retained_value_bytes -
        accumulator_bytes -
        order_bytes,
        max_workspace_slots: state.limits.max_workspace_slots -
        accumulator_slots -
        scratch,
      }
      let last_fold = state.fold + 2 == state.inputs.length()
      let builder = if last_fold {
        let output = match
          @graph.prepare_output(
            state.owner,
            @pipeline.Step(state.step),
            DeclaredNodes,
            limits,
            state.storage_bytes,
            state.output_available,
          ) {
          Ok(output) => output
          Err(issue) => return @bounded.Failed(UnionOutput(issue), 0, 1)
        }
        state.output = Some(output)
        guard @graph.output_storage_builder(output) is Some(builder) else {
          return @bounded.Failed(InvalidUnionFold, 0, 1)
        }
        builder
      } else {
        match
          @storage.prepare(
            @graph_type.union_fold_output(state.checked, state.fold).unwrap(),
            DeclaredNodes,
            limits,
          ) {
          Ok(builder) => builder
          Err(issue) => return @bounded.Failed(UnionFoldStorage(issue), 0, 1)
        }
      }
      let left = match state.accumulator {
        Some(storage) => Accumulated(storage)
        None => state.inputs[0]
      }
      // A failed cold setup does not transfer builder custody; cancel only this
      // private construction, leaving the input generations borrowed.
      state.active = match
        prepare_union_fold(
          state.checked,
          state.fold,
          left,
          right,
          builder,
          limits,
          state.remaining,
          subtraction=state.subtraction,
        ) {
        Ok(active) => Some(active)
        Err(issue) => {
          @storage.cancel(builder) |> ignore
          return @bounded.Failed(issue, 0, 1)
        }
      }
      state.phase = ExecuteUnionFold
      @bounded.Continue(0, 1)
    }
    ExecuteUnionFold => {
      guard state.active is Some(active) else {
        return @bounded.Failed(InvalidUnionFold, 0, 0)
      }
      let poll = advance_union_fold(active, budget)
      let work = match poll {
        UnionFoldContinue(work)
        | UnionFoldComplete(_, work)
        | UnionFoldFailed(_, work) => work
      }
      if poll is UnionFoldComplete(storage, _) {
        state.result = Some(storage)
      }
      if work < 0 ||
        work > budget ||
        (poll is UnionFoldContinue(_) && work == 0) {
        return @bounded.Failed(InvalidUnionFold, 0, 0)
      }
      state.remaining -= work
      match poll {
        UnionFoldContinue(_) => @bounded.Continue(0, work)
        UnionFoldFailed(issue, _) => @bounded.Failed(issue, 0, work)
        UnionFoldComplete(storage, _) => {
          // Subtract each fold's actual admitted traffic, not just the final
          // Graph size. Duplicate authored occurrences are never elided.
          let rows = @storage.input_row_count(storage)
          let bytes = @storage.measured_input_value_bytes(storage)
          if rows > state.rows_remaining || bytes > state.bytes_remaining {
            return @bounded.Failed(
              UnionFoldStorage(@storage.InputRowLimit),
              0,
              work,
            )
          }
          state.rows_remaining -= rows
          state.bytes_remaining -= bytes
          cleanup_union_fold(active)
          state.active = None
          if state.accumulator is Some(previous) {
            @storage.discard(previous)
            state.accumulator = None
          }
          if state.fold + 2 == state.inputs.length() {
            state.phase = CompleteUnionOutput
          } else {
            state.accumulator = Some(storage)
            state.result = None
            state.fold += 1
            state.phase = PrepareUnionFold
          }
          @bounded.Continue(0, work)
        }
      }
    }
    CompleteUnionOutput => {
      state.remaining -= 1
      guard state.result is Some(result) && state.output is Some(output) else {
        return @bounded.Failed(InvalidUnionFold, 0, 1)
      }
      state.result = None
      state.output = None
      state.phase = UnionFinished
      match @graph.finish_output_storage(output, result) {
        Ok(completed) => @bounded.Complete(completed, 1, 1)
        Err(issue) => {
          @storage.discard(result)
          @bounded.Failed(UnionOutput(issue), 0, 1)
        }
      }
    }
    UnionFinished => @bounded.Failed(InvalidUnionFold, 0, 0)
  }
}

///|
fn cleanup_union_state(state : UnionState) -> Bool {
  if state.active is Some(active) {
    cleanup_union_fold(active)
    state.active = None
  }
  if state.accumulator is Some(storage) {
    @storage.discard(storage)
    state.accumulator = None
  }
  if state.result is Some(storage) {
    @storage.discard(storage)
    state.result = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.inputs.clear()
  state.inputs.shrink_to_fit()
  state.available = () => false
  state.phase = UnionFinished
  true
}

///|
pub fn start_union_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[UnionExecution, UnionIssue] {
  guard @lower.sequence_step(sequence, step) is Some(@lower.GraphUnionStep(_)) else {
    return Err(InvalidUnionFold)
  }
  start_graph_composition_views(
    control, sequence, step, inputs, limits, storage_bytes, available, control_work_limit,
  )
}

///|
/// Uses the same bounded execution/cleanup owner as union, but can enter only
/// the checked subtraction step. Historical union permission is not reused.
pub fn start_subtraction_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[UnionExecution, UnionIssue] {
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphSubtractionStep(_)) else {
    return Err(InvalidUnionFold)
  }
  start_graph_composition_views(
    control, sequence, step, inputs, limits, storage_bytes, available, control_work_limit,
  )
}

///|
/// Select semantics only from the checked sequence variant. Transport/provider
/// code cannot supply a subtraction flag or replace the ordered input owner.
pub fn start_graph_composition_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int?,
) -> Result[UnionExecution, UnionIssue] {
  let owner = @lower.sequence_owner(sequence)
  let (prepared, subtraction) = match @lower.sequence_step(sequence, step) {
    Some(@lower.GraphUnionStep(prepared)) => (prepared, false)
    Some(@lower.GraphSubtractionStep(prepared)) => (prepared, true)
    _ => return Err(InvalidUnionFold)
  }
  let checked = @lower.graph_union_checked(prepared)
  if inputs.length() != @graph_type.union_input_count(checked) ||
    inputs.length() < 2 ||
    storage_bytes < 0L {
    return Err(InvalidUnionFold)
  }
  let sources = []
  for index in 0..<inputs.length() {
    let input = inputs[index]
    if @lifecycle.producer_view_kind(input) != @carrier.GraphKind ||
      !@lifecycle.producer_read_reference_matches_operation_input(
        @lifecycle.producer_view_read_reference(input),
        owner,
        step,
        index,
      ) {
      return Err(InvalidUnionFold)
    }
    sources.push(Viewed(input))
  }
  let retained_sources = sources.copy()
  let state : UnionState = {
    owner,
    step,
    checked,
    subtraction,
    inputs: sources,
    limits,
    storage_bytes,
    output_available: available,
    available: () => {
      available() && retained_sources.iter().all(graph_read_available)
    },
    remaining: Int::min(
      limits.max_work,
      control_work_limit.unwrap_or(limits.max_work),
    ),
    rows_remaining: limits.max_input_rows,
    bytes_remaining: limits.max_total_value_bytes,
    fold: 0,
    phase: PrepareUnionFold,
    active: None,
    accumulator: None,
    output: None,
    result: None,
  }
  let (session, token) = @bounded.start(
    control, state, union_step, cleanup_union_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_union(
  value : UnionExecution,
  quantum : Int,
) -> Result[UnionPoll, UnionIssue] {
  guard value.token is Some(token) else {
    return Err(UnionExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(UnionExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(UnionContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(UnionComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(UnionFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(UnionStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn union_cleanup_pending(value : UnionExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_union(value : UnionExecution) -> Result[Bool, UnionIssue] {
  @bounded.cleanup(value.session).map_err(issue => UnionExecutionIssue(issue))
}
