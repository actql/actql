///|
/// Package-private physical row layout. No constructors escape this package.
/// Row execution remains behind the unfinished fragment admission boundary.
priv struct Table {
  owner : @lower.BoundPrepared
  id : String
  names : Array[String]
  rows : Array[Array[Value]]
}

///|
priv enum RowIssue {
  OwnerMismatch
  InputMismatch
  InvalidRows
  RowLimit
  InvalidRowLimits
  Evaluation(Int, Int, EvalIssue)
}

///|
fn table_from_capture(input : CapturedRows) -> Table {
  let prepared = @lower.bound_preparation(input.owner)
  let id = match input.origin {
    ValuesNode(i) => @lower.node_id(@lower.node_at(prepared, i).unwrap())
    SuppliedInput(i) => @lower.input_id(prepared, i).unwrap()
  }
  let names = Array::makei(@schema.field_count(input.schema), i => {
    @schema.reference_name(@schema.field_at(input.schema, i).unwrap().name)
  })
  {
    owner: input.owner,
    id,
    names,
    rows: input.rows.map(row => row.map(capture)),
  }
}

///|
fn measure_result(v : Value, b : ValueBudget) -> Bool {
  match v {
    Captured(value) => measure(value, 2, b)
    Text(s) => charge_node(b, 2) && charge_text(b, s)
    Null | Boolean(_) | Number(_) => charge_node(b, 2)
  }
}

///|
fn retain_row(
  row : Array[Value],
  names : Array[String],
  output : ValueBudget,
) -> Bool {
  if !charge_node(output, 1) {
    return false
  }
  for i = 0; i < names.length(); i = i + 1 {
    if !charge_text(output, names[i]) || !measure_result(row[i], output) {
      return false
    }
  }
  true
}

///|
/// Row-major, atomic operation evaluation. Output and control budgets are
/// supplied by the caller and can span multiple kernels without resetting.
/// This is not yet complete physical live-memory accounting.
fn evaluate_rows_with_workspace(
  kernel : @lower.PreparedKernel,
  input : Table,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidRowLimits)
  }
  if !physical_equal(@lower.kernel_owner(kernel), input.owner) {
    return Err(OwnerMismatch)
  }
  if @lower.kernel_input(kernel) != input.id {
    return Err(InputMismatch)
  }
  // This input ceiling applies even when a filter would emit zero rows.
  if input.rows.length() > max_rows {
    return Err(RowLimit)
  }
  if !reserve_slots(workspace, input.names.length()) ||
    !reserve_slots(workspace, input.rows.length()) {
    return Err(RowLimit)
  }
  for row in input.rows {
    if !reserve_slots(workspace, row.length()) {
      return Err(RowLimit)
    }
  }
  if !reserve_slots(workspace, @lower.kernel_view_entries(kernel)) {
    return Err(RowLimit)
  }
  if !spend_control(control, @lower.kernel_view_entries(kernel)) {
    return Err(RowLimit)
  }
  let kind = @lower.kernel_body(kernel)
  let output_names : Array[String] = []
  let projection : Array[Int] = []
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < input.names.length(); i = i + 1 {
    if !spend_control(control, 1) ||
      !spend_control_text(control, input.names[i]) {
      return Err(RowLimit)
    }
    if ordinals.contains(input.names[i]) {
      return Err(InvalidRows)
    }
    if !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    ordinals[input.names[i]] = i
  }
  match kind {
    @lower.Select(fields) =>
      for field in fields {
        if !spend_control(control, 1) ||
          !spend_control_text(control, @schema.reference_name(field.input)) ||
          !spend_control_text(control, @schema.reference_name(field.output)) {
          return Err(RowLimit)
        }
        guard ordinals.get(@schema.reference_name(field.input)) is Some(index) else {
          return Err(InvalidRows)
        }
        if !reserve_slots(workspace, 2) {
          return Err(RowLimit)
        }
        output_names.push(@schema.reference_name(field.output))
        projection.push(index)
      }
    @lower.Filter(_) =>
      for name in input.names {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
    @lower.SnapshotMap(bindings) => {
      for name in input.names {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
      for (name, _) in bindings {
        if !spend_control(control, 1) || !spend_control_text(control, name) {
          return Err(RowLimit)
        }
        if ordinals.contains(name) {
          return Err(InvalidRows)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
    }
  }
  let rows : Array[Array[Value]] = []
  for row_index = 0; row_index < input.rows.length(); row_index = row_index + 1 {
    let source = input.rows[row_index]
    if source.length() != input.names.length() {
      return Err(InvalidRows)
    }
    if control.remaining == 0 {
      return Err(RowLimit)
    }
    control.remaining -= 1
    // One immutable operation-start snapshot; map siblings never update it.
    let snapshot : Map[String, Value] = Map([])
    if !(kind is @lower.Select(_)) {
      for i = 0; i < input.names.length(); i = i + 1 {
        if !spend_control(control, 1) ||
          !spend_control_text(control, input.names[i]) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        snapshot[input.names[i]] = source[i]
      }
    }
    let row : Array[Value] = []
    match kind {
      @lower.Select(_) =>
        for index in projection {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(source[index])
        }
      @lower.Filter(expr) => {
        let value = match evaluate_expression(expr, snapshot, [], control) {
          Ok(v) => v
          Err(e) => return Err(Evaluation(row_index, 0, e))
        }
        match value {
          Boolean(true) =>
            for v in source {
              if !spend_control(control, 1) {
                return Err(RowLimit)
              }
              if !reserve_slots(workspace, 1) {
                return Err(RowLimit)
              }
              row.push(v)
            }
          Boolean(false) | Null => {
            release_slots(workspace, snapshot.length())
            continue
          }
          Number(_) | Text(_) | Captured(_) => return Err(InvalidRows)
        }
      }
      @lower.SnapshotMap(bindings) => {
        for v in source {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(v)
        }
        for slot = 0; slot < bindings.length(); slot = slot + 1 {
          let expr = bindings[slot].1
          match evaluate_expression(expr, snapshot, [], control) {
            Ok(v) => {
              if !reserve_slots(workspace, 1) {
                return Err(RowLimit)
              }
              row.push(v)
            }
            Err(e) => return Err(Evaluation(row_index, slot, e))
          }
        }
      }
    }
    if !retain_row(row, output_names, output) {
      return Err(RowLimit)
    }
    if !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    rows.push(row)
    release_slots(workspace, snapshot.length())
  }
  let prepared = @lower.bound_preparation(input.owner)
  let node = @lower.node_at(prepared, @lower.kernel_step(kernel)).unwrap()
  Ok({
    owner: input.owner,
    id: @lower.node_id(node),
    names: output_names,
    rows,
  })
}
