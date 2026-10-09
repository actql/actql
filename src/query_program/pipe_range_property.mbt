///|
// A parenthesized range receiver is qualification of its existing column,
// whereas a receiver that resolves to a value remains ordinary property access.
// Bind only the former through the source owner's span-preserving AST operation.
fn bind_range_property_expression(
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  value_name_exists : (@query.NamePart) -> Bool,
  max_work : Int,
) -> (@query.Expression, Array[(String, String)], Int) raise Abort {
  let count = @query.expression_node_count(expression)
  let mut remaining = max_work
  let spend = fn(amount : Int, at : Int) -> Unit raise Abort {
    if amount < 0 || amount > remaining {
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @query.expression_origin(expression, at),
        }),
      )
    }
    remaining -= amount
  }
  let bindings : Array[(Int, @query.NamePart)] = []
  let slots : Array[(String, String)] = []
  let authored : Array[String] = []
  spend(count, @query.expression_root(expression))
  for node in 0..<count {
    if @query.expression_node(expression, node).unwrap().kind is Reference(path) {
      spend(path.length(), node)
      authored.append(path.map(part => ascii_upper(part.value)))
    }
  }
  for node in 0..<count {
    spend(1, node)
    guard @query.expression_node(expression, node).unwrap().kind
      is Property(child, property_name) else {
      continue
    }
    let mut receiver = child
    while @query.expression_node(expression, receiver).unwrap().kind
          is Parenthesized(inner) {
      spend(1, node)
      receiver = inner
    }
    guard @query.expression_node(expression, receiver).unwrap().kind
      is Reference(path) &&
      path.length() == 1 &&
      !value_name_exists(path[0]) else {
      continue
    }
    guard resolve([path[0], property_name]) is Some(slot) else { continue }
    let mut serial = bindings.length()
    let mut name = "aql_pipe_range_property_" + serial.to_string()
    while true {
      spend(authored.length() + slots.length() + 1, node)
      if !authored.contains(ascii_upper(name)) &&
        !slots.any(entry => entry.0 == name) {
        break
      }
      serial += 1
      name = "aql_pipe_range_property_" + serial.to_string()
    }
    bindings.push((node, { value: name, quoted: true, }))
    slots.push((name, slot))
  }
  let lowered = if bindings.is_empty() {
    expression
  } else {
    // The existing subtree owner scans/remaps nodes; reserve its full passes.
    for _ in 0..<3 {
      spend(count, @query.expression_root(expression))
    }
    @query.expression_with_field_bindings(expression, bindings).unwrap()
  }
  (lowered, slots, remaining)
}

///|
fn append_pipe_range_expression(
  construction : Construction,
  expression : @query.Expression,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
) -> @builder.Node raise Abort {
  append_resolved_range_expression(
    construction,
    expression,
    path => pipe_slot(path, visible, ranges),
    name => pipe_name_exists(visible, name),
    max_work,
  )
}

///|
// ORDER supplies an alias-first resolver over its actual available slots.
// Use the same range binding and work budget as ordinary Pipe expressions.
fn append_resolved_range_expression(
  construction : Construction,
  expression : @query.Expression,
  resolve : (Array[@query.NamePart]) -> String?,
  value_name_exists : (@query.NamePart) -> Bool,
  max_work : Int,
) -> @builder.Node raise Abort {
  let (lowered, slots, remaining) = bind_range_property_expression(
    expression,
    resolve,
    value_name_exists,
    max_work,
  )
  match
    @expression.append_with_properties(
      lowered,
      path => {
        if path.length() == 1 {
          for (name, slot) in slots {
            if path[0].value == name {
              return Some(slot)
            }
          }
        }
        resolve(path)
      },
      construction.builder,
      remaining,
      resolve_parameter=construction.parameter_resolver(),
    ) {
    Ok(node) => node
    Err(issue) => raise Abort(Expression(issue))
  }
}
