///|
// Aggregate-local order keys use the input scope, never SELECT siblings. A
// static typed property path is a total projection of an admitted row: NULL
// receivers propagate NULL and missing/non-object members fail common checking.
// Do not hoist arbitrary calls or arithmetic out of aggregate demand here.
fn aggregate_order_fields(
  construction : Construction,
  call : @query.AggregateCall,
  resolve : (Array[@query.NamePart]) -> String?,
  reserved : Array[String],
  evaluated : Array[(@query.Expression, String)],
  derives : Array[(String, @builder.Node)],
  max_work : Int,
) -> Array[String] raise Abort {
  let fields : Array[String] = []
  for term in call.order_by {
    let expression = term.expression
    let mut root = @query.expression_node(
      expression,
      @query.expression_root(expression),
    ).unwrap()
    while root.kind is Parenthesized(child) {
      root = @query.expression_node(expression, child).unwrap()
    }
    guard root.kind is Reference(path) else {
      raise Abort(UnsupportedAggregate)
    }
    if resolve(path) is Some(field) {
      fields.push(field)
      continue
    }
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
    let mut reused : String? = None
    for (previous, field) in evaluated {
      // Every comparison uses this same immutable GROUP input resolver.
      if same_expression(expression, previous) {
        reused = Some(field)
        break
      }
    }
    if reused is Some(field) {
      fields.push(field)
      continue
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
    let field = pipe_physical_name(reserved, "aql_aggregate_sort_")
    reserved.push(field)
    evaluated.push((expression, field))
    derives.push((field, value))
    fields.push(field)
  }
  fields
}
