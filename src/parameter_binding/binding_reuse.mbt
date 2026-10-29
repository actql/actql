///|
/// Forward only a completed read of the SAME declarations and supplied tree
/// position. These are immutable semantic facts, not an execution grant. No
/// pending constructor is advanced here, and no new input is checked here.
/// A successful result survives relaxed resource ceilings. An error survives
/// only identical limits, since a relaxed budget can change its first refusal.
pub fn reuse_binding_read(
  original : BindingReadInput,
  declarations : Declarations,
  supplied : @decode.Cursor?,
  limits : @value.Limits,
) -> Result[BindingResult, Issue]? {
  if !physical_equal(original.declarations, declarations) {
    return None
  }
  let same_input = match (original.supplied, supplied) {
    (None, None) => true
    (Some(a), Some(b)) => @decode.tree_index(a, b) == @decode.tree_index(a, a)
    _ => false
  }
  if !same_input {
    return None
  }
  match original.state {
    BindingCompleted(result) =>
      match result {
        Ok(_) =>
          if original.limits.max_nodes <= limits.max_nodes &&
            original.limits.max_depth <= limits.max_depth &&
            original.limits.max_text_bytes <= limits.max_text_bytes {
            Some(result)
          } else {
            None
          }
        Err(_) => if original.limits == limits { Some(result) } else { None }
      }
    _ => None
  }
}

///|
/// Borrow the completed original Result for its SAME declaration owner. The
/// consumer retains this reader, including its actual supplied input/limits;
/// later reuse still checks those inputs. No pending work is advanced here.
pub fn completed_binding_read(
  original : BindingReadInput,
  declarations : Declarations,
) -> Result[BindingResult, Issue]? {
  if !physical_equal(original.declarations, declarations) {
    return None
  }
  match original.state {
    BindingCompleted(result) => Some(result)
    _ => None
  }
}
