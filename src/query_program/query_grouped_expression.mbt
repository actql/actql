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
  if grouped_keys.is_empty() {
    return append_pipe_expression(
      construction, expression, visible, ranges, max_work,
    )
  }
  let bindings : Array[(Int, @query.NamePart)] = []
  let bound_visible = visible.copy()
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
      if same_expression(key, child, references=(left, right) => {
          same_group_reference(left, right, resolve_input)
        }) {
        let mut serial = bindings.length()
        let mut reference = "aql_pipe_group_bound_" +
          serial.to_string()
        while bound_visible.any(entry => {
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
  let expression = @query.expression_with_field_bindings(
    expression, bindings,
  ).unwrap()
  append_pipe_expression(
    construction, expression, bound_visible, ranges, max_work,
  )
}
