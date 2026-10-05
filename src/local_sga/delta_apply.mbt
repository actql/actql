///|
priv enum DeltaApplyPhase {
  PreparingInput
  StartApplication
  Applying
  CompleteOutput
  DeltaApplyFinished
}

///|
priv struct DeltaApplyState {
  mut input : DeltaApplyInputPreparation?
  mut preparation : @delta.ApplyPreparation?
  mut output : @graph.OutputBuilder?
  mut inputs_available : () -> Bool
  mut result : @storage.Storage?
  mut remaining : Int?
  mut phase : DeltaApplyPhase
}

///|
struct DeltaApplyExecution {
  session : @bounded.Session[DeltaApplyState, @graph.Completed, DeltaApplyIssue]
  mut token : @bounded.Token?
}

///|
pub(all) enum DeltaApplyIssue {
  InvalidDeltaApplyKernel
  DeltaApplyInvalidInput
  DeltaApplyWorkspaceLimit
  DeltaApplyInputUnavailable
  DeltaApplyControlWorkLimit
  DeltaApplyKernel(@delta.Issue)
  DeltaApplyOutput(@graph.Issue)
  DeltaApplyExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
pub enum DeltaApplyPoll {
  DeltaApplyContinue(progress~ : Int64, work~ : Int64)
  DeltaApplyComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  DeltaApplyFailed(DeltaApplyIssue, progress~ : Int64, work~ : Int64)
  DeltaApplyStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn delta_apply_step(
  state : DeltaApplyState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, DeltaApplyIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if !(state.inputs_available)() {
    return @bounded.Failed(DeltaApplyInputUnavailable, 0, 0)
  }
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  let budget = match state.remaining {
    Some(remaining) => {
      if remaining < 1 {
        return @bounded.Failed(DeltaApplyControlWorkLimit, 0, 0)
      }
      Int::min(quantum, remaining)
    }
    None => quantum
  }
  match state.phase {
    PreparingInput => {
      guard state.input is Some(input) else {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      let poll = match advance_delta_apply_input(input, budget) {
        Ok(poll) => poll
        Err(issue) => return @bounded.Failed(issue, 0, 0)
      }
      let work = match poll {
        DeltaApplyInputContinue(work~)
        | DeltaApplyInputReady(work~)
        | DeltaApplyInputFailed(_, work~) => work
      }
      if work < 0 ||
        work > budget ||
        (poll is DeltaApplyInputContinue(..) && work == 0) {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      if state.remaining is Some(remaining) {
        state.remaining = Some(remaining - work)
      }
      match poll {
        DeltaApplyInputContinue(..) => @bounded.Continue(0, work)
        DeltaApplyInputReady(..) => {
          state.phase = StartApplication
          @bounded.Continue(0, work)
        }
        DeltaApplyInputFailed(issue, ..) => @bounded.Failed(issue, 0, work)
      }
    }
    StartApplication => {
      guard state.input is Some(input) else {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      // The envelope's fixed header and the one-use handoff consume one unit.
      // No Graph configuration walk is repeated, and the same remaining budget
      // continues into action admission, application and output completion.
      if state.remaining is Some(remaining) {
        state.remaining = Some(remaining - 1)
      }
      match claim_delta_apply_input(input) {
        Err(issue) => @bounded.Failed(issue, 0, 1)
        Ok((preparation, output, current)) => {
          state.input = None
          state.preparation = Some(preparation)
          state.output = Some(output)
          state.inputs_available = current
          state.phase = Applying
          @bounded.Continue(0, 1)
        }
      }
    }
    Applying => {
      guard state.preparation is Some(preparation) else {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      let poll = match @delta.advance_apply(preparation, budget) {
        Ok(poll) => poll
        Err(issue) => return @bounded.Failed(DeltaApplyKernel(issue), 0, 0)
      }
      let (progress, work) = match poll {
        @delta.ApplyContinue(progress~, work~)
        | @delta.ApplyComplete(_, progress~, work~)
        | @delta.ApplyFailed(_, progress~, work~) => (progress, work)
      }
      // Preserve even an unpublishable result before validating its report, so
      // the existing session's cleanup cannot lose transferred kernel custody.
      if poll is @delta.ApplyComplete(result, ..) {
        state.result = Some(result)
        state.phase = CompleteOutput
      }
      if work < 0L ||
        work > budget.to_int64() ||
        progress < 0L ||
        progress > work ||
        (poll is @delta.ApplyContinue(..) && work == 0L) {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      if state.remaining is Some(remaining) {
        state.remaining = Some(remaining - work.to_int())
      }
      match poll {
        @delta.ApplyFailed(issue, ..) =>
          @bounded.Failed(
            DeltaApplyKernel(issue),
            progress.to_int(),
            work.to_int(),
          )
        _ => @bounded.Continue(progress.to_int(), work.to_int())
      }
    }
    CompleteOutput => {
      guard state.result is Some(result) && state.output is Some(output) else {
        return @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
      }
      if state.remaining is Some(remaining) {
        state.remaining = Some(remaining - 1)
      }
      state.result = None
      state.output = None
      state.phase = DeltaApplyFinished
      // The same output builder issued this Storage, and the existing Graph
      // retention verifier performs current availability checks before receipt.
      match @graph.finish_output_storage(output, result) {
        Ok(completed) => @bounded.Complete(completed, 1, 1)
        Err(issue) => {
          // Closed/foreign-port refusal deliberately does not claim payload
          // custody. This session still owns its transferred kernel result.
          @storage.discard(result)
          @bounded.Failed(DeltaApplyOutput(issue), 0, 1)
        }
      }
    }
    DeltaApplyFinished => @bounded.Failed(InvalidDeltaApplyKernel, 0, 0)
  }
}

///|
fn cleanup_delta_apply_state(state : DeltaApplyState) -> Bool {
  if state.input is Some(input) {
    cleanup_delta_input(input)
    state.input = None
  }
  if state.preparation is Some(preparation) {
    @delta.cleanup_apply(preparation) |> ignore
    state.preparation = None
  }
  if state.result is Some(result) {
    @storage.discard(result)
    state.result = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.inputs_available = () => false
  state.phase = DeltaApplyFinished
  true
}

///|
/// Resume a prepared application on the existing bounded execution and Graph
/// output owners. The caller must separately bind/admit both checked operands
/// and resolve preparation resources; this API is not a normal Plan selector.
/// Ownership transfers only after successful start. An unsuccessful start
/// leaves both the preparation and output with their original caller.
pub fn start_prepared_delta_apply(
  control : @bounded.Control,
  preparation : @delta.ApplyPreparation,
  output : @graph.OutputBuilder,
  inputs_available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[DeltaApplyExecution, DeltaApplyIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(DeltaApplyControlWorkLimit)
  }
  guard @graph.output_storage_builder(output) is Some(builder) &&
    @delta.apply_uses_output_builder(preparation, builder) else {
    return Err(InvalidDeltaApplyKernel)
  }
  let state : DeltaApplyState = {
    input: None,
    preparation: Some(preparation),
    output: Some(output),
    inputs_available,
    result: None,
    remaining: control_work_limit,
    phase: Applying,
  }
  let (session, token) = @bounded.start(
    control, state, delta_apply_step, cleanup_delta_apply_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
/// Bind both checked inputs during cold setup, then charge Relation conversion,
/// action admission, application and completion to the same bounded session.
/// This does not select a Plan or discharge its installed resource obligations.
pub fn start_delta_apply_inputs(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  base : @lifecycle.ProducerView,
  rows : @execution.ProducerRead,
  limits : @delta.Limits,
  storage_limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[DeltaApplyExecution, DeltaApplyIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(DeltaApplyControlWorkLimit)
  }
  let input = match
    prepare_delta_apply_input(
      sequence, step, base, rows, limits, storage_limits, storage_bytes, available,
    ) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  let state : DeltaApplyState = {
    input: Some(input),
    preparation: None,
    output: None,
    inputs_available: fn() { delta_input_available(input) },
    result: None,
    remaining: control_work_limit,
    phase: PreparingInput,
  }
  let (session, token) = @bounded.start(
    control, state, delta_apply_step, cleanup_delta_apply_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_delta_apply(
  value : DeltaApplyExecution,
  quantum : Int,
) -> Result[DeltaApplyPoll, DeltaApplyIssue] {
  guard value.token is Some(token) else {
    return Err(DeltaApplyExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(DeltaApplyExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(DeltaApplyContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(DeltaApplyComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(DeltaApplyFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(DeltaApplyStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn delta_apply_cleanup_pending(value : DeltaApplyExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_delta_apply(
  value : DeltaApplyExecution,
) -> Result[Bool, DeltaApplyIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    DeltaApplyExecutionIssue(issue)
  })
}
