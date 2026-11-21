///|
// A single compiler-expanded star occurrence retains its actual input slot.
// This is private construction DATA, not an SQL alias or a checked permission.
priv struct ExpandedStarColumn {
  projection : @query.Projection
  column : (String, String)
}

///|
// Expand only the current visible columns. The checked projection retains the
// original physical slots; exclusions never restore an old range or input.
fn expanded_star_columns(
  projection : @query.Projection,
  visible : Array[(String, String)],
  ranges? : Array[(@query.NamePart, Array[(String, String)])] = [],
  authored_aliases? : Array[(String, String)] = [],
  column_profiles? : Array[ResultColumn]? = None,
  max_work? : Int = 2147483646,
  expansions? : Array[ExpandedStarColumn]? = None,
) -> Array[(String, String)] raise Abort {
  let columns = match projection.expression {
    None => visible
    Some(receiver) => {
      let root = @query.expression_node(
        receiver,
        @query.expression_root(receiver),
      ).unwrap()
      guard root.kind is Reference(path) && path.length() == 1 else {
        raise Abort(UnsupportedProjection)
      }
      let matches = ranges.filter(range => same_name(path[0], range.0))
      if matches.length() > 1 {
        raise Abort(AmbiguousRelation)
      }
      guard matches.length() == 1 else { raise Abort(UnknownColumn) }
      matches[0].1
    }
  }
  let mut remaining = max_work
  if expansions is Some(expanded) {
    if expanded.length() > remaining {
      raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
    }
    remaining -= expanded.length()
    for original in expanded {
      if physical_equal(original.projection, projection) {
        if columns.length() > remaining {
          raise Abort(
            Expression({ issue: @expression.WorkLimit, origin: None, }),
          )
        }
        // A later scope cannot use this occurrence to restore a removed slot.
        guard columns.any(column => column == original.column) else {
          raise Abort(UnknownColumn)
        }
        return [original.column]
      }
    }
  }
  // Charge each actual profile consultation before scanning it. Ordinary
  // short-circuit name checks do not spend for lookups they never enter.
  let matches = fn(
    column : (String, String),
    name : @query.NamePart,
  ) -> Bool raise Abort {
    if column_profiles is Some(profiles) {
      if profiles.length() > remaining {
        raise Abort(Expression({ issue: @expression.WorkLimit, origin: None, }))
      }
      remaining -= profiles.length()
    }
    star_column_matches_name(column, name, column_profiles, authored_aliases)
  }
  for excluded in projection.except_columns {
    if !columns.any(column => matches(column, excluded)) {
      raise Abort(UnknownColumn)
    }
  }
  columns.filter(column => {
    !projection.except_columns.any(excluded => matches(column, excluded))
  })
}

///|
// SQL names belong to this original occurrence/slot. None remains anonymous
// even if its private storage String equals an authored name in another row.
fn star_column_matches_name(
  column : (String, String),
  name : @query.NamePart,
  profiles : Array[ResultColumn]?,
  authored_aliases : Array[(String, String)],
) -> Bool {
  match result_column_profile(profiles, column.0, column.1) {
    Some({ name: None, .. }) => false
    Some({ name: Some(original), .. }) => same_name(name, original)
    None =>
      same_name(name, {
        value: positional_authored_column_name(column.0, authored_aliases),
        quoted: false,
      })
  }
}
