///|
// DISTINCT collection ordering must name its input argument. Qualification,
// quotation and static property syntax do not change an admitted receiver.
// Resolve against the same immutable aggregate input scope for both sides.
fn aggregate_order_matches_argument(
  argument : @query.Expression,
  order : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
) -> Bool {
  let identity = fn(
    expression : @query.Expression,
  ) -> (String, Array[@query.NamePart])? {
    let mut index = @query.expression_root(expression)
    let suffix : Array[@query.NamePart] = []
    while true {
      match @query.expression_node(expression, index).unwrap().kind {
        Parenthesized(child) => index = child
        Property(child, name) => {
          suffix.push(name)
          index = child
        }
        Reference(parts) => {
          // Resolve this receiver before appending explicit property nodes.
          // (payload).name must not become the range-qualified payload.name.
          guard order_reference_identity(parts, resolve) is Some((slot, length)) else {
            return None
          }
          let members = parts[length:].to_owned()
          for i = suffix.length() - 1; i >= 0; i = i - 1 {
            members.push(suffix[i])
          }
          return Some((slot, members))
        }
        _ => return None
      }
    } nobreak {
      None
    }
  }
  match (identity(argument), identity(order)) {
    (Some((a, left)), Some((b, right))) => {
      if a != b || left.length() != right.length() {
        return false
      }
      for index in 0..<left.length() {
        if !same_name(left[index], right[index]) {
          return false
        }
      }
      true
    }
    _ => same_expression(argument, order)
  }
}

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
    let mut explicit_property = false
    while true {
      match root.kind {
        Parenthesized(child) =>
          root = @query.expression_node(expression, child).unwrap()
        Property(child, _) => {
          explicit_property = true
          root = @query.expression_node(expression, child).unwrap()
        }
        _ => break
      }
    }
    guard root.kind is Reference(path) else {
      raise Abort(UnsupportedAggregate)
    }
    if !explicit_property {
      if resolve(path) is Some(field) {
        fields.push(field)
        continue
      }
    }
    // Explicit Property nodes keep their receiver AST. Do not concatenate
    // members into a path that could instead resolve as a range qualifier.
    let mut receiver = explicit_property && resolve(path) is Some(_)
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
        resolve_parameter=construction.parameter_resolver(),
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
