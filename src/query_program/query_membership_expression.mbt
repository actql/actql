///|
// Match only the scalar atoms already admitted by the ordinary membership
// lowerer. A computed or annotated ARRAY is not a literal list, and a signed
// parameter is not an immediate parameter atom. Numeric admission is shared.
fn membership_literal_atom(expression : @query.Expression, index : Int) -> Bool {
  let mut current = index
  let mut signed = false
  let mut has_minus = false
  while true {
    match @query.expression_node(expression, current).unwrap().kind {
      Parenthesized(child) => current = child
      Unary("+", child) => {
        signed = true
        current = child
      }
      Unary("-", child) => {
        signed = true
        has_minus = true
        current = child
      }
      Number(text) =>
        return match @expression.numeric_literal(text) {
          Ok(value) => !(has_minus && value == 0.0)
          Err(_) => false
        }
      StringLiteral(_) | Boolean(_) | Null | ParameterReference(_) =>
        return !signed
      _ => return false
    }
  } nobreak {
    false
  }
}

///|
// Return the common operation and its ordered child trees, not evaluated
// values. Scope, parameter and literal equality still use the caller's existing
// comparison. Empty ARRAYs are not equated with the invalid SQL IN () syntax.
fn literal_membership_shape(
  expression : @query.Expression,
  index : Int,
) -> (String, Int, Array[Int])? {
  guard @query.expression_node(expression, index).unwrap().kind
    is Predicate(operation, arguments) &&
    arguments.length() >= 2 else {
    return None
  }
  let (name, items) = match operation {
    "IN" => ("in", arguments[1:].to_owned())
    "NOT IN" => ("not_in", arguments[1:].to_owned())
    "IN UNNEST" | "NOT IN UNNEST" => {
      guard arguments.length() == 2 else { return None }
      let mut array = arguments[1]
      while @query.expression_node(expression, array).unwrap().kind
            is Parenthesized(child) {
        array = child
      }
      guard @query.expression_node(expression, array).unwrap().kind
        is ArrayConstructor(items, None) else {
        return None
      }
      (if operation == "IN UNNEST" { "in" } else { "not_in" }, items)
    }
    _ => return None
  }
  for item in items {
    if !membership_literal_atom(expression, item) {
      return None
    }
  }
  Some((name, arguments[0], items))
}
