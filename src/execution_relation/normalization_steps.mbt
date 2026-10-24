///|
/// Continuation of the original expression frame. Input extent preflight,
/// normalization, output measurement and construction each yield under the
/// common control/cancellation owner; no Host Unicode implementation is used.
fn advance_normalization_function(
  state : TextFunctionState,
  cursor : @canonical.NormalizationCursor,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  let expression = state.expression
  guard @lower.expression_text_bound(expression) is Some(original) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  let output = @expression_context.text_bound_output(original)
  if state.normalization_phase == 0 {
    if state.position == state.input.length() {
      state.normalization_phase = 1
      state.position = 0
      return Ok(None)
    }
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, width, _)) else {
      return Err({ kind: Scalar(InvalidOperand), expression, })
    }
    let (points, bytes) = @text_bounds.input_extent(
      @text_bounds.output_input(output),
    )
    if state.count.to_int64() >= points ||
      width.to_int64() > bytes - state.normalization_input_bytes {
      return Err({ kind: TextBounds(@text_bounds.InputCeiling), expression, })
    }
    state.count += 1
    state.normalization_input_bytes += width.to_int64()
    state.position = next
    return Ok(None)
  }
  if state.normalization_phase == 1 {
    match @canonical.advance_normalization(cursor) {
      Err(_) => return Err({ kind: Scalar(InvalidOperand), expression, })
      Ok(false) => return Ok(None)
      Ok(true) => {
        state.normalization_phase = 2
        state.position = 0
        return Ok(None)
      }
    }
  }
  if @canonical.normalization_scalar(cursor, state.position) is Some(scalar) {
    let (units, width, wire) = text_function_scalar_widths(scalar)
    if !state.building &&
      width.to_int64() > @text_bounds.output_bytes(output) - (state.weight - 1L) {
      return Err({ kind: TextBounds(@text_bounds.OutputCeiling), expression, })
    }
    match append_text_function_codepoint(state, scalar, units, width, wire) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    state.position += 1
    return Ok(None)
  }
  if !state.building {
    if !reserve_slots(workspace, state.units) {
      return Err({ kind: WorkspaceLimit, expression, })
    }
    state.allocated = state.units
    state.builder = Some(StringBuilder(size_hint=state.units * 2))
    state.building = true
    state.position = 0
    return Ok(None)
  }
  guard state.builder is Some(builder) else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  let result = builder.to_string()
  state.builder = None
  if state.output_root is Some(root) {
    root.root.measurement = Some({
      wire_bytes: state.bytes,
      weight: state.weight,
    })
  }
  Ok(Some(Text(result)))
}
