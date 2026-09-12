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
  OrderedResourceAccountingPending
  Evaluation(Int, Int, EvalIssue)
}

///|
fn table_from_capture_bounded(
  input : CapturedRows,
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[Table, RowIssue] {
  if control.remaining < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidRowLimits)
  }
  let width = @schema.field_count(input.schema)
  // Admit the complete layout before allocating copied arrays. Borrowed
  // capture containers coexist with the new table during conversion.
  if !reserve_slots(workspace, input.rows.length()) ||
    !reserve_slots(workspace, input.rows.length()) ||
    !reserve_slots(workspace, width) {
    return Err(RowLimit)
  }
  for i = 0; i < width; i = i + 1 {
    if !spend_control(control, 1) ||
      !spend_control_text(
        control,
        @schema.reference_name(@schema.field_at(input.schema, i).unwrap().name),
      ) {
      return Err(RowLimit)
    }
  }
  for row in input.rows {
    if !spend_control(control, 1) {
      return Err(RowLimit)
    }
    if row.length() != width {
      return Err(InvalidRows)
    }
    // Subtraction-based reservation avoids overflowing rows * width.
    if !reserve_slots(workspace, width) ||
      !reserve_slots(workspace, width) ||
      !spend_control(control, width) {
      return Err(RowLimit)
    }
  }
  let prepared = @lower.bound_preparation(input.owner)
  let id = match input.origin {
    ValuesNode(i) => @lower.node_id(@lower.node_at(prepared, i).unwrap())
    SuppliedInput(i) => @lower.input_id(prepared, i).unwrap()
  }
  let names = Array::makei(@schema.field_count(input.schema), i => {
    @schema.reference_name(@schema.field_at(input.schema, i).unwrap().name)
  })
  Ok({
    owner: input.owner,
    id,
    names,
    rows: input.rows.map(row => row.map(capture)),
  })
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
/// Sources remain bound to checked preparation; no arbitrary row program.
priv enum RowBodySource {
  PreparedBody(@lower.PreparedKernel)
  CheckedProjection(@relation.CheckedOperation)
}

///|
// Transient dispatch view only; never serialized or accepted as a fragment.
priv enum RowBodyView {
  SnapshotMap(Array[(String, @lower.Expression)])
  Filter(@lower.Expression)
  Select(Array[@relation.ProjectionField])
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
  if !physical_equal(@lower.kernel_owner(kernel), input.owner) {
    return Err(OwnerMismatch)
  }
  if @lower.kernel_input(kernel) != input.id {
    return Err(InputMismatch)
  }
  let prepared = @lower.bound_preparation(input.owner)
  let node = @lower.node_at(prepared, @lower.kernel_step(kernel)).unwrap()
  evaluate_row_body(
    PreparedBody(kernel),
    input,
    @lower.node_id(node),
    max_rows,
    control,
    output,
    workspace,
  )
}

///|
// Both authored select and the checked producer projection use this evaluator.
// The latter is an input adaptation, not an invented authored AoA node.
fn evaluate_row_body(
  body : RowBodySource,
  input : Table,
  output_id : String,
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
  let view_entries = match body {
    PreparedBody(kernel) => @lower.kernel_view_entries(kernel)
    CheckedProjection(checked) => {
      if @relation.operation(checked) != Select {
        return Err(InvalidRows)
      }
      @schema.field_count(@relation.output_schema(checked))
    }
  }
  if !reserve_slots(workspace, view_entries) {
    return Err(RowLimit)
  }
  if !spend_control(control, view_entries) {
    return Err(RowLimit)
  }
  let kind : RowBodyView = match body {
    PreparedBody(kernel) =>
      match @lower.kernel_body(kernel) {
        @lower.SnapshotMap(bindings) => SnapshotMap(bindings)
        @lower.Filter(expr) => Filter(expr)
        @lower.Select(fields) => Select(fields)
        @lower.OrderedBindings(_) =>
          return Err(OrderedResourceAccountingPending)
      }
    CheckedProjection(checked) => Select(@relation.projection(checked))
  }
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
    Select(fields) =>
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
    Filter(_) =>
      for name in input.names {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
    SnapshotMap(bindings) => {
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
    if !(kind is Select(_)) {
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
      Select(_) =>
        for index in projection {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(source[index])
        }
      Filter(expr) => {
        let value = match
          evaluate_expression_with_workspace(
            expr,
            snapshot,
            [],
            control,
            workspace,
          ) {
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
      SnapshotMap(bindings) => {
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
          match
            evaluate_expression_with_workspace(
              expr,
              snapshot,
              [],
              control,
              workspace,
            ) {
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
  Ok({ owner: input.owner, id: output_id, names: output_names, rows, })
}
