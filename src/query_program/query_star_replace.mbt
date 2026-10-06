///|
// All replacements see one input snapshot. Ordinary SELECT/GROUP/ORDER owns
// their evaluation and physical slots; this does not execute expression trees.
fn expanded_replacement_projections(
  query : @query.Query,
  projections : Array[@query.Projection],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
) -> Array[@query.Projection] raise Abort {
  if !projections.any(projection => !projection.replacements.is_empty()) {
    return projections
  }
  let values : Array[@query.Projection] = []
  let mut remaining = max_work
  let spend = fn(count : Int) -> Unit raise Abort {
    if count < 0 || count > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= count
  }
  for projection in projections {
    spend(1)
    if projection.replacements.is_empty() {
      values.push(projection)
      continue
    }
    guard projection.star == Some("*") else {
      raise Abort(UnsupportedProjection)
    }
    let columns = expanded_star_columns(projection, visible, ranges~)
    spend(columns.length())
    for index in 0..<projection.replacements.length() {
      let replacement = projection.replacements[index]
      spend(index + columns.length())
      for other in 0..<index {
        if same_name(replacement.name, projection.replacements[other].name) {
          raise Abort(DuplicateOutput)
        }
      }
      let count = columns
        .filter(column => {
          same_name(replacement.name, { value: column.0, quoted: false, })
        })
        .length()
      if count == 0 {
        raise Abort(UnknownColumn)
      }
      if count > 1 {
        raise Abort(AmbiguousColumn)
      }
    }
    for column in columns {
      values.push(@query.star_column_projection(query, projection, column.0))
    }
  }
  values
}
