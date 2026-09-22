///|
/// Private resumable state for one ordered-binding row. The enclosing row
/// operation owns the immutable input snapshot, logical scope and budgets.
/// A single advance either starts one slot or performs one expression
/// transition; it never drains a second transition implicitly.
priv struct OrderedBindingsExecution {
  bindings : Array[(String, @lower.Expression)]
  snapshot : Map[String, Value]
  control : ControlBudget
  workspace : RowWorkspace
  scope : ExpressionRoots
  row : Int
  ordered : Bool
  mut slot : Int
  mut active : ExpressionFrame?
  mut values : Array[Value]
  mut roots : Array[ExpressionRootLease]
  mut finished : Bool
}

///|
priv enum OrderedBindingsAdvance {
  OrderedBindingsContinue
  OrderedBindingsComplete(Array[Value], Array[ExpressionRootLease])
}

///|
fn start_bindings_execution(
  bindings : Array[(String, @lower.Expression)],
  snapshot : Map[String, Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots,
  row : Int,
  ordered : Bool,
) -> OrderedBindingsExecution {
  {
    bindings,
    snapshot,
    control,
    workspace,
    scope,
    row,
    ordered,
    slot: 0,
    active: None,
    values: [],
    roots: [],
    finished: false,
  }
}

///|
fn start_ordered_bindings_execution(
  bindings : Array[(String, @lower.Expression)],
  snapshot : Map[String, Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots,
  row : Int,
) -> OrderedBindingsExecution {
  start_bindings_execution(
    bindings, snapshot, control, workspace, scope, row, true,
  )
}

///|
fn start_snapshot_bindings_execution(
  bindings : Array[(String, @lower.Expression)],
  snapshot : Map[String, Value],
  control : ControlBudget,
  workspace : RowWorkspace,
  scope : ExpressionRoots,
  row : Int,
) -> OrderedBindingsExecution {
  start_bindings_execution(
    bindings, snapshot, control, workspace, scope, row, false,
  )
}

///|
/// Release only state owned by this row execution. The input snapshot and
/// enclosing logical scope remain owned by the row operation.
fn cancel_ordered_bindings_execution(
  execution : OrderedBindingsExecution,
) -> Unit {
  if execution.finished {
    return
  }
  let active_slots = if execution.active is Some(_) { 2 } else { 0 }
  if execution.active is Some(frame) {
    close_expression_frame(frame)
    execution.active = None
  }
  for root in execution.roots {
    release_expression_root(root) |> ignore
  }
  let retained_slots = execution.values.length() * 2 + active_slots
  if retained_slots > 0 {
    release_slots(execution.workspace, retained_slots)
  }
  execution.values = []
  execution.roots = []
  execution.finished = true
}

///|
fn advance_ordered_bindings_execution(
  execution : OrderedBindingsExecution,
) -> Result[OrderedBindingsAdvance, RowIssue] {
  if execution.finished {
    return Err(InvalidRows)
  }
  if execution.active is Some(frame) {
    match advance_expression_frame(frame) {
      Err(issue) => {
        cancel_ordered_bindings_execution(execution)
        return Err(evaluation_row_issue(execution.row, execution.slot, issue))
      }
      Ok(None) => return Ok(OrderedBindingsContinue)
      Ok(Some(evaluated)) => {
        execution.active = None
        guard evaluated.root is Some(root) else {
          cancel_ordered_bindings_execution(execution)
          return Err(InvalidRows)
        }
        let lease = match register_scope_root(execution.scope, root) {
          Ok(value) => value
          Err(issue) => {
            cancel_ordered_bindings_execution(execution)
            return Err(LogicalRows(issue))
          }
        }
        execution.roots.push(lease)
        execution.values.push(evaluated.value)
        execution.slot += 1
        return Ok(OrderedBindingsContinue)
      }
    }
  }
  if execution.slot == execution.bindings.length() {
    execution.finished = true
    return Ok(OrderedBindingsComplete(execution.values, execution.roots))
  }
  match charge_logical_work(execution.scope.budget, 1L) {
    Err(issue) => {
      cancel_ordered_bindings_execution(execution)
      return Err(LogicalRows(issue))
    }
    Ok(_) => ()
  }
  if !reserve_slots(execution.workspace, 2) {
    cancel_ordered_bindings_execution(execution)
    return Err(RowLimit)
  }
  let expression = execution.bindings[execution.slot].1
  execution.active = match
    expression_frame(
      expression,
      execution.snapshot,
      if execution.ordered {
        execution.values
      } else {
        []
      },
      execution.control,
      execution.workspace,
      Some(
        expression_roots(execution.scope.budget, execution.control.max_frames),
      ),
    ) {
    Ok(frame) => Some(frame)
    Err(issue) => {
      release_slots(execution.workspace, 2)
      cancel_ordered_bindings_execution(execution)
      return Err(evaluation_row_issue(execution.row, execution.slot, issue))
    }
  }
  Ok(OrderedBindingsContinue)
}
