///|
/// Request-local protocol-validation scratch for the fixed empty normalization
/// journal, both before and after sealing. The immutable generated schema table
/// is a module-initialization owner and is borrowed here, never reconstructed.
/// This is not parsing, canonical admission, hashing, rendering or a phase grant.
pub(all) struct EmptyNormalizationValidationLayout {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  pending_frames_upper : Int
  live_frames_upper : Int
} derive(Eq, Debug)

///|
/// The admitted original shape has one object, scalar Strings and an empty
/// Array. Required/ObjectNext transitions retain one continuation; visiting a
/// child retains at most two pending frames. The popped frame can coexist with
/// both replacements (three live frames). No alternatives, unique-array copy,
/// nested object or nonempty array branch is reachable for this fixed body.
/// The two schema checks are sequential; their scratch is not summed.
pub fn empty_normalization_validation_layout() -> EmptyNormalizationValidationLayout {
  {
    // Cursor1, budget1, pending wrapper/backing2, old grow backing1,
    // live continuation variants3, up to three transient Some carriers,
    // advance result tuple1, String exact.map result carrier1.
    record_headers: 13L,
    // Cursor3, wrapper1, pending backing2+old1, frames3,
    // pop/array lookup Some reference payloads2. Integer lookup is a word.
    reference_slots: 12L,
    // Cursor3, budget4, wrapper2, frames <=3*(tag+3 indices),
    // Some tags/payload4, advance tuple2, exact.map tag/Bool2.
    scalar_words: 29L,
    pending_frames_upper: 2,
    live_frames_upper: 3,
  }
}
