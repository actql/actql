///|
/// Apply fixed or prefix watermark semantics in the proven input occurrence
/// order. All time values and threshold arithmetic are validated before the
/// completed table can escape this function.
fn[T : RelationRows] evaluate_watermark_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.live < 0 ||
    workspace.live > workspace.limit ||
    workspace.peak < workspace.live {
    return Err(InvalidRowLimits)
  }
  guard @lower.kernel_watermark(kernel)
    is Some((time_field, timestamp, policy, threshold)) else {
    return Err(InvalidRows)
  }
  let names = input.field_names()
  let width = names.length()
  guard checked_row_slots_add(width, 3) is Some(output_width) else {
    return Err(RowLimit)
  }
  let count = IndexedRows::row_count(input)
  if count > max_rows ||
    !reserve_slots(workspace, output_width) ||
    !reserve_slots(workspace, count) {
    return Err(RowLimit)
  }
  let time_name = @schema.reference_name(time_field)
  if !spend_control_text(control, time_name) {
    return Err(RowLimit)
  }
  let mut time_column = -1
  for column in 0..<width {
    if !spend_control(control, 1) || !spend_control_text(control, names[column]) {
      return Err(RowLimit)
    }
    if names[column] == time_name {
      if time_column >= 0 {
        return Err(InvalidRows)
      }
      time_column = column
    }
  }
  if time_column < 0 {
    return Err(InvalidRows)
  }
  let times : Array[Double] = []
  for row in 0..<count {
    if IndexedRows::row_width(input, row) != width {
      return Err(InvalidRows)
    }
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let time = match
      window_time_milliseconds(
        IndexedRows::read_cell(input, row, time_column),
        timestamp,
        control,
      ) {
      Ok(value) => value
      Err(issue) => return Err(window_time_row_issue(issue, row))
    }
    times.push(time)
  }
  let output_names = names.copy()
  output_names.push("watermark_ms")
  output_names.push("watermark_late")
  output_names.push("watermark_decision")
  if !spend_control(control, output_names.length()) {
    return Err(RowLimit)
  }
  let rows : Array[Array[Value]] = []
  let mut prefix_max = 0.0
  let mut has_prefix = false
  for row in 0..<count {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let watermark = match threshold {
      @lower.FixedWatermark(value) => value
      @lower.PrefixWatermark(skew, _) => {
        if !has_prefix || times[row] > prefix_max {
          prefix_max = times[row]
          has_prefix = true
        }
        let value = prefix_max - skew.to_double()
        if value.is_nan() || value.is_inf() {
          return Err(WindowArithmetic(row))
        }
        if value == 0.0 {
          0.0
        } else {
          value
        }
      }
    }
    let late = times[row] < watermark
    if late && policy is @relation.DropLate {
      continue
    }
    if !spend_control(control, output_width) ||
      !reserve_slots(workspace, output_width) {
      return Err(RowLimit)
    }
    let values = Array::makei(width, column => {
      IndexedRows::read_cell(input, row, column)
    })
    values.push(Number(watermark))
    values.push(Boolean(late))
    values.push(Text(if late { "mark" } else { "keep" }))
    if !retain_row(values, output_names, output) {
      return Err(RowLimit)
    }
    rows.push(values)
  }
  Ok({ owner: input.checked_owner(), id: output_id, names: output_names, rows, })
}
