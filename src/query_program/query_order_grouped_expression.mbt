///|
// ORDER may use a complete GROUP key inside a larger expression. Prove its
// original receiver meaning separately from ORDER's evaluated alias values.
fn append_order_grouped_expression(
  construction : Construction,
  expression : @query.Expression,
  grouped_keys : Array[(@query.Expression, String)],
  input_scope : JoinChainScope,
  projections : Array[@query.Projection],
  aggregate_slots : Array[(String, String)],
  resolve : (Array[@query.NamePart]) -> String?,
  active_fields : Array[String],
  selected : Array[(String, String)],
  materialized : Bool,
  distinct : Bool,
  max_work : Int,
) -> @builder.Node raise Abort {
  let resolve_input = fn(path : Array[@query.NamePart]) -> String? {
    pipe_slot(path, input_scope.visible, input_scope.ranges)
  }
  let resolve_order_input = fn(path : Array[@query.NamePart]) -> String? {
    if path.length() == 1 {
      // Parser-owned calls may share an implicit star input's spelling.
      // Their ORDER binding is an aggregate value, never input provenance.
      if aggregate_slots.any(pair => pair.0 == path[0].value) {
        return None
      }
      let matches = projections.filter(projection => {
        let name = match projection.name {
          Some(name) => Some(name.value)
          None =>
            match projection.expression {
              Some(value) =>
                match
                  @query.expression_node(value, @query.expression_root(value)).unwrap().kind {
                  Reference(source) => Some(source.last().unwrap().value)
                  Property(_, name) => Some(name.value)
                  _ => None
                }
              None => None
            }
        }
        // Use ORDER's exported-name rules for explicit and implicit aliases.
        name is Some(value) && same_name(path[0], { value, quoted: false, })
      })
      if order_output_slot(path, selected) is Some(_) && matches.is_empty() {
        return None
      }
      if !matches.is_empty() {
        guard matches.length() == 1 &&
          matches[0].aggregate is None &&
          matches[0].analytic is None &&
          matches[0].expression is Some(value) else {
          return None
        }
        let mut root = @query.expression_root(value)
        while @query.expression_node(value, root).unwrap().kind
              is Parenthesized(child) {
          root = child
        }
        return match @query.expression_node(value, root).unwrap().kind {
          Reference(source) => resolve_input(source)
          _ => None
        }
      }
    }
    resolve_input(path)
  }
  let available_keys = grouped_keys.filter_map(pair => {
    if !materialized && active_fields.contains(pair.1) {
      return Some(pair)
    }
    // Projection changes physical names, and may overwrite an input's name.
    // Only the recorded SELECT source slot proves that its key survives.
    for (name, source) in selected {
      if source == pair.1 && active_fields.contains(name) {
        return Some((pair.0, name))
      }
    }
    None
  })
  append_grouped_expression_resolved(
    construction,
    expression,
    available_keys,
    resolve_input,
    resolve_order_input,
    resolve,
    active_fields + selected.map(pair => pair.0),
    max_work,
  ) catch {
    Abort(issue) => {
      if distinct &&
        issue is Expression({ issue: @expression.UnknownReference, .. }) {
        raise Abort(InvalidQuery)
      }
      raise Abort(issue)
    }
  }
}
