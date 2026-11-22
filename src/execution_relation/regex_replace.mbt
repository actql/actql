///|
priv enum RegexReplacePhase {
  FindMatch
  FindFrom(Int)
  CopyUnmatched(Int)
  ReplacementPart(Int)
  CopyReplacement(Int, String, Int, Int)
  CopyTail
}

///|
priv struct RegexReplaceFrame {
  output : TextFunctionState
  search : RegexMatchFrame
  replacement : @replacement.Replacement
  max_replacements : Int64
  mut replacements_left : Int64
  mut remaining_bytes : Int64
  mut phase : RegexReplacePhase
  mut position : Int
  mut previous_match : Bool
  mut selected : @regex.Match?
}

///|
fn start_regex_replace(
  frame : ExpressionFrame,
  output : TextFunctionState,
  args : Array[Value],
) -> Result[Unit, EvalIssue] {
  let expression = output.expression
  let invalid = { kind: Scalar(InvalidOperand), expression, }
  guard @lower.expression_text_bound(expression) is Some(bound) &&
    @lower.text_bound_regex_replace(bound)
    is Some((pattern, flags, replacement)) &&
    args[1] is Text(_) &&
    args[2] is Text(_) else {
    return Err(invalid)
  }
  let extent = @lower.text_bound_output(bound)
  guard @text_bounds.output_operation(extent) is RegexReplace(expected) &&
    physical_equal(expected, replacement) &&
    @text_bounds.output_replacements(extent) is Some(max_replacements) else {
    return Err(invalid)
  }
  if output.null_result {
    return return_measured_text(frame, output, Null)
  }
  let search = start_checked_regex(
    expression,
    output.input,
    pattern,
    flags,
    bound,
    None,
    None,
    frame.workspace,
  )
  search.map(search => {
    frame.state = RegexReplacing({
      output,
      search,
      replacement,
      max_replacements,
      replacements_left: max_replacements,
      remaining_bytes: @text_bounds.output_bytes(extent),
      phase: FindMatch,
      position: 0,
      previous_match: false,
      selected: None,
    })
  })
}

///|
fn append_regex_replacement_scalar(
  state : RegexReplaceFrame,
  text : String,
  position : Int,
  end : Int,
) -> Result[Int, EvalIssue] {
  let expression = state.output.expression
  guard text_function_scalar(text, position)
    is Some((scalar, next, width, wire)) &&
    next <= end else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  if !state.output.building {
    if width.to_int64() > state.remaining_bytes {
      return Err({ kind: TextBounds(@text_bounds.OutputCeiling), expression, })
    }
    state.remaining_bytes -= width.to_int64()
  }
  append_text_function_codepoint(
    state.output,
    scalar,
    next - position,
    width,
    wire,
  ).map(_ => next)
}

///|
fn advance_past_empty_regex_match(
  state : RegexReplaceFrame,
  end : Int,
) -> Result[Unit, EvalIssue] {
  let input = state.output.input
  if end == input.length() {
    state.phase = CopyTail
  } else {
    // Move the search by one scalar without dropping that scalar from output.
    guard text_function_scalar(input, end) is Some((_, next, _, _)) else {
      return Err({
        kind: Scalar(InvalidOperand),
        expression: state.output.expression,
      })
    }
    state.phase = FindFrom(next)
  }
  Ok(())
}

///|
fn advance_regex_replacement_part(
  state : RegexReplaceFrame,
  index : Int,
) -> Result[Unit, EvalIssue] {
  let expression = state.output.expression
  let invalid = { kind: Scalar(InvalidOperand), expression, }
  guard state.selected is Some(selected) else { return Err(invalid) }
  let input = state.output.input
  match @replacement.part_at(state.replacement, index) {
    Some(Literal(text)) =>
      state.phase = CopyReplacement(index, text, 0, text.length())
    Some(Capture(capture)) =>
      state.phase = if @regex.capture_span(selected, capture) is Some(span) {
        CopyReplacement(index, input, span.start, span.end)
      } else {
        ReplacementPart(index + 1)
      }
    None => {
      let { start, end, } = @regex.match_span(selected)
      state.selected = None
      state.position = end
      state.previous_match = true
      if start < end {
        state.phase = FindFrom(end)
      } else {
        return advance_past_empty_regex_match(state, end)
      }
    }
  }
  Ok(())
}

///|
fn advance_regex_replace(
  frame : ExpressionFrame,
  state : RegexReplaceFrame,
) -> Result[Unit, EvalIssue] {
  let output = state.output
  let expression = output.expression
  let input = output.input
  match state.phase {
    FindMatch =>
      match advance_regex_search(state.search) {
        Err(issue) => return Err(issue)
        Ok(RegexSearching) => ()
        Ok(RegexComplete(None)) => {
          state.search.search = None
          state.phase = CopyTail
        }
        Ok(RegexComplete(Some(selected))) => {
          state.search.search = None
          let { start, end, } = @regex.match_span(selected)
          // The SQL dialect skips an empty match at the end of the previous
          // match, preserving the next input scalar and the replacement count.
          if start == end &&
            state.previous_match &&
            start == state.position &&
            @replacement.syntax(state.replacement) == @replacement.GoogleSql {
            return advance_past_empty_regex_match(state, end)
          }
          if state.replacements_left == 0L {
            return Err({
              kind: TextBounds(@text_bounds.ReplacementCeiling),
              expression,
            })
          }
          state.replacements_left -= 1L
          state.selected = Some(selected)
          state.phase = CopyUnmatched(start)
        }
      }
    FindFrom(from) =>
      return begin_regex_search(state.search, from).map(_ => {
        state.phase = FindMatch
      })
    CopyUnmatched(end) =>
      if state.position == end {
        state.phase = ReplacementPart(0)
      } else {
        return append_regex_replacement_scalar(
          state,
          input,
          state.position,
          end,
        ).map(next => state.position = next)
      }
    ReplacementPart(index) =>
      return advance_regex_replacement_part(state, index)
    CopyReplacement(index, text, at, end) =>
      if at == end {
        state.phase = ReplacementPart(index + 1)
      } else {
        return append_regex_replacement_scalar(state, text, at, end).map(next => {
          state.phase = CopyReplacement(index, text, next, end)
        })
      }
    CopyTail => {
      let end = input.length()
      if state.position < end {
        return append_regex_replacement_scalar(
          state,
          input,
          state.position,
          end,
        ).map(next => state.position = next)
      }
      if output.building {
        // The last match and search have retired. Keep the high-water backing
        // across both passes so any restarted search remains funded.
        return finish_measured_text_output(output).bind(value => {
          release_slots(
            frame.workspace,
            REGEX_MATCH_SLOTS + state.search.workspace.slots,
          )
          return_measured_text(frame, output, value)
        })
      }
      // Both passes consume the same immutable input and checked ASTs. Only
      // the search/copy cursor restarts, never the original child evaluation.
      return begin_measured_text_output(output, frame.workspace).map(_ => {
        state.position = 0
        state.previous_match = false
        state.replacements_left = state.max_replacements
        state.phase = FindFrom(0)
      })
    }
  }
  Ok(())
}
