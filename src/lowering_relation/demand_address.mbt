///|
/// A source-addressed test in one expression root's evaluation frame.
pub struct SourceDemandTest {
  pointer : String
  predicate : @typing.DemandTestKind
}

///|
pub(all) enum DemandAddressIssue {
  InvalidAddressLimits
  InvalidRoot
  InvalidNode
  AddressLimit
  MissingConditionSource
}

///|
/// Bind a shared semantic-source occurrence to its exact fragment root slot.
/// No wire-node path or author spelling is substituted for normalized source.
pub fn demand_source_pointer(
  index : DemandIndex,
  root : Int,
  node : Int,
  max_bytes~ : Int,
) -> Result[String?, DemandAddressIssue] {
  if max_bytes < 0 {
    return Err(InvalidAddressLimits)
  }
  let paths = match index.paths.get(root) {
    Some(paths) => paths
    None => return Err(InvalidRoot)
  }
  match @typing.node_form(@typing.demand_expression(paths), node) {
    None => return Err(InvalidNode)
    Some(ImplicitNull) => return Ok(None)
    Some(Expression(_, _) | MembershipList(_)) => ()
  }
  // An Int root index has a bounded decimal representation. Check the full
  // prefix before allowing the shared accessor to allocate the suffix.
  let prefix = "/roots/" + root.to_string() + "/source"
  if prefix.length() > max_bytes {
    return Err(AddressLimit)
  }
  match
    @typing.demand_pointer(paths, node, max_bytes=max_bytes - prefix.length()) {
    Ok(Some(suffix)) => Ok(Some(prefix + suffix))
    Ok(None) => Ok(None)
    Err(InvalidLimits) => Err(InvalidAddressLimits)
    Err(InvalidNode) => Err(InvalidNode)
    Err(BudgetExceeded) => Err(AddressLimit)
  }
}

///|
/// Detached tests, with a cumulative UTF-8 pointer-byte budget for the whole
/// returned list. A condition is only addressed, never evaluated again.
pub fn demand_source_tests(
  index : DemandIndex,
  root : Int,
  node : Int,
  max_tests~ : Int,
  max_pointer_bytes~ : Int,
) -> Result[Array[SourceDemandTest], DemandAddressIssue] {
  if max_tests < 0 || max_pointer_bytes < 0 {
    return Err(InvalidAddressLimits)
  }
  let paths = match index.paths.get(root) {
    Some(paths) => paths
    None => return Err(InvalidRoot)
  }
  let tests = match @typing.demand_tests(paths, node, max_tests~) {
    Ok(tests) => tests
    Err(InvalidLimits) => return Err(InvalidAddressLimits)
    Err(InvalidNode) => return Err(InvalidNode)
    Err(BudgetExceeded) => return Err(AddressLimit)
  }
  let result = []
  let mut bytes = max_pointer_bytes
  for condition in tests {
    let pointer = match
      demand_source_pointer(index, root, condition.node_index, max_bytes=bytes) {
      Ok(Some(pointer)) => pointer
      Ok(None) => return Err(MissingConditionSource)
      Err(issue) => return Err(issue)
    }
    // Already bounded above; encoding is temporary, not retained by the result.
    bytes -= @utf8.encode(pointer).length()
    result.push({ pointer, predicate: condition.kind, })
  }
  Ok(result)
}
