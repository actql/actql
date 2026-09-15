///|
/// Repository-local execution adapter, not the public Connector SPI. This
/// adapter accepts completed producer inputs only; it cannot acquire sources.
struct LocalComputeAttempt {
  mut state : LocalComputeState
}

///|
priv enum LocalComputeState {
  Pending(GeneratedSequence, Array[BoundProducerInput])
  Running
  Succeeded(CompletedSequence)
  Failed(SequenceRunIssue)
  Cancelled
}

///|
pub(all) enum LocalComputeIssue {
  InvalidInputLimit
  InputLimit
  RequiresCompletedProducer(Int)
  ForeignInput(Int)
  DuplicateInput(Int)
  MissingInput(Int)
  NotComplete
  AlreadyStarted
  Cancelled
  Execution(SequenceRunIssue)
}

///|
/// Freeze only the container of already opaque completed bindings. Meaning,
/// projection and receiving resource checks still run in the sequence driver.
/// The bound limits are physical preparation entries, not logical row budgets.
pub fn prepare_local_compute_attempt(
  generated : GeneratedSequence,
  produced : Array[BoundProducerInput],
  max_entries : Int,
) -> Result[LocalComputeAttempt, LocalComputeIssue] {
  if max_entries < 0 {
    return Err(InvalidInputLimit)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  let prepared = @lower.bound_preparation(owner)
  let count = @lower.preparation_input_count(prepared)
  // Inventory + membership bookkeeping + owned input container.
  if count > max_entries || produced.length() > (max_entries - count) / 2 {
    return Err(InputLimit)
  }
  let seen : Map[Int, Bool] = Map([])
  for i = 0; i < produced.length(); i = i + 1 {
    let input = produced[i]
    if !physical_equal(input.receiver, owner) ||
      input.input_index < 0 ||
      input.input_index >= count {
      return Err(ForeignInput(i))
    }
    if seen.contains(input.input_index) {
      return Err(DuplicateInput(input.input_index))
    }
    seen[input.input_index] = true
  }
  for index = 0; index < count; index = index + 1 {
    if !@lower.preparation_input_is_produced(prepared, index) {
      return Err(RequiresCompletedProducer(index))
    }
    if !seen.contains(index) {
      return Err(MissingInput(index))
    }
  }
  Ok({ state: Pending(generated, produced.copy()), })
}

///|
/// Synchronous, one-shot execution. There is no I/O callback, alternate source,
/// runtime fallback or implicit retry. A new attempt can reuse successful input
/// handles with new limits; a failed attempt cannot manufacture success.
pub fn execute_local_compute_attempt(
  attempt : LocalComputeAttempt,
  limits : SequenceExecutionLimits,
) -> Result[CompletedSequence, LocalComputeIssue] {
  match attempt.state {
    Pending(generated, produced) => {
      attempt.state = Running
      match execute_generated_sequence(generated, [], limits, produced~) {
        Ok(completed) => {
          attempt.state = Succeeded(completed)
          Ok(completed)
        }
        Err(issue) => {
          attempt.state = Failed(issue)
          Err(Execution(issue))
        }
      }
    }
    Cancelled => Err(Cancelled)
    _ => Err(AlreadyStarted)
  }
}

///|
/// Cancel before execution only. Dropping Pending releases this attempt's
/// references, not other owners' handles. No async/in-flight cancellation is
/// claimed, and cancelling a successful producer cannot invalidate consumers.
pub fn cancel_local_compute_attempt(attempt : LocalComputeAttempt) -> Bool {
  match attempt.state {
    Pending(_, _) => {
      attempt.state = Cancelled
      true
    }
    _ => false
  }
}

///|
pub fn local_compute_result(
  attempt : LocalComputeAttempt,
) -> Result[CompletedSequence, LocalComputeIssue] {
  match attempt.state {
    Succeeded(completed) => Ok(completed)
    Failed(issue) => Err(Execution(issue))
    Cancelled => Err(Cancelled)
    Pending(_, _) | Running => Err(NotComplete)
  }
}
