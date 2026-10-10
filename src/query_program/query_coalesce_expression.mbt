///|
// IFNULL and exactly two-operand COALESCE have the same installed lazy node.
// Only identify its shape here: the caller compares both operands through
// its existing clause-scope and node-resolution callbacks.
fn two_operand_coalesce_shape(
  expression : @query.Expression,
  index : Int,
) -> Array[Int]? {
  match @query.expression_node(expression, index) {
    Some({ kind: Call(path, operands), .. }) =>
      if path.length() == 1 && operands.length() == 2 {
        match ascii_upper(path[0].value) {
          "IFNULL" | "COALESCE" => Some(operands)
          _ => None
        }
      } else {
        None
      }
    _ => None
  }
}
