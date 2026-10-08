///|
// Both SQL SELECT and Pipe AGGREGATE may use a grouped expression inside a
// larger scalar tree. Reuse only an evaluated key whose original receiver
// resolution agrees; retaining a key does not restore its input object.
fn append_grouped_expression(
  construction : Construction,
  expression : @query.Expression,
  grouped_keys : Array[(@query.Expression, String)],
  resolve_input : (Array[@query.NamePart]) -> String?,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
) -> @builder.Node raise Abort {
  append_grouped_expression_resolved(
    construction,
    expression,
    grouped_keys,
    (left, right) => same_group_reference(left, right, resolve_input),
    path => pipe_slot(path, visible, ranges),
    visible.map(entry => entry.0),
    max_work,
  )
}

///|
// The caller supplies clause-aware reference meanings and value resolution.
// Bind only proven key subtrees; ordinary evaluation remains in the common
// expression bridge, including nullable object prefix projection.
fn append_grouped_expression_resolved(
  construction : Construction,
  expression : @query.Expression,
  grouped_keys : Array[(@query.Expression, String)],
  references : (Array[@query.NamePart], Array[@query.NamePart]) -> Bool,
  resolve : (Array[@query.NamePart]) -> String?,
  reserved_names : Array[String],
  max_work : Int,
) -> @builder.Node raise Abort {
  if grouped_keys.is_empty() {
    return match
      @expression.append_with_properties(
        expression,
        resolve,
        construction.builder,
        max_work,
        resolve_parameter=construction.parameter_resolver(),
      ) {
      Ok(node) => node
      Err(error) => raise Abort(Expression(error))
    }
  }
  let bindings : Array[(Int, @query.NamePart)] = []
  let bound_visible : Array[(String, String)] = []
  let authored_paths = join_reference_paths(expression)
  let mut binding_work = 0
  for node in 0..<@query.expression_node_count(expression) {
    binding_work += @query.expression_node_count(expression)
    if binding_work > max_work {
      raise Abort(
        Expression({
          issue: @expression.WorkLimit,
          origin: @query.expression_origin(expression, node),
        }),
      )
    }
    let child = @query.expression_child(expression, node).unwrap()
    for (key, field) in grouped_keys {
      binding_work += @query.expression_node_count(key) +
        @query.expression_node_count(child)
      if binding_work > max_work {
        raise Abort(
          Expression({
            issue: @expression.WorkLimit,
            origin: @query.expression_origin(expression, node),
          }),
        )
      }
      let same_key = match
        (
          group_reference_path(key, @query.expression_root(key)),
          group_reference_path(child, @query.expression_root(child)),
        ) {
        (Some(left), Some(right)) => references(left, right)
        _ => same_expression(key, child, references~)
      }
      if same_key {
        let mut serial = bindings.length()
        let mut reference = "aql_pipe_group_bound_" + serial.to_string()
        while reserved_names.any(name => {
                ascii_upper(name) == ascii_upper(reference)
              }) ||
              bound_visible.any(entry => {
                ascii_upper(entry.0) == ascii_upper(reference)
              }) ||
              authored_paths.any(path => {
                ascii_upper(path[0].value) == ascii_upper(reference)
              }) {
          serial += 1
          reference = "aql_pipe_group_bound_" + serial.to_string()
        }
        bindings.push((node, { value: reference, quoted: false, }))
        bound_visible.push((reference, field))
        break
      }
    }
  }
  let expression = @query.expression_with_field_bindings(expression, bindings).unwrap()
  match
    @expression.append_with_properties(
      expression,
      path => {
        if path.length() == 1 {
          for (name, slot) in bound_visible {
            if same_name(path[0], { value: name, quoted: false, }) {
              return Some(slot)
            }
          }
        }
        resolve(path)
      },
      construction.builder,
      max_work,
      resolve_parameter=construction.parameter_resolver(),
    ) {
    Ok(node) => node
    Err(error) => raise Abort(Expression(error))
  }
}

///|
// Preserve property paths across parentheses. Looking only at Reference nodes
// would turn (payload).score into the whole payload column for prefix inference.
fn group_reference_path(
  expression : @query.Expression,
  node : Int,
) -> Array[@query.NamePart]? {
  let members : Array[@query.NamePart] = []
  let mut current = node
  while true {
    match @query.expression_node(expression, current).unwrap().kind {
      Parenthesized(child) => current = child
      Property(child, name) => {
        members.push(name)
        current = child
      }
      Reference(path) => {
        let result = path.copy()
        let mut index = members.length() - 1
        while index >= 0 {
          result.push(members[index])
          index -= 1
        }
        return Some(result)
      }
      _ => return None
    }
  }
  None
}
