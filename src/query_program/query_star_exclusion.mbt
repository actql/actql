///|
// Expand only the current visible columns. The checked projection retains the
// original physical slots; exclusions never restore an old range or input.
fn expanded_star_columns(
  projection : @query.Projection,
  visible : Array[(String, String)],
) -> Array[(String, String)] raise Abort {
  for excluded in projection.except_columns {
    if !visible.any(column => {
        same_name(excluded, { value: column.0, quoted: false, })
      }) {
      raise Abort(UnknownColumn)
    }
  }
  visible.filter(column => {
    !projection.except_columns.any(excluded => {
      same_name(excluded, { value: column.0, quoted: false, })
    })
  })
}
