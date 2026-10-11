///|
// Each authored occurrence has a separate private column. This preserves two
// different labels for repeated references to the same evaluated input slot.
// Common projection, expansion and expressions retain ownership of all values.
fn lower_unpivot_row_labels(
  construction : Construction,
  clause : @query.UnpivotClause,
  columns : Array[(String, String)],
  selected : Array[(String, String)],
  keep : Array[(String, String)],
) -> (
  Array[Array[(String, @builder.Node)]],
  Array[(String, String)],
  Array[String],
) raise Abort {
  let physical = columns.map(column => column.1)
  for column in columns {
    if !physical.contains(column.0) {
      physical.push(column.0)
    }
  }
  let occurrences : Array[String] = []
  let projection = keep.map(column => construction.text(column.1))
  for column in selected {
    let slot = pipe_physical_name(physical, "aql_unpivot_input_")
    physical.push(slot)
    occurrences.push(slot)
    projection.push(construction.object([(slot, construction.text(column.1))]))
  }
  let name_slot = pipe_physical_name(physical, "aql_unpivot_name_")
  physical.push(name_slot)
  let value_slot = pipe_physical_name(physical, "aql_unpivot_value_")
  physical.push(value_slot)
  let label_slot = pipe_physical_name(physical, "aql_unpivot_label_")
  let labels = selected.mapi((index, column) => {
    match clause.row_labels[index] {
      Some(@query.TextLabel(value)) => value
      None => column.0
      _ => raise Abort(UnsupportedProjection)
    }
  })
  let mut label = construction.object([
    ("literal", construction.text(labels[labels.length() - 1])),
  ])
  for index = labels.length() - 2; index >= 0; index = index - 1 {
    label = construction.object([
      (
        "if",
        construction.array([
          construction.object([
            (
              "eq",
              construction.array([
                construction.object([("field", construction.text(name_slot))]),
                construction.object([
                  ("literal", construction.text(occurrences[index])),
                ]),
              ]),
            ),
          ]),
          construction.object([("literal", construction.text(labels[index]))]),
          label,
        ]),
      ),
    ])
  }
  let steps : Array[Array[(String, @builder.Node)]] = [
    [("select", construction.array(projection))],
    [
      (
        "unpivot",
        construction.object([
          (
            "columns",
            construction.array(occurrences.map(slot => construction.text(slot))),
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
    [("derive", construction.object([(label_slot, label)]))],
  ]
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
  (
    steps,
    keep +
    [
      (clause.value_columns[0].value, value_slot),
      (clause.name_column.value, label_slot),
    ],
    keep.map(column => column.1) + [name_slot, value_slot, label_slot],
  )
}
