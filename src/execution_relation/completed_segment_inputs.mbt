///|
// Borrowed provenance for an actual completed segment and all the original
// operation ports passed to its provider. This is not a completion issuer,
// execution owner, reservation or permission. Its caller funds the copied
// inventory before construction and retains the provider until borrowers stop.
struct CompletedSegmentInputs {
  output : CompletedOutput
  sequence : GeneratedSequence
  inputs : CompletedSegmentInputInventory
}

///|
// Two views of the SAME ordered proof. Ordinary callers retain their exact
// signatures and read references; fixed callers also retain supplied ports.
// The fixed variant control uses the existing Common fixed owner overhead.
priv enum CompletedSegmentInputInventory {
  Ordinary(Array[(Int, Int, ProducerRead)])
  Fixed(Array[(Int, Int, FixedRelationRead)])
}

///|
// This record and its copied reference array only. Tuple/read/sequence/output
// originals are borrowed; their construction and lifetime overlap remain the
// caller's separate inventory. No scalar here grants physical capacity.
pub fn completed_segment_inputs_construction_inventory(
  input_count : Int,
) -> PreparationRepresentationUnits? {
  if input_count < 0 {
    return None
  }
  guard @shape.reference_array_retained_extent(1L, input_count.to_int64())
    is Some(copied) else {
    return None
  }
  Some({
    record_headers: 1L + copied.record_headers,
    reference_slots: 3L + copied.reference_slots,
    scalar_words: copied.scalar_words,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  })
}

///|
// A bounded walk of the selected original graph, not a count-only assertion.
// Every external edge must occur exactly once in step/port order. In-segment
// producers are executed by the provider and cannot be supplied as captures.
fn[T] completed_segment_inputs_shape(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  inputs : Array[(Int, Int, T)],
  max_work : Int,
  matches : (T, @lower.BoundPrepared, Int, Int) -> Bool,
) -> Bool {
  let count = generated_sequence_step_count(sequence)
  guard max_work > 0 &&
    count > 0 &&
    count <= max_work &&
    inputs.length() <= max_work &&
    physical_equal(
      @lower.sequence_owner(output.completion.sequence),
      generated_sequence_owner(sequence),
    ) &&
    generated_sequence_step_index_at(sequence, count - 1) is Some(terminal) &&
    output.target == @pipeline.Step(terminal) else {
    return false
  }
  let owner = generated_sequence_owner(sequence)
  let mut work = 0
  let mut next = 0
  for position in 0..<count {
    guard generated_sequence_step_index_at(sequence, position) is Some(step) &&
      @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
      return false
    }
    for port in 0..<@lower.node_input_count(node) {
      if work >= max_work {
        return false
      }
      work += 1
      guard @lower.node_input_target(node, port) is Some(target) else {
        return false
      }
      let mut internal = false
      if target is @pipeline.Step(producer) {
        for previous in 0..<position {
          if work >= max_work {
            return false
          }
          work += 1
          if generated_sequence_step_index_at(sequence, previous) ==
            Some(producer) {
            internal = true
            break
          }
        }
      }
      if !internal {
        guard inputs.get(next) is Some((consumer, edge, read)) &&
          consumer == step &&
          edge == port &&
          matches(read, owner, step, port) else {
          return false
        }
        next += 1
      }
    }
  }
  next == inputs.length()
}

///|
// Closed provider caller only: it supplies exactly the reads used by this
// execution. Neither equal rows nor an independently rebound input substitutes
// for those originals. Output identity, bindings and readmitted status stay
// unchanged. Successful construction never completes a pending graph task.
pub fn retain_completed_segment_inputs(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  inputs : Array[(Int, Int, ProducerRead)],
  max_work : Int,
) -> CompletedSegmentInputs? {
  if max_work <= 0 || inputs.length() > max_work {
    return None
  }
  // Copy before liveness callbacks can mutate the caller's inventory.
  let inputs = inputs.copy()
  if !completed_segment_inputs_shape(
      output, sequence, inputs, max_work, producer_read_binding_matches_operation_input,
    ) {
    return None
  }
  for (_, _, read) in inputs {
    if !producer_read_available(read) {
      return None
    }
  }
  if !completed_output_available(output) {
    return None
  }
  Some({ output, sequence, inputs: Ordinary(inputs), })
}

///|
// The full exact inventory is required at every borrow. A shortened suffix,
// duplicate, reordered port or same-wire rebound cannot borrow this result.
pub fn completed_segment_inputs_output(
  value : CompletedSegmentInputs,
  sequence : GeneratedSequence,
  inputs : Array[(Int, Int, ProducerRead)],
) -> CompletedOutput? {
  guard value.inputs is Ordinary(originals) else { return None }
  if !physical_equal(value.sequence, sequence) ||
    originals.length() != inputs.length() {
    return None
  }
  for index, (step, port, read) in originals {
    let (actual_step, actual_port, actual_read) = inputs[index]
    if step != actual_step ||
      port != actual_port ||
      !physical_equal(read, actual_read) {
      return None
    }
  }
  for (_, _, read) in originals {
    if !producer_read_available(read) {
      return None
    }
  }
  if !completed_output_available(value.output) {
    return None
  }
  Some(value.output)
}

///|
fn fixed_segment_input_binding_matches(
  input : FixedRelationRead,
  owner : @lower.BoundPrepared,
  step : Int,
  port : Int,
) -> Bool {
  match input {
    CompletedRelation(read) =>
      producer_read_binding_matches_operation_input(read, owner, step, port)
    SuppliedRelation(read) =>
      physical_equal(read.receiver, owner) &&
      @lower.node_at(@lower.bound_preparation(owner), step).bind(node => {
        @lower.node_input_target(node, port)
      }) ==
      Some(@pipeline.Input(read.input_index))
  }
}

///|
/// Preserve every actual external port of a mixed completed/supplied segment.
/// This is the same completed-input proof, never a new completion or read grant.
pub fn retain_completed_fixed_segment_inputs(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  inputs : Array[(Int, Int, FixedRelationRead)],
  max_work : Int,
) -> CompletedSegmentInputs? {
  if max_work <= 0 || inputs.length() > max_work {
    return None
  }
  let inputs = inputs.copy()
  if !completed_segment_inputs_shape(
      output, sequence, inputs, max_work, fixed_segment_input_binding_matches,
    ) {
    return None
  }
  for (_, _, read) in inputs {
    if !fixed_relation_read_available(read) {
      return None
    }
  }
  if !completed_output_available(output) {
    return None
  }
  Some({ output, sequence, inputs: Fixed(inputs), })
}

///|
/// Borrow only with the same full ordered inventory and original read objects.
/// Rebound equal bindings or another restricted representation cannot replace
/// the actual read retained by this closed provider's completion proof.
pub fn completed_fixed_segment_inputs_output(
  value : CompletedSegmentInputs,
  sequence : GeneratedSequence,
  inputs : Array[(Int, Int, FixedRelationRead)],
) -> CompletedOutput? {
  guard value.inputs is Fixed(originals) else { return None }
  if !physical_equal(value.sequence, sequence) ||
    originals.length() != inputs.length() {
    return None
  }
  for index, (step, port, read) in originals {
    let (actual_step, actual_port, actual_read) = inputs[index]
    let same = match (read, actual_read) {
      (CompletedRelation(a), CompletedRelation(b)) => physical_equal(a, b)
      (SuppliedRelation(a), SuppliedRelation(b)) => physical_equal(a, b)
      _ => false
    }
    if step != actual_step || port != actual_port || !same {
      return None
    }
  }
  for (_, _, read) in originals {
    if !fixed_relation_read_available(read) {
      return None
    }
  }
  if !completed_output_available(value.output) {
    return None
  }
  Some(value.output)
}

///|
/// Immutable receiving-input provenance from the already retained segment.
/// Liveness is observed by completed_segment_inputs_output at its borrow
/// boundary; this projection does not repeat any availability callback.
pub fn completed_segment_inputs_has_original_pipeline_input(
  value : CompletedSegmentInputs,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  original : CompletedOutput,
) -> Bool {
  if input_index < 0 ||
    !physical_equal(generated_sequence_owner(value.sequence), receiver) {
    return false
  }
  match value.inputs {
    Ordinary(inputs) =>
      completed_segment_original_pipeline_input(
        inputs,
        read => Some(read),
        receiver,
        input_index,
        original,
      )
    Fixed(inputs) =>
      completed_segment_original_pipeline_input(
        inputs, fixed_relation_read_completed, receiver, input_index, original,
      )
  }
}

///|
fn[T] completed_segment_original_pipeline_input(
  inputs : Array[(Int, Int, T)],
  completed : (T) -> ProducerRead?,
  receiver : @lower.BoundPrepared,
  input_index : Int,
  original : CompletedOutput,
) -> Bool {
  let mut found = false
  for (step, port, input) in inputs {
    guard @lower.node_at(@lower.bound_preparation(receiver), step) is Some(node) else {
      return false
    }
    if @lower.node_input_target(node, port) ==
      Some(@pipeline.Input(input_index)) {
      guard completed(input) is Some(read) &&
        bound_producer_input_has_original_completion(read.bound, original) else {
        return false
      }
      found = true
    }
  }
  found
}
