///|
/// Logical retained representation of the empty Common normalization journal.
/// This is a constructor dependency, not a grant, a heap measurement, or proof
/// that an arbitrary query has no normalization entries. The caller must first
/// prove that shape from its admitted original preparation. Parsing, validation,
/// hashing, writer workspace and the caller's audit wrapper remain separate
/// simultaneously-live owners and are deliberately not hidden in these facts.
pub(all) struct EmptyNormalizationJournalLayout {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
  owned_utf16_units : Int64
  body_wire_units : Int64
  sealed_wire_units : Int64
} derive(Eq, Debug)

///|
/// Original-constructor upper inventory. No output is built or sampled here.
/// Canonical containers: two payload variants, two FrozenArrays, two Array
/// wrappers/backings, four field tuples. Three String variants and six owned
/// String values complete the tree. The seventh tree String is the borrowed
/// static "journal_cid" key. The 71-unit identity is shared by the tree and
/// RunEvidenceValue, not duplicated. The final 239-unit wire is newly owned.
/// The root is a three-element copy plus one append (at most six backing slots);
/// its empty entries array is a zero-element map (zero backing slots).
pub fn empty_normalization_journal_retained_layout() -> EmptyNormalizationJournalLayout {
  {
    // Canonical tree21, evidence1, final wire1.
    record_headers: 23L,
    // Variants5 + FrozenArrays2 + Array wrappers2 + backing6 + tuples8
    // + evidence4. Child reference slots do not duplicate child owners.
    reference_slots: 27L,
    // Five payload tags plus two Array(length, capacity) pairs.
    scalar_words: 9L,
    // Tree214 minus borrowed static key11, plus final wire239.
    owned_utf16_units: 442L,
    // The body remains a separate live input during issuance, not retained by
    // RunEvidenceValue. The caller adds its owner during that phase only.
    body_wire_units: 151L,
    sealed_wire_units: 239L,
  }
}
