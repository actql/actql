///|
// The ordinary expression lowerer represents these IS NOT predicates as one
// common NOT around the corresponding test. Match that exact shape only:
// do not erase a NOT, exchange a test, or replace null-safe comparison by =.
fn negated_is_predicate_shape(
  expression : @query.Expression,
  index : Int,
) -> (String, Array[Int])? {
  let mut current = index
  let explicit = match
    @query.expression_node(expression, current).unwrap().kind {
    Unary("NOT", child) => {
      current = child
      while @query.expression_node(expression, current).unwrap().kind
            is Parenthesized(child) {
        current = child
      }
      true
    }
    _ => false
  }
  guard @query.expression_node(expression, current).unwrap().kind
    is Predicate(operation, arguments) else {
    return None
  }
  let name = if explicit {
    match operation {
      "IS NULL" => "is_null"
      "IS TRUE" => "is_true"
      "IS FALSE" => "is_false"
      "IS UNKNOWN" => "is_unknown"
      "IS DISTINCT FROM" => "is_distinct_from"
      _ => return None
    }
  } else {
    match operation {
      "IS NOT NULL" => "is_null"
      "IS NOT TRUE" => "is_true"
      "IS NOT FALSE" => "is_false"
      "IS NOT UNKNOWN" => "is_unknown"
      "IS NOT DISTINCT FROM" => "is_distinct_from"
      _ => return None
    }
  }
  Some((name, arguments))
}
