///|
/// Metadata for an authenticated retained Content output. This grants neither
/// generation success nor receiving custody: only retained readmission may
/// use it with the original descriptor and verified immutable Store proof.
pub fn prepare_retained_serialization_completion(
  generated : GeneratedSequence,
  barrier : @lower.PreparedSerialization,
) -> CompletionPreparation? {
  let owner = @lower.serialization_owner(barrier)
  let step = @lower.serialization_step(barrier)
  guard physical_equal(generated_sequence_owner(generated), owner) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Serialize(_) else {
    return None
  }
  Some({
    contracts: generated.contracts,
    sequence: generated.sequence,
    retained_ids: [@lower.node_id(node)],
    selected_step: Some(step),
    selected_terminal_step: Some(step),
    serialization_output: Some(step),
  })
}

///|
/// Select the checked serialization output contract from its actual completed
/// input. Like the Infer completion preparation, this grants no success or Ref
/// authority; the installed common generation/issuance verifier must supply it.
pub fn prepare_serialization_completion(
  input : CompletedOutput,
  barrier : @lower.PreparedSerialization,
) -> CompletionPreparation? {
  let owner = @lower.serialization_owner(barrier)
  let step = @lower.serialization_step(barrier)
  let original = input.completion
  let sorted = @pipeline.serialization_sort(
      @lower.serialization_checked(barrier),
    )
    is Some(_)
  let exact_input = if sorted {
    completed_output_matches_serialization_sort(input, barrier) &&
    @lower.sequence_count(original.sequence) == step + 1
  } else {
    completed_output_matches_port(
      input,
      owner,
      @pipeline.serialization_order_input(@lower.serialization_order(barrier)),
    )
  }
  guard completed_output_available(input) &&
    !original.readmitted &&
    physical_equal(@lower.sequence_owner(original.sequence), owner) &&
    exact_input &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.payload(node) is @lower.Serialize(_) else {
    return None
  }
  Some({
    contracts: original.contracts,
    sequence: original.sequence,
    retained_ids: [@lower.node_id(node)],
    selected_step: Some(step),
    selected_terminal_step: Some(step),
    serialization_output: Some(step),
  })
}

///|
/// Borrow only the authentic checked PRESERVE ORDER input occurrence. A chain
/// child retains the full semantic sequence, not a newly compiled prefix, so
/// its sequence length is not evidence of which output actually completed.
/// The exact owner/target, receiving edge and live completion are authoritative.
pub fn serialization_completed_producer_input(
  barrier : @lower.PreparedSerialization,
  read : ProducerRead,
) -> CompletedOutput? {
  let owner = @lower.serialization_owner(barrier)
  guard @pipeline.serialization_sort(@lower.serialization_checked(barrier))
    is None &&
    producer_read_matches_operation_input(
      read,
      owner,
      @lower.serialization_step(barrier),
      0,
    ) &&
    prepare_serialization_completion(read.bound.output, barrier) is Some(_) else {
    return None
  }
  Some(read.bound.output)
}

///|
/// Prepare the checked pure segment after this authentic Content completion.
/// The source stays with its existing generation/Store owner. No encoder is
/// invoked and no Model call is authorized by constructing this view.
pub fn prepare_serialization_infer_input_segment(
  input : CompletedOutput,
  infer_step : Int,
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
) -> GeneratedSequence? {
  guard completed_output_available(input) &&
    input.target is @pipeline.Step(step) &&
    input.completion.serialization_output == Some(step) else {
    return None
  }
  let sequence = match
    @lower.prepare_serialization_infer_input_sequence(
      @lower.sequence_owner(input.completion.sequence),
      step,
      infer_step,
      limits,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  prepare_serialization_consumer_segment_sequence(
    input,
    sequence,
    step,
    infer_step - 1,
    max_work,
    max_entries,
  )
}

///|
/// Bind ordinary Relation consumers to the same live completed generation.
/// No metadata-only or restored encoder completion may substitute for this
/// borrowed output. Physical holding and cleanup stay with its existing owner.
pub fn prepare_serialization_consumer_segment(
  input : CompletedOutput,
  terminal : Int,
  limits : @lower.SequenceLimits,
  max_work : Int,
  max_entries : Int,
) -> GeneratedSequence? {
  guard completed_output_available(input) &&
    input.target is @pipeline.Step(step) &&
    input.completion.serialization_output == Some(step) else {
    return None
  }
  let sequence = match
    @lower.prepare_serialization_consumer_sequence(
      @lower.sequence_owner(input.completion.sequence),
      step,
      terminal,
      limits,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  prepare_serialization_consumer_segment_sequence(
    input, sequence, step, terminal, max_work, max_entries,
  )
}

///|
fn prepare_serialization_consumer_segment_sequence(
  input : CompletedOutput,
  sequence : @lower.PreparedSequence,
  step : Int,
  terminal_step : Int,
  max_work : Int,
  max_entries : Int,
) -> GeneratedSequence? {
  guard @lower.node_at(
      @lower.bound_preparation(@lower.sequence_owner(sequence)),
      terminal_step,
    )
    is Some(terminal) else {
    return None
  }
  let generated = match
    prepare_generated_sequence(
      input.completion.contracts,
      sequence,
      [],
      [@lower.node_id(terminal)],
      max_work,
      max_entries,
    ) {
    Ok(value) => value
    Err(_) => return None
  }
  select_generated_sequence_range(generated, step + 1, terminal_step)
}
