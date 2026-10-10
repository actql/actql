///|
priv enum MeanPhase {
  AdmitMeanView
  PrepareMeanOutput
  ExecuteMeanFold
  CompleteMeanOutput
  MeanFinished
}

///|
priv struct MeanState {
  owner : @lower.BoundPrepared
  step : Int
  checked : @graph_type.CheckedMean
  views : Array[@lifecycle.ProducerView]
  sources : Array[GraphReadSource]
  reservation : MeanReservation
  storage_bytes : Int64
  mut available : () -> Bool
  mut remaining : Int
  mut admitted : Int
  mut phase : MeanPhase
  mut active : MeanFold?
  mut output : @graph.OutputBuilder?
  mut result : @storage.Storage?
}

///|
pub(all) enum MeanIssue {
  InvalidMeanExecution
  MeanInputBinding
  MeanResources(MeanResourceIssue)
  MeanFoldFailure(MeanFoldIssue)
  MeanOutputFailure(@graph.Issue)
  MeanExecutionFailure(@bounded.Issue)
} derive(Eq, Debug)

///|
struct MeanExecution {
  session : @bounded.Session[MeanState, @graph.Completed, MeanIssue]
  mut token : @bounded.Token?
}

///|
pub enum MeanPoll {
  MeanContinue(progress~ : Int64, work~ : Int64)
  MeanComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  MeanFailed(MeanIssue, progress~ : Int64, work~ : Int64)
  MeanStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn mean_step(
  state : MeanState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, MeanIssue] {
  // This includes the yield after private storage finishes, before Material
  // can be issued. Stop observation never transfers the input generations.
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if !(state.available)() {
    return @bounded.Failed(MeanInputBinding, 0, 0)
  }
  if state.remaining < 1 {
    return @bounded.Failed(MeanFoldFailure(MeanFoldWorkLimit), 0, 0)
  }
  let budget = Int::min(quantum, state.remaining)
  match state.phase {
    AdmitMeanView => {
      state.remaining -= 1
      if state.admitted < state.views.length() {
        let input = state.views[state.admitted]
        if @lifecycle.producer_view_kind(input) != @carrier.GraphKind ||
          !@lifecycle.producer_read_reference_matches_operation_input(
            @lifecycle.producer_view_read_reference(input),
            state.owner,
            state.step,
            state.admitted,
          ) ||
          !graph_read_available(Viewed(input)) {
          return @bounded.Failed(MeanInputBinding, 0, 1)
        }
        state.sources.push(Viewed(input))
        state.admitted += 1
      } else {
        state.phase = PrepareMeanOutput
      }
      @bounded.Continue(0, 1)
    }
    PrepareMeanOutput => {
      state.remaining -= 1
      let limits = {
        ..mean_reserved_output_limits(state.reservation),
        max_work: state.remaining,
      }
      let output = match
        @graph.prepare_output(
          state.owner,
          @pipeline.Step(state.step),
          DeclaredNodes,
          limits,
          state.storage_bytes,
          state.available,
        ) {
        Ok(output) => output
        Err(issue) => return @bounded.Failed(MeanOutputFailure(issue), 0, 1)
      }
      state.output = Some(output)
      guard @graph.output_storage_builder(output) is Some(builder) else {
        return @bounded.Failed(InvalidMeanExecution, 0, 1)
      }
      state.active = match
        prepare_mean_fold(
          state.checked,
          state.sources,
          builder,
          limits,
          state.remaining,
          mean_reserved_arithmetic(state.reservation),
        ) {
        Ok(active) => Some(active)
        Err(issue) => return @bounded.Failed(MeanFoldFailure(issue), 0, 1)
      }
      state.phase = ExecuteMeanFold
      @bounded.Continue(0, 1)
    }
    ExecuteMeanFold => {
      guard state.active is Some(active) else {
        return @bounded.Failed(InvalidMeanExecution, 0, 0)
      }
      let poll = advance_mean_fold(active, budget)
      let work = match poll {
        MeanFoldContinue(work)
        | MeanFoldComplete(_, work)
        | MeanFoldFailed(_, work) => work
      }
      if poll is MeanFoldComplete(storage, _) {
        state.result = Some(storage)
      }
      if work < 0 || work > budget || (poll is MeanFoldContinue(_) && work == 0) {
        return @bounded.Failed(InvalidMeanExecution, 0, 0)
      }
      state.remaining -= work
      match poll {
        MeanFoldContinue(_) => @bounded.Continue(0, work)
        MeanFoldFailed(issue, _) =>
          @bounded.Failed(MeanFoldFailure(issue), 0, work)
        MeanFoldComplete(_, _) => {
          cleanup_mean_fold(active)
          state.active = None
          state.phase = CompleteMeanOutput
          @bounded.Continue(0, work)
        }
      }
    }
    CompleteMeanOutput => {
      state.remaining -= 1
      guard state.result is Some(result) && state.output is Some(output) else {
        return @bounded.Failed(InvalidMeanExecution, 0, 1)
      }
      match @graph.finish_output_storage(output, result) {
        Ok(completed) => {
          state.result = None
          state.output = None
          state.phase = MeanFinished
          @bounded.Complete(completed, 1, 1)
        }
        Err(issue) => @bounded.Failed(MeanOutputFailure(issue), 0, 1)
      }
    }
    MeanFinished => @bounded.Failed(InvalidMeanExecution, 0, 0)
  }
}

///|
fn cleanup_mean_state(state : MeanState) -> Bool {
  if state.active is Some(active) {
    cleanup_mean_fold(active)
    state.active = None
  }
  if state.result is Some(storage) {
    @storage.discard(storage)
    state.result = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  // Views are borrowed from existing task holders. Only this session's
  // references and private reservations end here, after physical stop.
  state.sources.clear()
  state.sources.shrink_to_fit()
  state.views.clear()
  state.views.shrink_to_fit()
  state.available = () => false
  state.phase = MeanFinished
  true
}

///|
pub fn start_mean_views(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@lifecycle.ProducerView],
  limits : @storage.Limits,
  profile : MeanLimits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[MeanExecution, MeanIssue] {
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphMeanStep(prepared)) else {
    return Err(InvalidMeanExecution)
  }
  let checked = @lower.graph_mean_checked(prepared)
  if inputs.length() !=
    @graph_type.mean_sample_count(@graph_type.checked_mean_options(checked)) ||
    storage_bytes < 0L {
    return Err(InvalidMeanExecution)
  }
  let reservation = match prepare_mean_reservation(checked, limits, profile) {
    Ok(reservation) => reservation
    Err(issue) => return Err(MeanResources(issue))
  }
  let state : MeanState = {
    owner: @lower.sequence_owner(sequence),
    step,
    checked,
    views: inputs.copy(),
    sources: [],
    reservation,
    storage_bytes,
    available,
    remaining: Int::min(
      limits.max_work,
      control_work_limit.unwrap_or(limits.max_work),
    ),
    admitted: 0,
    phase: AdmitMeanView,
    active: None,
    output: None,
    result: None,
  }
  let (session, token) = @bounded.start(
    control, state, mean_step, cleanup_mean_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_mean(
  value : MeanExecution,
  quantum : Int,
) -> Result[MeanPoll, MeanIssue] {
  guard value.token is Some(token) else {
    return Err(MeanExecutionFailure(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(MeanExecutionFailure(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(MeanContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(MeanComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(MeanFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(MeanStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn mean_cleanup_pending(value : MeanExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_mean(value : MeanExecution) -> Result[Bool, MeanIssue] {
  @bounded.cleanup(value.session).map_err(issue => MeanExecutionFailure(issue))
}
