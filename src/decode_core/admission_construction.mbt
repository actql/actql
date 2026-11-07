///|
/// Logical constructor records/slots only. Shared Source Strings and Spans
/// are borrowed by the index; they remain funded by their original owner.
pub(all) struct AdmissionConstructionUnits {
  record_headers : Int64
  reference_slots : Int64
  scalar_words : Int64
} derive(Eq, Debug)

///|
/// The existing logical JS construction envelope. Immutable index, key owners,
/// active ancestry and fixed decoder controls are separate lifetimes. This is not a byte quote, parse, admission
/// receipt or backend/allocator supply proof.
pub(all) struct AdmissionConstructionInventory {
  indexed : AdmissionConstructionUnits
  keys : AdmissionConstructionUnits
  ancestry : AdmissionConstructionUnits
  controls : AdmissionConstructionUnits
} derive(Eq, Debug)

///|
/// Pre-construction rejection bounds for the existing Node-tree admission.
/// Categories may independently overbound the same nodes; no false claim of
/// disjointness or ASCII/Values eligibility is required. Zero admits no node
/// but still covers the existing typed refusal and its control frame.
pub fn admission_construction_inventory(
  nodes : Int,
  fields : Int,
  objects : Int,
  arrays : Int,
  max_depth : Int,
) -> AdmissionConstructionInventory? {
  if nodes < 0 || fields < 0 || objects < 0 || arrays < 0 || max_depth < 0 {
    return None
  }
  // ObjectNext alone retains its seen Map. Completing that original frame
  // drops the Map; OwnedNode/ObjectValue retain only fields and borrowed keys.
  // Sibling objects therefore reuse the active-ancestry map envelope. Entry
  // storage remains bounded by ALL fields, including the duplicate refusal.
  let live_objects = Int::min(objects, max_depth)
  guard @shape.key_admission_construction_extent(live_objects, fields)
    is Some(keys) else {
    return None
  }
  let n = nodes.to_int64()
  let f = fields.to_int64()
  let o = objects.to_int64()
  let a = arrays.to_int64()
  let c = o + a
  let e = if n > 0L { n - 1L } else { 0L }
  let d = max_depth.to_int64() + 1L
  // OwnedNode/OwnedValue/Edge/OwnedField and indexed/child array storage.
  // Final Cursor+Usage are included; original source Spans/Strings are not
  // copied. Both edge kinds are conservatively co-counted.
  let indexed : AdmissionConstructionUnits = {
    record_headers: 2L * n + e + f + 2L * c + 4L,
    reference_slots: 6L * n + 2L * e + 4L * f + c + 8L * o + 11L,
    scalar_words: 3L * n + 4L * e + f + 2L * c + 8L * a + 7L,
  }
  // Work retains active ancestry and one current Visit, never all siblings.
  // Its source references borrow the input. Indexed/child backing replacement
  // and growing work backing are separately included.
  let ancestry : AdmissionConstructionUnits = {
    record_headers: d + 3L + c + 1L,
    reference_slots: 3L * d + 12L + 3L * d + 1L + 4L + n + 4L * c + e,
    scalar_words: 4L * d + 2L + 4L * c + e,
  }
  // Admission/Limits/Utf8Admission and Option/poll/Result/failure carriers,
  // copied failure path plus fresh path variants. Cursor/Usage are above.
  let controls : AdmissionConstructionUnits = {
    record_headers: 10L + d,
    reference_slots: 19L + 3L * d,
    scalar_words: 21L + 2L * d,
  }
  Some({
    indexed,
    keys: {
      record_headers: keys.record_headers,
      reference_slots: keys.reference_slots,
      scalar_words: keys.scalar_words,
    },
    ancestry,
    controls,
  })
}

///|
/// The preserving byte parser's original constructor peak, including refusal
/// and its owned decoded input String. The supplied Bytes remain borrowed.
/// The Source/UTF8/Map constructors keep their own inventory and tariff.
pub fn preserving_json_parser_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @source.JsonLiteralConstructionExtent? {
  guard @source.json_literal_construction_extent(bytes, nodes, depth)
    is Some(literal) else {
    return None
  }
  // Source already owns the active key-map peak, including pending-key
  // refusal and growth. Add only this byte parser's decoded input String and
  // its wrapper; replacing that same map component again would undercount it.
  Some({
    record_headers: literal.record_headers + 1L,
    reference_slots: literal.reference_slots,
    scalar_words: literal.scalar_words,
    owned_utf16_units: literal.owned_utf16_units + bytes.to_int64(),
  })
}

///|
/// Existing preserving byte-JSON parser and indexed admission, including
/// refusal. Parser and decoder maps are sequential, not two live peaks.
/// No tariff, resource allowance or physical-backend proof is supplied here.
pub fn preserving_json_admission_construction_inventory(
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> @source.JsonLiteralConstructionExtent? {
  guard preserving_json_parser_construction_inventory(bytes, nodes, depth)
    is Some(parser) &&
    admission_construction_inventory(
      nodes,
      nodes,
      nodes,
      0,
      Int::min(nodes, depth),
    )
    is Some(objects) &&
    admission_construction_inventory(
      nodes,
      nodes,
      0,
      nodes,
      Int::min(nodes, depth),
    )
    is Some(arrays) else {
    return None
  }
  // Objects+arrays cannot exceed nodes. Indexed construction is affine in
  // those counts, so its two homogeneous endpoints bound each coordinate.
  // The parser's active map peak also covers the decoder's sequential maps.
  let object_headers = objects.indexed.record_headers +
    objects.ancestry.record_headers +
    objects.controls.record_headers
  let object_refs = objects.indexed.reference_slots +
    objects.ancestry.reference_slots +
    objects.controls.reference_slots
  let object_words = objects.indexed.scalar_words +
    objects.ancestry.scalar_words +
    objects.controls.scalar_words
  let array_headers = arrays.indexed.record_headers +
    arrays.ancestry.record_headers +
    arrays.controls.record_headers
  let array_refs = arrays.indexed.reference_slots +
    arrays.ancestry.reference_slots +
    arrays.controls.reference_slots
  let array_words = arrays.indexed.scalar_words +
    arrays.ancestry.scalar_words +
    arrays.controls.scalar_words
  // Positive Int-bounded inputs keep these fixed linear Int64 sums in range.
  Some({
    record_headers: parser.record_headers +
    Int64::max(object_headers, array_headers),
    reference_slots: parser.reference_slots +
    Int64::max(object_refs, array_refs),
    scalar_words: parser.scalar_words + Int64::max(object_words, array_words),
    owned_utf16_units: parser.owned_utf16_units,
  })
}
