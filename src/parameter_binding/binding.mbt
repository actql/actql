///|
/// Admit the optional Program params map. Present maps must be nonempty.
pub fn read_declarations(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> Result[Declarations, Issue] {
  if limits.max_parameters < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  try {
    let entries : Array[Declaration] = []
    if root is Some(root) {
      preflight(root, {
        nodes: limits.max_nodes,
        text: limits.max_text_bytes,
        depth: limits.max_depth,
      })
      let object = decoded(@decode.open_object(root))
      let names = decoded(@decode.object_field_names(root))
      if names.is_empty() {
        invalid(root, EmptyDeclarations)
      }
      if names.length() > limits.max_parameters {
        invalid(root, ParameterLimit)
      }
      names.sort_by(@canonical.compare_utf16)
      for name in names {
        if !valid_name(name) {
          match @decode.closed_object(root, names.filter(n => n != name)) {
            Err(location) =>
              raise Abort(
                ParameterIssue(
                  InvalidName,
                  path=location.path,
                  span=location.span,
                ),
              )
            Ok(_) => invalid(root, InvalidName)
          }
        }
        let cursor = decoded(@decode.required(object, name))
        let syntax = match
          @contract.read_parameter_syntax(cursor, {
            max_nodes: limits.max_nodes,
            max_depth: limits.max_depth,
            max_text_bytes: limits.max_text_bytes,
          }) {
          Ok(value) => value
          Err(issue) => raise Abort(Contract(issue))
        }
        if syntax.metadata is Some(meta) {
          metadata(meta)
        }
        let default_value = match syntax.default_value {
          None => None
          Some(cursor) =>
            Some(
              check_value(cursor, syntax.parameter_type, {
                max_nodes: limits.max_nodes,
                max_depth: limits.max_depth,
                max_text_bytes: limits.max_text_bytes,
              }),
            )
        }
        entries.push({
          name,
          source: cursor,
          parameter_type: syntax.parameter_type,
          metadata: syntax.metadata,
          default_cursor: syntax.default_value,
          default_value,
        })
      }
    }
    Ok({ entries, })
  } catch {
    Abort(issue) => Err(issue)
  }
}

///|
/// Resolve one immutable set; missing values never mask invalid supplied values.
/// Values carry no typed CID, usage proof, Plan or Run authorization.
pub fn bind(
  declarations : Declarations,
  supplied : @decode.Cursor?,
  limits : @value.Limits,
) -> Result[BindingResult, Issue] {
  if limits.max_nodes < 0 || limits.max_depth < 0 || limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  try {
    let names = declarations.entries.map(e => e.name)
    let object = match supplied {
      None => None
      Some(cursor) => Some(decoded(@decode.closed_object(cursor, names)))
    }
    let budget : Budget = {
      nodes: limits.max_nodes,
      text: limits.max_text_bytes,
      depth: limits.max_depth,
    }
    let entries : Array[BoundParameter] = []
    let missing : Array[String] = []
    for declaration in declarations.entries {
      let provided = match object {
        None => None
        Some(o) => @decode.lookup(o, declaration.name)
      }
      let selected = match provided {
        Some(c) => Some(c)
        None => declaration.default_cursor
      }
      match selected {
        None => missing.push(declaration.name)
        Some(cursor) => {
          charge_text(declaration.name, cursor, budget)
          preflight(cursor, budget)
          let (value, origin) = if provided is Some(_) {
            (check_value(cursor, declaration.parameter_type, limits), Supplied)
          } else {
            (declaration.default_value.unwrap(), Default)
          }
          entries.push({
            name: declaration.name,
            value,
            origin,
            parameter_type: declaration.parameter_type,
          })
        }
      }
    }
    if missing.is_empty() {
      Ok(Ready({ declarations, entries, }))
    } else {
      Ok(NeedsBindings({ names: missing, }))
    }
  } catch {
    Abort(issue) => Err(issue)
  }
}
