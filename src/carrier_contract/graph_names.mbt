///|
/// Source-role aliases, excluded from the structural Graph contract preimage.
struct GraphRowNames {
  node : @row.FieldName
  source : @row.FieldName
  target : @row.FieldName
  label : @row.FieldName?
}

///|
pub fn graph_row_names(
  node : @row.FieldName,
  source : @row.FieldName,
  target : @row.FieldName,
  label : @row.FieldName?,
  max_name_bytes~ : Int,
) -> Result[GraphRowNames, @row.Issue] {
  if max_name_bytes < 0 {
    return Err(@row.InvalidLimits)
  }
  let mut remaining = max_name_bytes
  let names = [node, source, target]
  if label is Some(name) {
    names.push(name)
  }
  let placeholder = @value.primitive(StringType, nullable=false)
  for name in names {
    match
      @row.from_fields(
        [(name, placeholder)],
        max_fields=1,
        max_name_bytes=remaining,
      ) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    remaining -= @scalar.admit_utf8_length(@row.reference_name(name), remaining).unwrap()
  }
  Ok({ node, source, target, label, })
}

///|
pub fn graph_row_fields(
  names : GraphRowNames,
) -> (@row.FieldName, @row.FieldName, @row.FieldName, @row.FieldName?) {
  (names.node, names.source, names.target, names.label)
}

///|
pub fn graph_names(graph : Graph) -> GraphRowNames? {
  graph.row_names
}

///|
/// Attaches validated source-role names without claiming data or label evidence.
pub fn with_graph_names(graph : Graph, names : GraphRowNames?) -> Carrier {
  GraphValue({ ..graph, row_names: names, })
}
