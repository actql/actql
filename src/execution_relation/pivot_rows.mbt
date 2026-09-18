///|
/// One canonical index group. Sorted row indices retain logical input order
/// within an equal-key run, which is the only order observed by `first`.
priv struct PivotGroup {
  representative : Int?
  start : Int
  end : Int
}

///|
fn[T : IndexedRows] pivot_groups(
  input : T,
  indices : Array[Int],
  order : Array[ColumnOrder],
  max_groups : Int,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[PivotGroup], RowIssue] {
  let groups : Array[PivotGroup] = []
  let add = fn(representative : Int?, start : Int, end : Int) -> Bool {
    if groups.length() >= max_groups ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, 1) {
      return false
    }
    groups.push({ representative, start, end, })
    true
  }
  if order.is_empty() {
    if !add(indices.get(0), 0, indices.length()) {
      return Err(RowLimit)
    }
    return Ok(groups)
  }
  if indices.is_empty() {
    return Ok(groups)
  }
  let mut start = 0
  for position = 1; position < indices.length(); position = position + 1 {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    let different = match
      compare_row_indices(
        input,
        indices[position - 1],
        indices[position],
        order,
        control,
      ) {
      Ok(comparison) => comparison != 0
      Err(InvalidInput) => return Err(InvalidRows)
      Err(Limit) => return Err(RowLimit)
      Err(Scalar(issue)) => return Err(Comparison(issue))
    }
    if different {
      if !add(Some(indices[start]), start, position) {
        return Err(RowLimit)
      }
      start = position
    }
  }
  if !add(Some(indices[start]), start, indices.length()) {
    return Err(RowLimit)
  }
  Ok(groups)
}

///|
/// Empty pivot axes use first-occurrence index-group order rather than the
/// ordinary canonical key order. Sort only group coordinates, never rows.
fn first_occurrence_group_order(
  groups : Array[PivotGroup],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Array[Int], RowIssue] {
  let count = groups.length()
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  let mut source = Array::makei(count, i => i)
  if count < 2 {
    return Ok(source)
  }
  if !reserve_slots(workspace, count) || !spend_control(control, count) {
    return Err(RowLimit)
  }
  let mut target = Array::make(count, 0)
  let mut width = 1
  while width < count {
    let mut start = 0
    while start < count {
      let middle = start + Int::min(width, count - start)
      let end = middle + Int::min(width, count - middle)
      let mut left = start
      let mut right = middle
      for out = start; out < end; out = out + 1 {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        let choose_left = if left == middle {
          false
        } else if right == end {
          true
        } else {
          let a = groups[source[left]].representative.unwrap_or(-1)
          let b = groups[source[right]].representative.unwrap_or(-1)
          a <= b
        }
        if choose_left {
          target[out] = source[left]
          left += 1
        } else {
          target[out] = source[right]
          right += 1
        }
      }
      start = end
    }
    let previous = source
    source = target
    target = previous
    if width > count / 2 {
      break
    }
    width *= 2
  }
  Ok(source)
}

///|
fn pivot_fill_value(pivot : @lower.PreparedPivot) -> Value {
  match @lower.pivot_fill(pivot) {
    None | Some(@lower.Null) => Null
    Some(@lower.Value(value)) => capture(value.value)
  }
}

///|
/// Deterministic pivot lane. Binary64 sum/avg are deliberately excluded here:
/// their checked numeric slots require attempt-bound durable observations, not
/// a local fold hidden inside this row materializer.
fn[T : RelationRows] evaluate_pivot_rows(
  kernel : @lower.PreparedKernel,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  guard @lower.kernel_pivot(kernel) is Some(pivot) else {
    return Err(InvalidRows)
  }
  let function = @lower.pivot_function(pivot)
  if function is @relation.Sum || function is @relation.Avg {
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
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) ||
      !spend_control_text(control, names[i]) ||
      !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    if ordinals.contains(names[i]) {
      return Err(InvalidRows)
    }
    ordinals[names[i]] = i
  }
  let resolve = fn(field : @schema.FieldName) -> Result[Int, RowIssue] {
    let name = @schema.reference_name(field)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    match ordinals.get(name) {
      Some(index) => Ok(index)
      None => Err(InvalidRows)
    }
  }
  let index_count = @lower.pivot_index_count(pivot)
  let axis_count = @lower.pivot_axis_count(pivot)
  if !reserve_slots(workspace, index_count) ||
    !reserve_slots(workspace, axis_count) ||
    !reserve_slots(workspace, axis_count) ||
    !spend_control(control, index_count + axis_count) {
    return Err(RowLimit)
  }
  let order : Array[ColumnOrder] = []
  let index_by_name : Map[String, Int] = Map([])
  for i = 0; i < index_count; i = i + 1 {
    let field = @lower.pivot_index_at(pivot, i).unwrap()
    let ordinal = match resolve(field) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    order.push({ column: ordinal, descending: false, nulls_first: true, })
    let name = @schema.reference_name(field)
    if !index_by_name.contains(name) {
      index_by_name[name] = ordinal
    }
  }
  let pivot_column = match resolve(@lower.pivot_column(pivot)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let value_column = match resolve(@lower.pivot_value(pivot)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let axis_by_name : Map[String, Int] = Map([])
  for i = 0; i < axis_count; i = i + 1 {
    let name = @lower.pivot_axis_at(pivot, i).unwrap()
    if !spend_control_text(control, name) || axis_by_name.contains(name) {
      return Err(InvalidRows)
    }
    axis_by_name[name] = i
  }
  let schema = @lower.pivot_output_schema(pivot)
  let output_width = @schema.field_count(schema)
  if !reserve_slots(workspace, output_width) ||
    !reserve_slots(workspace, output_width) {
    return Err(RowLimit)
  }
  let output_names : Array[String] = []
  // false selects an index column; true selects one authored pivot bucket.
  let projection : Array[(Bool, Int)] = []
  for i = 0; i < output_width; i = i + 1 {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    if !spend_control(control, 1) || !spend_control_text(control, name) {
      return Err(RowLimit)
    }
    output_names.push(name)
    match index_by_name.get(name) {
      Some(column) => projection.push((false, column))
      None =>
        match axis_by_name.get(name) {
          Some(axis) => projection.push((true, axis))
          None => return Err(InvalidRows)
        }
    }
  }
  let indices = match stable_order_indices(input, order, control, workspace) {
    Ok(value) => value
    Err(InvalidInput) => return Err(InvalidRows)
    Err(Limit) => return Err(RowLimit)
    Err(Scalar(issue)) => return Err(Comparison(issue))
  }
  let groups = match
    pivot_groups(input, indices, order, max_rows, control, workspace) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let group_order = if axis_count == 0 && !order.is_empty() {
    match first_occurrence_group_order(groups, control, workspace) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    if !reserve_slots(workspace, groups.length()) ||
      !spend_control(control, groups.length()) {
      return Err(RowLimit)
    }
    Array::makei(groups.length(), i => i)
  }
  let fill = pivot_fill_value(pivot)
  let result : Array[Array[Value]] = []
  for group_index in group_order {
    let group = groups[group_index]
    if result.length() >= max_rows ||
      !spend_control(control, 1) ||
      !reserve_slots(workspace, axis_count) ||
      !reserve_slots(workspace, axis_count) ||
      !reserve_slots(workspace, output_width) {
      return Err(RowLimit)
    }
    let counts = Array::make(axis_count, 0)
    let selected : Array[Value?] = Array::make(axis_count, None)
    for position = group.start; position < group.end; position = position + 1 {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let source = indices[position]
      let axis = match IndexedRows::read_cell(input, source, pivot_column) {
        Text(name) => axis_by_name.get(name)
        Null => None
        _ => return Err(InvalidRows)
      }
      if axis is Some(axis) {
        let value = IndexedRows::read_cell(input, source, value_column)
        if !(value is Null) {
          counts[axis] += 1
          match function {
            @relation.Count => ()
            @relation.First =>
              if selected[axis] is None {
                selected[axis] = Some(value)
              }
            @relation.Min | @relation.Max =>
              match selected[axis] {
                None => selected[axis] = Some(value)
                Some(previous) => {
                  if !spend_control(control, 1) ||
                    !charge_comparison_operand(control, previous) ||
                    !charge_comparison_operand(control, value) {
                    return Err(RowLimit)
                  }
                  let comparison = match compare(value, previous) {
                    Ok(value) => value
                    Err(issue) => return Err(Comparison(issue))
                  }
                  if (function is @relation.Min && comparison < 0) ||
                    (function is @relation.Max && comparison > 0) {
                    selected[axis] = Some(value)
                  }
                }
              }
            @relation.Sum | @relation.Avg => return Err(InvalidRows)
            _ => return Err(InvalidRows)
          }
        }
      }
    }
    let row : Array[Value] = []
    for (aggregate, index) in projection {
      if aggregate {
        row.push(
          if function is @relation.Count {
            Number(counts[index].to_double())
          } else {
            selected[index].unwrap_or(fill)
          },
        )
      } else {
        guard group.representative is Some(source) else {
          return Err(InvalidRows)
        }
        row.push(IndexedRows::read_cell(input, source, index))
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    result.push(row)
  }
  Ok({
    owner: RelationRows::checked_owner(input),
    id: output_id,
    names: output_names,
    rows: result,
  })
}
