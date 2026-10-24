///|
/// Field-name byte envelope only. This must not replace text capacity unless
/// a separate proof excludes every text-valued intermediate expression.
fn client_local_scalar_name_bytes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  if sequences.is_empty() ||
    sequences.length() > 32 ||
    max_rows < 1 ||
    max_rows > 20000 {
    return None
  }
  let mut width = 0
  for sequence in sequences {
    let prepared = @lower.bound_preparation(
      @execution.generated_sequence_owner(sequence),
    )
    let mut input_width = 0
    let mut output_width = 0
    // Scalar values contain no payload text, but every row field name is charged.
    // Initial inputs and every original port count independently. A Step target
    // is not a pipeline Input, and repeated ports must never be deduplicated.
    for input in 0..<@lower.preparation_input_count(prepared) {
      guard @lower.preparation_input_schema(prepared, input) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(_) else {
        return None
      }
      let port_width = @schema.field_reference_name_bytes(schema)
      if input_width > 500000 - port_width {
        return None
      }
      input_width += port_width
      // A projected external producer can consume the sequence output budget
      // before any kernel executes; reserve its row envelope independently.
      if output_width > 500000 - port_width {
        return None
      }
      output_width += port_width
    }
    for index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared, index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(_) else {
        return None
      }
      let node_width = @schema.field_reference_name_bytes(schema)
      // A generated sequence can share its output budget across several steps.
      if output_width > 500000 - node_width {
        return None
      }
      output_width += node_width
      for port in 0..<@lower.node_input_count(node) {
        guard @lower.node_input_target(node, port) is Some(target) &&
          @lower.preparation_schema_at(prepared, target) is Some(input_schema) &&
          client_local_scalar_schema_width(input_schema) is Some(_) else {
          return None
        }
        let port_width = @schema.field_reference_name_bytes(input_schema)
        if input_width > 500000 - port_width {
          return None
        }
        input_width += port_width
      }
    }
    if input_width > width {
      width = input_width
    }
    if output_width > width {
      width = output_width
    }
  }
  if width < 0 || width > 500000 / max_rows {
    None
  } else {
    Some(width * max_rows)
  }
}
