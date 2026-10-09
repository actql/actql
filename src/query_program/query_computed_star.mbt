///|
// A computed receiver is evaluated in one ordinary derive before its fields.
// Bind only fields expanded from this SELECT's authored receiver stars; this
// does not grant a source name, presence proof or access to a removed column.
fn materialize_computed_star_receivers(
  original : Array[@query.Projection],
  expanded : Array[@query.Projection],
  physical : Array[String],
  lower : (@query.Expression) -> @builder.Node raise Abort,
  already_evaluated : (@query.Expression) -> Bool,
  max_work : Int,
) -> (
  Array[@query.Projection],
  Array[(String, String)],
  Array[(String, @builder.Node)],
) raise Abort {
  if !original.any(projection => {
      projection.star == Some("*") &&
      projection.expression is Some(receiver) &&
      !(@query.expression_node(receiver, @query.expression_root(receiver)).unwrap().kind
      is Reference(_))
    }) {
    return (expanded, [], [])
  }
  let receivers : Array[@query.Expression] = []
  let reserved = physical.copy()
  let mut remaining = max_work
  let spend = fn(count : Int) -> Unit raise Abort {
    if count < 0 || count > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= count
  }
  for projection in original {
    spend(1)
    if projection.star == Some("*") &&
      projection.expression is Some(receiver) &&
      !(@query.expression_node(receiver, @query.expression_root(receiver)).unwrap().kind
      is Reference(_)) {
      receivers.push(receiver)
    }
  }
  if receivers.is_empty() {
    return (expanded, [], [])
  }
  // Private names must also avoid authored references and output aliases,
  // including a user spelling that happens to match the generated prefix.
  for projection in expanded {
    spend(1)
    if projection.name is Some(name) {
      reserved.push(name.value)
    }
    if projection.expression is Some(expression) {
      spend(@query.expression_node_count(expression))
      for index in 0..<@query.expression_node_count(expression) {
        if @query.expression_node(expression, index).unwrap().kind
          is Reference(path) {
          spend(path.length())
          for name in path {
            reserved.push(name.value)
          }
        }
      }
    }
  }
  let values = expanded.copy()
  let bindings : Array[(String, String)] = []
  let derives : Array[(String, @builder.Node)] = []
  for receiver in receivers {
    let matches : Array[(Int, Int)] = []
    for index in 0..<values.length() {
      spend(1)
      if values[index].expression is Some(expression) &&
        !already_evaluated(expression) &&
        @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind
        is Property(child, _) {
        spend(
          @query.expression_node_count(expression) +
          @query.expression_node_count(receiver),
        )
        let subtree = @query.expression_child(expression, child).unwrap()
        if same_expression(subtree, receiver) {
          matches.push((index, child))
        }
      }
    }
    if matches.is_empty() {
      continue
    }
    let mut serial = bindings.length()
    let mut name = "aql_computed_star_" + serial.to_string()
    spend(reserved.length())
    while reserved.any(value => ascii_upper(value) == ascii_upper(name)) {
      spend(reserved.length())
      serial += 1
      name = "aql_computed_star_" + serial.to_string()
    }
    reserved.push(name)
    bindings.push((name, name))
    derives.push((name, lower(receiver)))
    for (index, child) in matches {
      let expression = values[index].expression.unwrap()
      spend(@query.expression_node_count(expression))
      let bound = @query.expression_with_field_bindings(expression, [
        (child, { value: name, quoted: true, }),
      ]).unwrap()
      values[index] = { ..values[index], expression: Some(bound), }
    }
  }
  (values, bindings, derives)
}
