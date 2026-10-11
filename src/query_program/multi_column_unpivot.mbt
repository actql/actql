///|
// Connect positional tuples through ordinary closed objects and UNPIVOT.
// Each positional tuple becomes one ordinary non-NULL closed object. The
// common checker owns the recursive value contracts and expansion evidence.
fn lower_multi_column_unpivot(
  construction : Construction,
  clause : @query.UnpivotClause,
  columns : Array[(String, String)],
) -> (
  Array[Array[(String, @builder.Node)]],
  Array[(String, String)],
  Array[String],
) raise Abort {
  let outputs = clause.value_columns
  if outputs.length() < 2 ||
    clause.column_sets.is_empty() ||
    clause.column_sets.length() != clause.row_labels.length() ||
    clause.column_sets.any(names => names.length() != outputs.length()) {
    raise Abort(InvalidContext)
  }
  for index in 0..<outputs.length() {
    if same_name(outputs[index], clause.name_column) {
      raise Abort(DuplicateOutput)
    }
    for prior in 0..<index {
      if same_name(outputs[prior], outputs[index]) {
        raise Abort(DuplicateOutput)
      }
    }
  }
  let selected : Array[Array[(String, String)]] = []
  for names in clause.column_sets {
    let resolved : Array[(String, String)] = []
    for name in names {
      // Preserve the current single-value output/input collision rule.
      if same_name(name, clause.name_column) ||
        outputs.any(output => same_name(name, output)) {
        raise Abort(DuplicateOutput)
      }
      let matches = columns.filter(column => {
        same_name(name, { value: column.0, quoted: false, })
      })
      if matches.is_empty() {
        raise Abort(UnknownColumn)
      }
      if matches.length() != 1 {
        raise Abort(AmbiguousColumn)
      }
      resolved.push(matches[0])
    }
    selected.push(resolved)
  }
  let keep = columns.filter(column => {
    !selected.any(set => set.any(input => input.1 == column.1))
  })
  let physical = columns.map(column => column.1)
  for column in columns {
    if !physical.contains(column.0) {
      physical.push(column.0)
    }
  }
  // User-authored destinations must not collide with compiler storage.
  for name in outputs + [clause.name_column] {
    if !physical.contains(name.value) {
      physical.push(name.value)
    }
  }
  let roles = outputs.mapi((index, _) => "v" + index.to_string())
  let occurrences : Array[String] = []
  let bundles : Array[(String, @builder.Node)] = []
  let labels : Array[String] = []
  for index in 0..<selected.length() {
    let slot = pipe_physical_name(physical, "aql_unpivot_input_")
    physical.push(slot)
    occurrences.push(slot)
    let members = selected[index].mapi((position, column) => {
      (
        roles[position],
        construction.object([("field", construction.text(column.1))]),
      )
    })
    bundles.push(
      (slot, construction.object([("object", construction.object(members))])),
    )
    labels.push(
      match clause.row_labels[index] {
        Some(@query.TextLabel(value)) => value
        None => selected[index].map(column => column.0).join("_")
        _ => raise Abort(UnsupportedProjection)
      },
    )
  }
  let name_slot = pipe_physical_name(physical, "aql_unpivot_name_")
  physical.push(name_slot)
  let bundle_slot = pipe_physical_name(physical, "aql_unpivot_value_")
  physical.push(bundle_slot)
  let label_slot = pipe_physical_name(physical, "aql_unpivot_label_")
  physical.push(label_slot)
  let value_slots : Array[String] = []
  let projection : Array[(String, @builder.Node)] = []
  for position in 0..<outputs.length() {
    let slot = pipe_physical_name(physical, "aql_unpivot_output_")
    physical.push(slot)
    value_slots.push(slot)
    projection.push(
      (
        slot,
        construction.object([
          (
            "property",
            construction.object([
              (
                "value",
                construction.object([("field", construction.text(bundle_slot))]),
              ),
              ("name", construction.text(roles[position])),
            ]),
          ),
        ]),
      ),
    )
  }
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
  projection.push((label_slot, label))
  let steps : Array[Array[(String, @builder.Node)]] = [
    [("derive", construction.object(bundles))],
    [
      (
        "select",
        construction.array(
          (keep.map(column => column.1) + occurrences).map(name => {
            construction.text(name)
          }),
        ),
      ),
    ],
    [
      (
        "unpivot",
        construction.object([
          (
            "columns",
            construction.array(occurrences.map(name => construction.text(name))),
          ),
          (
            "keep",
            construction.array(keep.map(column => construction.text(column.1))),
          ),
          ("name_column", construction.text(name_slot)),
          ("value_column", construction.text(bundle_slot)),
        ]),
      ),
    ],
    [("derive", construction.object(projection))],
  ]
  if !clause.include_nulls {
    // The bundle itself is non-NULL. Exclude only all-NULL component tuples.
    steps.push([
      (
        "filter",
        construction.object([
          (
            "or",
            construction.array(
              value_slots.map(slot => {
                construction.object([
                  (
                    "not",
                    construction.object([
                      (
                        "is_null",
                        construction.object([("field", construction.text(slot))]),
                      ),
                    ]),
                  ),
                ])
              }),
            ),
          ),
        ]),
      ),
    ])
  }
  (
    steps,
    keep +
    outputs.mapi((position, name) => (name.value, value_slots[position])) +
    [(clause.name_column.value, label_slot)],
    keep.map(column => column.1) +
    [name_slot, bundle_slot, label_slot] +
    value_slots,
  )
}
