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
  let original = match prepare_binding_read(declarations, supplied, limits) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  finish_binding_read(original)
}
