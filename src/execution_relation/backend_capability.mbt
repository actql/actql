///|
pub(all) enum BackendCapabilityIssueKind {
  UnsupportedComparison(@lower.BinaryOperator)
  PreparationLimit
}

///|
/// Retains both the root's step/parameter pointer and the offending expression's
/// source location. This is backend readiness, not a language typing failure.
pub struct BackendCapabilityIssue {
  kind : BackendCapabilityIssueKind
  root : @lower.ExpressionRoot
  expression : @lower.Expression
}

///|
fn supported_comparison(
  left : @contract.Contract,
  right : @contract.Contract,
) -> Bool {
  match left.shape {
    Number => right.shape is @contract.Number
    Boolean => right.shape is @contract.Boolean
    Text(_) => right.shape is @contract.Text(_)
    Date => right.shape is @contract.Date
    Timestamp => right.shape is @contract.Timestamp
    Decimal(..) => right.shape is @contract.Decimal(..)
    ResourceRef(resource_kind=left_kind) =>
      right.shape is @contract.ResourceRef(resource_kind=right_kind) &&
      left_kind == right_kind
    ArtifactRef(..) => right.shape is @contract.ArtifactRef(..)
    Json | Array(_, ..) | Object(_) | Vector(..) => false
  }
}

///|
fn supported_binary_comparison(
  operation : @lower.BinaryOperator,
  left : @contract.Contract,
  right : @contract.Contract,
) -> Bool {
  match left.shape {
    ResourceRef(..) | ArtifactRef(..) =>
      supported_comparison(left, right) &&
      (
        operation is Equal ||
        operation is NotEqual ||
        operation is IsDistinctFrom ||
        operation is NullIf
      )
    _ => supported_comparison(left, right)
  }
}

///|
/// Inspect every checked branch, without evaluating any expression or inspecting
/// input rows. One shared construction allowance bounds visits, copied child
/// views and queued edges across all roots; runtime logical-work is untouched.
fn check_backend_capabilities(
  roots : @lower.RootIndex,
  max_entries : Int,
) -> Result[Unit, BackendCapabilityIssue] {
  let mut remaining = max_entries
  for i = 0; i < @lower.root_count(roots); i = i + 1 {
    guard @lower.root_at(roots, i) is Some(root) else { continue }
    if remaining <= 0 {
      return Err({ kind: PreparationLimit, root, expression: root.expression, })
    }
    remaining -= 1
    let pending = [root.expression]
    while pending.pop() is Some(expression) {
      let copied = @lower.expression_view_entries(expression)
      if remaining <= 0 || copied > remaining - 1 {
        return Err({ kind: PreparationLimit, root, expression, })
      }
      remaining -= 1 + copied
      let body = @lower.expression_body(expression)
      let edges = match body {
        Field(_, _) | Literal(_) | TypedNull => 0
        Unary(_, _) => 1
        Property(_, _, _) => 1
        Object(fields) => fields.length()
        Binary(_, _, _) => 2
        VectorScore(_, _, _) => 2
        VectorConcat(children) => children.length()
        Conditional(_, _, _) => 3
        Many(_, children) => children.length()
        Case(clauses, _) => {
          if remaining == 0 || clauses.length() > (remaining - 1) / 2 {
            return Err({ kind: PreparationLimit, root, expression, })
          }
          clauses.length() * 2 + 1
        }
      }
      if edges > remaining {
        return Err({ kind: PreparationLimit, root, expression, })
      }
      remaining -= edges
      match body {
        Field(_, _) | Literal(_) | TypedNull => ()
        Unary(_, child) => pending.push(child)
        Property(child, _, _) => pending.push(child)
        Object(fields) =>
          for j = fields.length() - 1; j >= 0; j = j - 1 {
            pending.push(fields[j].1)
          }
        Binary(op, left, right) => {
          match op {
            Equal
            | NotEqual
            | IsDistinctFrom
            | Less
            | LessEqual
            | Greater
            | GreaterEqual
            | NullIf =>
              if !supported_binary_comparison(
                  op,
                  @lower.expression_contract(left),
                  @lower.expression_contract(right),
                ) {
                return Err({
                  kind: UnsupportedComparison(op),
                  root,
                  expression,
                })
              }
            Add | Subtract | Multiply | Divide | Modulo => ()
          }
          pending.push(right)
          pending.push(left)
        }
        VectorScore(_, left, right) => {
          pending.push(right)
          pending.push(left)
        }
        VectorConcat(children) =>
          for j = children.length() - 1; j >= 0; j = j - 1 {
            pending.push(children[j])
          }
        Many(_, children) =>
          for j = children.length() - 1; j >= 0; j = j - 1 {
            pending.push(children[j])
          }
        Conditional(condition, yes, no) => {
          pending.push(no)
          pending.push(yes)
          pending.push(condition)
        }
        Case(clauses, otherwise) => {
          pending.push(otherwise)
          for j = clauses.length() - 1; j >= 0; j = j - 1 {
            let (condition, result) = clauses[j]
            pending.push(result)
            pending.push(condition)
          }
        }
      }
    }
  }
  Ok(())
}
