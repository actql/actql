///|
// Private parenthesized continuations already carry an AS-bound scope.
// Authored producers carry only their output kind and receive a fresh range.
fn script_input_scope(
  construction : Construction,
  sources : ScriptSources,
  input : Input,
  range : @query.NamePart,
) -> JoinChainScope? raise Abort {
  if script_result_columns(sources, input.name) is Some(original_columns) &&
    original_columns.any(column => column.name is None || column.name_view is Some(_)) {
    // The original Input has already excluded private exact-integer companions.
    // Namespace metadata must not restore those storage slots as user fields.
    let columns = input.visible_fields.map(field => {
      result_column_profile(Some(original_columns), field, field).unwrap_or({
        label: field, slot: field, name: Some({ value: field, quoted: false, }), name_view: None,
      })
    })
    let physical = columns.map(column => (column.slot, column.slot))
    let named : Array[(String, String)] = []
    for column in columns {
      if column.name is Some(name) {
        named.push((name.value, column.slot))
      }
    }
    return Some({
      // Star and column ordinals retain every value. Expressions resolve only
      // original public names; compile_steps also fences private slot paths.
      visible: physical,
      columns: physical.copy(),
      value_table: false,
      value_columns: [],
      ranges: [(range, physical.copy())],
      star_ranges: [(range, physical.copy())],
      receivers: [],
      result_columns: Some(columns),
      scalar_ranges: [],
      key_labels: seed_infer_key_labels(construction, [], named),
    })
  }
  match sources.value_tables.get(input.name) {
    Some(scope) => Some(bind_value_table_scope(construction, scope, range))
    None => sources.ranges.get(input.name)
  }
}

///|
// A value table's row kind survives a producer boundary; its range name does
// not. Bind the retained value slot to the consumer's range, without exporting
// a CTE body's former receiver as an ordinary column or restoring its aliases.
fn bind_value_table_scope(
  construction : Construction,
  scope : JoinChainScope,
  name : @query.NamePart,
) -> JoinChainScope raise Abort {
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
    key_labels: if object_value {
      seed_infer_key_labels(construction, scope.key_labels, [])
    } else {
      rename_infer_key_label(construction, scope.key_labels, slot, name.value)
    },
    result_columns: None,
    scalar_ranges: if object_value {
      []
    } else {
      [(name, slot)]
    },
  }
}

///|
// Select the existing producer-binding route for CTEs containing UNNEST.
// This only dispatches lowering; compile_steps determines the actual output
// kind after SELECT, OFFSET and subsequent operations, without guessing types.
fn has_cte_unnest_input(query : @query.Query) -> Bool {
  let pending = [(query, false)]
  while pending.pop() is Some((current, inside_cte)) {
    if inside_cte {
      for index in 0..<@query.operation_count(current) {
        if @query.operation_at(current, index) is Some(UnnestSource(_, _, _)) {
          return true
        }
      }
    }
    for index in 0..<@query.query_binding_count(current) {
      pending.push(
        (@query.query_binding_at(current, index).unwrap().query, true),
      )
    }
    for index in 0..<@query.set_part_count(current) {
      pending.push(
        (@query.set_part_at(current, index).unwrap().right, inside_cte),
      )
    }
  }
  false
}
