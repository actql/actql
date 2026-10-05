///|
/// Subtraction reuses the same named-definition/typed-key compatibility and
/// property alignment as structural union. This wrapper records subtraction's
/// distinct semantics; it does not authorize execution or allocate an owner.
struct CheckedSubtraction {
  composition : CheckedUnion
}

///|
pub(all) enum SubtractionObligation {
  AdmitSubtractionInputs
  PreserveSubtractionIdentities
  CheckSubtractionEdgeEndpoints
  ApplySubtractionPropertyStrategies
  InduceSubtractionEndpoints
  CanonicalSubtractionOrder
  ResolveSubtractionResources
} derive(Eq, Debug)

///|
pub fn subtraction_pending_count(_ : CheckedSubtraction) -> Int {
  7
}

///|
pub fn subtraction_pending_at(
  _ : CheckedSubtraction,
  index : Int,
) -> SubtractionObligation? {
  match index {
    0 => Some(AdmitSubtractionInputs)
    1 => Some(PreserveSubtractionIdentities)
    2 => Some(CheckSubtractionEdgeEndpoints)
    3 => Some(ApplySubtractionPropertyStrategies)
    4 => Some(InduceSubtractionEndpoints)
    5 => Some(CanonicalSubtractionOrder)
    6 => Some(ResolveSubtractionResources)
    _ => None
  }
}

///|
pub fn subtraction_source(value : CheckedSubtraction) -> @decode.Cursor {
  union_source(value.composition)
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
