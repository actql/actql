///|
priv struct RegexCaptureText {
  start : Int
  end : Int
  mut position : Int
  mut remaining_bytes : Int64
}

///|
fn start_regex_extract(
  frame : ExpressionFrame,
  state : TextFunctionState,
  args : Array[Value],
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  let invalid = { kind: Scalar(InvalidOperand), expression, }
  guard @lower.expression_text_bound(expression) is Some(bound) &&
    @lower.text_bound_regex_extract(bound) is Some((pattern, flags, capture)) &&
    args[1] is Text(_) &&
    args[2] is Number(index) &&
    index == capture.to_double() else {
    return Err(invalid)
  }
  let output = @lower.text_bound_output(bound)
  guard @text_bounds.output_operation(output) is RegexExtract else {
    return Err(invalid)
  }
  if state.null_result {
    return return_measured_text(frame, state, Null)
  }
  let search = match
    start_checked_regex(
      expression,
      state.input,
      pattern,
      flags,
      bound,
      None,
      None,
      frame.workspace,
    ) {
    Ok(search) => search
    Err(issue) => return Err(issue)
  }
  frame.state = RegexExtracting(
    state,
    search,
    capture,
    @text_bounds.output_bytes(output),
  )
  Ok(())
}

///|
fn advance_regex_extract(
  frame : ExpressionFrame,
  state : TextFunctionState,
  search : RegexMatchFrame,
  capture : Int,
  max_bytes : Int64,
) -> Result[Unit, EvalIssue] {
  match advance_regex_search(search) {
    Err(issue) => Err(issue)
    Ok(RegexSearching) => Ok(())
    Ok(RegexComplete(found)) => {
      let span = found.bind(result => @regex.capture_span(result, capture))
      let next = if span is Some({ start, end, }) {
        match admit_text_expression_output(state.expression, frame.scope) {
          Err(issue) => return Err(issue)
          Ok(root) => state.output_root = root
        }
        // Only offsets survive into the sizing and copying steps. Keep the
        // matcher quote until the separately reserved cursor owns them.
        frame.state = RegexCaptureText(state, {
          start,
          end,
          position: start,
          remaining_bytes: max_bytes,
        })
        Ok(())
      } else {
        return_measured_text(frame, state, Null)
      }
      search.search = None
      release_slots(frame.workspace, REGEX_MATCH_SLOTS + search.workspace.slots)
      next
    }
  }
}

///|
fn advance_regex_capture(
  frame : ExpressionFrame,
  state : TextFunctionState,
  capture : RegexCaptureText,
) -> Result[Unit, EvalIssue] {
  let expression = state.expression
  if capture.position == capture.end {
    if state.building {
      return finish_measured_text_output(state).bind(value => {
        return_measured_text(frame, state, value)
      })
    }
    return begin_measured_text_output(state, frame.workspace).map(_ => {
      capture.position = capture.start
    })
  }
  guard text_function_scalar(state.input, capture.position)
    is Some((scalar, next, width, wire)) &&
    next <= capture.end else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if !state.building {
    if width.to_int64() > capture.remaining_bytes {
      return Err({ kind: TextBounds(@text_bounds.OutputCeiling), expression, })
    }
    capture.remaining_bytes -= width.to_int64()
  }
  append_text_function_codepoint(
    state,
    scalar,
    next - capture.position,
    width,
    wire,
  ).map(_ => capture.position = next)
}
