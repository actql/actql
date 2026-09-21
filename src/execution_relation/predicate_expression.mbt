///|
/// A private expression frame exposed only as a bounded Boolean predicate.
/// The caller owns the immutable row bindings for this execution lifetime.
struct PredicateExpressionExecution {
  inner : ExpressionExecution
  mut finished : Bool
}

///|
pub(all) enum PredicateExpressionPoll {
  PredicateExpressionContinue
  PredicateExpressionComplete(Bool)
}

///|
/// Start one checked predicate without draining any expression work.
/// `max_work` is the remaining operation-wide expression budget supplied by
/// the caller; callers must carry the returned remainder across rows.
pub fn start_predicate_expression(
  expression : @lower.Expression,
  input : Map[String, Value],
  max_work : Int,
  max_frames : Int,
  max_workspace_slots : Int,
) -> Result[PredicateExpressionExecution, EvalIssue] {
  start_expression_execution(
    expression,
    input,
    [],
    max_work,
    max_frames,
    max_workspace_slots,
  ).map(inner => { inner, finished: false, })
}

///|
/// Advance by one semantic expression transition. Logical expression work can
/// consume more than one budget unit inside that transition, but no additional
/// expression node is entered before this function returns.
pub fn advance_predicate_expression(
  execution : PredicateExpressionExecution,
) -> Result[PredicateExpressionPoll, EvalIssue] {
  if execution.finished {
    return Err({
      kind: InvalidControlLimits,
      expression: execution.inner.frame.root,
    })
  }
  match advance_expression_execution(execution.inner) {
    Err(issue) => {
      execution.finished = true
      Err(issue)
    }
    Ok(ExpressionContinue) => Ok(PredicateExpressionContinue)
    Ok(ExpressionComplete(value)) => {
      execution.finished = true
      match value {
        Boolean(value) => Ok(PredicateExpressionComplete(value))
        Null => Ok(PredicateExpressionComplete(false))
        Number(_) | Text(_) | Captured(_) =>
          Err({
            kind: Scalar(InvalidOperand),
            expression: execution.inner.frame.root,
          })
      }
    }
  }
}

///|
pub fn predicate_expression_remaining(
  execution : PredicateExpressionExecution,
) -> Int {
  expression_execution_remaining(execution.inner)
}

///|
/// Cancel an unfinished predicate and release its temporary roots and
/// workspace. Caller-owned row bindings are not released here.
pub fn cancel_predicate_expression(
  execution : PredicateExpressionExecution,
) -> Bool {
  if !execution.finished {
    cancel_expression_execution(execution.inner) |> ignore
    execution.finished = true
  }
  true
}
