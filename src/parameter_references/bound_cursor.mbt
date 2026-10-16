///|
/// Read an already selected value only for an occurrence in this exact source.
/// Reuse this Owner's pointer encoding; equal text or a name alone is not an
/// occurrence binding. The returned value remains the original binding.
pub fn bound_value_for_cursor(
  bound : BoundIndex,
  cursor : @decode.Cursor,
  max_work : Int,
) -> Result[(@parameter.BoundParameter?, Int), BindingIssue] {
  if max_work < 0 {
    return Err(InvalidLimits)
  }
  let index = bound.index
  if @decode.tree_index(index.source, cursor) is None {
    return Ok((None, 0))
  }
  let root_path = @decode.cursor_path(index.source)
  let path = @decode.cursor_path(cursor)
  if root_path.length() > path.length() {
    return Ok((None, 0))
  }
  if root_path.length() > max_work ||
    path.length() > max_work - root_path.length() {
    return Err(WorkLimit)
  }
  let budget = { remaining: max_work - root_path.length() - path.length(), }
  for at in 0..<root_path.length() {
    if root_path[at] != path[at] {
      return Ok((None, max_work - budget.remaining))
    }
  }
  let out = StringBuilder()
  write_segments(out, path, root_path.length(), budget) catch {
    _ => return Err(WorkLimit)
  }
  let pointer = out.to_string()
  let mut name : String? = None
  for reference in index.entries {
    for amount in [1, reference.path.length(), pointer.length()] {
      if amount > budget.remaining {
        return Err(WorkLimit)
      }
      budget.remaining -= amount
    }
    if reference.path == pointer {
      name = Some(reference.name)
      break
    }
  }
  guard name is Some(name) else {
    return Ok((None, max_work - budget.remaining))
  }
  for selected in bound.selected {
    for amount in [1, selected.name.length(), name.length()] {
      if amount > budget.remaining {
        return Err(WorkLimit)
      }
      budget.remaining -= amount
    }
    if selected.name == name {
      return Ok((Some(selected), max_work - budget.remaining))
    }
  }
  Ok((None, max_work - budget.remaining))
}
