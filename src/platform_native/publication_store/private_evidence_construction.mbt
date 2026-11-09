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
// The observed SQLite Blob is an encrypted/Base64 envelope, not plaintext.
// Its own extent bounds malformed JSON; a legal envelope may exceed the
// existing 1MiB plaintext limit. Clamp only the plaintext upper bound, while
// the original envelope law and caller's Store limit still bound the copy.
#warnings("-unused_value")
fn private_evidence_envelope_construction(
  envelope_bytes : Int64,
) -> PrivateEvidenceCustodyConstruction? {
  if envelope_bytes < 1L || envelope_bytes > raw_cipher_envelope_bytes(1048576L) {
    return None
  }
  private_evidence_custody_construction(
    Int64::min(envelope_bytes, 1048576L).to_int(),
  )
}

///|
// The existing parser still admits/refuses the SAME JSON and Base64 envelope.
// Charge a single dominating mixed-container family instead of simultaneously
// assuming one growing Array AND one growing Map AND one entry per input byte.
// In a complete JSON prefix with V values, K object fields and P nonempty
// containers, syntax consumes at least 2V+3K-1+(containers-P) bytes. At most
// 1024 unfinished containers survive the pinned parser's existing depth guard.
// Thus ceil((bytes+min(bytes,1024)+1)/2) worst-Map/value units dominate the
// combined Array, Map, field-link and value/token controls, including malformed
// prefixes. This is representation DATA, not a lower syntax/Store/read limit.
fn private_evidence_json_construction_extent(
  bytes : Int64,
) -> @shape.CollectionConstructionExtent? {
  if bytes < 1L || bytes > 1398272L {
    return None
  }
  let units = (bytes + Int64::min(bytes, 1024L) + 2L) / 2L
  @shape.collection_construction_extent({
    records: 4L * units + 16L,
    record_references: 6L * units + 32L,
    record_words: 4L * units + 16L,
    reference_arrays: 0L,
    reference_items: 0L,
    scalar_arrays: 0L,
    scalar_items: 0L,
    maps: units,
    map_entries: 0L,
  })
}

///|
#warnings("-unused_value")
fn private_evidence_custody_construction(
  plaintext_bytes : Int,
) -> PrivateEvidenceCustodyConstruction? {
  if plaintext_bytes < 1 || plaintext_bytes > 1048576 {
    return None
  }
  let p = plaintext_bytes.to_int64()
  let e = raw_cipher_envelope_bytes(p)
  guard private_evidence_json_construction_extent(e) is Some(json) else {
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
