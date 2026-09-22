///|
/// Private, attempt-local expression state exposed through bounded advances.
/// The caller owns the immutable row and prior-slot bindings for this
/// execution lifetime. This is not completion evidence or an admission API.
struct ExpressionExecution {
  frame : ExpressionFrame
  mut finished : Bool
}

///|
pub(all) enum ExpressionExecutionPoll {
  ExpressionContinue
  ExpressionComplete(Value)
}

///|
/// Start one checked expression without evaluating an expression transition.
/// The supplied work and workspace bounds apply to the complete expression.
pub fn start_expression_execution(
  expression : @lower.Expression,
  input : Map[String, Value],
  slots : Array[Value],
  max_work : Int,
  max_frames : Int,
  max_workspace_slots : Int,
) -> Result[ExpressionExecution, EvalIssue] {
  let budget : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_workspace_slots)
  expression_frame(expression, input, slots, budget, workspace, None).map(frame => {
    frame,
    finished: false,
  })
}

///|
/// Advance exactly one semantic expression transition. Vector score and
/// concatenation component loops therefore remain observable and cancellable.
pub fn advance_expression_execution(
  execution : ExpressionExecution,
) -> Result[ExpressionExecutionPoll, EvalIssue] {
  if execution.finished {
    return Err({ kind: InvalidControlLimits, expression: execution.frame.root, })
  }
  match advance_expression_frame(execution.frame) {
    Err(issue) => {
      execution.finished = true
      Err(issue)
    }
    Ok(None) => Ok(ExpressionContinue)
    Ok(Some(result)) => {
      execution.finished = true
      Ok(ExpressionComplete(result.value))
    }
  }
}

///|
pub fn expression_execution_remaining(execution : ExpressionExecution) -> Int {
  execution.frame.budget.remaining
}

///|
/// Cancel an unfinished expression and release only its temporary roots and
/// workspace. Caller-owned row and prior-slot bindings remain caller-owned.
pub fn cancel_expression_execution(execution : ExpressionExecution) -> Bool {
  if !execution.finished {
    close_expression_frame(execution.frame)
    execution.finished = true
  }
  true
}
