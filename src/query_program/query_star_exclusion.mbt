///|
// Expand only the current visible columns. The checked projection retains the
// original physical slots; exclusions never restore an old range or input.
fn expanded_star_columns(
  projection : @query.Projection,
  visible : Array[(String, String)],
  ranges? : Array[(@query.NamePart, Array[(String, String)])] = [],
  authored_aliases? : Array[(String, String)] = [],
) -> Array[(String, String)] raise Abort {
  let columns = match projection.expression {
    None => visible
    Some(receiver) => {
      let root = @query.expression_node(
        receiver,
        @query.expression_root(receiver),
      ).unwrap()
      guard root.kind is Reference(path) && path.length() == 1 else {
        raise Abort(UnsupportedProjection)
      }
      let matches = ranges.filter(range => same_name(path[0], range.0))
      if matches.length() > 1 {
        raise Abort(AmbiguousRelation)
      }
      guard matches.length() == 1 else { raise Abort(UnknownColumn) }
      matches[0].1
    }
  }
  // Positional operands may store duplicate named columns under separate
  // private slots. Exclusion uses their authored names and retains the slots.
  let authored_name = (name : String) => {
    let mut authored = name
    for mapping in authored_aliases {
      if mapping.0 == name {
        authored = mapping.1
        break
      }
    }
    authored
  }
  for excluded in projection.except_columns {
    if !columns.any(column => {
        same_name(excluded, { value: authored_name(column.0), quoted: false, })
      }) {
      raise Abort(UnknownColumn)
    }
  }
  columns.filter(column => {
    !projection.except_columns.any(excluded => {
      same_name(excluded, { value: authored_name(column.0), quoted: false, })
    })
  })
}
