///|
/// Project only the declaration retained by this original admitted binding.
/// Default origin must still carry that declaration's exact checked value;
/// equal value identities or a caller's reconstructed entry are not witnesses.
pub fn bound_value_declaration(
  values : BoundValues,
  index : Int,
) -> Declaration? {
  guard values.entries.get(index) is Some(value) &&
    values.declarations.entries.get(index) is Some(declaration) &&
    value.name == declaration.name &&
    physical_equal(value.parameter_type, declaration.parameter_type) else {
    return None
  }
  match value.origin {
    Supplied => ()
    Default => {
      guard declaration.default_value is Some(original) &&
        physical_equal(value.value, original) else {
        return None
      }
    }
  }
  Some(declaration)
}
