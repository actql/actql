///|
priv enum FieldNameSource {
  InputFields(Iter[(String, Value)])
  PriorSlot(Int)
}

///|
priv struct FieldNameState {
  expression : @lower.Expression
  name : String
  source : FieldNameSource
  mut offset : Int
  mut measured : Bool
  mut candidate : (String, Value)?
}

///|
/// Borrow the immutable frame input. The pinned Map iterator follows one linked
/// entry per next(), without hashing a whole spelling or copying the row.
/// Pay the original name charge before resolving either input or slot bindings.
fn advance_field_name(
  state : FieldNameState,
  slots : Array[Value],
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
    state.measured = true
    state.offset = 0
    return Ok(None)
  }
  match state.source {
    PriorSlot(index) =>
      match slots.get(index) {
        Some(value) => Ok(Some(value))
        None => Err({ kind: MissingValue, expression, })
      }
    InputFields(entries) => {
      if state.candidate is None {
        guard entries.next() is Some((actual, value)) else {
          return Err({ kind: MissingValue, expression, })
        }
        if actual.length() == state.name.length() {
          state.candidate = Some((actual, value))
          state.offset = 0
        }
        return Ok(None)
      }
      let (actual, value) = state.candidate.unwrap()
      let end = state.offset + Int::min(64, state.name.length() - state.offset)
      for index in state.offset..<end {
        if actual[index] != state.name[index] {
          state.candidate = None
          state.offset = 0
          return Ok(None)
        }
      }
      state.offset = end
      if end == state.name.length() {
        Ok(Some(value))
      } else {
        Ok(None)
      }
    }
  }
}
