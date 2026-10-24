///|
// Only checked original scalar schemas justify this smaller value envelope.
// Unknown or nested contracts retain the general budget; no rows are sampled.
fn client_local_scalar_schema_width(schema : @schema.Schema) -> Int? {
  let width = @schema.field_count(schema)
  if width > 100 {
    return None
  }
  for index in 0..<width {
    guard @schema.field_at(schema, index) is Some(field) else { return None }
    match @schema.field_contract(field).shape {
      @contract.Number | @contract.Boolean => ()
      _ => return None
    }
  }
  Some(width)
}

///|
fn client_local_scalar_nodes(
  sequences : Array[@execution.GeneratedSequence],
  max_rows : Int,
) -> Int? {
  if sequences.is_empty() ||
    sequences.length() > 32 ||
    max_rows < 1 ||
    max_rows > 20000 {
    return None
  }
  let mut width = 1
  for sequence in sequences {
    let prepared = @lower.bound_preparation(
      @execution.generated_sequence_owner(sequence),
    )
    let mut input_width = 0
    let mut output_width = 0
    // Each row container and each scalar cell consumes one node.
    // Initial inputs and every original port count independently. A Step target
    // is not a pipeline Input, and repeated ports must never be deduplicated.
    for input in 0..<@lower.preparation_input_count(prepared) {
      guard @lower.preparation_input_schema(prepared, input) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(port_width) else {
        return None
      }
      if input_width > 20000 - (port_width + 1) {
        return None
      }
      input_width += port_width + 1
      // A projected external producer can consume the sequence output budget
      // before any kernel executes; reserve its row envelope independently.
      if output_width > 20000 - (port_width + 1) {
        return None
      }
      output_width += port_width + 1
    }
    for index in 0..<@lower.node_count(prepared) {
      guard @lower.node_at(prepared, index) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) &&
        client_local_scalar_schema_width(schema) is Some(node_width) else {
        return None
      }
      // A generated sequence can share its output budget across several steps.
      if output_width > 20000 - (node_width + 1) {
        return None
      }
      output_width += node_width + 1
      for port in 0..<@lower.node_input_count(node) {
        guard @lower.node_input_target(node, port) is Some(target) &&
          @lower.preparation_schema_at(prepared, target) is Some(input_schema) &&
          client_local_scalar_schema_width(input_schema) is Some(port_width) else {
          return None
        }
        if input_width > 20000 - (port_width + 1) {
          return None
        }
        input_width += port_width + 1
      }
    }
    if input_width > width {
      width = input_width
    }
    if output_width > width {
      width = output_width
    }
  }
  client_local_scalar_node_limit(width, max_rows)
}

///|
fn client_local_scalar_node_limit(width : Int, max_rows : Int) -> Int? {
  if width < 1 || max_rows < 1 || max_rows > 20000 || width > 20000 / max_rows {
    return None
  }
  Some(width * max_rows)
}
