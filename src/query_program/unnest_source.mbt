///|
/// Direct scalar value-table stars use the ordinary visible element/index
/// columns. Unknown expression shapes and STRUCT expansion remain unsupported;
/// the shared checker still validates the array and all bound values.
fn unnest_scalar_parameter(
  expression : @query.Expression,
  declarations : @parameters.Declarations?,
) -> Bool {
  guard declarations is Some(declarations) else { return false }
  let mut root = @query.expression_root(expression)
  while @query.expression_node(expression, root)
        is Some({ kind: Parenthesized(child), .. }) {
    root = child
  }
  guard @query.expression_node(expression, root)
    is Some({ kind: ParameterReference(name), .. }) else {
    return false
  }
  for declaration in @parameters.declarations(declarations) {
    if declaration.name == name {
      return match declaration.parameter_type.contract.shape {
        @contract.Array(element, ..) => !(element.shape is @contract.Object(_))
        _ => false
      }
    }
  }
  false
}
