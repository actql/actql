///|
// Fixed Join laws do not issue Source completions. Retain the original checked
// occurrence, both inputs, authored keys/projection and pending runtime duties.
// This audit proves neither row admission, cardinality nor an output bound.
fn audit_local_completion_free_join(
  operation : @pipeline.CheckedOperation,
  pipeline : @pipeline.CheckedPipeline,
  index : Int,
  parameters : @parameters.BoundValues?,
  closure : @context.ProgramOperationClosure,
  available : Int,
) -> Int? {
  guard available >= 4 &&
    @pipeline.step_at(pipeline, index) is Some(step) &&
    step.input is Some(left_target) else {
    return None
  }
  let (right_target, checked) = match (operation, step.operation) {
    (
      @pipeline.Join(right~, checked~),
      @pipeline.Join(right=original_target, checked=original),
    ) => {
      guard right == original_target && physical_equal(checked, original) else {
        return None
      }
      (right, checked)
    }
    _ => return None
  }
  for target in [left_target, right_target] {
    if target is @pipeline.Step(prior) && (prior < 0 || prior >= index) {
      return None
    }
  }
  let left = @join.input_schema(checked, Left)
  let right = @join.input_schema(checked, Right)
  let output = @join.output_schema(checked)
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
    physical_equal(actual_output, output) else {
    return None
  }
  let mut remaining = available - 4
  for schema in [left, right, output] {
    for field in 0..<@schema.field_count(schema) {
      guard remaining > 0 && @schema.field_at(schema, field) is Some(original) else {
        return None
      }
      let name = @schema.reference_name(original.name)
      if name.length() > remaining - 1 {
        return None
      }
      remaining -= name.length() + 1
    }
  }
  let source = @join.source(checked)
  guard @decode.open_object(source) is Ok(body) &&
    @decode.lookup(body, "on") is Some(on) &&
    @join.key_count(checked) > 0 else {
    return None
  }
  let array_count = @decode.array_length(on)
  guard array_count == Some(@join.key_count(checked)) ||
    (array_count is None && @join.key_count(checked) == 1) else {
    return None
  }
  for key_index in 0..<@join.key_count(checked) {
    if remaining <= 0 {
      return None
    }
    remaining -= 1
    let authored = if array_count is Some(_) {
      @decode.element_at(on, key_index).unwrap()
    } else {
      on
    }
    guard @join.key_at(checked, key_index) is Some(key) &&
      @decode.tree_index(authored, key.source) ==
      @decode.tree_index(authored, authored) else {
      return None
    }
    remaining = match local_dedupe_field_work(left, key.left, remaining) {
      Some(value) => value
      None => return None
    }
    remaining = match local_dedupe_field_work(right, key.right, remaining) {
      Some(value) => value
      None => return None
    }
  }
  match @join.projection_count(checked) {
    None => ()
    Some(count) => {
      guard @decode.lookup(body, "select") is Some(select) &&
        @decode.open_object(select) is Ok(fields) &&
        count == @schema.field_count(output) else {
        return None
      }
      for projection_index in 0..<count {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        guard @join.projection_at(checked, projection_index) is Some(projection) else {
          return None
        }
        let name = @schema.reference_name(projection.output)
        if name.length() > remaining {
          return None
        }
        remaining -= name.length()
        guard @decode.lookup(fields, name) is Some(authored) &&
          @decode.tree_index(authored, projection.source) ==
          @decode.tree_index(authored, authored) else {
          return None
        }
        remaining = match
          local_dedupe_field_work(output, projection.output, remaining) {
          Some(value) => value
          None => return None
        }
      }
    }
  }
  let mut expected = 3
  if @join.kind(checked) is Full {
    expected += 2
  }
  if @join.assertion(checked) is Some(_) {
    expected += 1
  }
  if @join.null_key(checked) is Fail {
    expected += 1
  }
  if @join.output_guard(checked) is Some(Parameter(_)) {
    expected += 1
  }
  guard @join.pending_validation_count(checked) == expected else { return None }
  for pending in 0..<expected {
    guard remaining > 0 &&
      @join.pending_validation_at(checked, pending) ==
      local_join_expected_obligation(checked, pending) else {
      return None
    }
    remaining -= 1
  }
  match @join.output_guard(checked) {
    Some(Parameter(name)) => {
      guard parameters is Some(values) else { return None }
      let mut selected : @parameters.BoundParameter? = None
      for parameter in 0..<@parameters.bound_value_count(values) {
        guard remaining > 0 &&
          @parameters.bound_value_at(values, parameter) is Some(original) else {
          return None
        }
        if original.name.length() > remaining - 1 {
          return None
        }
        remaining -= original.name.length() + 1
        if original.name == name {
          guard @parameters.bound_value_declaration(values, parameter)
            is Some(_) else {
            return None
          }
          selected = Some(original)
        }
      }
      guard selected is Some(original) else { return None }
      let mut found = false
      for resolution in 0..<@context.operation_closure_count(closure) {
        if remaining <= 0 {
          return None
        }
        remaining -= 1
        guard @context.operation_closure_at(closure, resolution)
          is Some(StaticResolution(Scalar(resolved))) &&
          physical_equal(resolved.site.pipeline, pipeline) &&
          resolved.site.step == index &&
          physical_equal(resolved.parameter, original) &&
          @pipeline.operation_scalar_demand(resolved.site.requirement)
          is Some(SafeInteger(wanted, minimum~)) &&
          wanted == name &&
          minimum == 1L &&
          resolved.value is Integer(value) &&
          value >= 1L &&
          value <= 9007199254740991L else {
          continue
        }
        found = true
        break
      }
      if !found {
        return None
      }
    }
    _ => ()
  }
  Some(remaining)
}

///|
fn local_join_expected_obligation(
  checked : @join.CheckedJoin,
  index : Int,
) -> @join.Obligation? {
  match index {
    0 => return Some(ResolveCardinality)
    1 => return Some(ResolveOutputLimit)
    2 => return Some(PreserveRowOrder)
    _ => ()
  }
  let mut offset = index - 3
  if @join.kind(checked) is Full {
    if offset == 0 {
      return Some(StableIdentity(Left))
    }
    if offset == 1 {
      return Some(StableIdentity(Right))
    }
    offset -= 2
  }
  if @join.assertion(checked) is Some(cardinality) {
    if offset == 0 {
      return Some(ValidateCardinality(cardinality))
    }
    offset -= 1
  }
  if @join.null_key(checked) is Fail {
    if offset == 0 {
      return Some(RejectNullKeys)
    }
    offset -= 1
  }
  if @join.output_guard(checked) is Some(Parameter(name)) && offset == 0 {
    return Some(BindGuard(name))
  }
  None
}
