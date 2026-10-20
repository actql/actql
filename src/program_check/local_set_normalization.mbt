///|
// Read the exact checked binary occurrence and both original input schemas.
// The existing Append/Set owners retain typed alignment and row validation;
// this audit neither reconstructs a body nor establishes input completeness.
fn audit_local_completion_free_binary(
  operation : @pipeline.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  available : Int,
) -> Int? {
  guard available >= 4 &&
    @pipeline.step_at(pipeline, index) is Some(step) &&
    step.input is Some(left_target) else {
    return None
  }
  let (right_target, left, right, output, alignment) = match
    (operation, step.operation) {
    (
      @pipeline.Append(right~, checked~),
      @pipeline.Append(right=original_target, checked=original),
    ) => {
      guard right == original_target &&
        physical_equal(checked, original) &&
        @schema.field_count(@append.output_schema(checked)) <=
        (available - 4) / 4 else {
        return None
      }
      (
        right,
        @append.input_schema(checked, Left),
        @append.input_schema(checked, Right),
        @append.output_schema(checked),
        @append.alignment(checked),
      )
    }
    (
      @pipeline.Set(right~, checked~),
      @pipeline.Set(right=original_target, checked=original),
    ) => {
      guard right == original_target &&
        physical_equal(checked, original) &&
        @schema.field_count(@set.output_schema(checked)) <= (available - 4) / 4 else {
        return None
      }
      (
        right,
        @set.input_schema(checked, Left),
        @set.input_schema(checked, Right),
        @set.output_schema(checked),
        @set.alignment(checked),
      )
    }
    _ => return None
  }
  // Both targets and role occurrences belong to this original pipeline step.
  for target in [left_target, right_target] {
    if target is @pipeline.Step(prior) && (prior < 0 || prior >= index) {
      return None
    }
  }
  guard @pipeline.input_occurrence_count(step) == 2 &&
    @pipeline.input_occurrence_at(step, 0) is Some(first) &&
    @pipeline.input_occurrence_at(step, 1) is Some(second) &&
    first.role == @pipeline.Left &&
    first.target == left_target &&
    second.role == @pipeline.Right &&
    second.target == right_target &&
    @pipeline.schema_at(pipeline, left_target) is Some(actual_left) &&
    @pipeline.schema_at(pipeline, right_target) is Some(actual_right) &&
    physical_equal(actual_left, left) &&
    physical_equal(actual_right, right) &&
    @pipeline.step_schema(step) is Some(actual_output) &&
    physical_equal(actual_output, output) &&
    alignment.length() == @schema.field_count(output) else {
    return None
  }
  let mut remaining = available - 4 - alignment.length() * 4
  for position, field in alignment {
    guard @schema.field_at(left, field.left_index) is Some(l) &&
      @schema.field_at(right, field.right_index) is Some(r) &&
      @schema.field_at(output, position) is Some(o) &&
      l.name == field.field &&
      r.name == field.field &&
      o.name == field.field else {
      return None
    }
    let name = @schema.reference_name(field.field)
    if name.length() > remaining / 4 {
      return None
    }
    remaining -= name.length() * 4
  }
  Some(remaining)
}
