///|
/// Additional controls of an original Result/Int-work observation only:
/// Ref[Int]1H1W, its Some1H1R1W and returned (Result,spent)1H1R1W.
/// The original Result/reader/input backing is separate. These structural
/// units carry no work meaning, byte tariff, capacity or permission.
pub fn int_work_observation_construction_extent() -> CollectionConstructionExtent {
  int_work_observation_controls
}

///|
/// Shared returned (original Result,Int spent) carrier only:1H1R1W. This does
/// not include the Result payload, a reader/Ref or its input/backing lifetime.
pub fn int_work_result_pair_construction_extent() -> CollectionConstructionExtent {
  int_work_result_pair_controls
}

///|
// Installed immutable descriptors: repeated getters construct no quotation
// record. Their identity is never an input verdict, grant or Resource token.
let int_work_result_pair_controls : CollectionConstructionExtent = {
  record_headers: 1L,
  reference_slots: 1L,
  scalar_words: 1L,
}

///|
let int_work_observation_controls : CollectionConstructionExtent = {
  record_headers: int_work_result_pair_controls.record_headers + 2L,
  reference_slots: int_work_result_pair_controls.reference_slots + 1L,
  scalar_words: int_work_result_pair_controls.scalar_words + 2L,
}
