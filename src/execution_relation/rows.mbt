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
pub(all) enum RowIssue {
  OwnerMismatch
  InputMismatch
  InvalidRows
  RowLimit
  InvalidRowLimits
  MissingOrderedResourceContext
  LogicalRows(LogicalBudgetIssue)
  Evaluation(Int, Int, EvalIssue)
  Comparison(ScalarIssue)
  Aggregation(ScalarIssue)
  DedupeTopTie(Int, Int)
  DedupeIdentityCollision
  AssertionPredicate(Int)
  AssertionNullKey(Int, Int)
  AssertionDuplicate(Int, Int)
  JoinNullKey(Bool, Int, Int)
  JoinDuplicateKey(Bool, Int, Int)
  AsOfTopTie(Int, Int, Int)
  WindowTime(Int)
  WindowArithmetic(Int)
  AnalyticEnvelope(AnalyticEnvelopeScope)
  NestItemLimitRequired
  NestItemLimit(Int)
  NestEnvelope(NestEnvelopeScope)
}

///|
pub(all) enum AnalyticEnvelopeScope {
  InputWireBytes
  OutputWireBytes
  PartitionWireBytes
  FrameMemberships
  OutputRows
  Measurement
} derive(Eq, Debug)

///|
pub(all) enum NestEnvelopeScope {
  GroupedBytes
  AttachedBytes
  Measurement
} derive(Eq, Debug)

///|
/// Keep execution-resource exhaustion distinct from semantic expression
/// failures at every row-kernel boundary.
fn evaluation_row_issue(row : Int, slot : Int, issue : EvalIssue) -> RowIssue {
  match issue.kind {
    ControlLimit | WorkspaceLimit => RowLimit
    _ => Evaluation(row, slot, issue)
  }
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
  if !@schema.all_fields_required(input.schema) {
    return Err(InvalidRows)
  }
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
fn[T : RowValues] retain_row(
  row : T,
  names : Array[String],
  output : ValueBudget,
) -> Bool {
  if !charge_node(output, 1) {
    return false
  }
  for i = 0; i < names.length(); i = i + 1 {
    if !charge_text(output, names[i]) {
      return false
    }
    let measured = if row.value_present(i) {
      measure_result(row.value_at(i), output)
    } else {
      charge_node(output, 2)
    }
    if !measured {
      return false
    }
  }
  true
}

///|
/// Sources remain bound to checked preparation; no arbitrary row program.
priv enum RowBodySource {
  PreparedBody(@lower.PreparedKernel)
  Projection(@lower.PreparedProjection)
}

///|
// Transient dispatch view only; never serialized or accepted as a fragment.
priv enum RowBodyView {
  SnapshotMap(Array[(String, @lower.Expression)])
  OrderedBindings(Array[(String, @lower.Expression)])
  Filter(@lower.Expression)
  AssertAll(@lower.Expression)
  AssertUnique(Array[@schema.FieldName])
  JsonPick(@schema.FieldName, Array[String], String)
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
  ordered_budget? : LogicalBudget? = None,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelope? : SelectedAnalyticEnvelope? = None,
  identity_limits? : ValueLimits? = None,
  numeric? : NumericAggregateExecution? = None,
) -> Result[Table, RowIssue] {
  evaluate_rows_dispatch(
    kernel,
    input,
    {
      release: fn(_table) { () },
      sort: fn(kernel, input, id) {
        evaluate_sort_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
      },
      dedupe: fn(kernel, input, id) {
        evaluate_dedupe_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
      },
      distinct: fn(input, id) {
        evaluate_distinct_rows(input, id, max_rows, control, output, workspace)
      },
      take: fn(input, id, count, offset) {
        evaluate_take_rows(
          input, id, count, offset, max_rows, control, output, workspace,
        )
      },
      top_k: fn(kernel, input, id, count) {
        evaluate_top_k_rows(
          kernel, input, id, count, max_rows, control, output, workspace,
        )
      },
      unnest: fn(kernel, input, id) {
        evaluate_unnest_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
      },
      unpivot: fn(kernel, input, id) {
        evaluate_unpivot_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
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
        )
      },
      lag: fn(kernel, input, id) {
        evaluate_lag_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
      },
      watermark: fn(kernel, input, id) {
        evaluate_watermark_rows(
          kernel, input, id, max_rows, control, output, workspace,
        )
      },
      body: fn(body, input, id, logical) {
        evaluate_row_body(
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
        )
      },
    },
    ordered_budget~,
  )
}

///|
// Physical callbacks never choose semantic prefixes or reinterpret a kernel.
priv struct RowBackend[T] {
  release : (T) -> Unit
  sort : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  dedupe : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  distinct : (T, String) -> Result[T, RowIssue]
  take : (T, String, Int64, Int64) -> Result[T, RowIssue]
  top_k : (@lower.PreparedKernel, T, String, Int64) -> Result[T, RowIssue]
  unnest : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  unpivot : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  pivot : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  lag : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  watermark : (@lower.PreparedKernel, T, String) -> Result[T, RowIssue]
  body : (RowBodySource, T, String, LogicalBudget?) -> Result[T, RowIssue]
}

///|
fn[T : RelationRows] evaluate_rows_dispatch(
  kernel : @lower.PreparedKernel,
  input : T,
  backend : RowBackend[T],
  ordered_budget? : LogicalBudget? = None,
) -> Result[T, RowIssue] {
  if !physical_equal(@lower.kernel_owner(kernel), input.checked_owner()) {
    return Err(OwnerMismatch)
  }
  if @lower.kernel_input(kernel) != input.relation_id() {
    return Err(InputMismatch)
  }
  let prepared = @lower.bound_preparation(input.checked_owner())
  let node = @lower.node_at(prepared, @lower.kernel_step(kernel)).unwrap()
  if @lower.kernel_is_sort(kernel) {
    return (backend.sort)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_is_dedupe(kernel) {
    return (backend.dedupe)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_is_distinct(kernel) {
    let selected = match @lower.projection_node_id(node) {
      None => input
      Some(id) =>
        match
          (backend.body)(
            Projection(@lower.kernel_distinct_projection(kernel).unwrap()),
            input,
            id,
            None,
          ) {
          Ok(table) => table
          Err(e) => return Err(e)
        }
    }
    let result = (backend.distinct)(selected, @lower.node_id(node))
    if @lower.projection_node_id(node) is Some(_) {
      (backend.release)(selected)
    }
    return result
  }
  if @lower.kernel_top_k_count(kernel) is Some(count) {
    return (backend.top_k)(kernel, input, @lower.node_id(node), count)
  }
  if @lower.kernel_unnest(kernel) is Some(_) {
    return (backend.unnest)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_unpivot_outputs(kernel) is Some(_) {
    return (backend.unpivot)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_pivot(kernel) is Some(_) {
    return (backend.pivot)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_lag(kernel) is Some(_) {
    return (backend.lag)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_watermark(kernel) is Some(_) {
    return (backend.watermark)(kernel, input, @lower.node_id(node))
  }
  if @lower.kernel_take(kernel) is Some((count, offset)) {
    let input = if @lower.order_node_id(node) is Some(id) {
      match (backend.sort)(kernel, input, id) {
        Ok(table) => table
        Err(e) => return Err(e)
      }
    } else {
      input
    }
    let result = (backend.take)(input, @lower.node_id(node), count, offset)
    if @lower.order_node_id(node) is Some(_) {
      (backend.release)(input)
    }
    return result
  }
  (backend.body)(
    PreparedBody(kernel),
    input,
    @lower.node_id(node),
    ordered_budget,
  )
}

///|
// Both authored select and the checked producer projection use this evaluator.
// The latter is an input adaptation, not an invented authored AoA node.
fn[T : RelationRows] evaluate_row_body(
  body : RowBodySource,
  input : T,
  output_id : String,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  ordered_budget? : LogicalBudget? = None,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelope? : SelectedAnalyticEnvelope? = None,
  identity_limits? : ValueLimits? = None,
  numeric? : NumericAggregateExecution? = None,
) -> Result[Table, RowIssue] {
  let rows : Array[Array[Value]] = []
  let names = match
    evaluate_row_body_into(
      body,
      input,
      max_rows,
      control,
      output,
      workspace,
      fn(row, _source, _names, _projection) {
        rows.push(row)
        Ok(())
      },
      ordered_budget~,
      aggregate_outputs~,
      analytic_envelope~,
      identity_limits~,
      numeric~,
    ) {
    Ok(names) => names
    Err(issue) => return Err(issue)
  }
  Ok({ owner: input.checked_owner(), id: output_id, names, rows, })
}

///|
/// Internal sink boundary: evaluation, logical retention and failure order are
/// fixed here. A sink only owns physical output construction. Its buffers must
/// not be exposed until this entire operation (and its driver) succeeds.
fn[T : RelationRows] evaluate_row_body_into(
  body : RowBodySource,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
  ordered_budget? : LogicalBudget? = None,
  aggregate_outputs? : Array[SelectedAggregateOutput] = [],
  analytic_envelope? : SelectedAnalyticEnvelope? = None,
  identity_limits? : ValueLimits? = None,
  numeric? : NumericAggregateExecution? = None,
  preserve_filter_rows? : Bool = false,
) -> Result[Array[String], RowIssue] {
  if body is PreparedBody(kernel) {
    if !physical_equal(@lower.kernel_owner(kernel), input.checked_owner()) {
      return Err(OwnerMismatch)
    }
    if @lower.kernel_input(kernel) != input.relation_id() {
      return Err(InputMismatch)
    }
  }
  let scope = ordered_budget.map(b => {
    (
      { budget: b, slots: [], free: [], limit: workspace.limit, } :
      ExpressionRoots)
  })
  let result = evaluate_row_body_impl(
    body,
    input,
    max_rows,
    control,
    output,
    workspace,
    scope,
    accept_row,
    aggregate_outputs,
    analytic_envelope,
    identity_limits.unwrap_or(output.limits),
    numeric,
    preserve_filter_rows,
  )
  if scope is Some(s) {
    if result is Err(_) {
      s.budget.failed = true
    }
    cleanup_expression_roots(s)
  }
  result
}

///|
fn[T : RelationRows] evaluate_row_body_impl(
  body : RowBodySource,
  input : T,
  max_rows : Int,
  control : ControlBudget,
  output : ValueBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots?,
  accept_row : (Array[Value], Int, Array[String], Array[Int]?) -> Result[
    Unit,
    RowIssue,
  ],
  aggregate_outputs : Array[SelectedAggregateOutput],
  analytic_envelope : SelectedAnalyticEnvelope?,
  identity_limits : ValueLimits,
  numeric : NumericAggregateExecution?,
  preserve_filter_rows : Bool,
) -> Result[Array[String], RowIssue] {
  if max_rows < 0 ||
    control.remaining < 0 ||
    control.max_frames < 0 ||
    workspace.limit < 0 ||
    workspace.live != 0 ||
    workspace.peak != 0 {
    return Err(InvalidRowLimits)
  }
  let input_names = input.field_names()
  let input_count = IndexedRows::row_count(input)
  // This input ceiling applies even when a filter would emit zero rows.
  if input_count > max_rows {
    return Err(RowLimit)
  }
  if !reserve_slots(workspace, input_names.length()) ||
    !reserve_slots(workspace, input_count) {
    return Err(RowLimit)
  }
  for row = 0; row < input_count; row = row + 1 {
    if !reserve_slots(workspace, IndexedRows::row_width(input, row)) {
      return Err(RowLimit)
    }
  }
  if body is PreparedBody(kernel) &&
    @lower.kernel_count_group(kernel) is Some(group) {
    return evaluate_count_group_into(
      group, input, max_rows, control, output, workspace, accept_row,
    )
  }
  if body is PreparedBody(kernel) && @lower.kernel_group(kernel) is Some(group) {
    return evaluate_group_into(
      group,
      input,
      max_rows,
      control,
      output,
      workspace,
      scope,
      accept_row,
      aggregate_outputs,
      identity_limits,
      numeric,
      step=@lower.kernel_step(kernel),
    )
  }
  if body is PreparedBody(kernel) &&
    @lower.kernel_analytic(kernel) is Some(analytic) {
    return evaluate_analytic_into(
      analytic,
      input,
      max_rows,
      control,
      output,
      workspace,
      scope,
      aggregate_outputs,
      analytic_envelope,
      identity_limits,
      numeric,
      step=@lower.kernel_step(kernel),
      accept_row,
    )
  }
  let view_entries = match body {
    PreparedBody(kernel) => @lower.kernel_view_entries(kernel)
    Projection(view) => @lower.projection_field_count(view)
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
        @lower.AssertAll(expr) => AssertAll(expr)
        @lower.AssertUnique(keys) => AssertUnique(keys)
        @lower.JsonPick(column, path, output) => JsonPick(column, path, output)
        @lower.Select(fields) => Select(fields)
        @lower.Limit(_, _, _) => return Err(InvalidRows)
        @lower.TopK(_, _) => return Err(InvalidRows)
        @lower.PartitionedTopK(_, _) => return Err(InvalidRows)
        @lower.Pivot(_) => return Err(InvalidRows)
        @lower.Unnest(_, _, _, _, _) => return Err(InvalidRows)
        @lower.Unpivot(_, _, _, _) => return Err(InvalidRows)
        @lower.DistinctRows => return Err(InvalidRows)
        @lower.DedupeRows => return Err(InvalidRows)
        @lower.StableSort(_) => return Err(InvalidRows)
        @lower.Lag(_, _) => return Err(InvalidRows)
        @lower.Watermark(_, _, _, _) => return Err(InvalidRows)
        @lower.AnalyticRows(_) => return Err(InvalidRows)
        @lower.CountGroups(_) => return Err(InvalidRows)
        @lower.Groups(_) => return Err(InvalidRows)
        @lower.OrderedBindings(bindings) =>
          if scope is Some(_) {
            OrderedBindings(bindings)
          } else {
            return Err(MissingOrderedResourceContext)
          }
      }
    Projection(view) => Select(@lower.projection_fields(view))
  }
  if preserve_filter_rows && !(kind is Filter(_)) {
    return Err(InvalidRows)
  }
  let output_names : Array[String] = []
  let projection : Array[Int] = []
  let ordinals : Map[String, Int] = Map([])
  for i = 0; i < input_names.length(); i = i + 1 {
    if !spend_control(control, 1) ||
      !spend_control_text(control, input_names[i]) {
      return Err(RowLimit)
    }
    if ordinals.contains(input_names[i]) {
      return Err(InvalidRows)
    }
    if !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    ordinals[input_names[i]] = i
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
    Filter(_) | AssertAll(_) | AssertUnique(_) =>
      for name in input_names {
        if !spend_control(control, 1) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
    JsonPick(_, _, output) => {
      for name in input_names {
        if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
      if !spend_control(control, 1) ||
        !spend_control_text(control, output) ||
        !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      output_names.push(output)
    }
    SnapshotMap(bindings) | OrderedBindings(bindings) => {
      for name in input_names {
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
          if kind is SnapshotMap(_) {
            return Err(InvalidRows)
          }
          continue
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        output_names.push(name)
      }
    }
  }
  if kind is AssertUnique(keys) {
    match validate_unique_rows(input, keys, ordinals, control, workspace) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  // Complete input admission precedes all binding evaluation and shadowing.
  let input_roots : Array[ExpressionRootLease] = []
  if scope is Some(s) {
    match admit_logical_rows(s.budget, input_count.to_int64()) {
      Ok(_) => ()
      Err(e) => return Err(LogicalRows(e))
    }
    for row = 0; row < input_count; row = row + 1 {
      let source = IndexedRow::{ table: input, row, }
      if RowValues::value_count(source) != input_names.length() {
        return Err(InvalidRows)
      }
      if !reserve_slots(workspace, 1) {
        return Err(RowLimit)
      }
      let root = match retain_logical_row(s.budget, input_names, source) {
        Ok(r) => r
        Err(e) => return Err(LogicalRows(e))
      }
      match register_scope_root(s, root) {
        Ok(r) => input_roots.push(r)
        Err(e) => return Err(LogicalRows(e))
      }
    }
  }
  for row_index = 0; row_index < input_count; row_index = row_index + 1 {
    let source = IndexedRow::{ table: input, row: row_index, }
    if RowValues::value_count(source) != input_names.length() {
      return Err(InvalidRows)
    }
    if control.remaining == 0 {
      return Err(RowLimit)
    }
    control.remaining -= 1
    if scope is Some(s) {
      match charge_logical_work(s.budget, 1L) {
        Ok(_) => ()
        Err(e) => return Err(LogicalRows(e))
      }
    }
    // One immutable operation-start snapshot; map siblings never update it.
    let snapshot : Map[String, Value] = Map([])
    let needs_snapshot = match kind {
      SnapshotMap(_) | OrderedBindings(_) | Filter(_) | AssertAll(_) => true
      Select(_) | AssertUnique(_) | JsonPick(_, _, _) => false
    }
    if needs_snapshot {
      for i = 0; i < input_names.length(); i = i + 1 {
        if !RowValues::value_present(source, i) {
          continue
        }
        if !spend_control(control, 1) ||
          !spend_control_text(control, input_names[i]) {
          return Err(RowLimit)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        snapshot[input_names[i]] = RowValues::value_at(source, i)
      }
    }
    let row : Array[Value] = []
    let slot_roots : Array[ExpressionRootLease] = []
    match kind {
      Select(_) =>
        for index in projection {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(RowValues::value_at(source, index))
        }
      Filter(expr) => {
        let value = match
          evaluate_expression_with_workspace(
            expr,
            snapshot,
            [],
            control,
            workspace,
            logical_work=scope.map(s => s.budget),
          ) {
          Ok(v) => v
          Err(e) => return Err(evaluation_row_issue(row_index, 0, e))
        }
        match value {
          Boolean(true) if !preserve_filter_rows =>
            for i = 0; i < RowValues::value_count(source); i = i + 1 {
              if !spend_control(control, 1) {
                return Err(RowLimit)
              }
              if !reserve_slots(workspace, 1) {
                return Err(RowLimit)
              }
              row.push(RowValues::value_at(source, i))
            }
          Boolean(true) => ()
          Boolean(false) | Null => {
            if scope is Some(_) {
              match release_expression_root(input_roots[row_index]) {
                Ok(_) => ()
                Err(e) => return Err(LogicalRows(e))
              }
            }
            release_slots(workspace, snapshot.length())
            continue
          }
          Number(_) | Text(_) | Captured(_) => return Err(InvalidRows)
        }
      }
      AssertAll(expr) => {
        let value = match
          evaluate_expression_with_workspace(
            expr,
            snapshot,
            [],
            control,
            workspace,
            logical_work=scope.map(s => s.budget),
          ) {
          Ok(v) => v
          Err(e) => return Err(evaluation_row_issue(row_index, 0, e))
        }
        match value {
          Boolean(true) => ()
          Boolean(false) | Null | Number(_) | Text(_) | Captured(_) =>
            return Err(AssertionPredicate(row_index))
        }
        for i = 0; i < RowValues::value_count(source); i = i + 1 {
          if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(RowValues::value_at(source, i))
        }
      }
      AssertUnique(_) =>
        for i = 0; i < RowValues::value_count(source); i = i + 1 {
          if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(RowValues::value_at(source, i))
        }
      JsonPick(column, path, _) => {
        for i = 0; i < RowValues::value_count(source); i = i + 1 {
          if !spend_control(control, 1) || !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(RowValues::value_at(source, i))
        }
        let name = @schema.reference_name(column)
        guard ordinals.get(name) is Some(index) else { return Err(InvalidRows) }
        let picked = match
          json_pick_value(RowValues::value_at(source, index), path, control) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        if !reserve_slots(workspace, 1) {
          return Err(RowLimit)
        }
        row.push(picked)
      }
      SnapshotMap(bindings) => {
        for i = 0; i < RowValues::value_count(source); i = i + 1 {
          if !spend_control(control, 1) {
            return Err(RowLimit)
          }
          if !reserve_slots(workspace, 1) {
            return Err(RowLimit)
          }
          row.push(RowValues::value_at(source, i))
        }
        for slot = 0; slot < bindings.length(); slot = slot + 1 {
          let expr = bindings[slot].1
          if scope is Some(s) {
            match charge_logical_work(s.budget, 1L) {
              Ok(_) => ()
              Err(e) => return Err(LogicalRows(e))
            }
            if !reserve_slots(workspace, 1) {
              return Err(RowLimit)
            }
          }
          match
            evaluate_expression_retained(
              expr,
              snapshot,
              [],
              control,
              workspace,
              logical_work=scope.map(s => s.budget),
            ) {
            Ok(v) => {
              if scope is Some(s) {
                guard v.root is Some(root) else { return Err(InvalidRows) }
                match register_scope_root(s, root) {
                  Ok(lease) => slot_roots.push(lease)
                  Err(e) => return Err(LogicalRows(e))
                }
              }
              if !reserve_slots(workspace, 1) {
                return Err(RowLimit)
              }
              row.push(v.value)
            }
            Err(e) => return Err(evaluation_row_issue(row_index, slot, e))
          }
        }
      }
      OrderedBindings(bindings) => {
        guard scope is Some(s) else {
          return Err(MissingOrderedResourceContext)
        }
        let execution = start_ordered_bindings_execution(
          bindings, snapshot, control, workspace, s, row_index,
        )
        let mut completed : (Array[Value], Array[ExpressionRootLease])? = None
        while completed is None {
          match advance_ordered_bindings_execution(execution) {
            Ok(OrderedBindingsContinue) => ()
            Ok(OrderedBindingsComplete(values, roots)) =>
              completed = Some((values, roots))
            Err(issue) => return Err(issue)
          }
        }
        let (values, roots) = completed.unwrap()
        for root in roots {
          slot_roots.push(root)
        }
        let by_name : Map[String, Int] = Map([])
        for i = 0; i < bindings.length(); i = i + 1 {
          if !reserve_slots(workspace, 1) ||
            !spend_control_text(control, bindings[i].0) {
            return Err(RowLimit)
          }
          by_name[bindings[i].0] = i
        }
        for name in output_names {
          if !reserve_slots(workspace, 1) || !spend_control_text(control, name) {
            return Err(RowLimit)
          }
          row.push(
            match by_name.get(name) {
              Some(i) => values[i]
              None => RowValues::value_at(source, ordinals[name])
            },
          )
        }
        release_slots(workspace, values.length() + by_name.length())
      }
    }
    if !(if preserve_filter_rows {
        retain_row(source, output_names, output)
      } else {
        retain_row(row, output_names, output)
      }) {
      return Err(RowLimit)
    }
    if scope is Some(s) {
      let event = if preserve_filter_rows {
        row_event_output(
          s,
          output_names,
          source,
          slot_roots,
          input_roots[row_index],
        )
      } else {
        row_event_output(
          s,
          output_names,
          row,
          slot_roots,
          input_roots[row_index],
        )
      }
      match event {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
      release_slots(workspace, slot_roots.length())
    }
    if !reserve_slots(workspace, 1) {
      return Err(RowLimit)
    }
    match
      accept_row(
        row,
        row_index,
        output_names,
        if kind is Select(_) {
          Some(projection)
        } else {
          None
        },
      ) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    release_slots(workspace, snapshot.length())
  }
  Ok(output_names)
}
