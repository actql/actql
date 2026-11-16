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
        // CrossJoin copies checked cells and names. Its complete input/output
        // schemas and every original expression still pass the same proof.
        @lower.ValuesStep(_) | @lower.AppendStep(_) | @lower.CrossJoinStep(_) =>
          true
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
// Borrow cached literal geometry only through the same closed checked graph.
// Field selection, filtering, stable sorting and limiting cannot create Text.
// Other sources, families and value-producing expressions keep the old policy.
fn client_local_original_values_copy_text_bound(
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
  let remaining = Ref(max_work)
  let literal_text = Ref(0L)
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
    // Each input must borrow a preceding member of this SAME checked graph.
    // Missing, supplied and captured inputs cannot inherit literal geometry.
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
      let mut row_text_fields = 0L
      for field in 0..<fields {
        guard @schema.field_at(schema, field) is Some(field) else {
          return None
        }
        match field.contract.shape {
          @contract.Text(_) => row_text_fields += 1L
          @contract.Number | @contract.Boolean => ()
          _ => return None
        }
      }
      text_fields = Int64::max(text_fields, row_text_fields)
      match operation {
        @lower.ValuesStep(_) => {
          guard @lower.node_values_literal_text_bytes(node) is Some(bytes) &&
            @execution.checked_preparation_add_product(
              literal_text.val,
              bytes.to_int64(),
              1L,
            )
            is Some(next) else {
            return None
          }
          literal_text.val = next
        }
        @lower.RowStep(kernel) =>
          match @lower.kernel_body(kernel) {
            @lower.Filter(expression) =>
              if !client_local_copy_filter_text(
                  expression, remaining, literal_text,
                ) {
                return None
              }
            @lower.Select(_) | @lower.Limit(_, _, _) | @lower.StableSort(_) =>
              ()
            _ => return None
          }
        _ => return None
      }
    }
  }
  // A copied cell cannot contain more Text than all original literal backing.
  // Count every possible field/row occurrence; equal Text never grants sharing.
  guard literal_text.val > 0L &&
    @execution.checked_preparation_add_product(
      0L,
      text_fields,
      demand.rows.to_int64(),
    )
    is Some(copies) &&
    @execution.checked_preparation_add_product(0L, literal_text.val, copies)
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
    @execution.checked_preparation_add_product(
      0L,
      literal_text.val,
      text_fields,
    )
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

///|
// Only predicates with scalar results and field/literal Text leaves qualify.
// Walk every child, including dormant branches; Text-producing expressions
// retain the general policy rather than receiving a guessed output bound.
fn client_local_copy_filter_text(
  expression : @lower.Expression,
  remaining : Ref[Int],
  text : Ref[Int64],
) -> Bool {
  if remaining.val < 1 {
    return false
  }
  remaining.val -= 1
  match @lower.expression_body(expression) {
    @lower.Field(_, _) => true
    @lower.Literal(_) =>
      match @lower.expression_contract(expression).shape {
        @contract.Text(bounds) => {
          guard bounds.max_utf8_bytes is Some(bytes) &&
            bytes >= 0L &&
            @execution.checked_preparation_add_product(text.val, bytes, 1L)
            is Some(next) else {
            return false
          }
          text.val = next
          true
        }
        @contract.Number | @contract.Boolean => true
        _ => false
      }
    @lower.TypedNull => true
    @lower.Unary(_, child) =>
      match @lower.expression_contract(expression).shape {
        @contract.Number | @contract.Boolean =>
          client_local_copy_filter_text(child, remaining, text)
        _ => false
      }
    @lower.Binary(_, left, right) =>
      match @lower.expression_contract(expression).shape {
        @contract.Number | @contract.Boolean =>
          client_local_copy_filter_text(left, remaining, text) &&
          client_local_copy_filter_text(right, remaining, text)
        _ => false
      }
    _ => false
  }
}

///|
// Borrow cached admission geometry from the SAME literal Values originals.
// No second row/payload scan, parse, serialization or value copy occurs.
// Checked CrossJoin may only copy these fields. A closed Graph construction
// keeps its own storage/identity/snapshot budgets; only immediate numeric MATCH
// rows and predicates join this Relation Text proof. Unknown families retain
// the independent selected general policy.
fn client_local_original_values_text_bound(
  sequences : Array[@execution.GeneratedSequence],
  demand : ClientLocalValueNodeDemand,
  max_work? : Int = client_local_schema_proof_work(),
) -> (Int, Int, Int)? {
  let mut remaining = max_work
  let mut text = 0L
  let mut copied = false
  let mut text_fields = 0L
  let mut literal_total = 0L
  let mut graph = false
  let mut graph_inputs_required = true
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
        @lower.node_at(prepared, step) is Some(node) else {
        return None
      }
      if operation is @lower.GraphConstructionStep(_) {
        // This opaque Carrier is never priced as a Relation. Its provider
        // keeps the original Graph storage, labels, identity and snapshots.
        graph = true
        continue
      }
      guard @lower.node_relation_schema(node) is Some(schema) &&
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
        guard @schema.field_at(schema, field) is Some(field) else {
          return None
        }
        if field.contract.nullable {
          graph_inputs_required = false
        }
        if @schema.field_contract(field).shape is @contract.Text(_) {
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
          guard @execution.checked_preparation_add_product(
              literal_total,
              bytes.to_int64(),
              1L,
            )
            is Some(total) else {
            return None
          }
          literal_total = total
        }
        // The checked CrossJoin projection copies original fields; it does
        // not evaluate expressions or synthesize Text. Count every repeated
        // Text field and output row, including duplicate aliases.
        @lower.CrossJoinStep(_) => copied = true
        @lower.GraphMatchStep(matched) => {
          graph = true
          if fields > remaining {
            return None
          }
          remaining -= fields
          for field in 0..<fields {
            guard @schema.field_at(schema, field) is Some(field) &&
              !field.contract.nullable else {
              return None
            }
            match field.contract.shape {
              @contract.Number | @contract.Boolean => ()
              _ => return None
            }
          }
          if @lower.graph_match_predicate(matched) is Some(predicate) {
            guard client_local_graph_immediate_predicate_work(
                predicate, remaining,
              )
              is Some(used) else {
              return None
            }
            remaining -= used
          }
        }
        _ => return None
      }
    }
  }
  if graph && !graph_inputs_required {
    return None
  }
  // Several Graph definitions can read different original Values. Sum every
  // cached literal occurrence, including repeated prepared views, rather than
  // assuming the largest source covers their simultaneous input. No rows or
  // Graph properties are scanned or rebuilt by this optimization.
  let text = if graph { literal_total } else { text }
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

///|
// Deliberately closed, allocation-free predicate proof. A complete immediate
// leaf or one immediate binary node cannot hide Text in a dormant descendant.
// More general expressions keep the original independent policy.
fn client_local_graph_immediate_predicate_leaf(
  expression : @lower.Expression,
) -> Bool {
  if @lower.expression_contract(expression).nullable {
    return false
  }
  match @lower.expression_contract(expression).shape {
    @contract.Number | @contract.Boolean => ()
    _ => return false
  }
  match @lower.expression_body(expression) {
    @lower.Field(_, _) | @lower.Literal(_) => true
    _ => false
  }
}

///|
fn client_local_graph_immediate_predicate_work(
  expression : @lower.Expression,
  remaining : Int,
) -> Int? {
  if remaining < 1 || @lower.expression_contract(expression).nullable {
    return None
  }
  match @lower.expression_contract(expression).shape {
    @contract.Number | @contract.Boolean => ()
    _ => return None
  }
  match @lower.expression_body(expression) {
    @lower.Field(_, _) | @lower.Literal(_) => Some(1)
    @lower.Binary(_, left, right) if remaining >= 3 &&
      client_local_graph_immediate_predicate_leaf(left) &&
      client_local_graph_immediate_predicate_leaf(right) => Some(3)
    _ => None
  }
}
