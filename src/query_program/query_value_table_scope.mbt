///|
// Private parenthesized continuations already carry an AS-bound scope.
// Authored producers carry only their output kind and receive a fresh range.
fn script_input_scope(
  sources : ScriptSources,
  input : String,
  range : @query.NamePart,
) -> JoinChainScope? {
  match sources.value_tables.get(input) {
    Some(scope) => Some(bind_value_table_scope(scope, range))
    None => sources.ranges.get(input)
  }
}

///|
// A value table's row kind survives a producer boundary; its range name does
// not. Bind the retained value slot to the consumer's range, without exporting
// a CTE body's former receiver as an ordinary column or restoring its aliases.
fn bind_value_table_scope(
  scope : JoinChainScope,
  name : @query.NamePart,
) -> JoinChainScope {
  if !scope.value_table || scope.columns.length() != 1 {
    return scope
  }
  let slot = scope.columns[0].1
  let object_value = !scope.value_columns.is_empty()
  let visible = if object_value {
    scope.visible.copy()
  } else {
    [(name.value, slot)]
  }
  {
    visible,
    columns: [(name.value, slot)],
    value_table: true,
    value_columns: scope.value_columns.map(column => {
      (name.value, column.1, column.2)
    }),
    ranges: [(name, if object_value { visible.copy() } else { [] })],
    star_ranges: [(name, visible.copy())],
    receivers: if object_value {
      [(name, slot)]
    } else {
      []
    },
    scalar_ranges: if object_value {
      []
    } else {
      [(name, slot)]
    },
  }
}
