///|
// OVER partition/order keys see one immutable SELECT input scope. Numeric
// order literals are values, not the ordinals of the query's final ORDER BY.
// Only ordinary expressions become private derive slots; common analytic
// checking retains key type and order law.
fn analytic_order_field(
  construction : Construction,
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  reserved : Array[String],
  evaluated : Array[(@query.Expression, String)],
  derives : Array[(String, @builder.Node)],
  max_work : Int,
) -> String raise Abort {
  let mut root = @query.expression_node(
    expression,
    @query.expression_root(expression),
  ).unwrap()
  while root.kind is Parenthesized(child) {
    root = @query.expression_node(expression, child).unwrap()
  }
  if root.kind is Reference(path) {
    if resolve(path) is Some(field) {
      return field
    }
    // Preserve the direct-column refusal. Property paths instead resolve an
    // existing receiver prefix through the common expression lowerer.
    let mut receiver = false
    for length = 1; length < path.length(); length = length + 1 {
      if resolve(path[:length].to_owned()) is Some(_) {
        receiver = true
        break
      }
    }
    if !receiver {
      raise Abort(UnknownColumn)
    }
  }
  for (value, field) in evaluated {
    if same_expression(expression, value) {
      return field
    }
  }
  let value = match
    @expression.append_with_properties(
      expression,
      resolve,
      construction.builder,
      max_work,
    ) {
    Ok(value) => value
    Err(error) => raise Abort(Expression(error))
  }
  let field = pipe_physical_name(reserved, "aql_analytic_sort_")
  reserved.push(field)
  derives.push((field, value))
  evaluated.push((expression, field))
  field
}
