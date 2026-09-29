///|
/// Created after local execution succeeds, or after an installed trusted Host
/// verifier accepts an external realization of the retained final target.
/// This is component evidence, not whole-Program admission/publication evidence.
struct CompletedSequence {
  // Fresh only at successful completion, preserved by verified representation
  // conversion. Equal owner/target/CID does not identify the same completion.
  result_identity : Ref[Unit]
  // A readmitted fact may supply a producer, not complete a pending task.
  readmitted : Bool
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  store : CompletedStore
  // Strong ownership anchors: keep upstream completions alive with this result.
  // This retention is intentional even when no subsequent cell read needs them.
  _producer_inputs : Array[BoundProducerInput]
  input_bindings : Array[ProducerBindingIdentity]
  live : (() -> Bool)?
}

///|
/// The parent preserves the exact checked owner and Parameter bindings; a raw
/// TableStore or caller-supplied rows cannot construct a successful output.
struct CompletedOutput {
  completion : CompletedSequence
  target : @pipeline.Target
  table : CompletedTable?
  representation : RetainedOutputMaterial?
}

///|
/// Restrict an existing completion without copying/re-admitting its storage or
/// weakening its original liveness. This cannot manufacture successful output.
pub fn restrict_completed_output(
  output : CompletedOutput,
  live : () -> Bool,
) -> CompletedOutput {
  let original = output.completion
  // Capture only the logical predicate, not the original completion's storage.
  // A verified representation conversion must not retain old row buffers just
  // because this result had an additional logical-use restriction.
  let original_live = original.live
  let completion = {
    ..original,
    live: Some(fn() {
      let prior = match original_live {
        None => true
        Some(check) => check()
      }
      prior && live()
    }),
  }
  { ..output, completion, }
}

///|
/// Anchor a bounded provider's terminal output to the task-level fixed inputs
/// the provider was started with. A multi-step provider seals its terminal
/// step over internal operation inputs; the task boundary needs the receiving
/// ports instead. The caller must pass exactly the reads it gave the provider.
/// Storage, liveness and result identity are unchanged; upstream completions
/// stay anchored alongside the provider's own anchors.
pub fn anchor_completed_output_inputs(
  output : CompletedOutput,
  inputs : Array[ProducerRead],
) -> CompletedOutput? {
  let original = output.completion
  let owner = @lower.sequence_owner(original.sequence)
  if original.readmitted ||
    !completed_output_available(output) ||
    inputs.length() !=
    @lower.preparation_input_count(@lower.bound_preparation(owner)) {
    return None
  }
  for index, input in inputs {
    if !physical_equal(input.bound.receiver, owner) ||
      input.bound.input_index != index ||
      !producer_read_available(input) {
      return None
    }
  }
  let anchors = original._producer_inputs.copy()
  for input in inputs {
    anchors.push(input.bound)
  }
  let completion = {
    ..original,
    _producer_inputs: anchors,
    input_bindings: inputs.map(input => input.bound.identity),
  }
  Some({ ..output, completion, })
}

///|
/// Anchor the exact ordered inputs of a selected operation. A physical task
/// may have fewer receiving ports than its enclosing authored Stage.
pub fn anchor_completed_output_operation_inputs(
  output : CompletedOutput,
  step : Int,
  inputs : Array[ProducerRead],
) -> CompletedOutput? {
  let original = output.completion
  let owner = @lower.sequence_owner(original.sequence)
  guard !original.readmitted &&
    completed_output_available(output) &&
    output.target == @pipeline.Step(step) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_count(node) == inputs.length() else {
    return None
  }
  for index, input in inputs {
    if !producer_read_matches_operation_input(input, owner, step, index) {
      return None
    }
  }
  let anchors = original._producer_inputs.copy()
  for input in inputs {
    anchors.push(input.bound)
  }
  let completion = {
    ..original,
    _producer_inputs: anchors,
    input_bindings: inputs.map(input => input.bound.identity),
  }
  Some({ ..output, completion, })
}

///|
pub fn completed_output(
  completion : CompletedSequence,
  target : @pipeline.Target,
) -> CompletedOutput? {
  if !completion_is_live(completion) {
    return None
  }
  let store = completion.store
  if store is RetainedStore(_, retained_target, material) {
    return if target == retained_target && (material.available)() {
      Some({ completion, target, table: None, representation: Some(material), })
    } else {
      None
    }
  }
  let slot = match target {
    Input(i) => {
      if i < 0 || i >= store.input_count() {
        return None
      }
      i
    }
    Step(i) => {
      if i < 0 || i >= @lower.sequence_count(completion.sequence) {
        return None
      }
      store.input_count() + i
    }
  }
  guard store.table_at(slot) is Some(table) else { return None }
  Some({ completion, target, table: Some(table), representation: None, })
}

///|
pub fn completed_row_count(output : CompletedOutput) -> Int {
  match output.table {
    Some(table) => IndexedRows::row_count(table)
    None => output.representation.unwrap().receipt.rows
  }
}

///|
/// Inspect an existing completion's exact bound owner and retained target.
/// This neither constructs evidence nor validates a connector's input/attempt
/// relationship; that remains the installed completion verifier's obligation.
pub fn completed_output_matches_port(
  output : CompletedOutput,
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Bool {
  physical_equal(@lower.sequence_owner(output.completion.sequence), owner) &&
  output.target == target &&
  completed_output_available(output)
}

///|
/// Exact fixed-input provenance, in receiving-port order. This does not infer
/// input identity from equal rows, schemas or CIDs, and does not revalidate the
/// upstream's current liveness after this independent result has completed.
pub fn completed_output_matches_inputs(
  output : CompletedOutput,
  inputs : Array[ProducerRead],
) -> Bool {
  let completion = output.completion
  let owner = @lower.sequence_owner(completion.sequence)
  let count = @lower.preparation_input_count(@lower.bound_preparation(owner))
  if completion.readmitted ||
    inputs.length() != count ||
    completion.input_bindings.length() != count ||
    !completed_output_available(output) {
    return false
  }
  for index, input in inputs {
    if !physical_equal(input.bound.receiver, owner) ||
      input.bound.input_index != index {
      return false
    }
  }
  // Generated execution can receive the bindings in a different array order;
  // their checked port positions, not that incidental order, are authoritative.
  for identity in completion.input_bindings {
    guard identity.carrier is None &&
      identity.supplied is None &&
      inputs.get(identity.input_index) is Some(input) &&
      physical_equal(input.bound.identity, identity) else {
      return false
    }
  }
  true
}

///|
/// Verify the receiving-port proof of one selected checked operation.
pub fn completed_output_matches_operation_inputs(
  output : CompletedOutput,
  step : Int,
  inputs : Array[ProducerRead],
) -> Bool {
  let completion = output.completion
  let owner = @lower.sequence_owner(completion.sequence)
  guard !completion.readmitted &&
    completed_output_available(output) &&
    output.target == @pipeline.Step(step) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_count(node) == inputs.length() &&
    completion.input_bindings.length() == inputs.length() else {
    return false
  }
  for index, input in inputs {
    if !producer_read_binding_matches_operation_input(input, owner, step, index) ||
      !physical_equal(completion.input_bindings[index], input.bound.identity) {
      return false
    }
  }
  true
}

///|
pub fn completed_column_count(output : CompletedOutput) -> Int {
  match output.table {
    Some(table) => IndexedRows::column_count(table)
    None => @schema.field_count(output.representation.unwrap().receipt.schema)
  }
}

///|
pub fn completed_column_name(output : CompletedOutput, column : Int) -> String? {
  match output.table {
    Some(table) => RelationRows::field_names(table).get(column)
    None =>
      @schema.field_at(output.representation.unwrap().receipt.schema, column).map(field => {
          @schema.reference_name(field.name)
        },
      )
  }
}

///|
/// Scalars and admitted nested values are immutable. No row/container accessor
/// exposes the retained table or permits alteration of producer evidence.
pub fn completed_cell(
  output : CompletedOutput,
  row : Int,
  column : Int,
) -> Value? {
  guard output.table is Some(table) else { return None }
  if row < 0 ||
    row >= IndexedRows::row_count(table) ||
    column < 0 ||
    column >= IndexedRows::row_width(table, row) {
    return None
  }
  Some(IndexedRows::read_cell(table, row, column))
}

///|
/// Capability of this admitted representation, not a claim about the result's
/// validity. A cell-based consumer must admit conversion before starting work
/// when false; it must not interpret absent cell access as NULL or an empty row.
pub fn completed_has_cell_access(output : CompletedOutput) -> Bool {
  output.table is Some(_)
}

///|
/// Logical-use restrictions and this physical copy's availability are distinct.
/// Loss of a representation does not rewrite the immutable completion record.
pub fn completed_output_available(output : CompletedOutput) -> Bool {
  if !completion_is_live(output.completion) {
    return false
  }
  match output.representation {
    None => true
    Some(material) => (material.available)()
  }
}
