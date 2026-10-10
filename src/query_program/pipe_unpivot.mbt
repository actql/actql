///|
// Reuse evaluated input fields. Generated columns use unique physical names
// to avoid overwriting kept columns with the same public name.
// Common UNPIVOT owns expansion, typing, key evidence and capacity validation.
fn lower_pipe_unpivot(
  construction : Construction,
  clause : @query.UnpivotClause,
  columns : Array[(String, String)],
) -> (
  Array[Array[(String, @builder.Node)]],
  Array[(String, String)],
  Array[String],
) raise Abort {
  if clause.columns.is_empty() {
    raise Abort(UnsupportedProjection)
  }
  if same_name(clause.value_column, clause.name_column) ||
    clause.columns.any(column => {
      same_name(column, clause.value_column) ||
      same_name(column, clause.name_column)
    }) {
    raise Abort(DuplicateOutput)
  }
  // Rebind only when a selected field has a private/renamed physical slot.
  // The ordinary projection copies evaluated values; it adds no label value
  // or expression evaluation to each expanded output row.
  let rebind = clause.columns.any(name => {
    columns.any(column => {
      same_name(name, { value: column.0, quoted: false, }) &&
      column.0 != column.1
    })
  })
  let mapped = if rebind {
    columns.map(column => (column.0, column.0))
  } else {
    columns
  }
  let physical = mapped.map(column => column.1)
  let selected : Array[(String, String)] = []
  for name in clause.columns {
    let matching = mapped.filter(column => {
      same_name(name, { value: column.0, quoted: false, })
    })
    if matching.is_empty() {
      raise Abort(UnknownColumn)
    }
    if matching.length() != 1 {
      raise Abort(AmbiguousColumn)
    }
    selected.push(matching[0])
  }
  let keep = mapped.filter(column => !selected.any(value => value.1 == column.1))
  let name_slot = pipe_physical_name(physical, "aql_unpivot_name_")
  physical.push(name_slot)
  let value_slot = pipe_physical_name(physical, "aql_unpivot_value_")
  physical.push(value_slot)
  let steps : Array[Array[(String, @builder.Node)]] = [
    [
      (
        "unpivot",
        construction.object([
          (
            "columns",
            construction.array(
              selected.map(column => construction.text(column.1)),
            ),
          ),
          (
            "keep",
            construction.array(keep.map(column => construction.text(column.1))),
          ),
          ("name_column", construction.text(name_slot)),
          ("value_column", construction.text(value_slot)),
        ]),
      ),
    ],
  ]
  if rebind {
    steps.insert(0, [
      (
        "select",
        construction.array(
          columns.map(column => {
            construction.object([(column.0, construction.text(column.1))])
          }),
        ),
      ),
    ])
  }
  if !clause.include_nulls {
    steps.push([
      (
        "filter",
        construction.object([
          (
            "not",
            construction.object([
              (
                "is_null",
                construction.object([("field", construction.text(value_slot))]),
              ),
            ]),
          ),
        ]),
      ),
    ])
  }
  let visible = keep +
    [
      (clause.value_column.value, value_slot),
      (clause.name_column.value, name_slot),
    ]
  (steps, visible, keep.map(column => column.1) + [name_slot, value_slot])
}
