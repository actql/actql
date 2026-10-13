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
    !output.completion.readmitted &&
    output.target is @pipeline.Step(terminal) &&
    input.bound.consumer_step is Some(first) &&
    first <= terminal &&
    output.completion.input_bindings.length() == 1 &&
    physical_equal(output.completion.input_bindings[0], input.bound.identity) &&
    producer_read_binding_matches_operation_input(
      input,
      @lower.sequence_owner(output.completion.sequence),
      first,
      0,
    ) else {
    return false
  }
  true
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
