///|
// Empty search can insert at most once per input UTF-8 byte plus one. This
// remains conservative for nonempty search and preserves every unmatched byte.
fn client_local_replace_output_text_bytes(
  input : Int64,
  replacement : Int64,
) -> Int64? {
  guard input >= 0L &&
    replacement >= 0L &&
    @execution.checked_preparation_add_product(input, 1L, 1L) is Some(positions) else {
    return None
  }
  @execution.checked_preparation_add_product(input, positions, replacement)
}

///|
// Output, all coheld/intermediate Text, and presence of the explicit REPLACE
// family. The only copied view is a three-child expression array. Its view and
// one pending summary fit the SAME prefunded proof frame's4H10R14W/depth; no
// String, JSON, schema, Map or retained proof owner is constructed here.
fn client_local_replace_expression_text(
  expression : @lower.Expression,
  field_bytes : Int64,
  remaining : Ref[Int],
  depth : Int,
) -> (Int64, Int64, Bool)? {
  let entries = @lower.expression_view_entries(expression)
  if depth < 0 ||
    remaining.val < 1 ||
    entries > 3 ||
    entries > remaining.val - 1 {
    return None
  }
  remaining.val -= 1 + entries
  match @lower.expression_body(expression) {
    @lower.Field(_, _) =>
      match @lower.expression_contract(expression).shape {
        @contract.Text(_) => Some((field_bytes, field_bytes, false))
        @contract.Number | @contract.Boolean => Some((0L, 0L, false))
        _ => None
      }
    @lower.TypedNull => Some((0L, 0L, false))
    @lower.Literal(value) =>
      match value.value {
        @admitted.Null | @admitted.Number(_) | @admitted.Boolean(_) =>
          Some((0L, 0L, false))
        @admitted.Text(text) =>
          // Original immutable literal length; no second UTF-8 encoder/copy.
          @execution.checked_preparation_add_product(
            0L,
            text.length().to_int64(),
            3L,
          ).map(bytes => (bytes, bytes, false))
        _ => None
      }
    @lower.Unary(@lower.Length, child) =>
      client_local_replace_expression_text(
        child,
        field_bytes,
        remaining,
        depth - 1,
      ).map(summary => (0L, summary.1, summary.2))
    @lower.Many(@lower.Replace, children) => {
      if children.length() != 3 {
        return None
      }
      // The replacement must be this actual admitted immutable literal, never
      // a declared type maximum or an external/derived replacement field.
      match @lower.expression_body(children[2]) {
        @lower.Literal(value) =>
          match value.value {
            @admitted.Text(_) | @admitted.Null => ()
            _ => return None
          }
        @lower.TypedNull => ()
        _ => return None
      }
      let mut input = 0L
      let mut replacement = 0L
      let mut total = 0L
      // Fold each summary immediately. All three children, including search
      // and nullable/dormant input subexpressions, retain their own inventory.
      for index in 0..<3 {
        guard client_local_replace_expression_text(
            children[index],
            field_bytes,
            remaining,
            depth - 1,
          )
          is Some((bytes, held, _)) &&
          @execution.checked_preparation_add_product(total, held, 1L)
          is Some(next) else {
          return None
        }
        total = next
        if index == 0 {
          input = bytes
        }
        if index == 2 {
          replacement = bytes
        }
      }
      guard client_local_replace_output_text_bytes(input, replacement)
        is Some(output) &&
        @execution.checked_preparation_add_product(total, output, 1L)
        is Some(total) else {
        return None
      }
      Some((output, total, true))
    }
    // Other Text families/branches keep the original general policy. In
    // particular this does not broaden the independent copy proof's negative.
    _ => None
  }
}

///|
// A separate closed-VALUES REPLACE proof. Numeric IO specialization changes
// no evaluator work, full Fragment workspace, operation support or512MiB owner.
fn client_local_original_values_replace_text_bound(
  sequences : Array[@execution.GeneratedSequence],
  demand : ClientLocalValueNodeDemand,
  graph : @strategy.CheckedDAG?,
  graph_offset : Int,
  max_work? : Int = client_local_schema_proof_work(),
) -> (Int, Int, Int)? {
  guard graph is Some(graph) &&
    graph_offset == 0 &&
    @strategy.graph_captured_prefix(graph) == 0 &&
    @strategy.graph_task_count(graph) == sequences.length() &&
    !sequences.is_empty() &&
    max_work > 0 else {
    return None
  }
  // This proof runs after the other schema/copy visitors have returned. One
  // work Ref and recursive frames reuse their already reserved original Plan
  // scratch; no second collector, metadata representation or quota is issued.
  let remaining = Ref(max_work)
  let mut literals = 0L
  let mut text_fields = 0L
  for task, sequence in sequences {
    if remaining.val < 1 {
      return None
    }
    remaining.val -= 1
    let original = @execution.generated_prepared_sequence(sequence)
    let owner = @lower.sequence_owner(original)
    guard @strategy.graph_task_owner(graph, task) is Some(expected) &&
      physical_equal(owner, expected) else {
      return None
    }
    let prepared = @lower.bound_preparation(owner)
    for input in 0..<@lower.preparation_input_count(prepared) {
      let mut found = false
      for index in 0..<@strategy.graph_data_count(graph) {
        if remaining.val < 1 {
          return None
        }
        remaining.val -= 1
        guard @strategy.graph_data_at(graph, index) is Some(edge) else {
          return None
        }
        if edge.consumer == task && edge.input == input {
          if found || edge.producer < 0 || edge.producer >= task {
            return None
          }
          found = true
        }
      }
      if !found {
        return None
      }
    }
    for step in 0..<@lower.sequence_count(original) {
      if remaining.val < 1 {
        return None
      }
      remaining.val -= 1
      guard @lower.sequence_step(original, step) is Some(operation) &&
        @lower.node_at(prepared, step) is Some(node) &&
        @lower.node_relation_schema(node) is Some(schema) &&
        client_local_json_leaf_schema(schema) else {
        return None
      }
      let fields = @schema.field_count(schema)
      if fields > remaining.val {
        return None
      }
      remaining.val -= fields
      let mut count = 0L
      for index in 0..<fields {
        guard @schema.field_at(schema, index) is Some(field) else {
          return None
        }
        match field.contract.shape {
          @contract.Text(_) => count += 1L
          @contract.Number | @contract.Boolean => ()
          _ => return None
        }
      }
      text_fields = Int64::max(text_fields, count)
      match operation {
        @lower.ValuesStep(_) => {
          guard @lower.node_values_literal_text_bytes(node) is Some(bytes) &&
            @execution.checked_preparation_add_product(
              literals,
              bytes.to_int64(),
              1L,
            )
            is Some(next) else {
            return None
          }
          literals = next
        }
        @lower.RowStep(kernel) =>
          if @lower.kernel_bindings(kernel) is Some(_) {
            ()
          } else {
            let entries = @lower.kernel_view_entries(kernel)
            if entries > client_local_scalar_text_proof_slots() ||
              entries > remaining.val {
              return None
            }
            remaining.val -= entries
            match @lower.kernel_body(kernel) {
              @lower.Select(_) | @lower.Limit(_, _, _) | @lower.StableSort(_) =>
                ()
              _ => return None
            }
          }
        _ => return None
      }
    }
  }
  let mut field_bytes = literals
  let mut held = literals
  let mut replaced = false
  for sequence in sequences {
    let original = @execution.generated_prepared_sequence(sequence)
    for step in 0..<@lower.sequence_count(original) {
      if remaining.val < 1 {
        return None
      }
      remaining.val -= 1
      guard @lower.sequence_step(original, step) is Some(operation) else {
        return None
      }
      if operation is @lower.RowStep(kernel) &&
        @lower.kernel_bindings(kernel) is Some(bindings) {
        for index in 0..<@lower.bindings_count(bindings) {
          guard @lower.binding_at(bindings, index) is Some((_, expression)) &&
            client_local_replace_expression_text(
              expression,
              field_bytes,
              remaining,
              client_local_value_node_proof_depth(),
            )
            is Some((output, intermediate, seen)) &&
            @execution.checked_preparation_add_product(held, intermediate, 1L)
            is Some(next) else {
            return None
          }
          held = next
          field_bytes = Int64::max(field_bytes, output)
          replaced = replaced || seen
        }
      }
    }
  }
  // Keep every intermediate plus all possible field/row/name occurrences.
  // Equal byte contents and unused selected fields grant no sharing credit.
  guard replaced &&
    @execution.checked_preparation_add_product(
      0L,
      text_fields,
      demand.rows.to_int64(),
    )
    is Some(copies) &&
    @execution.checked_preparation_add_product(0L, held, copies)
    is Some(payload) &&
    @execution.checked_preparation_add_product(
      payload,
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
    is Some(wire) &&
    @execution.checked_preparation_add_product(0L, held, text_fields)
    is Some(row_payload) &&
    @execution.checked_preparation_add_product(
      row_payload,
      demand.original.max_name_width,
      1L,
    )
    is Some(row_text) &&
    client_local_json_leaf_wire_byte_bound(demand.original.fields, 1, row_text)
    is Some(row_wire) else {
    return None
  }
  Some((total.to_int(), wire, row_wire))
}
