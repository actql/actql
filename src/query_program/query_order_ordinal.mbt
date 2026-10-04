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
      let mut ordinal = 0
      for unit in text {
        let digit = unit.to_int() - 48
        if digit < 0 || digit > 9 || ordinal > (visible.length() - digit) / 10 {
          raise Abort(UnsupportedOrdering)
        }
        ordinal = ordinal * 10 + digit
        if ordinal > visible.length() {
          raise Abort(UnsupportedOrdering)
        }
      }
      if ordinal < 1 {
        raise Abort(UnsupportedOrdering)
      }
      Some(visible[ordinal - 1])
    }
    // The reference folds a directly negated numeric token into a literal.
    // Negation of a parenthesized expression remains ordinary computation.
    Unary("-", child) => {
      if @query.expression_node(expression, child).unwrap().kind is Number(_) {
        raise Abort(UnsupportedOrdering)
      }
      None
    }
    StringLiteral(_) | Boolean(_) | Null => raise Abort(UnsupportedOrdering)
    _ => None
  }
}
