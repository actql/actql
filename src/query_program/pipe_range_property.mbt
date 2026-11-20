///|
// A nearer clause binding may override an input range. Fields are evaluated slots,
// never expanded SELECT expressions or inferred from actual rows.
fn row_reference_fields(
  path : Array[@query.NamePart],
  value_name_exists : (@query.NamePart) -> Bool,
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> Array[(String, String)]? {
  if path.length() != 1 || value_name_exists(path[0]) {
    return None
  }
  let matches = ranges.filter(range => same_name(path[0], range.0))
  if matches.length() != 1 {
    return None
  }
  let fields = matches[0].1
  let seen : Map[String, Bool] = Map([])
  for (name, _) in fields {
    let key = ascii_upper(name)
    if seen.contains(key) {
      return None
    }
    seen[key] = true
  }
  // This private view stays inside one synchronous compiler expression.
  // The consumer only reads it; materialized Object fields get their own array.
  Some(fields)
}

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
  value_ranges? : Array[@query.NamePart] = [],
  column_profiles? : Array[ResultColumn]? = None,
  namespace_out? : Array[NamespaceView?]? = None,
) -> @builder.Node raise Abort {
  let row_ranges = ranges.filter(range => {
    !value_ranges.any(name => same_name(name, range.0))
  })
  append_resolved_range_expression(
    construction,
    expression,
    path => pipe_expression_slot(path, scope_named_columns(visible, column_profiles), scope_named_ranges(ranges, column_profiles), value_ranges~),
    name => {
      pipe_name_exists(visible, name) &&
      !ordinary_range_name(name, ranges, value_ranges)
    },
    max_work,
    resolve_row=Some(path => row_reference_fields(path, _ => false, row_ranges)),
    column_profiles~,
    namespace_out~,
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
  resolve_row? : ((Array[@query.NamePart]) -> Array[(String, String)]?)? = None,
  column_profiles? : Array[ResultColumn]? = None,
  namespace_out? : Array[NamespaceView?]? = None,
) -> @builder.Node raise Abort {
  let (lowered, slots, remaining) = bind_range_property_expression(
    expression, resolve, value_name_exists, max_work,
  )
  let bound_resolve = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      for (name, slot) in slots {
        if path[0].value == name { return Some(slot) }
      }
    }
    resolve(path)
  }
  let namespace_frame = if column_profiles is Some(_) {
    Some(expression_namespace(lowered, bound_resolve, path => resolve_row.bind(resolver => resolver(path)), column_profiles, remaining))
  } else { None }
  if namespace_out is Some(output) { output.push(namespace_frame.bind(frame => frame.root)) }
  match
    @expression.append_with_properties(
      lowered,
      bound_resolve,
      construction.builder,
      namespace_frame.map(frame => frame.remaining).unwrap_or(remaining),
      resolve_parameter=construction.parameter_resolver(),
      resolve_row~,
      resolve_row_with_work=match namespace_frame {
        None => None
        Some(frame) => Some((path, available) => {
          for (original, fields) in frame.rows {
            if same_path(path, original) {
              return namespace_row_fields(fields, column_profiles, available).map(projected => Some(projected))
            }
          }
          Ok(None)
        })
      },
    ) {
    Ok(node) => node
    Err(issue) => raise Abort(Expression(issue))
  }
}
