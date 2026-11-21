///|
// Existing row workspace allowance for the fixed expression state, its
// captured reserve callback, and the simultaneous backing-quote arguments.
// The matcher separately supplies the growing collection representation.
const REGEX_MATCH_SLOTS : Int = 4

///|
priv struct RegexWorkspace {
  owner : RowWorkspace
  mut slots : Int
}

///|
fn reserve_regex_backing(
  workspace : RegexWorkspace,
  extent : @shape.CollectionConstructionExtent,
) -> Bool {
  guard preparation_representation_cost({
      record_headers: extent.record_headers,
      reference_slots: extent.reference_slots,
      scalar_words: extent.scalar_words,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(bytes) else {
    return false
  }
  let slot_bytes = execution_capacity_node_bytes()
  let slots = bytes / slot_bytes +
    (if bytes % slot_bytes == 0L { 0L } else { 1L })
  if slots > 2147483647L {
    return false
  }
  let growth = slots.to_int() - workspace.slots
  if growth <= 0 {
    return true
  }
  if !reserve_slots(workspace.owner, growth) {
    return false
  }
  workspace.slots += growth
  true
}

///|
priv struct RegexMatchFrame {
  expression : @lower.Expression
  input : String
  pattern : @regex.Pattern
  flags : String
  max_points : Int64
  max_bytes : Int64
  left_root : ExpressionRootLease?
  right_root : ExpressionRootLease?
  workspace : RegexWorkspace
  mut position : Int
  mut points : Int64
  mut bytes : Int64
  mut search : @regex.Search?
}

///|
fn start_regex_match(
  expression : @lower.Expression,
  input : String,
  left_root : ExpressionRootLease?,
  right_root : ExpressionRootLease?,
  workspace : RowWorkspace,
) -> Result[RegexMatchFrame, EvalIssue] {
  guard @lower.expression_text_bound(expression) is Some(bound) &&
    @lower.text_bound_regex_pattern(bound) is Some((pattern, flags)) &&
    @text_bounds.output_operation(@lower.text_bound_output(bound)) is RegexMatch else {
    return Err({ kind: Scalar(InvalidOperand), expression, })
  }
  start_checked_regex(
    expression, input, pattern, flags, bound, left_root, right_root, workspace,
  )
}

///|
fn start_checked_regex(
  expression : @lower.Expression,
  input : String,
  pattern : @regex.Pattern,
  flags : String?,
  bound : @lower.ExpressionTextBound,
  left_root : ExpressionRootLease?,
  right_root : ExpressionRootLease?,
  workspace : RowWorkspace,
) -> Result[RegexMatchFrame, EvalIssue] {
  if !reserve_slots(workspace, REGEX_MATCH_SLOTS) {
    return Err({ kind: WorkspaceLimit, expression, })
  }
  let (max_points, max_bytes) = @text_bounds.input_extent(
    @text_bounds.output_input(@lower.text_bound_output(bound)),
  )
  Ok({
    expression,
    input,
    pattern,
    flags: flags.unwrap_or(""),
    max_points,
    max_bytes,
    left_root,
    right_root,
    workspace: { owner: workspace, slots: 0, },
    position: 0,
    points: 0L,
    bytes: 0L,
    search: None,
  })
}

///|
priv enum RegexProgress {
  RegexSearching
  RegexComplete(@regex.Match?)
}

///|
fn advance_regex_search(
  state : RegexMatchFrame,
) -> Result[RegexProgress, EvalIssue] {
  let expression = state.expression
  let invalid = { kind: Scalar(InvalidOperand), expression, }
  if state.search is Some(search) {
    return match search.advance() {
      SearchContinue => Ok(RegexSearching)
      SearchComplete(result) => Ok(RegexComplete(result))
      SearchFailed(SearchWorkspaceLimit) =>
        Err({ kind: WorkspaceLimit, expression, })
      SearchFailed(_) | SearchTerminal => Err(invalid)
    }
  }
  if state.position < state.input.length() {
    guard text_function_scalar(state.input, state.position)
      is Some((_, next, width, _)) else {
      return Err(invalid)
    }
    if state.points >= state.max_points ||
      width.to_int64() > state.max_bytes - state.bytes {
      return Err({ kind: TextBounds(@text_bounds.InputCeiling), expression, })
    }
    state.position = next
    state.points += 1L
    state.bytes += width.to_int64()
    return Ok(RegexSearching)
  }
  // The physical reserve gates every backing increase. Entry limits only
  // prevent index overflow. Expression control work meters every transition.
  let workspace = state.workspace
  match
    @regex.start_search(
      state.pattern,
      state.input,
      {
        from: 0,
        multiline: state.flags.contains("m"),
        dot_all: state.flags.contains("s"),
        max_entries: 2147483647,
      },
      reserve=extent => reserve_regex_backing(workspace, extent),
    ) {
    Ok(search) => {
      state.search = Some(search)
      Ok(RegexSearching)
    }
    Err(SearchWorkspaceLimit) => Err({ kind: WorkspaceLimit, expression, })
    Err(_) => Err(invalid)
  }
}
