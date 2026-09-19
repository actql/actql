///|
/// One family execution selected before runtime data access. The common Local
/// driver owns selection and lifecycle; the provider owns only typed bounded
/// kernel progress for the exact prepared sequence.
struct ManagedProvider {
  accepts : (@execution.GeneratedSequence) -> Bool
  capacity : (@execution.GeneratedSequence) -> @execution.ExecutionCapacity?
  start : (
    @execution.GeneratedSequence,
    Array[@execution.ProducerRead],
    Int,
    Int,
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue]
}

///|
struct ManagedProviderExecution {
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue]
  cancel : () -> Bool
  stopped : () -> Bool
  // True confirms that cleanup is complete. False keeps cleanup pending.
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue]
}

///|
pub enum ManagedProviderPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  Failed(@connector.FixedComputeIssue, progress~ : Int64, work~ : Int64)
  Stopped(progress~ : Int64, work~ : Int64)
}

///|
pub fn managed_provider_continue(
  progress : Int64,
  work : Int64,
) -> ManagedProviderPoll {
  Continue(progress~, work~)
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
  ) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue],
) -> ManagedProvider {
  { accepts, capacity, start, }
}

///|
pub fn managed_provider_execution(
  advance : (Int) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue],
  cancel : () -> Bool,
  stopped : () -> Bool,
  cleanup : () -> Result[Bool, @connector.FixedComputeIssue],
) -> ManagedProviderExecution {
  { advance, cancel, stopped, cleanup, }
}

///|
pub fn managed_provider_accepts(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
) -> Bool {
  (provider.accepts)(sequence)
}

///|
pub fn managed_provider_capacity(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
) -> @execution.ExecutionCapacity? {
  (provider.capacity)(sequence)
}

///|
pub fn start_managed_provider(
  provider : ManagedProvider,
  sequence : @execution.GeneratedSequence,
  inputs : Array[@execution.ProducerRead],
  max_rows : Int,
  max_value_bytes : Int,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  (provider.start)(sequence, inputs, max_rows, max_value_bytes)
}

///|
pub fn advance_managed_provider(
  execution : ManagedProviderExecution,
  quantum : Int,
) -> Result[ManagedProviderPoll, @connector.FixedComputeIssue] {
  (execution.advance)(quantum)
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
