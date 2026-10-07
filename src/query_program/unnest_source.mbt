///|
// Inspect admitted parameter contracts, never the rows, to establish a value
// table's visible STRUCT fields even when the input is empty or NULL.
fn unnest_parameter_element(
  expression : @query.Expression,
  declarations : @parameters.Declarations?,
) -> @contract.Contract? {
  guard declarations is Some(declarations) else { return None }
  let mut root = @query.expression_root(expression)
  while @query.expression_node(expression, root)
        is Some({ kind: Parenthesized(child), .. }) {
    root = child
  }
  guard @query.expression_node(expression, root)
    is Some({ kind: ParameterReference(name), .. }) else {
    return None
  }
  for declaration in @parameters.declarations(declarations) {
    if declaration.name == name {
      return match declaration.parameter_type.contract.shape {
        @contract.Array(element, ..) => Some(element)
        _ => None
      }
    }
  }
  None
}

///|
// A STRUCT value-table range denotes its original value, but is not an extra
// visible column. Current columns take precedence over a bare range name.
fn unnest_expression_columns(
  visible : Array[(String, String)],
  receiver : (@query.NamePart, String)?,
) -> Array[(String, String)] {
  match receiver {
    Some((name, slot)) if !pipe_name_exists(visible, name) =>
      visible + [(name.value, slot)]
    _ => visible
  }
}
