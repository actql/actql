///|
/// Dimensions retained during the original admission's existing node/key
/// visits. One immutable record belongs to the whole admitted tree, shared by
/// child cursors. No per-node cache, reparse or estimate-only tree walk.
pub(all) struct AdmissionPreparationData {
  fields : Int
  texts : Int
  max_key_utf16 : Int
  total_utf16 : Int64
} derive(Eq, Debug)

///|
pub fn admission_preparation_data(cursor : Cursor) -> AdmissionPreparationData {
  cursor.preparation
}
