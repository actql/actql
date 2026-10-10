///|
// Input field copies preserve evaluated values. Their unique physical names
// prevent generated columns from overwriting kept columns with the same name.
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
  let physical : Array[String] = []
  let projected : Array[@builder.Node] = []
  let mapped : Array[(String, String)] = []
  for column in columns {
    let slot = pipe_physical_name(physical, "aql_unpivot_input_")
    physical.push(slot)
    mapped.push((column.0, slot))
    projected.push(construction.object([(slot, construction.text(column.1))]))
  }
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
  let label_slot = pipe_physical_name(physical, "aql_unpivot_label_")
  physical.push(label_slot)
  let steps : Array[Array[(String, @builder.Node)]] = [
    [("select", construction.array(projected))],
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
  // Names returned by common UNPIVOT denote physical source fields. Translate
  // only those labels; do not expose or normalize their internal slot names.
  let mut label = construction.object([
    ("literal", construction.text(selected[selected.length() - 1].0)),
  ])
  for index = selected.length() - 2; index >= 0; index = index - 1 {
    let column = selected[index]
    label = construction.object([
      (
        "if",
        construction.array([
          construction.object([
            (
              "eq",
              construction.array([
                construction.object([("field", construction.text(name_slot))]),
                construction.object([("literal", construction.text(column.1))]),
              ]),
            ),
          ]),
          construction.object([("literal", construction.text(column.0))]),
          label,
        ]),
      ),
    ])
  }
  steps.push([("derive", construction.object([(label_slot, label)]))])
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
      (clause.name_column.value, label_slot),
    ]
  (
    steps,
    visible,
    keep.map(column => column.1) + [name_slot, value_slot, label_slot],
  )
}
