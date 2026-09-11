///|
/// Created only after every prepared operation succeeds. This is component
/// execution evidence, not whole-Program admission or publication evidence.
priv struct CompletedSequence {
  contracts : RegisteredRelationContracts
  sequence : @lower.PreparedSequence
  store : TableStore
  producer_inputs : Array[BoundProducerInput]
}

///|
/// The parent preserves the exact checked owner and Parameter bindings; a raw
/// TableStore or caller-supplied rows cannot construct a successful output.
priv struct CompletedOutput {
  completion : CompletedSequence
  target : @pipeline.Target
  table : Table
}

///|
fn completed_output(
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
