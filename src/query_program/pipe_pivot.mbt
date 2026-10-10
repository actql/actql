///|
// PIVOT groups by the current unaggregated columns. Its common operation owns
// type/NULL/aggregate/key evidence; the frontend retains the authored IN order
// and aliases independently of the common canonical physical column order.
fn compile_pipe_pivot(
  construction : Construction,
  clause : @query.PivotClause,
  visible : Array[(String, String)],
  columns : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
) -> (@builder.Node, Array[(String, String)]) raise Abort {
  guard pipe_slot(clause.argument, visible, ranges) is Some(value) &&
    pipe_slot(clause.column, visible, ranges) is Some(column) else {
    raise Abort(UnknownColumn)
  }
  let index = columns.filter(pair => pair.1 != value && pair.1 != column)
  let output = index.copy()
  for entry in clause.values {
    let suffix = entry.1.map(name => name.value).unwrap_or(entry.0)
    let name = clause.prefix
      .map(prefix => prefix.value + "_" + suffix)
      .unwrap_or(suffix)
    if output.any(pair => {
        same_name({ value: pair.0, quoted: false, }, {
          value: name,
          quoted: false,
        })
      }) {
      raise Abort(DuplicateOutput)
    }
    output.push((name, entry.0))
  }
  let pivot = construction.object([
    ("index", construction.array(index.map(pair => construction.text(pair.1)))),
    ("column", construction.text(column)),
    ("value", construction.text(value)),
    (
      "values",
      construction.array(clause.values.map(pair => construction.text(pair.0))),
    ),
    ("aggregate", construction.text(clause.function_name.to_lower())),
  ])
  (pivot, output)
}
