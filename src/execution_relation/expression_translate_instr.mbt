///|
/// INSTR extends the existing STRPOS continuation: every scalar traversal and
/// candidate code-unit comparison is a separately charged expression poll.
/// Arguments stay finite integral Numbers until a reachable bound admits an Int.
fn advance_instr_function(
  state : TextFunctionState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.instr_phase == 0 {
    if state.position < state.input.length() {
      guard text_function_scalar(state.input, state.position)
        is Some((_, next, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.position = next
      state.count += 1
      return Ok(None)
    }
    let length = state.count.to_double()
    let position = state.instr_position
    let occurrence = state.instr_occurrence
    if state.search.is_empty() {
      // Empty patterns occupy all n+1 boundaries, including the trailing one.
      // Compare before addition so enormous finite integers cannot overflow.
      let start = if position > 0.0 {
        position
      } else {
        length + 2.0 + position
      }
      if start < 1.0 || start > length + 1.0 {
        return Ok(Some(Number(0.0)))
      }
      let available = if position > 0.0 { length + 2.0 - start } else { start }
      if occurrence > available {
        return Ok(Some(Number(0.0)))
      }
      let result = if position > 0.0 {
        start + (occurrence - 1.0)
      } else {
        start - (occurrence - 1.0)
      }
      return Ok(Some(Number(result)))
    }
    let start = if position > 0.0 { position - 1.0 } else { length + position }
    if start < 0.0 || start >= length || occurrence > length {
      return Ok(Some(Number(0.0)))
    }
    // The input's actual scalar count bounds both conversions, not a new
    // Number-domain ceiling. In particular very large valid operands return 0.
    state.substring_start = start.to_int64()
    state.instr_remaining = occurrence.to_int()
    if position > 0.0 {
      state.position = 0
      state.count = 0
    }
    state.instr_phase = 1
    return Ok(None)
  }
  if state.instr_phase == 1 {
    if state.count.to_int64() == state.substring_start {
      state.instr_phase = 2
      return Ok(None)
    }
    if state.instr_position > 0.0 {
      guard text_function_scalar(state.input, state.position)
        is Some((_, next, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.position = next
      state.count += 1
    } else {
      guard text_function_previous_scalar(state.input, state.position)
        is Some((_, previous, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.position = previous
      state.count -= 1
    }
    return Ok(None)
  }
  if state.instr_phase == 3 {
    // Advance one original scalar even after a match: occurrences may overlap.
    if state.instr_position > 0.0 {
      if state.position == state.input.length() {
        return Ok(Some(Number(0.0)))
      }
      guard text_function_scalar(state.input, state.position)
        is Some((_, next, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.position = next
      state.count += 1
    } else {
      if state.position == 0 {
        return Ok(Some(Number(0.0)))
      }
      guard text_function_previous_scalar(state.input, state.position)
        is Some((_, previous, _, _)) else {
        return Err({ kind: Scalar(InvalidOperand), expression, })
      }
      state.position = previous
      state.count -= 1
    }
    state.matched = 0
    state.instr_phase = 2
    return Ok(None)
  }
  if state.search.length() > state.input.length() - state.position {
    if state.instr_position > 0.0 {
      return Ok(Some(Number(0.0)))
    }
    state.instr_phase = 3
    return Ok(None)
  }
  if state.input[state.position + state.matched] == state.search[state.matched] {
    state.matched += 1
    if state.matched == state.search.length() {
      state.instr_remaining -= 1
      if state.instr_remaining == 0 {
        return Ok(Some(Number((state.count + 1).to_double())))
      }
      state.instr_phase = 3
    }
  } else {
    state.instr_phase = 3
  }
  Ok(None)
}

///|
/// Check every source scalar pair even for an empty input or unused mapping.
/// Retained cursors need no unadmitted map allocation; duplicate work remains
/// subject to the existing control/logical-work and cancellation owners.
fn advance_translate_validation(
  state : TextFunctionState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  if state.translate_outer == state.search.length() {
    state.translate_validated = true
    return Ok(None)
  }
  guard text_function_scalar(state.search, state.translate_outer)
    is Some((scalar, next, _, _)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if state.translate_inner == 0 {
    state.translate_inner = next
    return Ok(None)
  }
  if state.translate_inner == state.search.length() {
    state.translate_outer = next
    state.translate_inner = 0
    return Ok(None)
  }
  guard text_function_scalar(state.search, state.translate_inner)
    is Some((candidate, next, _, _)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if scalar == candidate {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  state.translate_inner = next
  Ok(None)
}

///|
/// Look up one source/target scalar pair per poll. Output is written only by
/// the shared exact-size admission/build passes; translated output is never
/// looked up again. Missing target scalars delete the corresponding input.
fn advance_translate_scalar(
  state : TextFunctionState,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  guard text_function_scalar(state.input, state.position)
    is Some((scalar, input_next, _, _)) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if state.matched == state.search.length() {
    match append_text_function_scalar(state, state.input, state.position) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  } else {
    guard text_function_scalar(state.search, state.matched)
      is Some((candidate, source_next, _, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    let target = text_function_scalar(state.replacement, state.emission)
    if state.emission < state.replacement.length() && target is None {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    if candidate != scalar {
      state.matched = source_next
      if target is Some((_, next, _, _)) {
        state.emission = next
      }
      return Ok(None)
    }
    if target is Some((mapped, next, width, wire)) {
      match
        append_text_function_codepoint(
          state,
          mapped,
          next - state.emission,
          width,
          wire,
        ) {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
    }
  }
  state.position = input_next
  state.matched = 0
  state.emission = 0
  Ok(None)
}
