///|
/// Created only after every prepared operation succeeds. This is component
/// execution evidence, not whole-Program admission or publication evidence.
struct CompletedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  store : TableStore
  producer_inputs : Array[BoundProducerInput]
}

///|
/// The parent preserves the exact checked owner and Parameter bindings; a raw
/// TableStore or caller-supplied rows cannot construct a successful output.
struct CompletedOutput {
  completion : CompletedSequence
  target : @pipeline.Target
  table : Table
}

///|
pub fn completed_output(
  completion : CompletedSequence,
  target : @pipeline.Target,
) -> CompletedOutput? {
  let store = completion.store
  let slot = match target {
    Input(i) => {
      if i < 0 || i >= store.wiring.input_count {
        return None
      }
      i
    }
    Step(i) => {
      if i < 0 || i >= @lower.sequence_count(completion.sequence) {
        return None
      }
      store.wiring.input_count + i
    }
  }
  guard store.tables[slot] is Some(held) else { return None }
  Some({ completion, target, table: held.table, })
}

///|
pub fn completed_row_count(output : CompletedOutput) -> Int {
  output.table.rows.length()
}

///|
pub fn completed_column_count(output : CompletedOutput) -> Int {
  output.table.names.length()
}

///|
pub fn completed_column_name(output : CompletedOutput, column : Int) -> String? {
  output.table.names.get(column)
}

///|
/// Scalars and admitted nested values are immutable. No row/container accessor
/// exposes the retained table or permits alteration of producer evidence.
pub fn completed_cell(
  output : CompletedOutput,
  row : Int,
  column : Int,
) -> Value? {
  match output.table.rows.get(row) {
    Some(values) => values.get(column)
    None => None
  }
}
