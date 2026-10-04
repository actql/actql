///|
// Representation selection precedes execution; an error never retries through
// another evaluator. Filter retains sparse rows; projection makes dense rows.
fn evaluate_completed_body(
  body : RowBodySource,
  input : CompletedTable,
  id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  logical : LogicalBudget?,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelope? : SelectedAnalyticEnvelope? = None,
  identity_limits? : ValueLimits? = None,
  numeric? : NumericAggregateExecution? = None,
) -> Result[CompletedTable, RowIssue] {
  let projection = match body {
    Projection(_) => true
    PreparedBody(kernel) => @lower.kernel_is_projection(kernel)
  }
  if input is PresenceTable(table) && !projection {
    guard body is PreparedBody(kernel) &&
      @lower.kernel_body(kernel) is @lower.Filter(_) else {
      return Err(InvalidRows)
    }
    let rows = []
    let names = match
      evaluate_row_body_into(
        body,
        input,
        max_rows,
        control,
        output,
        workspace,
        fn(_row, source, _names, _selected) {
          let row = table.rows[source]
          if !reserve_slots(workspace, 1) ||
            !reserve_slots(workspace, row.cells.length()) ||
            !spend_control(control, row.cells.length()) {
            return Err(RowLimit)
          }
          rows.push({ ..row, cells: row.cells.copy(), })
          Ok(())
        },
        ordered_budget=logical,
        preserve_filter_rows=true,
      ) {
      Ok(names) => names
      Err(issue) => return Err(issue)
    }
    return Ok(PresenceTable({ ..table, id, names, rows, }))
  }
  if input is RowTable(_) || !projection {
    return evaluate_row_body(
      body,
      input,
      id,
      max_rows,
      control,
      output,
      workspace,
      ordered_budget=logical,
      aggregate_outputs~,
      analytic_envelope~,
      identity_limits~,
      numeric~,
    ).map(table => RowTable(table))
  }
  if input is AdmittedTable(_) || input is PresenceTable(_) {
    let owner = RelationRows::checked_owner(input)
    let rows : Array[Array[@admitted.Value]] = []
    let names = match
      evaluate_row_body_into(
        body,
        input,
        max_rows,
        control,
        output,
        workspace,
        fn(_row, source, _names, selected) {
          guard selected is Some(indices) else { return Err(InvalidRows) }
          // Preserve admitted immutable values in their existing representation.
          // The shared evaluator already performed semantic checks and charging;
          // this sink charges only the additional reference-array construction.
          if !reserve_slots(workspace, 1) ||
            !reserve_slots(workspace, indices.length()) ||
            !spend_control(control, indices.length()) {
            return Err(RowLimit)
          }
          let cells = []
          for column in indices {
            match input {
              AdmittedTable(table) => cells.push(table.rows[source][column])
              PresenceTable(table) => {
                let row = table.rows[source]
                guard relation_row_required_value(row, column) is Ok(value) else {
                  return Err(InvalidRows)
                }
                cells.push(value)
              }
              _ => return Err(InvalidRows)
            }
          }
          rows.push(cells)
          Ok(())
        },
        ordered_budget=logical,
        aggregate_outputs~,
        analytic_envelope~,
        identity_limits~,
        numeric~,
      ) {
      Ok(names) => names
      Err(issue) => return Err(issue)
    }
    return Ok(AdmittedTable({ owner, id, names, rows, }))
  }
  let count = IndexedRows::row_count(input)
  let columns : Array[CompletedNumberColumn] = []
  let names = match
    evaluate_row_body_into(
      body,
      input,
      max_rows,
      control,
      output,
      workspace,
      fn(row, source, names, _projection) {
        if source == 0 {
          if !reserve_slots(workspace, names.length()) {
            return Err(RowLimit)
          }
          for _name in names {
            // Both the row evaluator's temporary output and typed destination
            // coexist. Reserve before constructing either numeric buffer.
            if !reserve_slots(workspace, count) ||
              !reserve_slots(workspace, count) ||
              !spend_control(control, count) {
              return Err(RowLimit)
            }
            columns.push({
              values: FixedArray::make(count, 0.0),
              valid: FixedArray::make(count, b'\x00'),
            })
          }
        }
        if !spend_control(control, row.length()) {
          return Err(RowLimit)
        }
        for i = 0; i < row.length(); i = i + 1 {
          match row[i] {
            Null => ()
            Number(n) => {
              columns[i].values[source] = n
              columns[i].valid[source] = b'\x01'
            }
            _ => return Err(InvalidRows)
          }
        }
        Ok(())
      },
      ordered_budget=logical,
      aggregate_outputs~,
      analytic_envelope~,
      identity_limits~,
      numeric~,
    ) {
    Ok(names) => names
    Err(issue) => return Err(issue)
  }
  if count == 0 {
    if !reserve_slots(workspace, names.length()) ||
      !spend_control(control, names.length()) {
      return Err(RowLimit)
    }
    for _name in names {
      columns.push({
        values: FixedArray::make(0, 0.0),
        valid: FixedArray::make(0, b'\x00'),
      })
    }
  }
  Ok(
    NumberTable({
      owner: RelationRows::checked_owner(input),
      id,
      names,
      columns,
      count,
      selection: None,
    }),
  )
}

///|
// Index kernels have already checked and charged logical output. This adapter
// only constructs a physical selection and charges its extra copied indices.
fn completed_selection(
  input : CompletedTable,
  id : String,
  indices : Array[Int],
  control : ControlBudget,
  workspace : RowWorkspace,
) -> Result[CompletedTable, RowIssue] {
  match input {
    PresenceTable(_) => Err(InvalidRows)
    AdmittedTable(table) =>
      Ok(
        AdmittedTable({
          ..table,
          id,
          names: table.names.copy(),
          rows: indices.map(i => table.rows[i]),
        }),
      )
    ColumnTable(table) => {
      if !reserve_slots(workspace, indices.length()) ||
        !spend_control(control, indices.length()) {
        return Err(RowLimit)
      }
      let selection = indices.map(i => {
        match table.selection {
          Some(previous) => previous[i]
          None => i
        }
      })
      Ok(
        ColumnTable({
          ..table,
          id,
          count: indices.length(),
          selection: Some(selection),
        }),
      )
    }
    RowTable(table) =>
      Ok(
        RowTable({
          ..table,
          id,
          names: table.names.copy(),
          rows: indices.map(i => table.rows[i]),
        }),
      )
    NumberTable(table) => {
      if !reserve_slots(workspace, indices.length()) ||
        !spend_control(control, indices.length()) {
        return Err(RowLimit)
      }
      let selection = indices.map(i => {
        match table.selection {
          Some(previous) => previous[i]
          None => i
        }
      })
      Ok(
        NumberTable({
          ..table,
          id,
          count: indices.length(),
          selection: Some(selection),
        }),
      )
    }
  }
}

///|
fn evaluate_completed_rows(
  kernel : @lower.PreparedKernel,
  input : CompletedTable,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  logical : LogicalBudget?,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelope? : SelectedAnalyticEnvelope? = None,
  identity_limits? : ValueLimits? = None,
  numeric? : NumericAggregateExecution? = None,
) -> Result[CompletedTable, RowIssue] {
  evaluate_rows_dispatch(
    kernel,
    input,
    {
      release: fn(_table) { () },
      sort: fn(kernel, input, id) {
        match
          evaluate_sort_selection(
            kernel, input, max_rows, control, output, workspace,
          ) {
          Err(e) => Err(e)
          Ok(indices) =>
            completed_selection(input, id, indices, control, workspace)
        }
      },
      dedupe: fn(kernel, input, id) {
        match
          evaluate_dedupe_selection(
            kernel, input, max_rows, control, output, workspace,
          ) {
          Err(e) => Err(e)
          Ok(indices) =>
            completed_selection(input, id, indices, control, workspace)
        }
      },
      distinct: fn(input, id) {
        match
          evaluate_distinct_selection(
            input, max_rows, control, output, workspace,
          ) {
          Err(e) => Err(e)
          Ok(indices) =>
            completed_selection(input, id, indices, control, workspace)
        }
      },
      take: fn(input, id, count, offset) {
        match
          evaluate_take_selection(
            input, count, offset, max_rows, control, output, workspace,
          ) {
          Err(e) => Err(e)
          Ok((start, selected)) => {
            if !reserve_slots(workspace, selected) ||
              !spend_control(control, selected) {
              return Err(RowLimit)
            }
            completed_selection(
              input,
              id,
              Array::makei(selected, i => start + i),
              control,
              workspace,
            )
          }
        }
      },
      top_k: fn(kernel, input, id, count) {
        match
          evaluate_top_k_selection(
            kernel, input, count, max_rows, control, output, workspace,
          ) {
          Err(issue) => Err(issue)
          Ok(indices) =>
            completed_selection(input, id, indices, control, workspace)
        }
      },
      unnest: fn(kernel, input, id) {
        if input is RowTable(_) {
          evaluate_unnest_rows(
            kernel, input, id, max_rows, control, output, workspace,
          ).map(table => RowTable(table))
        } else {
          evaluate_unnest_columns(
            kernel, input, id, max_rows, control, output, workspace,
          )
        }
      },
      unpivot: fn(kernel, input, id) {
        if input is RowTable(_) {
          evaluate_unpivot_rows(
            kernel, input, id, max_rows, control, output, workspace,
          ).map(table => RowTable(table))
        } else {
          evaluate_unpivot_columns(
            kernel, input, id, max_rows, control, output, workspace,
          )
        }
      },
      pivot: fn(kernel, input, id) {
        evaluate_pivot_rows(
          kernel,
          input,
          id,
          max_rows,
          control,
          output,
          workspace,
          numeric~,
          step=@lower.kernel_step(kernel),
        ).map(table => RowTable(table))
      },
      lag: fn(kernel, input, id) {
        evaluate_lag_rows(
          kernel, input, id, max_rows, control, output, workspace,
        ).map(table => RowTable(table))
      },
      watermark: fn(kernel, input, id) {
        evaluate_watermark_rows(
          kernel, input, id, max_rows, control, output, workspace,
        ).map(table => RowTable(table))
      },
      body: fn(body, input, id, logical) {
        evaluate_completed_body(
          body,
          input,
          id,
          max_rows,
          control,
          output,
          workspace,
          logical,
          aggregate_outputs~,
          analytic_envelope~,
          identity_limits~,
          numeric~,
        )
      },
    },
    ordered_budget=logical,
  )
}
