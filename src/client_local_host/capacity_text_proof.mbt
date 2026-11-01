///|
/// An optimization proof, never operation admission. Walk all original checked
/// expression nodes, including dormant branches, then admit only step families
/// whose implementation cannot synthesize Text outside those checked slots.
/// Field-name bytes are NOT proved zero and need their own occurrence envelope.
fn client_local_text_free_scalar_sequences(
  sequences : Array[@execution.GeneratedSequence],
  max_work? : Int = 100000,
  max_slots? : Int = 10000,
) -> Bool {
  if sequences.is_empty() || max_work < 1 || max_slots < 0 {
    return false
  }
  let mut remaining = max_work
  for sequence in sequences {
    let original = @execution.generated_prepared_sequence(sequence)
    let prepared = @lower.bound_preparation(@lower.sequence_owner(original))
    for index in 0..<@lower.preparation_input_count(prepared) {
      if remaining == 0 {
        return false
      }
      remaining -= 1
      guard @lower.preparation_input_schema(prepared, index) is Some(schema) else {
        return false
      }
      let width = @schema.field_count(schema)
      if width > remaining {
        return false
      }
      remaining -= width
      guard client_local_scalar_schema_width(schema) is Some(_) else {
        return false
      }
    }
    for index in 0..<@lower.node_count(prepared) {
      if remaining == 0 {
        return false
      }
      remaining -= 1
      guard @lower.node_at(prepared, index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) else {
        return false
      }
      let width = @schema.field_count(schema)
      if width > remaining {
        return false
      }
      remaining -= width
      guard client_local_scalar_schema_width(schema) is Some(_) else {
        return false
      }
    }
    // Inspect the complete retained sequence, not its selected view. A selected
    // provider must not hide a text-producing sibling from the shared plan.
    for index in 0..<@lower.sequence_count(original) {
      if remaining == 0 {
        return false
      }
      remaining -= 1
      guard @lower.sequence_step(original, index) is Some(step) else {
        return false
      }
      // Count groups only copy checked scalar keys and emit Number counts.
      // Schemas and typed children remain checked across the complete original sequence.
      let supported = match step {
        @lower.ValuesStep(_) | @lower.AppendStep(_) => true
        @lower.RowStep(kernel) =>
          match @lower.kernel_body(kernel) {
            @lower.SnapshotMap(_)
            | @lower.OrderedBindings(_)
            | @lower.Filter(_)
            | @lower.AssertAll(_)
            | @lower.AssertUnique(_)
            | @lower.Select(_)
            | @lower.Limit(_, _, _)
            | @lower.TopK(_, _)
            | @lower.DistinctRows
            | @lower.DedupeRows
            | @lower.CountGroups(_)
            | @lower.StableSort(_) => true
            _ => false
          }
        _ => false
      }
      if !supported {
        return false
      }
    }
    let slots = match
      @pipeline.collect_expression_slots(
        @lower.pipeline(prepared),
        max_work=remaining,
        max_slots~,
      ) {
      Ok(slots) => slots
      Err(_) => return false
    }
    let used = @pipeline.expression_slots_work(slots)
    if used < 0 || used > remaining {
      return false
    }
    remaining -= used
    for index in 0..<@pipeline.expression_slot_count(slots) {
      if remaining == 0 {
        return false
      }
      remaining -= 1
      guard @pipeline.expression_slot_at(slots, index) is Some(slot) else {
        return false
      }
      for node_index in 0..<@typing.node_count(slot.expression) {
        if remaining == 0 {
          return false
        }
        remaining -= 1
        guard @typing.node_at(slot.expression, node_index) is Some(node) else {
          return false
        }
        match node.contract.shape {
          @contract.Number | @contract.Boolean => ()
          _ => return false
        }
      }
    }
  }
  true
}
