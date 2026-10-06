///|
/// Adopted AoA law manifests only, not complete profile or Unit dependencies.
pub(all) enum AdoptedOperationLaw {
  RelaScalar
  RelaPrimitive
  SgaStructural
  SgaIdentity
  GraphLaw
  VecaNumeric
} derive(Eq, Debug)

///|
/// Reuse the checked operation profile classification. ActQL-owned rules,
/// selected profile data, expression laws, and shared identity rules are separate.
pub fn operation_profile_adopted_law_count(profile : OperationProfile) -> Int {
  match profile {
    RelA | SGA => 2
    VecA | Graph => 1
    TEA | CalendarProfile | TextRankProfile => 0
  }
}

///|
pub fn operation_profile_adopted_law_at(
  profile : OperationProfile,
  index : Int,
) -> AdoptedOperationLaw? {
  match profile {
    RelA =>
      match index {
        0 => Some(RelaScalar)
        1 => Some(RelaPrimitive)
        _ => None
      }
    SGA =>
      match index {
        0 => Some(SgaStructural)
        1 => Some(SgaIdentity)
        _ => None
      }
    VecA => if index == 0 { Some(VecaNumeric) } else { None }
    Graph => if index == 0 { Some(GraphLaw) } else { None }
    TEA | CalendarProfile | TextRankProfile => None
  }
}
