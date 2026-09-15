///|
/// Created after local execution succeeds, or after an installed trusted Host
/// verifier accepts an external realization of the retained final target.
/// This is component evidence, not whole-Program admission/publication evidence.
struct CompletedSequence {
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
  table : CompletedTable
}

///|
/// Restrict an existing completion without copying/re-admitting its storage or
/// weakening its original liveness. This cannot manufacture successful output.
pub fn restrict_completed_output(
  output : CompletedOutput,
  live : () -> Bool,
) -> CompletedOutput {
  let original = output.completion
  let completion = {
    ..original,
    live: Some(fn() { completion_is_live(original) && live() }),
  }
  { ..output, completion, }
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
  Some({ completion, target, table, })
}

///|
pub fn completed_row_count(output : CompletedOutput) -> Int {
  IndexedRows::row_count(output.table)
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
  completion_is_live(output.completion)
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
  if inputs.length() != count ||
    completion.input_bindings.length() != count ||
    !completion_is_live(completion) {
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
    guard inputs.get(identity.input_index) is Some(input) &&
      physical_equal(input.bound.identity, identity) else {
      return false
    }
  }
  true
}

///|
pub fn completed_column_count(output : CompletedOutput) -> Int {
  IndexedRows::column_count(output.table)
}

///|
pub fn completed_column_name(output : CompletedOutput, column : Int) -> String? {
  RelationRows::field_names(output.table).get(column)
}

///|
/// Scalars and admitted nested values are immutable. No row/container accessor
/// exposes the retained table or permits alteration of producer evidence.
pub fn completed_cell(
  output : CompletedOutput,
  row : Int,
  column : Int,
) -> Value? {
  if row < 0 ||
    row >= IndexedRows::row_count(output.table) ||
    column < 0 ||
    column >= IndexedRows::row_width(output.table, row) {
    return None
  }
  Some(IndexedRows::read_cell(output.table, row, column))
}
