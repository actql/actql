///|
/// A continuation of the existing Value recheck owner, followed by the original
/// row-Text control charge. It neither normalizes data nor invents a root proof.
priv struct RawTextAdmission {
  cursor : @admitted.RecheckCursor
  workspace : RowWorkspace
  mut value : @admitted.Value?
  mut remaining : Int
  mut checked : Bool
  mut closed : Bool
}

///|
fn start_raw_text_admission(
  text : String,
  workspace : RowWorkspace,
) -> Result[RawTextAdmission, RowIssue] {
  // The state, one recheck owner and its single scalar frame need three slots.
  if !reserve_slots(workspace, 3) {
    return Err(RowLimit)
  }
  guard @admitted.start_recheck_runtime_text(
      text,
      @contract.primitive(@contract.StringType, nullable=false),
      { max_nodes: 1, max_text_bytes: 2147483647, max_depth: 0, },
    )
    is Some(cursor) else {
    release_slots(workspace, 3)
    return Err(InvalidRows)
  }
  Ok({
    cursor,
    workspace,
    value: None,
    remaining: 0,
    checked: false,
    closed: false,
  })
}

///|
fn close_raw_text_admission(state : RawTextAdmission) -> Unit {
  if state.closed {
    return
  }
  @admitted.cancel_recheck_runtime_value(state.cursor)
  state.value = None
  state.remaining = 0
  state.closed = true
  release_slots(state.workspace, 3)
}

///|
fn advance_raw_text_admission(
  state : RawTextAdmission,
  control : ControlBudget,
) -> Result[@admitted.Value?, RowIssue] {
  if state.closed {
    return Err(InvalidRows)
  }
  if !state.checked {
    match @admitted.advance_recheck_runtime_value(state.cursor) {
      RecheckContinue => return Ok(None)
      RecheckFailed => {
        close_raw_text_admission(state)
        return Err(RowLimit)
      }
      RecheckComplete(value, _, bytes) => {
        state.value = Some(value.value)
        state.remaining = bytes
        state.checked = true
        return Ok(None)
      }
    }
  }
  if state.remaining > 0 {
    if !spend_control(control, 1) {
      close_raw_text_admission(state)
      return Err(RowLimit)
    }
    state.remaining -= 1
    return Ok(None)
  }
  let value = state.value
  close_raw_text_admission(state)
  Ok(value)
}
