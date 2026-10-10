///|
// All replacements see one input snapshot. Ordinary SELECT/GROUP/ORDER owns
// their evaluation and physical slots; this does not execute expression trees.
fn expanded_replacement_projections(
  query : @query.Query,
  projections : Array[@query.Projection],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  max_work : Int,
  object_columns? : ((@query.Expression) -> Array[String] raise Abort)? = None,
  authored_aliases? : Array[(String, String)] = [],
) -> Array[@query.Projection] raise Abort {
  let is_object_star = fn(projection : @query.Projection) -> Bool {
    guard projection.star == Some("*") &&
      projection.expression is Some(receiver) else {
      return false
    }
    guard @query.expression_node(receiver, @query.expression_root(receiver)).unwrap().kind
      is Reference(path) else {
      return true
    }
    if path.is_empty() {
      return false
    }
    if path.length() == 1 {
      return !ranges.any(range => same_name(range.0, path[0])) &&
        pipe_name_exists(visible, path[0])
    }
    true
  }
  if !projections.any(projection => {
      !projection.replacements.is_empty() || is_object_star(projection)
    }) {
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
  spend(authored_aliases.length())
  let authored_names : Map[String, String] = Map([])
  for mapping in authored_aliases {
    authored_names[mapping.0] = mapping.1
  }
  for projection in projections {
    spend(1)
    let object_star = is_object_star(projection)
    if projection.replacements.is_empty() && !object_star {
      values.push(projection)
      continue
    }
    guard projection.star == Some("*") else {
      raise Abort(UnsupportedProjection)
    }
    let columns = if object_star {
      guard object_columns is Some(resolve) else {
        raise Abort(UnsupportedProjection)
      }
      let fields = resolve(projection.expression.unwrap())
      spend(fields.length())
      // The contract owner supplies names/order. Exclusion and replacement use
      // the same SELECT snapshot and ordinary field-name rules as range stars.
      for excluded in projection.except_columns {
        spend(fields.length())
        if !fields.any(field => {
            same_name(excluded, { value: field, quoted: false, })
          }) {
          raise Abort(UnknownColumn)
        }
      }
      for _ in fields {
        spend(projection.except_columns.length())
      }
      fields
      .filter(field => {
        !projection.except_columns.any(excluded => {
          same_name(excluded, { value: field, quoted: false, })
        })
      })
      .map(field => (field, field))
    } else {
      expanded_star_columns(projection, visible, ranges~, authored_aliases~)
    }
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
          same_name(replacement.name, {
            value: if object_star {
              column.0
            } else {
              authored_names.get(column.0).unwrap_or(column.0)
            },
            quoted: false,
          })
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
      if object_star && projection.expression is Some(receiver) {
        spend(@query.expression_node_count(receiver) + 1)
      }
      values.push(@query.star_column_projection(query, projection, column.0))
    }
  }
  values
}
