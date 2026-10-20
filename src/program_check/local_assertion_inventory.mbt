///|
// The audit covers fixed checked assertion semantics, not successful physical
// validation. Atomic failure, NULL/duplicate refusal and proof consumption stay
// with the existing lowering and execution owners.
fn audit_local_completion_free_assertion(
  operation : @relation.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  step : Int,
  available : Int,
) -> Int? {
  guard available > 0 &&
    @relation.operation(operation) == @relation.AssertRows &&
    @pipeline.step_at(pipeline, step) is Some(original) &&
    original.operation is @pipeline.Unary(checked) &&
    physical_equal(checked, operation) else {
    return None
  }
  let input = @relation.input_schema(operation)
  let output = @relation.output_schema(operation)
  guard physical_equal(input, output) &&
    @pipeline.step_schema(original) is Some(schema) &&
    physical_equal(schema, output) else {
    return None
  }
  let source = @relation.source(operation)
  guard @decode.open_object(source) is Ok(body) &&
    @relation.pending_validation_count(operation) == 2 else {
    return None
  }
  let mut remaining = available - 1
  for
    index, kind in [
      @relation.AtomicRowAssertion,
      @relation.AssertionConsumption,
    ] {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    guard @relation.pending_validation_at(operation, index) is Some(pending) &&
      pending.kind == kind &&
      @decode.tree_index(source, pending.source) ==
      @decode.tree_index(source, source) else {
      return None
    }
  }
  for index in 0..<@schema.field_count(input) {
    if remaining <= 0 || @schema.field_at(input, index) is None {
      return None
    }
    remaining -= 1
  }
  match (@decode.lookup(body, "where"), @decode.lookup(body, "unique_by")) {
    (Some(predicate), None) => {
      if remaining <= 0 {
        return None
      }
      remaining -= 1
      guard @relation.binding_count(operation) == 1 &&
        @relation.binding_at(operation, 0) is Some(binding) &&
        @decode.tree_index(predicate, binding.source) ==
        @decode.tree_index(predicate, predicate) &&
        @typing.result_type(binding.expression).shape is @contract.Boolean &&
        @relation.assertion_key_count(operation) == 0 else {
        return None
      }
    }
    (None, Some(keys)) => {
      let count = @relation.assertion_key_count(operation)
      guard count > 0 &&
        @decode.array_length(keys) == Some(count) &&
        @relation.binding_count(operation) == 0 else {
        return None
      }
      for index in 0..<count {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        guard @relation.assertion_key_at(operation, index) is Some(key) &&
          @decode.element_at(keys, index) is Some(authored) &&
          @decode.tree_index(authored, key.source) ==
          @decode.tree_index(authored, authored) else {
          return None
        }
        remaining = match local_dedupe_field_work(input, key.field, remaining) {
          Some(left) => left
          None => return None
        }
      }
    }
    _ => return None
  }
  Some(remaining)
}
