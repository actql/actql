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
  guard @shape.key_admission_construction_extent(objects, fields) is Some(keys) else {
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
