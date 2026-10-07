///|
pub(all) enum ArrayProfileIssue {
  InvalidLimits
  BudgetExceeded
  InvalidCheckedProgram
  UnsupportedNestedArray(Int, Int, @expression.Location)
}

///|
// Read authoritative node contracts; do not infer a second type from SQL text.
// A STRUCT between arrays is allowed. Opaque JSON contents are not SQL arrays.
fn array_nested_source(
  expression : @typing.TypedExpression,
  max_work : Int,
) -> Result[(@expression.Location?, Int), ArrayProfileIssue] {
  let count = @typing.node_count(expression)
  if count > max_work {
    return Err(BudgetExceeded)
  }
  for index in 0..<count {
    match @typing.node_form(expression, index) {
      Some(Expression("array", _)) | Some(Expression("empty_array", _)) => {
        guard @typing.node_at(expression, index) is Some(node) else {
          return Err(InvalidCheckedProgram)
        }
        match node.contract.shape {
          @contract.Array(item, ..) =>
            if item.shape is @contract.Array(_, ..) {
              guard @expression.origin(
                  @typing.expression(expression),
                  node.source,
                )
                is Some(location) else {
                return Err(InvalidCheckedProgram)
              }
              return Ok((Some(location), index + 1))
            }
          _ => return Err(InvalidCheckedProgram)
        }
      }
      _ => ()
    }
  }
  Ok((None, count))
}

///|
/// Validate source ARRAY constructors after the ordinary checker has resolved
/// references and parameters. Machine Program input retains its recursive array
/// contract. This check neither evaluates expressions nor creates an Owner.
pub fn check_array_profile(
  program : @check.CheckedProgram,
  max_work~ : Int,
  max_slots~ : Int,
) -> Result[Unit, ArrayProfileIssue] {
  if max_work < 0 || max_slots < 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_work
  let mut slots_left = max_slots
  for unit in 0..<@check.unit_count(program) {
    if remaining == 0 {
      return Err(BudgetExceeded)
    }
    remaining -= 1
    guard @check.unit_pipeline(program, unit) is Some(pipeline) else {
      return Err(InvalidCheckedProgram)
    }
    let slots = match
      @pipeline.collect_expression_slots(
        pipeline,
        max_work=remaining,
        max_slots=slots_left,
      ) {
      Ok(slots) => slots
      Err(WorkLimit | SlotLimit) => return Err(BudgetExceeded)
      Err(_) => return Err(InvalidCheckedProgram)
    }
    remaining -= @pipeline.expression_slots_work(slots)
    let count = @pipeline.expression_slot_count(slots)
    slots_left -= count
    for index in 0..<count {
      guard @pipeline.expression_slot_at(slots, index) is Some(slot) else {
        return Err(InvalidCheckedProgram)
      }
      let (source, work) = match
        array_nested_source(slot.expression, remaining) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      remaining -= work
      if source is Some(source) {
        return Err(UnsupportedNestedArray(unit, slot.step, source))
      }
    }
  }
  Ok(())
}
