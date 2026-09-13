///|
/// Created only after every prepared operation succeeds. This is component
/// execution evidence, not whole-Program admission or publication evidence.
struct CompletedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  store : CompletedStore
  // Strong ownership anchors: keep upstream completions alive with this result.
  // This retention is intentional even when no subsequent cell read needs them.
  _producer_inputs : Array[BoundProducerInput]
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
pub fn completed_output(
  completion : CompletedSequence,
  target : @pipeline.Target,
) -> CompletedOutput? {
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
