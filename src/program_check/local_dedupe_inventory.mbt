///|
// First-row selection, canonical group order and failure on a top tie are
// existing execution laws. Audit their original checked inputs without issuing
// a Source completion or copying/reinterpreting the key and order arrays.
fn audit_local_completion_free_dedupe(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
) -> Int? {
  guard available > 0 &&
    @relation.operation(operation) == @relation.DedupeRows &&
    @pipeline.step_at(pipeline, step) is Some(original) &&
    original.operation is @pipeline.Unary(checked) &&
    physical_equal(checked, operation) else {
    return None
  }
  let input = @relation.input_schema(operation)
  let output = @relation.output_schema(operation)
  guard physical_equal(input, output) &&
    @pipeline.step_schema(original) is Some(schema) &&
    physical_equal(schema, output) &&
    @relation.dedupe_order_count(operation) > 0 else {
    return None
  }
  let source = @relation.source(operation)
  guard @decode.open_object(source) is Ok(body) &&
    @decode.lookup(body, "by") is Some(by) &&
    @decode.lookup(body, "order_by") is Some(order) &&
    @decode.array_length(by) == Some(@relation.dedupe_key_count(operation)) &&
    @decode.array_length(order) == Some(@relation.dedupe_order_count(operation)) else {
    return None
  }
  let mut remaining = available - 1
  for index in 0..<@schema.field_count(input) {
    if remaining <= 0 || @schema.field_at(input, index) is None {
      return None
    }
    remaining -= 1
  }
  for index in 0..<@relation.dedupe_key_count(operation) {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    guard @relation.dedupe_key_at(operation, index) is Some(key) &&
      @decode.element_at(by, index) is Some(authored) &&
      @decode.tree_index(authored, key.source) ==
      @decode.tree_index(authored, authored) else {
      return None
    }
    remaining = match local_dedupe_field_work(input, key.field, remaining) {
      Some(left) => left
      None => return None
    }
  }
  for index in 0..<@relation.dedupe_order_count(operation) {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    guard @relation.dedupe_order_at(operation, index) is Some(term) &&
      @decode.element_at(order, index) is Some(authored) &&
      @decode.tree_index(authored, term.source) ==
      @decode.tree_index(authored, authored) else {
      return None
    }
    remaining = match local_dedupe_field_work(input, term.field, remaining) {
      Some(left) => left
      None => return None
    }
  }
  Some(remaining)
}

///|
fn local_dedupe_field_work(
  schema : @schema.Schema,
  field : @schema.FieldName,
  available : Int,
) -> Int? {
  let name = @schema.reference_name(field)
  let mut remaining = available
  let mut width = @schema.field_count(schema)
  while width > 0 {
    if remaining <= 0 || name.length() > remaining - 1 {
      return None
    }
    remaining -= name.length() + 1
    width /= 2
  }
  guard @schema.lookup_reference(schema, name) is Some(_) else { return None }
  Some(remaining)
}
