///|
// Continuation of the SAME expression frame and its two operand roots. The
// existing fixed progress controls are mode-local: position/matched are the
// input/pattern offsets, probe_position/translate_inner the last % restart,
// and translate_outer/translate_validated the original-pattern comparison.
// No pattern/input array, substring, regex engine or replacement is created.
fn advance_like_function(
  state : TextFunctionState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if !state.translate_validated {
    let original = state.replacement
    if state.translate_outer == original.length() {
      state.translate_validated = true
      state.probe_position = -1
    } else {
      if original.code_unit_at(state.translate_outer) !=
        state.search.code_unit_at(state.translate_outer) {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.translate_outer += 1
    }
    return Ok(None)
  }
  if state.null_result {
    return Ok(Some(Null))
  }
  if state.matched == state.search.length() &&
    state.position == state.input.length() {
    return Ok(Some(Boolean(true)))
  }
  if state.matched < state.search.length() {
    guard text_function_scalar(state.search, state.matched)
      is Some((token, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    if token == '%' {
      state.translate_inner = next
      state.probe_position = state.position
      state.matched = next
      return Ok(None)
    }
    let (literal, next, wildcard) = if token == '\\' {
      guard text_function_scalar(state.search, next)
        is Some((escaped, after, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      (escaped, after, false)
    } else {
      (token, next, token == '_')
    }
    if state.position < state.input.length() {
      guard text_function_scalar(state.input, state.position)
        is Some((observed, after, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      if wildcard || literal == observed {
        state.position = after
        state.matched = next
        return Ok(None)
      }
    }
  }
  if state.probe_position >= 0 && state.probe_position < state.input.length() {
    guard text_function_scalar(state.input, state.probe_position)
      is Some((_, next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    state.probe_position = next
    state.position = next
    state.matched = state.translate_inner
    return Ok(None)
  }
  Ok(Some(Boolean(false)))
}
