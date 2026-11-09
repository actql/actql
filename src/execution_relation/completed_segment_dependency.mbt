///|
// Data-only proof for a single-input checked segment. The real completion must
// retain the exact operation binding it consumed, not merely equal source rows.
// This issues no completion, reservation, Source permission or Model grant.
pub fn completed_output_matches_segment_input(
  output : CompletedOutput,
  input : ProducerRead,
) -> Bool {
  guard completed_output_available(output) &&
    producer_read_available(input) &&
    output.target is @pipeline.Step(terminal) &&
    input.bound.consumer_step is Some(first) &&
    first <= terminal &&
    producer_read_binding_matches_operation_input(
      input,
      @lower.sequence_owner(output.completion.sequence),
      first,
      0,
    ) else {
    return false
  }
  // Managed bounded chains re-admit their terminal representation. Their
  // terminal port bindings are not the segment's first external port. Compare
  // the retained original producer anchor, WITHOUT changing those bindings or
  // promoting a readmitted fact to pending-task completion evidence.
  for anchor in output.completion._producer_inputs {
    if physical_equal(anchor, input.bound) {
      return true
    }
  }
  false
}

///|
// Ownership-only bridge for the closed segment receiver. As with the existing
// input-anchor APIs, its trusted caller MUST supply the exact read given to the
// actual execution, never an equal-looking replacement. Preserve result identity,
// terminal receiving bindings, readmitted status and original liveness. This
// cannot manufacture success or authorize completion of a pending task.
pub fn retain_completed_segment_input(
  output : CompletedOutput,
  input : ProducerRead,
) -> CompletedOutput? {
  guard completed_output_available(output) &&
    producer_read_available(input) &&
    output.target is @pipeline.Step(terminal) &&
    input.bound.consumer_step is Some(first) &&
    first <= terminal &&
    producer_read_binding_matches_operation_input(
      input,
      @lower.sequence_owner(output.completion.sequence),
      first,
      0,
    ) else {
    return None
  }
  let anchors = output.completion._producer_inputs.copy()
  anchors.push(input.bound)
  let completion = { ..output.completion, _producer_inputs: anchors, }
  Some({ ..output, completion, })
}

///|
// The captured Source owner uses this predicate to compare its real original
// completion to a prepared operation read without exposing either raw value.
pub fn producer_read_matches_completed_output(
  input : ProducerRead,
  output : CompletedOutput,
) -> Bool {
  producer_read_available(input) &&
  completed_output_same_occurrence(output, input.bound.output)
}

///|
/// Immutable provenance of an operation that has already completed. The
/// scheduler may clear its temporary ProducerRead slot after commit; the sealed
/// completion retains the exact consumed binding. This is not availability,
/// pending-task completion authority or permission to execute another operation.
pub fn completed_output_has_original_operation_input(
  output : CompletedOutput,
  original : CompletedOutput,
  input_index : Int,
) -> Bool {
  guard !output.completion.readmitted &&
    output.target is @pipeline.Step(step) &&
    output.completion.input_bindings.get(input_index) is Some(identity) else {
    return false
  }
  let receiver = @lower.sequence_owner(output.completion.sequence)
  for anchor in output.completion._producer_inputs {
    if physical_equal(anchor.identity, identity) &&
      physical_equal(anchor.receiver, receiver) &&
      anchor.consumer_step == Some(step) &&
      anchor.input_index == input_index &&
      bound_producer_input_has_original_completion(anchor, original) {
      return true
    }
  }
  false
}

///|
fn bound_producer_input_has_original_completion(
  bound : BoundProducerInput,
  original : CompletedOutput,
) -> Bool {
  physical_equal(
    bound.output.completion.result_identity,
    original.completion.result_identity,
  ) &&
  bound.output.target == original.target
}

///|
/// Immutable ordinary input provenance retained by the already-started managed
/// task. This neither invokes its availability callback nor grants a new use.
pub fn managed_input_binding_has_original_completion(
  binding : ManagedInputBinding,
  original : CompletedOutput,
) -> Bool {
  match binding.ordinary {
    Some(input) =>
      bound_producer_input_has_original_completion(input.bound, original)
    None => false
  }
}
