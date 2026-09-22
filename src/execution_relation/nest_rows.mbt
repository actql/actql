///|
fn nest_index_issue(issue : JoinIndexIssue) -> RowIssue {
  match issue {
    InvalidInput => InvalidRows
    Limit => RowLimit
    NullKey(..) | DuplicateKey(..) => InvalidRows
    Scalar(issue) => Comparison(issue)
  }
}

///|
fn admitted_nest_value(
  value : Value,
  control : ControlBudget,
) -> Result[@admitted.Value, RowIssue] {
  match value {
    Null => Ok(@admitted.null_value())
    Number(number) =>
      match @admitted.number_value(number) {
        Some(value) => Ok(value)
        None => Err(InvalidRows)
      }
    Boolean(boolean) => Ok(@admitted.boolean_value(boolean))
    Text(text) => {
      // Plain row Text is not structurally proven to be admitted. Charge the
      // UTF-8 scan before the admission API normalizes or copies it.
      if !spend_control_text(control, text) {
        return Err(RowLimit)
      }
      match @admitted.text_value(text, 2147483647) {
        Some(value) => Ok(value)
        None => Err(InvalidRows)
      }
    }
    Captured(value) => Ok(value)
  }
}

///|
fn measure_nest_value(
  value : Value,
  ceiling : Int64,
  used : Int64,
  control : ControlBudget,
  output : ValueBudget,
) -> Result[Int64, RowIssue] {
  if ceiling < 0L || used < 0L || used > ceiling {
    return Err(NestEnvelope(Measurement))
  }
  let measured = match
    measure_logical_value(
      value,
      control.remaining.to_int64(),
      2147483647,
      output.limits.max_nodes,
      output.limits.max_depth,
    ) {
    Ok(value) => value
    Err(LogicalWorkLimit) => return Err(RowLimit)
    Err(_) => return Err(NestEnvelope(Measurement))
  }
  if !spend_control_bytes(control, measured.weight) {
    return Err(RowLimit)
  }
  Ok(measured.wire_bytes.to_int64())
}

///|
fn[T] construct_reserved_nest_metadata(
  workspace : RowWorkspace,
  width : Int,
  construct : () -> Result[T, RowIssue],
) -> Result[T, RowIssue] {
  if width < 0 || width > (workspace.limit - workspace.live) / 3 {
    return Err(RowLimit)
  }
  if !reserve_slots(workspace, width * 3) {
    return Err(RowLimit)
  }
  construct()
}

///|
/// Indexed correlation with parent-major output and resolved child order.
/// Parent duplicates remain separate occurrences and NULL keys never match.
fn[P : RelationRows, C : RelationRows] evaluate_nest_rows(
  kernel : @lower.PreparedNestKernel,
  parent : P,
  child : C,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  selected_item_limit? : Int64? = None,
  grouped_byte_limit? : Int64? = None,
  attached_byte_limit? : Int64? = None,
) -> Result[Table, RowIssue] {
  let owner = @lower.nest_kernel_owner(kernel)
  if !physical_equal(parent.checked_owner(), owner) ||
    !physical_equal(child.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if parent.relation_id() != @lower.nest_kernel_input(kernel, true) ||
    child.relation_id() != @lower.nest_kernel_input(kernel, false) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    workspace.limit < 0 {
    return Err(InvalidRowLimits)
  }
  if IndexedRows::row_count(parent) > max_rows ||
    IndexedRows::row_count(child) > max_rows {
    return Err(RowLimit)
  }
  let authored = @lower.nest_kernel_item_limit(kernel)
  let limit = match (authored, selected_item_limit) {
    (Some(left), Some(right)) => Some(Int64::min(left, right))
    (Some(value), None) | (None, Some(value)) => Some(value)
    (None, None) => None
  }
  guard limit is Some(item_limit) else { return Err(NestItemLimitRequired) }
  guard grouped_byte_limit is Some(grouped_limit) &&
    attached_byte_limit is Some(attached_limit) else {
    return Err(NestEnvelope(Measurement))
  }
  if item_limit < 0L || grouped_limit < 0L || attached_limit < 0L {
    return Err(InvalidRowLimits)
  }
  let baseline = workspace.live
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let parent_names = parent.field_names()
    let child_names = child.field_names()
    let keys : Array[(Int, Int)] = []
    for index in 0..<@lower.nest_kernel_key_count(kernel) {
      if !reserve_slots(workspace, 2) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let pair = @lower.nest_kernel_key_at(kernel, index).unwrap()
      let left = match resolve_column(parent_names, pair.left, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      let right = match resolve_column(child_names, pair.right, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      keys.push((left, right))
    }
    let child_order : Array[ColumnOrder] = []
    for index in 0..<@lower.nest_kernel_order_count(kernel) {
      if !reserve_slots(workspace, 1) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let term = @lower.nest_kernel_order_at(kernel, index).unwrap()
      let column = match resolve_column(child_names, term.field, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      child_order.push({
        column,
        descending: term.descending,
        nulls_first: term.nulls_first,
      })
    }
    let maximum_pairs = Int::max(0, workspace.limit / 2)
    let pairs = match
      inner_join_indices(
        parent,
        child,
        keys,
        false,
        maximum_pairs,
        control,
        workspace,
        right_tie_order=child_order,
      ) {
      Ok(value) => value
      Err(issue) => return Err(nest_index_issue(issue))
    }
    let projection : Array[(String, Int)] = []
    for index in 0..<@lower.nest_kernel_field_count(kernel) {
      if !reserve_slots(workspace, 2) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let field = @lower.nest_kernel_field_at(kernel, index).unwrap()
      let column = match resolve_column(child_names, field.input, control) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      projection.push((field.output, column))
    }
    let output_schema = @lower.nest_kernel_output_schema(kernel)
    let output_width = @schema.field_count(output_schema)
    let into = @lower.nest_kernel_into(kernel)
    let metadata = construct_reserved_nest_metadata(workspace, output_width, fn() {
      let names : Array[String] = []
      let output_columns : Array[Int?] = []
      let attachment_columns : Array[Int] = []
      for index in 0..<output_width {
        let output = @schema.field_at(output_schema, index).unwrap()
        let field = output.name
        let name = @schema.reference_name(field)
        if !spend_control_text(control, name) {
          return Err(RowLimit)
        }
        names.push(name)
        if field == @schema.Unqualified(into) {
          output_columns.push(None)
        } else {
          let column = match resolve_column(parent_names, field, control) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          output_columns.push(Some(column))
        }
        match output.contract.shape {
          @contract.Array(_, ..) | @contract.Object(_) =>
            attachment_columns.push(index)
          _ => ()
        }
      }
      Ok((names, output_columns, attachment_columns))
    })
    let (names, output_columns, attachment_columns) = match metadata {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    release_slots(workspace, output_width - attachment_columns.length())
    retained += names.length()
    let grouped_slots = IndexedRows::row_count(child)
    if !reserve_slots(workspace, grouped_slots) {
      return Err(RowLimit)
    }
    let grouped = Array::make(grouped_slots, false)
    let rows : Array[Array[Value]] = []
    let mut pair_index = 0
    let mut grouped_bytes = 0L
    let mut attached_bytes = 0L
    for parent_row in 0..<IndexedRows::row_count(parent) {
      if !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let start = pair_index
      while pair_index < pairs.length() && pairs[pair_index].0 == parent_row {
        pair_index += 1
      }
      let count = pair_index - start
      if count.to_int64() > item_limit {
        return Err(NestItemLimit(parent_row))
      }
      if !reserve_slots(workspace, count) ||
        !reserve_slots(workspace, names.length()) ||
        !reserve_slots(workspace, 1) ||
        !spend_control(control, count + names.length() + 1) {
        return Err(RowLimit)
      }
      retained += count + names.length() + 1
      let nested : Array[@admitted.Value] = []
      for position in start..<pair_index {
        let child_row = pairs[position].1
        let entries : Array[(String, @admitted.Value)] = []
        if !reserve_slots(workspace, projection.length()) ||
          !spend_control(control, projection.length()) {
          return Err(RowLimit)
        }
        retained += projection.length()
        for (name, column) in projection {
          let value = match
            admitted_nest_value(
              IndexedRows::read_cell(child, child_row, column),
              control,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
          entries.push((name, value))
        }
        guard @admitted.object_value(entries) is Some(object) else {
          return Err(InvalidRows)
        }
        nested.push(object)
      }
      let nested = Captured(@admitted.array_value(nested))
      let row = output_columns.map(column => {
        match column {
          Some(column) => IndexedRows::read_cell(parent, parent_row, column)
          None => nested
        }
      })
      let nested_bytes = match
        measure_nest_value(
          nested,
          Int64::max(grouped_limit, attached_limit),
          0L,
          control,
          output,
        ) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if count > 0 {
        let group = pairs[start].1
        if !grouped[group] {
          if nested_bytes > grouped_limit - grouped_bytes {
            return Err(NestEnvelope(GroupedBytes))
          }
          grouped_bytes += nested_bytes
          grouped[group] = true
        }
      }
      for column in attachment_columns {
        let bytes = if output_columns[column] is None {
          nested_bytes
        } else {
          match
            measure_nest_value(
              row[column],
              attached_limit,
              attached_bytes,
              control,
              output,
            ) {
            Ok(value) => value
            Err(issue) => return Err(issue)
          }
        }
        if bytes > attached_limit - attached_bytes {
          return Err(NestEnvelope(AttachedBytes))
        }
        attached_bytes += bytes
      }
      if !retain_row(row, names, output) {
        return Err(RowLimit)
      }
      rows.push(row)
    }
    release_slots(
      workspace,
      output_columns.length() + attachment_columns.length() + grouped_slots,
    )
    Ok({
      owner,
      id: @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @lower.nest_kernel_step(kernel),
        ).unwrap(),
      ),
      names,
      rows,
    })
  }
  let result = run()
  let keep = match result {
    Ok(_) => retained
    Err(_) => 0
  }
  release_slots(workspace, workspace.live - baseline - keep)
  result
}
