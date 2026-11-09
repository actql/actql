///|
/// Construction DATA for the existing encrypted custody, not a reservation,
/// disk quota, cryptographic key, physical acknowledgement or execution grant.
/// Original wire/Run/Store/Library owners remain borrowed and separately backed.
pub(all) struct PrivateEvidenceCustodyConstruction {
  retained : @execution.PreparationRepresentationUnits
  workspace : @execution.PreparationRepresentationUnits
  envelope_bytes : Int
}

///|
// Scalar admission scans the original String without constructing UTF8 first.
#warnings("-unused_value")
fn private_evidence_custody_wire_construction(
  wire : String,
) -> PrivateEvidenceCustodyConstruction? {
  guard @scalar.admit_utf8_length(wire, 1048576) is Ok(bytes) else {
    return None
  }
  private_evidence_custody_construction(bytes)
}

///|
// The selected envelope bounds untrusted readback before its JSON parser.
// Every token/container/field consumes a byte; homogeneous array and Map
// endpoints conservatively cover malformed input as well as the four-field
// canonical envelope. No observed successful row count narrows this bound.
#warnings("-unused_value")
fn private_evidence_custody_construction(
  plaintext_bytes : Int,
) -> PrivateEvidenceCustodyConstruction? {
  if plaintext_bytes < 1 || plaintext_bytes > 1048576 {
    return None
  }
  let p = plaintext_bytes.to_int64()
  let e = raw_cipher_envelope_bytes(p)
  guard @shape.collection_construction_extent({
      // Json values/tokens, field pairs and parser/result/refusal controls.
      records: 4L * e + 16L,
      record_references: 6L * e + 32L,
      record_words: 4L * e + 16L,
      reference_arrays: e,
      reference_items: e,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: e,
      map_entries: e,
    })
    is Some(json) else {
    return None
  }
  Some({
    retained: {
      // PrivateEffectEvidenceCustody(16 fields), its two-reference typed
      // wrapper, Result/Some and returned child-vector slot. The terminal
      // record and capacity key are ASCII and bounded by their closed spellings
      // plus the original 71-character holding/evidence identities.
      record_headers: 8L,
      reference_slots: 22L,
      scalar_words: 8L,
      owned_utf16_units: 512L,
      owned_wire_bytes: e + 32L + 256L,
    },
    workspace: {
      record_headers: json.record_headers + 32L,
      reference_slots: json.reference_slots + 48L,
      scalar_words: json.scalar_words + 32L,
      // Native Base64 is a UTF16 buffer reinterpreted as a String. Its
      // three outputs overlap the concatenation frontiers. Readback adds
      // decoded envelope/JSON Strings, Base64 canonical comparisons and
      // failed parser/StringBuilder growth. Whole encoded text bounds all
      // disjoint leaf spellings, including malformed readback.
      owned_utf16_units: 12L * e + 512L,
      // Input UTF8, C AEAD scratch(p+64), status/result(p+29), managed
      // ciphertext(p+28), readback row, plaintext/status, concatenated
      // decrypt input and independent wire comparison overlap. The original
      // encrypted envelope in retained is not counted again as a new owner.
      owned_wire_bytes: 8L * p + 4L * e + 512L,
    },
    envelope_bytes: e.to_int(),
  })
}
