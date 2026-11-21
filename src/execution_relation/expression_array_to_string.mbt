///|
// One borrowed array, delimiter, replacement and selected part, plus cursor
// state. All original operand roots remain held by the common Text frame.
const ARRAY_TEXT_JOIN_SLOTS : Int = 9

///|
priv struct ArrayTextJoin {
  items : @admitted.FrozenArray[@admitted.Value]
  delimiter : String
  null_text : String?
  mut index : Int
  mut part : String?
  mut separator : Bool
  mut seen : Bool
}

///|
fn advance_array_text_join(
  state : TextFunctionState,
  join : ArrayTextJoin,
  workspace : RowWorkspace,
) -> Result[Value?, EvalIssue] {
  if join.part is Some(part) {
    let from = if join.separator { join.delimiter } else { part }
    if state.position == from.length() {
      state.position = 0
      if join.separator {
        join.separator = false
      } else {
        join.part = None
        join.seen = true
      }
      return Ok(None)
    }
    match append_text_function_scalar(state, from, state.position) {
      Err(issue) => return Err(issue)
      Ok(next) => state.position = next
    }
    return Ok(None)
  }
  if @admitted.element_at(join.items, join.index) is Some(item) {
    join.part = match item {
      @admitted.Text(text) => Some(text)
      @admitted.Null => join.null_text
      _ =>
        return Err({
          kind: Scalar(InvalidOperand),
          expression: state.expression,
        })
    }
    join.index += 1
    join.separator = join.seen
    return Ok(None)
  }
  if state.building {
    return finish_measured_text_output(state).map(value => Some(value))
  }
  match begin_measured_text_output(state, workspace) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  join.index = 0
  join.seen = false
  Ok(None)
}
