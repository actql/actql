///|
// An untyped integer literal in ORDER names a visible column position. Keep
// it separate from expression evaluation and never expose physical helpers.
fn order_ordinal_column(
  expression : @query.Expression,
  visible : Array[String],
) -> String? raise Abort {
  let mut root = @query.expression_node(
    expression,
    @query.expression_root(expression),
  ).unwrap()
  while true {
    match root.kind {
      Parenthesized(child) | Unary("+", child) =>
        root = @query.expression_node(expression, child).unwrap()
      _ => break
    }
  }
  match root.kind {
    Number(text) => {
      guard @query.exact_integer_literal(text) is Some(value) &&
        value <= visible.length().to_int64() else {
        raise Abort(InvalidQuery)
      }
      let ordinal = value.to_int()
      if ordinal < 1 {
        raise Abort(InvalidQuery)
      }
      Some(visible[ordinal - 1])
    }
    // The reference folds a directly negated numeric token into a literal.
    // Negation of a parenthesized expression remains ordinary computation.
    Unary("-", child) => {
      if @query.expression_node(expression, child).unwrap().kind is Number(_) {
        raise Abort(InvalidQuery)
      }
      None
    }
    StringLiteral(_) | Boolean(_) | Null => raise Abort(InvalidQuery)
    _ => None
  }
}
