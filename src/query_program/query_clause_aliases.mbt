///|
// SELECT aliases are materialized only when a later clause demands them. Their
// evaluated slots are shared with final SELECT; window inputs cannot consume
// aliases containing another window computation.
fn materialize_clause_aliases(
  projections : Array[@query.Projection],
  input_scope : JoinChainScope,
  references : Array[Array[@query.NamePart]],
  active_fields : Array[String],
  analytic_outputs : Array[(String, String)],
  analytic_expression_bindings : Array[(String, String)],
  cached_values : Array[(@query.Expression, String)],
  qualify_values : Array[(@query.Expression, String)],
  physical : Array[String],
  derives : Array[(String, @builder.Node)],
  output_name : (@query.Projection) -> String raise Abort,
  lower_expression : (@query.Expression) -> @builder.Node raise Abort,
  slot_prefix : String,
  reject_window_aliases : Bool,
) -> Array[(@query.NamePart, String)] raise Abort {
  let aliases : Array[(@query.NamePart, String)] = []
  for projection in projections {
    if projection.star is Some(_) {
      continue
    }
    let name = projection.name.unwrap_or({
      value: output_name(projection),
      quoted: false,
    })
    if aliases.any(binding => same_name(binding.0, name)) {
      raise Abort(DuplicateOutput)
    }
    if reject_window_aliases &&
      references.any(path => {
        !(path.length() > 1 &&
        pipe_slot(path[:2].to_owned(), input_scope.visible, input_scope.ranges)
        is Some(_)) &&
        same_name(path[0], name)
      }) &&
      (
        projection.analytic is Some(_) ||
        projection.expression
        .map(expression => {
          join_reference_paths(expression).any(path => {
            path.length() == 1 &&
            analytic_expression_bindings.any(binding => {
              path[0].value == binding.0
            })
          })
        })
        .unwrap_or(false)
      ) {
      raise Abort(UnsupportedAnalytic)
    }
    if projection.analytic is Some(_) {
      guard analytic_output_slot(name.value, analytic_outputs) is Some(slot) else {
        raise Abort(UnsupportedAnalytic)
      }
      aliases.push((name, slot))
      continue
    }
    if projection.aggregate is Some(_) {
      aliases.push((name, name.value))
      continue
    }
    let expression = projection.expression.unwrap()
    if !references.any(path => {
        // A qualified input receiver keeps its range meaning even
        // when followed by nested property access. The common lowerer
        // resolves that two-part prefix before a one-part alias.
        !(path.length() > 1 &&
        pipe_slot(path[:2].to_owned(), input_scope.visible, input_scope.ranges)
        is Some(_)) &&
        same_name(path[0], name)
      }) {
      continue
    }
    let cached = qualify_cached_slot(expression, cached_values + qualify_values)
    let direct = match
      @query.expression_node(expression, @query.expression_root(expression)).unwrap().kind {
      Reference(path) =>
        pipe_slot(path, input_scope.visible, input_scope.ranges)
      _ => None
    }
    let slot = match
      (match cached {
        Some(_) => cached
        None => direct
      }) {
      Some(slot) => slot
      None => {
        let slot = pipe_physical_name(physical, slot_prefix)
        physical.push(slot)
        derives.push((slot, lower_expression(expression)))
        qualify_values.push((expression, slot))
        active_fields.push(slot)
        slot
      }
    }
    aliases.push((name, slot))
  }
  aliases
}
