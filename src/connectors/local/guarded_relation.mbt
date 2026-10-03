///|
priv enum GuardedRelationPhase {
  InputGuard
  StartCompute
  Compute
  StartOutputGuard
  OutputGuard
  Finished
}

///|
priv struct GuardedRelationState {
  control : @bounded.Control
  sequence : @execution.GeneratedSequence
  provider : ManagedProvider
  input : @execution.SuppliedRelationRead
  execution : @execution.SequenceExecutionLimits
  max_rows : Int
  max_value_bytes : Int
  name_bytes : Int
  input_guard : @execution.FixedRecordGuardScan
  mut measurement : @execution.FixedInputGuardMeasureLimits
  mut output_guard : @execution.FixedRecordGuardScan?
  mut child : ManagedProviderExecution?
  mut output : @execution.CompletedOutput?
  mut phase : GuardedRelationPhase
  mut scan_work : Int64
  mut cancelled : Bool
  mut accepted : Bool
}

///|
/// Opaque custody for the checked residual. Only this owner can expose the
/// output after both guard passes; the execution handle alone is not evidence.
struct GuardedRelationExecution {
  state : GuardedRelationState
  execution : ManagedProviderExecution
}

///|
pub fn guarded_relation_execution(
  owner : GuardedRelationExecution,
) -> ManagedProviderExecution {
  owner.execution
}

///|
pub fn guarded_relation_completed_output(
  owner : GuardedRelationExecution,
) -> @execution.CompletedOutput? {
  guard owner.state.accepted &&
    !owner.state.cancelled &&
    owner.state.phase is Finished &&
    owner.state.output is Some(output) &&
    @execution.completed_output_matches_supplied_inputs(output, [
      owner.state.input,
    ]) else {
    return None
  }
  Some(output)
}

///|
pub fn start_guarded_supplied_relation(
  sequence : @execution.GeneratedSequence,
  input : @execution.SuppliedRelationRead,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_rows : Int,
  max_value_bytes : Int,
  max_name_bytes~ : Int,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  prepare_guarded_supplied_relation(
    sequence,
    input,
    execution,
    measurement,
    max_rows,
    max_value_bytes,
    max_name_bytes~,
  ).map(guarded_relation_execution)
}

///|
/// Reuse the existing Local provider and common bounded measurement sessions.
/// Acquisition guards surround Compute, sharing one remaining physical budget.
/// The completed output remains child-owned until all checks and cleanup end.
pub fn prepare_guarded_supplied_relation(
  sequence : @execution.GeneratedSequence,
  input : @execution.SuppliedRelationRead,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_rows : Int,
  max_value_bytes : Int,
  max_name_bytes~ : Int,
) -> Result[GuardedRelationExecution, @connector.FixedComputeIssue] {
  guard max_rows >= 0 &&
    max_value_bytes >= 0 &&
    max_name_bytes >= 0 &&
    @execution.supplied_relation_read_matches_input(
      input,
      @execution.generated_sequence_owner(sequence),
      0,
    ) else {
    return Err(@connector.InvalidLimits)
  }
  guard local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) else {
    return Err(@connector.ComputeUnsupported)
  }
  let control = @bounded.control()
  let input_guard = match
    @execution.start_supplied_record_guard(
      control,
      input,
      max_value_bytes,
      measurement,
      execution.rows.operation_entries,
    ) {
    Ok(value) => value
    Err(issue) => return Err(@connector.Guard(issue))
  }
  let state : GuardedRelationState = {
    control,
    sequence,
    provider,
    input,
    execution,
    max_rows,
    max_value_bytes,
    name_bytes: max_name_bytes,
    input_guard,
    measurement,
    output_guard: None,
    child: None,
    output: None,
    phase: InputGuard,
    scan_work: 0L,
    cancelled: false,
    accepted: false,
  }
  let child_execution = managed_provider_execution_with_child_work_issue(
    quantum => advance_guarded_relation(state, quantum),
    fn() {
      if state.cancelled || state.phase is Finished {
        return false
      }
      state.cancelled = true
      @bounded.request_cancel(state.control) |> ignore
      if state.child is Some(child) {
        cancel_managed_provider(child) |> ignore
      }
      true
    },
    fn() { state.phase is Finished },
    fn() {
      if !(state.phase is Finished) {
        return Ok(false)
      }
      match @execution.cleanup_fixed_record_guard(state.input_guard) {
        Ok(true) => ()
        _ => return Ok(false)
      }
      if state.output_guard is Some(scan) {
        match @execution.cleanup_fixed_record_guard(scan) {
          Ok(true) => ()
          _ => return Ok(false)
        }
      }
      if state.child is Some(child) {
        match cleanup_managed_provider(child) {
          Ok(true) => ()
          other => return other
        }
      }
      state.output = None
      state.accepted = false
      Ok(true)
    },
    fn() {
      match state.child {
        Some(child) =>
          match managed_provider_cumulative_work(child) {
            Err(issue) => Some(issue)
            Ok(_) => None
          }
        None => None
      }
    },
  )
  Ok({ state, execution: child_execution, })
}

///|
fn guarded_relation_failure(
  state : GuardedRelationState,
  issue : @connector.FixedComputeIssue,
  work : Int64,
) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue] {
  state.phase = Finished
  Ok(managed_provider_failed(issue, work, work))
}

///|
fn advance_guarded_relation(
  state : GuardedRelationState,
  quantum : Int,
) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue] {
  if quantum <= 0 || state.phase is Finished {
    return Err(@connector.InvalidLimits)
  }
  match state.phase {
    InputGuard | OutputGuard => {
      let before_compute = state.phase is InputGuard
      let scan = if before_compute {
        state.input_guard
      } else {
        state.output_guard.unwrap()
      }
      let poll = match @execution.advance_fixed_record_guard(scan, quantum) {
        Ok(value) => value
        Err(_) => return Err(@connector.InvalidLimits)
      }
      let work = match poll {
        @bounded.ContinueWith(_, work~, ..)
        | @bounded.Completed(_, work~, ..)
        | @bounded.FailedWith(_, work~, ..)
        | @bounded.StoppedWith(_, work~, ..) => work
      }
      let delta = work - state.scan_work
      state.scan_work = work
      match poll {
        @bounded.ContinueWith(_, ..) =>
          Ok(managed_provider_continue(delta, delta))
        @bounded.FailedWith(issue, ..) =>
          guarded_relation_failure(state, @connector.Guard(issue), delta)
        @bounded.StoppedWith(_, ..) => {
          state.phase = Finished
          Ok(managed_provider_stopped_poll(delta, delta))
        }
        @bounded.Completed(remaining, ..) => {
          state.measurement = remaining
          if before_compute {
            // Free the measurement envelope before admitting Compute storage.
            guard @execution.cleanup_fixed_record_guard(scan) is Ok(true) else {
              return Err(@connector.InvalidLimits)
            }
            state.phase = StartCompute
            Ok(managed_provider_continue(delta, delta))
          } else {
            state.phase = Finished
            state.accepted = true
            Ok(managed_provider_complete(state.output.unwrap(), delta, delta))
          }
        }
      }
    }
    StartCompute | StartOutputGuard => {
      if state.cancelled {
        state.phase = Finished
        return Ok(managed_provider_stopped_poll(0L, 0L))
      }
      if state.measurement.max_work < 1 {
        return guarded_relation_failure(
          state,
          @connector.Guard(@execution.MeasurementWork),
          0L,
        )
      }
      // Account the bounded phase setup separately from either child's work.
      state.measurement = {
        ..state.measurement,
        max_work: state.measurement.max_work - 1,
      }
      if state.phase is StartCompute {
        let child = match
          start_managed_provider_with_inputs_and_execution(
            state.provider,
            state.sequence,
            [managed_provider_supplied_relation_input(state.input)],
            state.max_rows,
            state.name_bytes,
            state.execution,
          ) {
          Ok(value) => value
          Err(issue) => return guarded_relation_failure(state, issue, 1L)
        }
        state.child = Some(child)
        state.phase = Compute
      } else {
        let output = state.output.unwrap()
        if @execution.completed_row_count(output) > state.max_rows {
          return guarded_relation_failure(
            state,
            @connector.Guard(@execution.OutputRows),
            1L,
          )
        }
        let scan = match
          @execution.start_completed_record_guard(
            state.control,
            output,
            state.max_value_bytes,
            state.measurement,
            state.execution.rows.operation_entries,
          ) {
          Ok(value) => value
          Err(issue) =>
            return guarded_relation_failure(state, @connector.Guard(issue), 1L)
        }
        state.output_guard = Some(scan)
        state.scan_work = 0L
        state.phase = OutputGuard
      }
      Ok(managed_provider_continue(1L, 1L))
    }
    Compute => {
      let poll = match advance_managed_provider(state.child.unwrap(), quantum) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match poll {
        Complete(output, progress~, work~) => {
          guard @execution.anchor_completed_output_supplied_inputs(output, [
              state.input,
            ])
            is Some(anchored) else {
            return guarded_relation_failure(
              state,
              @connector.InputUnavailable,
              work,
            )
          }
          state.output = Some(anchored)
          state.phase = StartOutputGuard
          // A zero-work child handoff may perform the next bounded setup now;
          // never manufacture work or return an invalid zero-work Continue.
          if work == 0L {
            return advance_guarded_relation(state, quantum)
          }
          Ok(managed_provider_continue(progress, work))
        }
        Failed(_, ..) | Stopped(..) => {
          state.phase = Finished
          Ok(poll)
        }
        CarrierComplete(_, progress~, work~) => {
          state.phase = Finished
          Ok(
            managed_provider_failed(
              @connector.ComputeUnsupported,
              progress,
              work,
            ),
          )
        }
        Continue(..) => Ok(poll)
      }
    }
    Finished => Err(@connector.InvalidLimits)
  }
}
