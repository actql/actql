///|
/// One family execution selected before runtime data access. The common Local
/// driver owns selection and lifecycle; the provider owns only typed bounded
/// kernel progress for the exact prepared sequence.
struct ManagedProvider {
  accepts : (@execution.GeneratedSequence) -> Bool
  capacity : (@execution.GeneratedSequence) -> @execution.ExecutionCapacity?
  start : (
    @execution.GeneratedSequence,
    Array[ManagedProviderInput],
    Int,
    Int,
    @execution.SequenceExecutionLimits,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue]
  /// A provider that runs selected common numeric reductions receives the
  /// task-owned reduction callbacks at start; others never see them.
  start_numeric : ((
    @execution.GeneratedSequence,
    Array[ManagedProviderInput],
    Int,
    Int,
    @execution.SequenceExecutionLimits,
    @execution.NumericAggregateExecution?,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue])?
  // A trusted Model family can delegate its exact pre-boundary Relation
  // segment to the same bounded Local owner. This is not an acceptance Bool.
  infer_relation_prefix : (
    @execution.GeneratedSequence,
    Int,
    @execution.SequenceExecutionLimits,
    @execution.FixedInputGuardMeasureLimits,
  )?
}

///|
/// One exact ordered input to a family provider. Carrier values remain
/// read-only views bound to their producer occurrence; they are not coerced
/// into Relation rows or family storage handles.
pub enum ManagedProviderInput {
  RelationInput(@execution.ProducerRead)
  SuppliedRelationInput(@execution.SuppliedRelationRead)
  CarrierInput(@carrier_runtime.ProducerView)
}

///|
pub fn managed_provider_relation_input(
  value : @execution.ProducerRead,
) -> ManagedProviderInput {
  RelationInput(value)
}

///|
pub fn managed_provider_supplied_relation_input(
  value : @execution.SuppliedRelationRead,
) -> ManagedProviderInput {
  SuppliedRelationInput(value)
}

///|
pub fn managed_provider_carrier_input(
  value : @carrier_runtime.ProducerView,
) -> ManagedProviderInput {
  CarrierInput(value)
}

///|
struct ManagedProviderExecution {
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue]
  cancel : () -> Bool
  stopped : () -> Bool
  // True confirms that cleanup is complete. False keeps cleanup pending.
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue]
  mut reported_work : Result[Int64, ManagedProviderWorkIssue]
  mut child_work_issue : () -> ManagedProviderWorkIssue?
  mut retained_completion : (() -> Bool)?
  mut cleanup_continuation : (() -> Int64)?
}

///|
/// A diagnostic accounting failure, not permission to bill or resume Compute.
pub(all) enum ManagedProviderWorkIssue {
  InvalidReport
  CounterOverflow
} derive(Eq, Debug)

///|
pub enum ManagedProviderPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Waiting(progress~ : Int64, work~ : Int64)
  Settling(Int, progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  CarrierComplete(@carrier_runtime.Material, progress~ : Int64, work~ : Int64)
  Failed(@connector.FixedComputeIssue, progress~ : Int64, work~ : Int64)
  Stopped(progress~ : Int64, work~ : Int64)
}

///|
pub fn managed_provider_carrier_complete(
  material : @carrier_runtime.Material,
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  CarrierComplete(material, progress~, work~)
}

///|
pub fn managed_provider_continue(
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Continue(progress~, work~)
}

///|
/// No Compute is ready until the existing Host supplies current authority.
/// This may report work already completed, but never invents progress.
pub fn managed_provider_waiting(
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Waiting(progress~, work~)
}

///|
/// The same Model slot remains paused until its Store custody is acknowledged.
pub fn managed_provider_settling(
  slot : Int,
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Settling(slot, progress~, work~)
}

///|
pub fn managed_provider_complete(
  output : @execution.CompletedOutput,
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Complete(output, progress~, work~)
}

///|
pub fn managed_provider_failed(
  issue : @connector.FixedComputeIssue,
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Failed(issue, progress~, work~)
}

///|
pub fn managed_provider_stopped_poll(
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Stopped(progress~, work~)
}

///|
/// Bind a trusted family package to the common Local managed driver. The
/// callbacks receive only checked sequence and exact producer handles.
pub fn managed_provider(
  accepts : (@execution.GeneratedSequence) -> Bool,
  capacity : (@execution.GeneratedSequence) -> @execution.ExecutionCapacity?,
  start : (
    @execution.GeneratedSequence,
    Array[@execution.ProducerRead],
    Int,
    Int,
    @execution.SequenceExecutionLimits,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue],
) -> ManagedProvider {
  managed_provider_with_inputs(accepts, capacity, (
    sequence,
    inputs,
    rows,
    bytes,
    execution,
  ) => {
    let relations = []
    for input in inputs {
      match input {
        RelationInput(value) => relations.push(value)
        SuppliedRelationInput(_) | CarrierInput(_) =>
          return Err(@connector.Execution(@execution.InputSet))
      }
    }
    start(sequence, relations, rows, bytes, execution)
  })
}

///|
/// Bind a provider that consumes the common ordered Relation/Carrier input
/// set. Family code still owns all semantic interpretation and kernel work.
pub fn managed_provider_with_inputs(
  accepts : (@execution.GeneratedSequence) -> Bool,
  capacity : (@execution.GeneratedSequence) -> @execution.ExecutionCapacity?,
  start : (
    @execution.GeneratedSequence,
    Array[ManagedProviderInput],
    Int,
    Int,
    @execution.SequenceExecutionLimits,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue],
) -> ManagedProvider {
  {
    accepts,
    capacity,
    start,
    start_numeric: None,
    infer_relation_prefix: None,
  }
}

///|
/// A provider whose kernel runs selected common numeric reductions. The
/// driver passes the task-owned callbacks; without them the provider starts
/// as if the task had no numeric reduction slots.
pub fn managed_provider_with_numeric(
  accepts : (@execution.GeneratedSequence) -> Bool,
  capacity : (@execution.GeneratedSequence) -> @execution.ExecutionCapacity?,
  start : (
    @execution.GeneratedSequence,
    Array[ManagedProviderInput],
    Int,
    Int,
    @execution.SequenceExecutionLimits,
    @execution.NumericAggregateExecution?,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue],
) -> ManagedProvider {
  {
    accepts,
    capacity,
    start: (sequence, inputs, rows, bytes, execution) => {
      start(sequence, inputs, rows, bytes, execution, None)
    },
    start_numeric: Some(start),
    infer_relation_prefix: None,
  }
}

///|
/// Retain the bounded Local input recipe actually used by a trusted Model
/// family. Eligibility still checks the accepted whole sequence, its exact
/// Infer boundary and the original generated prefix under this recipe.
/// This supplies neither Model authority nor a resource/cleanup admission.
pub fn managed_provider_with_infer_relation_prefix(
  provider : ManagedProvider,
  prefix : @execution.GeneratedSequence,
  boundary_step : Int,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  {
    ..provider,
    infer_relation_prefix: Some((prefix, boundary_step, execution, measurement)),
  }
}

///|
pub fn managed_provider_execution(
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue],
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
) -> ManagedProviderExecution {
  {
    advance,
    cancel,
    stopped,
    cleanup,
    reported_work: Ok(0L),
    child_work_issue: fn() { None },
    retained_completion: None,
    cleanup_continuation: None,
  }
}

///|
pub fn managed_provider_accepts(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
) -> Bool {
  (provider.accepts)(sequence)
}

///|
/// Internal composition binding, without changing the public constructor's
/// four-callback function type or creating another accounting owner.
fn managed_provider_execution_with_child_work_issue(
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue],
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
  child_work_issue : () -> ManagedProviderWorkIssue?,
) -> ManagedProviderExecution {
  let owner = managed_provider_execution(advance, cancel, stopped, cleanup)
  owner.child_work_issue = child_work_issue
  owner
}

///|
pub fn managed_provider_capacity(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
) -> @execution.ExecutionCapacity? {
  (provider.capacity)(sequence)
}

///|
pub fn start_managed_provider_with_execution(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
  inputs : Array[@execution.ProducerRead],
  max_rows : Int,
  max_value_bytes : Int,
  execution : @execution.SequenceExecutionLimits,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  (provider.start)(
    sequence,
    inputs.map(input => RelationInput(input)),
    max_rows,
    max_value_bytes,
    execution,
  )
}

///|
pub fn start_managed_provider_with_inputs_and_execution(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  max_rows : Int,
  max_value_bytes : Int,
  execution : @execution.SequenceExecutionLimits,
  numeric? : @execution.NumericAggregateExecution? = None,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  match provider.start_numeric {
    Some(start) =>
      start(sequence, inputs, max_rows, max_value_bytes, execution, numeric)
    None =>
      (provider.start)(sequence, inputs, max_rows, max_value_bytes, execution)
  }
}

///|
/// Whether the provider runs selected common numeric reductions itself.
pub fn managed_provider_runs_numeric(provider : ManagedProvider) -> Bool {
  provider.start_numeric is Some(_)
}

///|
pub fn advance_managed_provider(
  execution : ManagedProviderExecution,
  quantum : Int,
) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue] {
  let result = (execution.advance)(quantum)
  if result is Ok(poll) {
    let (progress, work) = match poll {
      Continue(progress~, work~)
      | Waiting(progress~, work~)
      | Settling(_, progress~, work~)
      | Complete(_, progress~, work~)
      | CarrierComplete(_, progress~, work~)
      | Failed(_, progress~, work~)
      | Stopped(progress~, work~) => (progress, work)
    }
    if execution.reported_work is Ok(total) {
      if progress < 0L ||
        work < 0L ||
        work > quantum.to_int64() ||
        (poll is Continue(..) && work == 0L) {
        execution.reported_work = Err(InvalidReport)
      } else if total > 9223372036854775807L - work {
        execution.reported_work = Err(CounterOverflow)
      } else {
        execution.reported_work = Ok(total + work)
      }
    }
  }
  // A composition must not turn an invalid child's unaccountable work into a
  // smaller normal parent total. Latch the fault before cleanup drops children.
  if execution.reported_work is Ok(_) &&
    (execution.child_work_issue)() is Some(issue) {
    execution.reported_work = Err(issue)
  }
  if execution.reported_work is Err(_) {
    // Accounting cannot authorize more Compute. Keep the same owner able to
    // poll its physical stop and retry cleanup even after this sticky fault.
    cancel_managed_provider(execution) |> ignore
  }
  result
}

///|
/// Sum of this owner's validated per-poll deltas, including terminal and
/// stop-only work. Reads and cleanup do not add work. Available after cleanup;
/// an overflow/invalid report remains an error, never a saturated normal total.
pub fn managed_provider_cumulative_work(
  execution : ManagedProviderExecution,
) -> Result[Int64, ManagedProviderWorkIssue] {
  execution.reported_work
}

///|
/// Charge a validated handoff delta to the SAME provider accounting owner.
/// Stage cursors validate cumulative reports before calling this function;
/// reading totals, cleanup and physical file release never synthesize work.
pub fn managed_provider_record_handoff_work(
  execution : ManagedProviderExecution,
  work : Int64,
) -> Result[Unit, ManagedProviderWorkIssue] {
  match execution.reported_work {
    Err(issue) => Err(issue)
    Ok(total) => {
      if work < 0L {
        execution.reported_work = Err(InvalidReport)
      } else if total > 9223372036854775807L - work {
        execution.reported_work = Err(CounterOverflow)
      } else {
        execution.reported_work = Ok(total + work)
      }
      match execution.reported_work {
        Ok(_) => Ok(())
        Err(issue) => {
          cancel_managed_provider(execution) |> ignore
          Err(issue)
        }
      }
    }
  }
}

///|
pub fn cancel_managed_provider(execution : ManagedProviderExecution) -> Bool {
  (execution.cancel)()
}

///|
pub fn managed_provider_stopped(execution : ManagedProviderExecution) -> Bool {
  (execution.stopped)()
}

///|
/// Retry provider-owned cleanup. True confirms complete reclamation; false
/// preserves cleanup custody for a later retry.
pub fn cleanup_managed_provider(
  execution : ManagedProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  (execution.cleanup)()
}

///|
/// Observe a stopped provider's actual finite private reclamation cursor.
/// Absent, active or externally blocked owners cannot authorize continuation.
pub fn managed_provider_cleanup_continuation(
  execution : ManagedProviderExecution,
) -> Int64 {
  if !managed_provider_stopped(execution) {
    return -1L
  }
  execution.cleanup_continuation.map(observe => observe()).unwrap_or(-1L)
}

///|
/// The same provider may separately retain a completed output and all physical
/// cleanup duties after its enclosing Local task no longer needs scratch.
/// This observation is not provider reclamation, output release or a stop ACK.
/// The original four-callback constructor and its cleanup meaning are unchanged.
pub fn managed_provider_execution_with_retained_completion(
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue],
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
  retained_completion : () -> Bool,
) -> ManagedProviderExecution {
  let owner = managed_provider_execution(advance, cancel, stopped, cleanup)
  owner.retained_completion = Some(retained_completion)
  owner
}

///|
/// Observe only the installed provider's distinct completed-scratch handoff.
/// A true value leaves its SAME cleanup handle and output obligations live.
pub fn managed_provider_retained_completion(
  execution : ManagedProviderExecution,
) -> Bool {
  (execution.stopped)() &&
  execution.retained_completion.map(check => check()).unwrap_or(false)
}
