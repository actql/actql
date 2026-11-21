///|
// Range kind comes from the existing scope, not column spelling or values.
fn value_range_names(
  object_receivers : Array[(@query.NamePart, String)],
  scalar_receivers : Array[(@query.NamePart, String)],
) -> Array[@query.NamePart] {
  (object_receivers + scalar_receivers).map(receiver => receiver.0)
}

///|
fn ordinary_range_name(
  name : @query.NamePart,
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  value_ranges : Array[@query.NamePart],
) -> Bool {
  ranges.any(range => same_name(name, range.0)) &&
  !value_ranges.any(range => same_name(name, range))
}

///|
// A bare ordinary range is a row expression, not a single physical field.
// A value-table range continues to resolve its original whole-value slot.
// Column selectors (USING, ITEM KEY, etc.) retain the separate pipe_slot API.
fn pipe_expression_slot(
  path : Array[@query.NamePart],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  value_ranges? : Array[@query.NamePart] = [],
  column_profiles? : Array[ResultColumn]? = None,
) -> String? {
  if path.length() == 1 && ordinary_range_name(path[0], ranges, value_ranges) {
    return None
  }
  profiled_pipe_slot(path, visible, ranges, column_profiles)
}

///|
fn scope_expression_slot(
  path : Array[@query.NamePart],
  scope : JoinChainScope,
) -> String? {
  if path.length() == 1 &&
    ordinary_range_name(
      path[0],
      scope.ranges,
      value_range_names(scope.receivers, scope.scalar_ranges),
    ) {
    return None
  }
  profiled_pipe_slot(path, scope.visible, scope.ranges, scope.result_columns)
}

///|
// Resolve directly against the immutable occurrence/slot view. Do not copy all
// ranges/field tuples for every reference in an expression.
fn profiled_pipe_slot(
  path : Array[@query.NamePart],
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  profiles : Array[ResultColumn]?,
) -> String? {
  if profiles is None {
    return pipe_slot(path, visible, ranges)
  }
  if path.is_empty() || path.length() > 2 {
    return None
  }
  let mut fields = visible
  if path.length() == 2 {
    let mut found = false
    for range in ranges {
      if same_name(path[0], range.0) {
        if found {
          return None
        }
        fields = range.1
        found = true
      }
    }
    if !found {
      return None
    }
  }
  let mut selected : String? = None
  for field in fields {
    let name = match result_column_profile(profiles, field.0, field.1) {
      Some(column) => column.name
      None => Some({ value: field.0, quoted: false, })
    }
    if name is Some(name) && same_name(path.last().unwrap(), name) {
      if selected is Some(_) {
        return None
      }
      selected = Some(field.1)
    }
  }
  selected
}
