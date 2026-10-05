///|
/// Subtraction reuses the same named-definition/typed-key compatibility and
/// property alignment as structural union. This wrapper records subtraction's
/// distinct semantics; it does not authorize execution or allocate an owner.
struct CheckedSubtraction {
  composition : CheckedUnion
}

///|
pub fn check_subtraction(
  source : @decode.Cursor,
  left : @carrier.Carrier,
  right : @carrier.Carrier,
  limits : Limits,
) -> Result[CheckedSubtraction, Issue] {
  check_structural_composition(source, [left, right], limits, allow_list=false).map(composition => {
      composition,
    },
  )
}

///|
pub fn subtraction_composition(value : CheckedSubtraction) -> CheckedUnion {
  value.composition
}

///|
pub fn subtraction_output(value : CheckedSubtraction) -> @carrier.Carrier {
  union_output(value.composition)
}

///|
pub fn subtraction_usage(value : CheckedSubtraction) -> Usage {
  union_usage(value.composition)
}
