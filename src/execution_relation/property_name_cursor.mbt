///|
priv struct PropertyNameState {
  expression : @lower.Expression
  name : String
  index : Int
  value : Value
  mut offset : Int
  mut measured : Bool
  mut actual : String
  mut selected : Value?
}

///|
/// Retain the original receiver while paying its authored name's UTF-8 charge.
/// Name-budget failure precedes missing-member/type failure as before. Matching
/// begins only afterward and never normalizes either spelling or data.
fn advance_property_name(
  state : PropertyNameState,
  budget : ControlBudget,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if !state.measured {
    if state.offset < state.name.length() {
      guard text_function_scalar(state.name, state.offset)
        is Some((_, next, width, _)) &&
        spend_control(budget, width) else {
        return Err({ kind: ControlLimit, expression, })
      }
      state.offset = next
      return Ok(None)
    }
    match state.value {
      Null => return Ok(Some(Null))
      Captured(@admitted.Object(fields)) => {
        guard @admitted.element_at(fields, state.index)
          is Some((actual, selected)) else {
          return Err({ kind: MissingValue, expression, })
        }
        if actual.length() != state.name.length() {
          return Err({ kind: MissingValue, expression, })
        }
        state.actual = actual
        state.selected = Some(capture(selected))
        state.measured = true
        state.offset = 0
      }
      _ => return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    return Ok(None)
  }
  let end = state.offset + Int::min(64, state.name.length() - state.offset)
  for index in state.offset..<end {
    if state.actual[index] != state.name[index] {
      return Err({ kind: MissingValue, expression, })
    }
  }
  state.offset = end
  if end == state.name.length() {
    Ok(state.selected)
  } else {
    Ok(None)
  }
}
