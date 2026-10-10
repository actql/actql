///|
// Only the operand of an evaluated GROUP key may use this identity. The
// original unary-plus expression remains in derive and in the common checker,
// so exposing its operand cannot admit a nonnumeric key or bypass failure.
// General expression equality must still distinguish +value from value.
fn group_unary_plus_operand(
  expression : @query.Expression,
) -> @query.Expression? {
  let mut index = @query.expression_root(expression)
  let mut positive = false
  while true {
    match @query.expression_node(expression, index).unwrap().kind {
      Parenthesized(child) => index = child
      Unary("+", child) => {
        positive = true
        index = child
      }
      _ => break
    }
  }
  if positive {
    @query.expression_child(expression, index)
  } else {
    None
  }
}
