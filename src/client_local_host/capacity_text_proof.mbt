///|
/// An optimization proof, never operation admission. Walk all original checked
/// expression nodes, including dormant branches, then admit only step families
/// whose implementation cannot synthesize Text outside those checked slots.
/// Field-name bytes are NOT proved zero and need their own occurrence envelope.
fn client_local_scalar_text_proof_slots() -> Int {
  10000
}

///|
fn client_local_text_free_scalar_sequences(
  sequences : Array[@execution.GeneratedSequence],
  max_work? : Int = 100000,
  max_slots? : Int = client_local_scalar_text_proof_slots(),
) -> Bool {
  client_local_scalar_text_inventory(sequences, false, max_work~, max_slots~)
  is Some(_)
}

///|
// A single visitor serves the old strict proof and the optional Decimal proof.
// Both inspect EVERY checked child and the complete original sequence. No
// expression is evaluated and this cannot grant operation support.
fn client_local_scalar_text_inventory(
  sequences : Array[@execution.GeneratedSequence],
  decimal : Bool,
  max_work? : Int = 100000,
  max_slots? : Int = client_local_scalar_text_proof_slots(),
) -> (Int, Int64)? {
  if sequences.is_empty() || max_work < 1 || max_slots < 0 {
    return None
  }
  let mut remaining = max_work
  let mut precision = 0
  let mut text = 0L
  for sequence in sequences {
    let original = @execution.generated_prepared_sequence(sequence)
    let prepared = @lower.bound_preparation(@lower.sequence_owner(original))
    // External Decimal input may have arbitrarily long admitted lexical text.
    // This specialization only observes internally constructed source-free
    // rows; captured input keeps its independent original general envelope.
    if decimal && @lower.preparation_input_count(prepared) != 0 {
      return None
    }
    for index in 0..<@lower.preparation_input_count(prepared) {
      if remaining == 0 {
        return None
      }
      remaining -= 1
      guard @lower.preparation_input_schema(prepared, index) is Some(schema) else {
        return None
      }
      let width = @schema.field_count(schema)
      if width > remaining {
        return None
      }
      remaining -= width
      guard client_local_scalar_schema_precision(schema, decimal) is Some(p) else {
        return None
      }
      precision = Int::max(precision, p)
    }
    for index in 0..<@lower.node_count(prepared) {
      if remaining == 0 {
        return None
      }
      remaining -= 1
      guard @lower.node_at(prepared, index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) else {
        return None
      }
      let width = @schema.field_count(schema)
      if width > remaining {
        return None
      }
      remaining -= width
      guard client_local_scalar_schema_precision(schema, decimal) is Some(p) else {
        return None
      }
      precision = Int::max(precision, p)
    }
    // Inspect the complete retained sequence, not its selected view. A selected
    // provider must not hide a text-producing sibling from the shared plan.
    for index in 0..<@lower.sequence_count(original) {
      if remaining == 0 {
        return None
      }
      remaining -= 1
      guard @lower.sequence_step(original, index) is Some(step) else {
        return None
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
            // Aggregate private coefficient/workspace limits remain unchanged.
            // Its public rows and every expression still pass the same proof.
            @lower.Groups(_) => decimal
            _ => false
          }
        _ => false
      }
      if !supported {
        return None
      }
    }
    let slots = match
      @pipeline.collect_expression_slots(
        @lower.pipeline(prepared),
        max_work=remaining,
        max_slots~,
      ) {
      Ok(slots) => slots
      Err(_) => return None
    }
    let used = @pipeline.expression_slots_work(slots)
    if used < 0 || used > remaining {
      return None
    }
    remaining -= used
    for index in 0..<@pipeline.expression_slot_count(slots) {
      if remaining == 0 {
        return None
      }
      remaining -= 1
      guard @pipeline.expression_slot_at(slots, index) is Some(slot) else {
        return None
      }
      for node_index in 0..<@typing.node_count(slot.expression) {
        if remaining == 0 {
          return None
        }
        remaining -= 1
        guard @typing.node_at(slot.expression, node_index) is Some(node) else {
          return None
        }
        match node.contract.shape {
          @contract.Number | @contract.Boolean => ()
          @contract.Decimal(precision=p, ..) => {
            if !decimal {
              return None
            }
            precision = Int::max(precision, p)
          }
          @contract.Text(bounds) => {
            if !decimal {
              return None
            }
            guard bounds.max_utf8_bytes is Some(bytes) &&
              bytes >= 0L &&
              @execution.checked_preparation_add_product(text, bytes, 1L)
              is Some(next) else {
              return None
            }
            text = next
          }
          _ => return None
        }
      }
    }
  }
  Some((precision, text))
}

///|
// Derive one conservative public row-text envelope from original checked
// precision and ALL typed Text bounds, including CAST inputs/dormant branches.
// Unknown text, unsupported shapes and exhausted proof work keep old policy.
fn client_local_decimal_text_bound(
  sequences : Array[@execution.GeneratedSequence],
  demand : ClientLocalValueNodeDemand,
  original_text_limit : Int,
  max_work? : Int = 100000,
  max_slots? : Int = client_local_scalar_text_proof_slots(),
) -> Int? {
  guard original_text_limit >= 0 &&
    client_local_scalar_text_inventory(sequences, true, max_work~, max_slots~)
    is Some((precision, text)) &&
    precision > 0 &&
    @execution.checked_preparation_add_product(
      demand.original.max_name_width,
      demand.original.max_node_width,
      precision.to_int64() + 3L,
    )
    is Some(row) &&
    @execution.checked_preparation_add_product(row, text, 1L) is Some(row) &&
    client_local_scalar_product(row, demand.rows, 0) is Some(total) else {
    return None
  }
  Some(Int::min(original_text_limit, total))
}

///|
// Borrow cached admission geometry from the SAME literal Values originals.
// No second row/payload scan, parse, serialization or value copy occurs.
// Checked CrossJoin may only copy these fields. Parameters and all other step
// families retain the independent selected general policy.
fn client_local_original_values_text_bound(
  sequences : Array[@execution.GeneratedSequence],
  demand : ClientLocalValueNodeDemand,
  max_work? : Int = client_local_schema_proof_work(),
) -> (Int, Int, Int)? {
  let mut remaining = max_work
  let mut text = 0L
  let mut copied = false
  let mut text_fields = 0L
  for sequence in sequences {
    let original = @execution.generated_prepared_sequence(sequence)
    let owner = @lower.sequence_owner(original)
    let prepared = @lower.bound_preparation(owner)
    if @lower.preparation_input_count(prepared) != 0 {
      return None
    }
    for step in 0..<@lower.sequence_count(original) {
      if remaining < 1 {
        return None
      }
      remaining -= 1
      guard @lower.sequence_step(original, step) is Some(operation) &&
        @lower.node_at(prepared, step) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) &&
        client_local_json_leaf_schema(schema) else {
        return None
      }
      let fields = @schema.field_count(schema)
      if fields > remaining {
        return None
      }
      remaining -= fields
      let mut row_text_fields = 0L
      for field in 0..<fields {
        if @schema.field_at(schema, field) is Some(field) &&
          @schema.field_contract(field).shape is @contract.Text(_) {
          row_text_fields += 1L
        }
      }
      text_fields = Int64::max(text_fields, row_text_fields)
      match operation {
        @lower.ValuesStep(_) => {
          guard @lower.node_values_literal_text_bytes(node) is Some(bytes) else {
            return None
          }
          text = Int64::max(text, bytes.to_int64())
        }
        // The checked CrossJoin projection copies original fields; it does
        // not evaluate expressions or synthesize Text. Count every repeated
        // Text field and output row, including duplicate aliases.
        @lower.CrossJoinStep(_) => copied = true
        _ => return None
      }
    }
  }
  let text = if copied {
    // The existing literal admission charges each payload's UTF-8 at least
    // three times: whole Values preflight, literal scan and its reservation.
    // Only this closed flat literal family may recover that bound; Parameters
    // and expression-produced values were excluded above. Names/schema charges
    // make integer division conservative, including empty literal Text.
    let literal_text = text / 3L
    guard @execution.checked_preparation_add_product(
        0L,
        text_fields,
        demand.rows.to_int64(),
      )
      is Some(copies) &&
      @execution.checked_preparation_add_product(0L, literal_text, copies)
      is Some(expanded) else {
      return None
    }
    expanded
  } else {
    text
  }
  guard text > 0L &&
    @execution.checked_preparation_add_product(
      text,
      demand.original.max_name_width,
      demand.rows.to_int64(),
    )
    is Some(total) &&
    total < 2147483647L &&
    client_local_json_leaf_wire_byte_bound(
      demand.original.fields,
      demand.rows,
      total,
    )
    is Some(wire) else {
    return None
  }
  let row_wire = if copied {
    // Copy expansion changes cumulative output, not a single row or one
    // transfer block. Keep the original per-row name occurrence separately.
    let row_text = text / demand.rows.to_int64() +
      demand.original.max_name_width
    guard client_local_json_leaf_wire_byte_bound(
        demand.original.fields,
        1,
        row_text,
      )
      is Some(value) else {
      return None
    }
    value
  } else {
    wire
  }
  Some((total.to_int(), wire, row_wire))
}
