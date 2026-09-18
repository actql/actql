///|
/// Expand an admitted array without preallocating from its declared bound.
/// Input-row and element order are retained exactly; outer synthetic rows use
/// NULL for both the element and exposed index.
fn[T : RelationRows] evaluate_unnest_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  guard @lower.kernel_unnest(kernel)
    is Some((column, element, index_name, outer, max_items)) else {
    return Err(InvalidRows)
  }
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  let names = input.field_names()
  let width = names.length()
  let source_name = @schema.reference_name(column)
  let mut source_column = -1
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) || !spend_control_text(control, names[i]) {
      return Err(RowLimit)
    }
    if names[i] == source_name {
      if source_column >= 0 {
        return Err(InvalidRows)
      }
      source_column = i
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  if source_column < 0 {
    return Err(InvalidRows)
  }
  let checked_output = @lower.kernel_output_schema(kernel)
  let output_names = Array::makei(@schema.field_count(checked_output), i => {
    @schema.reference_name(@schema.field_at(checked_output, i).unwrap().name)
  })
  if output_names.length() !=
    width + 1 + (if index_name is Some(_) { 1 } else { 0 }) {
    return Err(InvalidRows)
  }
  for name in output_names {
    if !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    if name != element &&
      !(index_name is Some(index) && name == index) &&
      !ordinals.contains(name) {
      return Err(InvalidRows)
    }
  }
  let result : Array[Array[Value]] = []
  let rows = IndexedRows::row_count(input)
  if !reserve_slots(workspace, rows) ||
    !reserve_slots(workspace, width) ||
    !reserve_slots(workspace, output_names.length()) {
    return Err(RowLimit)
  }
  for source = 0; source < rows; source = source + 1 {
    if IndexedRows::row_width(input, source) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) || !reserve_slots(workspace, width) {
      return Err(RowLimit)
    }
    let cell = IndexedRows::read_cell(input, source, source_column)
    let mut emitted = false
    match cell {
      Captured(@admitted.Array(items)) => {
        let count = @admitted.element_count(items)
        if max_items is Some(limit) && count.to_int64() > limit {
          return Err(InvalidRows)
        }
        for item_index = 0; item_index < count; item_index = item_index + 1 {
          guard @admitted.element_at(items, item_index) is Some(item) else {
            return Err(InvalidRows)
          }
          if result.length() >= max_rows ||
            !reserve_slots(workspace, output_names.length()) ||
            !spend_control(control, 1) {
            return Err(RowLimit)
          }
          let row = output_names.map(name => {
            if name == element {
              capture(item)
            } else if index_name is Some(index) && name == index {
              Number(item_index.to_double())
            } else {
              IndexedRows::read_cell(input, source, ordinals.get(name).unwrap())
            }
          })
          if !retain_row(row, output_names, output) {
            return Err(RowLimit)
          }
          result.push(row)
          emitted = true
        }
      }
      Null => ()
      _ => return Err(InvalidRows)
    }
    if outer && !emitted {
      if result.length() >= max_rows ||
        !reserve_slots(workspace, output_names.length()) ||
        !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let row = output_names.map(name => {
        if name == element || (index_name is Some(index) && name == index) {
          Null
        } else {
          IndexedRows::read_cell(input, source, ordinals.get(name).unwrap())
        }
      })
      if !retain_row(row, output_names, output) {
        return Err(RowLimit)
      }
      result.push(row)
    }
  }
  Ok({
    owner: RelationRows::checked_owner(input),
    id: output_id,
    names: output_names,
    rows: result,
  })
}
