///|
fn join_index_failure(issue : JoinIndexIssue) -> RowIssue {
  match issue {
    InvalidInput => InvalidRows
    Limit => RowLimit
    NullKey(left~, row~, key~) => JoinNullKey(left, row, key)
    DuplicateKey(left~, row~, previous~) =>
      JoinDuplicateKey(left, row, previous)
    Scalar(issue) => Comparison(issue)
  }
}

///|
/// Two immutable physical inputs, one admitted logical output. Projection is
/// built directly; the unprojected Cartesian payload is never materialized.
fn[L : RelationRows, R : RelationRows] evaluate_join_rows(
  kernel : @lower.PreparedJoinKernel,
  left : L,
  right : R,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  selected_ceiling? : (Int, Int64)? = None,
) -> Result[Table, RowIssue] {
  let owner = @lower.join_kernel_owner(kernel)
  if !physical_equal(left.checked_owner(), owner) ||
    !physical_equal(right.checked_owner(), owner) {
    return Err(OwnerMismatch)
  }
  if left.relation_id() != @lower.join_kernel_input(kernel, true) ||
    right.relation_id() != @lower.join_kernel_input(kernel, false) {
    return Err(InputMismatch)
  }
  if max_rows < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 ||
    workspace.limit < 0 {
    return Err(InvalidRowLimits)
  }
  if IndexedRows::row_count(left) > max_rows ||
    IndexedRows::row_count(right) > max_rows {
    return Err(RowLimit)
  }
  let profile = @lower.join_kernel_profile(kernel)
  let resolve = fn(
    names : Array[String],
    field : @schema.FieldName,
  ) -> Result[Int, RowIssue] {
    let reference = @schema.reference_name(field)
    for index, name in names {
      if !spend_control(control, 1) ||
        !spend_control_text(control, reference) ||
        !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      if name == reference {
        return Ok(index)
      }
    }
    Err(InvalidRows)
  }
  let mut retained = 0
  let run = fn() -> Result[Table, RowIssue] {
    let keys : Array[(Int, Int)] = []
    let orders : Array[Array[ColumnOrder]] = [[], []]
    if !reserve_slots(workspace, 2) {
      return Err(RowLimit)
    }
    for index in 0..<@lower.inner_join_key_count(profile) {
      if !reserve_slots(workspace, 4) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let (lf, rf) = @lower.inner_join_key_at(profile, index).unwrap()
      let lc = match resolve(left.field_names(), lf) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      let rc = match resolve(right.field_names(), rf) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      keys.push((lc, rc))
      orders[0].push({ column: lc, descending: false, nulls_first: true, })
      orders[1].push({ column: rc, descending: false, nulls_first: true, })
    }
    if validate_join_obligations(
        profile, left, right, keys, orders, control, workspace,
      )
      is Err(e) {
      return Err(e)
    }
    let mut ceiling = match @lower.join_kernel_output_limit(kernel) {
      Some(limit) =>
        if limit < max_rows.to_int64() {
          limit.to_int()
        } else {
          max_rows
        }
      None => max_rows
    }
    if selected_ceiling is Some((step, bound)) &&
      step == @lower.join_kernel_step(kernel) {
      if bound < 0L {
        return Err(InvalidRowLimits)
      }
      if bound < ceiling.to_int64() {
        ceiling = bound.to_int()
      }
    }
    let kind = @lower.inner_join_kind(profile)
    let names : Array[String] = []
    let columns : Array[(Bool, Int)] = []
    for index in 0..<@lower.inner_join_field_count(profile) {
      if !reserve_slots(workspace, 3) || !spend_control(control, 1) {
        return Err(RowLimit)
      }
      let field = @lower.inner_join_field_at(profile, index).unwrap()
      let name = @schema.reference_name(field.output)
      if !spend_control_text(control, name) {
        return Err(RowLimit)
      }
      names.push(name)
      let (on_left, source) = match field.input {
        Qualified(side, name) =>
          (side == @schema.Left, @schema.Unqualified(name))
        _ => return Err(InvalidRows)
      }
      let column = match
        resolve(
          if on_left {
            left.field_names()
          } else {
            right.field_names()
          },
          source,
        ) {
        Ok(v) => v
        Err(e) => return Err(e)
      }
      columns.push((on_left, column))
      retained += 1
    }
    let rows : Array[Array[Value]] = []
    let emit = fn(lrow : Int?, rrow : Int?) -> Result[Unit, RowIssue] {
      if !reserve_slots(workspace, 1) ||
        !reserve_slots(workspace, names.length()) ||
        !spend_control(control, 1) ||
        !spend_control(control, names.length()) {
        return Err(RowLimit)
      }
      retained += 1 + names.length()
      let row = columns.map(pair => {
        if pair.0 {
          match lrow {
            Some(row) => IndexedRows::read_cell(left, row, pair.1)
            None => Null
          }
        } else {
          match rrow {
            Some(row) => IndexedRows::read_cell(right, row, pair.1)
            None => Null
          }
        }
      })
      if !retain_row(row, names, output) {
        return Err(RowLimit)
      }
      rows.push(row)
      Ok(())
    }
    if kind == @join.Inner {
      let pairs = match
        inner_join_indices(
          left, right, keys, false, ceiling, control, workspace,
        ) {
        Ok(value) => value
        Err(issue) => return Err(join_index_failure(issue))
      }
      for (left, right) in pairs {
        match emit(Some(left), Some(right)) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
    } else {
      let pairs = match
        non_inner_join_indices(
          kind, left, right, keys, ceiling, control, workspace,
        ) {
        Ok(value) => value
        Err(issue) => return Err(join_index_failure(issue))
      }
      for pair in pairs {
        match emit(pair.left, pair.right) {
          Ok(_) => ()
          Err(issue) => return Err(issue)
        }
      }
    }
    Ok({
      owner,
      id: @lower.node_id(
        @lower.node_at(
          @lower.bound_preparation(owner),
          @lower.join_kernel_step(kernel),
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
  release_slots(workspace, workspace.live - keep)
  result
}
