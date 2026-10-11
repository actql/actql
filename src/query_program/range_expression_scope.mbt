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
) -> String? {
  if path.length() == 1 && ordinary_range_name(path[0], ranges, value_ranges) {
    return None
  }
  pipe_slot(path, visible, ranges)
}

///|
fn scope_expression_slot(
  path : Array[@query.NamePart],
  scope : JoinChainScope,
) -> String? {
  pipe_expression_slot(
    path,
    scope.visible,
    scope.ranges,
    value_ranges=value_range_names(scope.receivers, scope.scalar_ranges),
  )
}
