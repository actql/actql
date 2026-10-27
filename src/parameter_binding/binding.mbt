///|
/// Admit the optional Program params map. Present maps must be nonempty.
pub fn read_declarations(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> Result[Declarations, Issue] {
  observe_declarations(root, limits).0
}

///|
/// One original declaration preflight, followed by the same typed reader.
/// The split holder retains only immutable input/limits, original source usage
/// and at most one completed semantic outcome; it carries no resource grant.
pub fn observe_declarations(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
) -> (Result[Declarations, Issue], Int, Int) {
  // Ordinary synchronous callers drive the same reader to completion.
  let (preflight, nodes, text) = preflight_declaration_read(root, limits)
  let result = match preflight {
    Err(issue) => Err(issue)
    Ok(_) => finish_declaration_read_owned(root, limits, (nodes, text))
  }
  (result, nodes, text)
}

///|
fn finish_declaration_read_owned(
  root : @decode.Cursor?,
  limits : DeclarationLimits,
  usage : (Int, Int),
) -> Result[Declarations, Issue] {
  // Ordinary and funded consumers drive the SAME original semantic reader.
  // This local holder does not escape a synchronous ordinary read.
  finish_declaration_read({ root, limits, usage, state: AwaitingHeader, })
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
  // This is the selected input domain, not a guess from equal path labels.
  // Outer-map validation belongs to supplied data; defaults are charged and
  // may fail their current binding budget without being supplied values.
  let mut origin = Supplied
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
    let missing : Array[Declaration] = []
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
        None => missing.push(declaration)
        Some(cursor) => {
          origin = if provided is Some(_) { Supplied } else { Default }
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
    let usage = (
      limits.max_nodes - budget.nodes,
      limits.max_text_bytes - budget.text,
    )
    if missing.is_empty() {
      Ok(Ready({ declarations, entries, usage, }))
    } else {
      Ok(NeedsBindings({ declarations, entries: missing, usage, }))
    }
  } catch {
    Abort(issue) => Err(BindingInput(origin, issue))
  }
}
