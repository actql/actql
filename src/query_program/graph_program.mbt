///|
fn graph_macro_value(
  path : Array[@query.NamePart],
  argument : Array[@query.NamePart],
  bindings : Array[GraphBinding],
) -> @expression.MacroValue? {
  if path.length() != 1 || path[0].quoted || argument.length() != 1 {
    return None
  }
  let name = ascii_upper(path[0].value)
  for binding in bindings {
    if !same_name(argument[0], binding.variable) {
      continue
    }
    let role = match (binding.kind, name) {
      (NodeIdentity(identity), "NODE_ID") =>
        return Some(@expression.Field(identity))
      (Edge, "EDGE_SOURCE") => "src"
      (Edge, "EDGE_TARGET") => "dst"
      (Edge, "EDGE_LABEL") =>
        match binding.label_field {
          Some(field) => field
          None => return None
        }
      (Path, "PATH_LENGTH") => {
        if binding.fields.contains("hop_count") {
          return Some(@expression.Field(binding.prefix + "hop_count"))
        }
        return Some(@expression.Integer(binding.hops))
      }
      _ => return None
    }
    if !binding.fields.contains(role) {
      return None
    }
    return Some(@expression.Field(binding.prefix + role))
  }
  None
}
