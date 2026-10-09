///|
// Recognize only the existing binary strict STRING concatenation shape.
// No associative flattening, conversion, reordering or value evaluation proves
// equivalence here; the usual expression comparison checks both child trees.
fn strict_concat_pair(kind : @query.ExpressionKind) -> (Int, Int)? {
  match kind {
    Binary("||", left, right) => Some((left, right))
    Call(path, [left, right]) if path.length() == 1 &&
      ascii_upper(path[0].value) == "CONCAT" => Some((left, right))
    _ => None
  }
}
