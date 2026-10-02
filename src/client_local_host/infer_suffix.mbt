///|
/// Start an already prepared Compute suffix with retained, exact completions.
/// Input views keep each operation port distinct, including repeated reads.
/// The caller retains the producing owners until this child is reclaimed.
pub fn start_client_infer_suffix(
  sequence : @execution.GeneratedSequence,
  outputs : Array[@execution.CompletedOutput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> Result[@local.ManagedProviderExecution, ClientInferInputIssue] {
  guard @execution.generated_sequence_step_index_at(sequence, 0) is Some(first) &&
    @local.local_bounded_relation_provider(execution, measurement, sequence)
    is Some(provider) else {
    return Err(UnsupportedProgram)
  }
  let owner = @execution.generated_sequence_owner(sequence)
  let inputs : Array[@local.ManagedProviderInput] = []
  for position in 0..<@execution.generated_sequence_step_count(sequence) {
    guard @execution.generated_sequence_step_index_at(sequence, position)
      is Some(step) &&
      @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
      return Err(UnsupportedProgram)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(@pipeline.Step(source)) else {
        return Err(UnsupportedProgram)
      }
      if source >= first {
        continue
      }
      let mut selected : @execution.BoundProducerInput? = None
      for output in outputs {
        match
          @execution.bind_completed_operation_input(
            owner, step, port, owner, output,
          ) {
          Ok(bound) => {
            if selected is Some(_) {
              return Err(UnsupportedProgram)
            }
            selected = Some(bound)
          }
          Err(_) => ()
        }
      }
      guard selected is Some(bound) else { return Err(UnsupportedProgram) }
      let read = match
        @execution.prepare_producer_read(
          owner,
          bound,
          execution.rows.operation_entries,
          measurement.max_bytes,
        ) {
        Ok(read) => read
        Err(issue) => return Err(ProducerRead(issue))
      }
      inputs.push(@local.managed_provider_relation_input(read))
    }
  }
  @local.start_managed_provider_with_inputs_and_execution(
    provider,
    sequence,
    inputs,
    execution.rows.max_rows,
    measurement.max_bytes,
    execution,
  ).map_err(issue => Local(issue))
}
