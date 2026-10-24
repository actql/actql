///|
// GROUP BY ALL selects expressions, not output names. Infer against the same
// pre-group input snapshot used by SELECT; the common group checker retains
// responsibility for admissible key types and evaluation.
fn inferred_group_keys(
  query : @query.Query,
  projections : Array[@query.Projection],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  resolve : (Array[@query.NamePart]) -> String?,
  max_work : Int,
) -> Array[@query.Expression] raise Abort {
  let mut remaining = max_work
  let spend = fn(count : Int) -> Unit raise Abort {
    if count < 0 || count > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= count
  }
  let selected = selected_projections(query)
  let internal : Array[@query.NamePart] = []
  // Embedded aggregate/window atoms are parser-owned references. Authored
  // aggregate aliases never hide an input column with the same spelling.
  for projection in projections {
    spend(selected.length() + 1)
    if projection.aggregate is Some(_) &&
      projection.name is Some(name) &&
      !selected.any(item => item.aggregate is Some(_) && item.name == Some(name)) {
      internal.push(name)
    }
  }
  for index in 0..<@query.operation_count(query) {
    spend(1)
    if @query.operation_at(query, index) is Some(AnalyticExpressions(_, names)) {
      spend(names.length())
      internal.append(names)
    }
  }
  let expressions : Array[@query.Expression] = []
  let paths : Array[Array[(String, Array[@query.NamePart])]] = []
  let simple : Array[(Int, (String, Array[@query.NamePart]))] = []
  for projection in projections {
    spend(1)
    let expanded = if projection.star == Some("*") {
      let columns = expanded_star_columns(projection, visible, ranges~)
      spend(columns.length())
      columns.map(column => {
        @query.star_column_projection(query, projection, column.0)
      })
    } else {
      [projection]
    }
    for item in expanded {
      spend(1)
      if item.aggregate is Some(_) || item.analytic is Some(_) {
        continue
      }
      guard item.expression is Some(expression) else {
        raise Abort(UnsupportedGrouping)
      }
      spend(@query.expression_node_count(expression))
      let authored_paths = join_reference_paths(expression)
      for _ in authored_paths {
        spend(internal.length())
      }
      let root = @query.expression_node(
        expression,
        @query.expression_root(expression),
      ).unwrap()
      // Star expansion creates a checked input-column reference with an empty
      // source span. It is not an embedded window/aggregate atom even when
      // its schema name equals a parser-generated private reference.
      let schema_column = root.kind is Reference(_) &&
        root.start == 0 &&
        root.end == 0
      if !schema_column &&
        authored_paths.any(path => {
          path.length() == 1 && internal.any(name => same_name(path[0], name))
        }) {
        continue
      }
      let normalized : Array[(String, Array[@query.NamePart])] = []
      let normalize = fn(
        path : Array[@query.NamePart],
        members : Array[@query.NamePart],
        node : Int,
      ) -> Unit raise Abort {
        let mut length = path.length()
        while length > 0 {
          spend(length)
          if resolve(path[:length].to_owned()) is Some(slot) {
            normalized.push((slot, path[length:].to_owned() + members))
            return
          }
          length -= 1
        }
        raise Abort(
          Expression({
            issue: @expression.UnknownReference,
            origin: @query.expression_origin(expression, node),
          }),
        )
      }
      let pending = [@query.expression_root(expression)]
      while pending.pop() is Some(node) {
        spend(@query.expression_node_count(expression))
        if group_reference_parts(expression, node) is Some((path, members)) {
          normalize(path, members, node)
          continue
        }
        match @query.expression_node(expression, node).unwrap().kind {
          Parenthesized(child)
          | Unary(_, child)
          | Cast(child, _)
          | Property(child, _) => pending.push(child)
          Binary(_, left, right) | ArrayOffset(left, right, _) => {
            pending.push(right)
            pending.push(left)
          }
          StructConstructor(fields) =>
            for (_, child) in fields {
              pending.push(child)
            }
          Call(_, args) | Predicate(_, args) | ArrayConstructor(args, _) =>
            pending.append(args)
          SearchedCase(branches, otherwise) => {
            pending.push(otherwise)
            for (condition, value) in branches {
              pending.push(value)
              pending.push(condition)
            }
          }
          _ => ()
        }
      }
      let position = expressions.length()
      expressions.push(expression)
      paths.push(normalized)
      if group_reference_parts(expression, @query.expression_root(expression))
        is Some(_) {
        simple.push((position, normalized[0]))
      }
    }
  }
  // Shortest paths win even when a shorter SELECT item occurs later.
  // Computed keys do not add prefixes for other computed SELECT expressions.
  simple.sort_by((a, b) => {
    let length = a.1.1.length().compare(b.1.1.length())
    if length == 0 {
      a.0.compare(b.0)
    } else {
      length
    }
  })
  let prefixes : Array[(String, Array[@query.NamePart])] = []
  let chosen : Array[Int] = []
  let covered = fn(
    path : (String, Array[@query.NamePart]),
  ) -> Bool raise Abort {
    for prefix in prefixes {
      spend(prefix.1.length() + 1)
      if path.0 == prefix.0 && path.1.length() >= prefix.1.length() {
        let mut matches = true
        for index in 0..<prefix.1.length() {
          if !same_name(prefix.1[index], path.1[index]) {
            matches = false
            break
          }
        }
        if matches {
          return true
        }
      }
    }
    false
  }
  for (position, path) in simple {
    if !covered(path) {
      prefixes.push(path)
      chosen.push(position)
    }
  }
  for position in 0..<expressions.length() {
    spend(simple.length() + 1)
    if simple.any(item => item.0 == position) {
      continue
    }
    for path in paths[position] {
      if !covered(path) {
        chosen.push(position)
        break
      }
    }
  }
  chosen.sort()
  chosen.map(index => expressions[index])
}
