///|
// Parser-generated references cannot equal an authored name token. A star
// may still supply such a name from its checked schema. Keep the private
// reference separate in expression scope without removing the public column
// or changing qualified input-range lookup.
fn private_expression_columns(
  visible : Array[(String, String)],
  private_columns : Array[(String, String)],
) -> Array[(String, String)] {
  private_columns +
  visible.filter(entry => {
    !private_columns.any(binding => {
      same_name({ value: entry.0, quoted: false, }, {
        value: binding.0,
        quoted: false,
      })
    })
  })
}

///|
// A SELECT-owned window reference has a different meaning from a same-named
// GROUP input key. Retain that distinction during evaluated-key reuse as well
// as ordinary value lowering; both still use the shared expression owner.
fn append_private_grouped_expression(
  construction : Construction,
  expression : @query.Expression,
  grouped_keys : Array[(@query.Expression, String)],
  resolve_input : (Array[@query.NamePart]) -> String?,
  visible : Array[(String, String)],
  ranges : Array[(@query.NamePart, Array[(String, String)])],
  private_columns : Array[(String, String)],
  max_work : Int,
) -> @builder.Node raise Abort {
  let columns = private_expression_columns(visible, private_columns)
  append_grouped_expression_resolved(
    construction,
    expression,
    grouped_keys,
    resolve_input,
    path => {
      if path.length() == 1 &&
        pipe_slot(path, private_columns, []) is Some(slot) {
        Some(slot)
      } else {
        resolve_input(path)
      }
    },
    path => pipe_slot(path, columns, ranges),
    columns.map(entry => entry.0),
    max_work,
  )
}
