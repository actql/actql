///|
fn input_field_clause() -> @query.InferClause {
  let query = @query.parse_query(
    "FROM tickets |> INFER task ITEM KEY (id) INPUT (TEXT = text) AS assessment",
    mapping_syntax_limits(),
  ).unwrap()
  match @query.operation_at(query, 0).unwrap() {
    Infer(clause) => clause
    _ => abort("expected INFER")
  }
}

///|
test "INFER INPUT field resolution is bounded and never chooses an ambiguous spelling" {
  let clause = input_field_clause()
  let text = @contract.primitive(@contract.StringType, nullable=true)
  let single = @contract.object_contract(
    [("text", text)],
    nullable=false,
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  guard single.shape is @contract.Object(fields) else { abort("object") }
  assert_eq(resolve_infer_input_names(clause, fields, 9), ["text"])
  let exhausted = try {
    ignore(resolve_infer_input_names(clause, fields, 8))
    false
  } catch {
    Abort(Expression({ issue: @expression.WorkLimit, .. })) => true
    _ => false
  }
  assert_true(exhausted)
  let collision = @contract.object_contract(
    [("text", text), ("TEXT", text)],
    nullable=false,
    max_fields=10,
    max_name_bytes=100,
  ).unwrap()
  guard collision.shape is @contract.Object(fields) else { abort("object") }
  let ambiguous = try {
    ignore(resolve_infer_input_names(clause, fields, 100))
    false
  } catch {
    Abort(AmbiguousColumn) => true
    _ => false
  }
  assert_true(ambiguous)
  assert_eq(infer_input_names(clause, None, 0), ["TEXT"])
}
